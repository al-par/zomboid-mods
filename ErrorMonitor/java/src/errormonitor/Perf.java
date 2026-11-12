package errormonitor;

import com.sun.management.GarbageCollectionNotificationInfo;
import com.sun.management.GcInfo;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryUsage;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.locks.LockSupport;
import javax.management.Notification;
import javax.management.NotificationEmitter;
import javax.management.openmbean.CompositeData;

// Frame times come from a hook at the start of GameWindow.frameStep. Where the time goes comes from a
// sampler thread that reads the main Lua thread's call stack, so the game thread does no extra work
// for it. Lock order: Monitor.lock may be held while taking Perf.lock, never the other way round.
final class Perf {
    static volatile Perf instance;

    static final String VANILLA = "vanilla Lua";
    static final String REPORT_FILE = "perf.txt";
    private static final int MAX_DEPTH = 200;
    private static final int RING = 16384;
    private static final int MAX_HITCHES = 40;
    private static final int MAX_FREEZES = 20;
    private static final int MAX_FREEZE_CAPTURES = 6;
    private static final long FREEZE_RECAPTURE_NS = 10_000_000_000L;
    private static final int MAX_TIMELINE = 24 * 60;
    private static final int GC_RING = 512;
    private static final long WINDOW_MILLIS = 60_000;
    private static final int LUA_FAILURES_BEFORE_GIVING_UP = 200;

    final Monitor monitor;
    final Config config;
    final Object lock = new Object();
    final long jvmStartWall = ManagementFactory.getRuntimeMXBean().getStartTime();
    final long heapMax = Runtime.getRuntime().maxMemory();
    private final LuaStack lua = new LuaStack();
    private final long hitchNs;
    private final long freezeNs;
    private final long sampleNs;

    // Written by the frame hook on the main thread, under lock.
    private Thread mainThread;
    private long lastFrameNs;
    private boolean skipNextFrame = true;
    final Histogram session = new Histogram();
    final Histogram window = new Histogram();
    long measuredSince;

    // Written by the sampler thread, under lock.
    volatile boolean luaReady;
    private boolean luaBroken;
    private int luaFailuresInARow;
    long sampledNs;
    long luaNs;
    final Map<String, long[]> modSelf = new HashMap<>();
    final Map<String, long[]> modTotal = new HashMap<>();
    final Map<LuaStack.Site, Stat> functions = new HashMap<>();
    final Map<LuaStack.Site, long[]> entries = new HashMap<>();
    private final long[] ringTime = new long[RING];
    private final long[] ringWeight = new long[RING];
    private final LuaStack.Site[] ringTop = new LuaStack.Site[RING];
    private final int[] ringLine = new int[RING];
    private final String[] ringCulprit = new String[RING];
    private int ringNext;
    private final String[] owners = new String[64];
    private long windowSampledNs;
    private long windowLuaNs;

    // Hitches and freezes.
    private final List<Hitch> pendingHitches = new ArrayList<>();
    final List<Hitch> hitches = new ArrayList<>();
    long hitchCount;
    long hitchCountMeasured;
    private long windowHitches;
    private Freeze freeze;
    private final List<Freeze> endedFreezes = new ArrayList<>();
    final List<Freeze> freezes = new ArrayList<>();
    long freezeCount;

    // Garbage collection, from JMX notifications.
    private final long[] gcEnd = new long[GC_RING];
    private final long[] gcDuration = new long[GC_RING];
    private int gcNext;
    long gcPauses;
    long gcPauseMillis;
    long gcLongestPause;
    long heapAfterGc = -1;
    private long windowGcMillis;
    final List<String> collectors = new ArrayList<>();

    // Context from the Lua half.
    private volatile boolean measuring = true;
    private boolean contextSeen;
    String state = "starting";
    boolean measuredInGame;

    final List<Row> timeline = new ArrayList<>();
    private long windowStartWall;

    static final class Stat {
        long ns;
        final Map<Integer, long[]> lines = new HashMap<>();
    }

    static final class Hitch {
        final long startWall;
        final long startNs;
        final long durationNs;
        final String state;
        String cause;

        Hitch(long startWall, long startNs, long durationNs, String state) {
            this.startWall = startWall;
            this.startNs = startNs;
            this.durationNs = durationNs;
            this.state = state;
        }
    }

    static final class Freeze {
        final long startWall;
        final long startNs;
        final String state;
        long durationNs = -1;
        long lastCaptureNs;
        final List<String> captures = new ArrayList<>();

        Freeze(long startWall, long startNs, String state) {
            this.startWall = startWall;
            this.startNs = startNs;
            this.state = state;
        }
    }

    record Row(long startWall, String state, long frames, double avgMs, double p99Ms, double maxMs, long hitches,
               double luaMsPerFrame, double luaShare, long gcMillis, long heapBytes) {
    }

    // Frame times in 0.25 ms buckets up to 2 s; longer frames share the last bucket but keep their exact max.
    static final class Histogram {
        private static final long BUCKET_NS = 250_000;
        private final int[] counts = new int[8000];
        long frames;
        long totalNs;
        long maxNs;

        void add(long ns) {
            counts[(int) Math.min(counts.length - 1, ns / BUCKET_NS)]++;
            frames++;
            totalNs += ns;
            maxNs = Math.max(maxNs, ns);
        }

        double percentileMs(double p) {
            if (frames == 0) {
                return 0;
            }
            long target = (long) Math.ceil(frames * p);
            long seen = 0;
            for (int i = 0; i < counts.length; i++) {
                seen += counts[i];
                if (seen >= target) {
                    return i == counts.length - 1 ? maxNs / 1e6 : (i + 1) * BUCKET_NS / 1e6;
                }
            }
            return maxNs / 1e6;
        }

        double averageMs() {
            return frames == 0 ? 0 : totalNs / 1e6 / frames;
        }

        void clear() {
            java.util.Arrays.fill(counts, 0);
            frames = 0;
            totalNs = 0;
            maxNs = 0;
        }
    }

    Perf(Monitor monitor, Config config, long now) {
        this.monitor = monitor;
        this.config = config;
        this.hitchNs = config.hitchMillis * 1_000_000L;
        this.freezeNs = config.freezeMillis * 1_000_000L;
        this.sampleNs = config.sampleMicros * 1000L;
        this.windowStartWall = now;
        this.measuredSince = now;
    }

    void start() {
        listenForGc();
        Thread sampler = new Thread(this::runSampler, "ErrorMonitor-sampler");
        sampler.setDaemon(true);
        sampler.start();
    }

    // ---- main thread ----

    void frame() {
        long now = System.nanoTime();
        synchronized (lock) {
            if (mainThread == null) {
                mainThread = Thread.currentThread();
            }
            if (lastFrameNs != 0) {
                long d = now - lastFrameNs;
                if (freeze != null) {
                    freeze.durationNs = d;
                    endedFreezes.add(freeze);
                    freeze = null;
                }
                if (skipNextFrame) {
                    skipNextFrame = false;
                } else {
                    window.add(d);
                    if (measuring) {
                        session.add(d);
                    }
                    if (d >= hitchNs && pendingHitches.size() < 1000) {
                        pendingHitches.add(new Hitch(System.currentTimeMillis() - d / 1_000_000, lastFrameNs, d, state));
                    }
                }
            }
            lastFrameNs = now;
        }
    }

    // ---- context ----

    void stateChanged(String newState) {
        synchronized (lock) {
            if (!contextSeen || !newState.equals(state)) {
                // The frame that spans a loading screen says nothing about how the game runs.
                skipNextFrame = true;
            }
            contextSeen = true;
            state = newState;
            boolean inGame = newState.equals("in game");
            if (inGame && !measuredInGame) {
                // Until the first save is loaded the whole session was measured; from now on only play counts.
                measuredInGame = true;
                session.clear();
                sampledNs = 0;
                luaNs = 0;
                modSelf.clear();
                modTotal.clear();
                functions.clear();
                entries.clear();
                hitchCountMeasured = 0;
                measuredSince = System.currentTimeMillis();
            }
            measuring = inGame || !measuredInGame;
        }
        luaReady = true;
    }

    // ---- sampler thread ----

    private void runSampler() {
        LuaStack.Site[] sites = new LuaStack.Site[MAX_DEPTH];
        int[] lineNumbers = new int[MAX_DEPTH];
        boolean resolved = false;
        long last = System.nanoTime();
        while (true) {
            try {
                LockSupport.parkNanos(sampleNs);
                long now = System.nanoTime();
                long weight = Math.min(now - last, sampleNs * 4);
                last = now;
                int depth = 0;
                if (luaReady && !luaBroken) {
                    if (!resolved) {
                        lua.resolve();
                        resolved = true;
                    }
                    try {
                        depth = lua.read(sites, lineNumbers);
                        luaFailuresInARow = 0;
                    } catch (ReflectiveOperationException | RuntimeException e) {
                        // A racy read; give up only if it keeps happening.
                        if (++luaFailuresInARow >= LUA_FAILURES_BEFORE_GIVING_UP) {
                            luaBroken = true;
                            Monitor.agentProblem("reading the Lua stack (Lua profiling stopped)", e);
                        }
                        continue;
                    }
                }
                record(now, weight, sites, lineNumbers, depth);
                checkFreeze(now, sites, lineNumbers, depth);
            } catch (Throwable t) {
                luaBroken = true;
                Monitor.agentProblem("performance sampler", t);
            }
        }
    }

    private void record(long now, long weight, LuaStack.Site[] sites, int[] lineNumbers, int depth) {
        String culprit = null;
        for (int i = 0; i < depth; i++) {
            if (sites[i].mod != null) {
                culprit = sites[i].mod;
                break;
            }
        }
        if (culprit == null && depth > 0) {
            culprit = VANILLA;
        }
        synchronized (lock) {
            int r = ringNext;
            ringTime[r] = now;
            ringWeight[r] = weight;
            ringTop[r] = depth > 0 ? sites[0] : null;
            ringLine[r] = depth > 0 ? lineNumbers[0] : 0;
            ringCulprit[r] = culprit;
            ringNext = (r + 1) % RING;

            windowSampledNs += weight;
            if (depth > 0) {
                windowLuaNs += weight;
            }
            if (!measuring) {
                return;
            }
            sampledNs += weight;
            if (depth == 0) {
                return;
            }
            luaNs += weight;
            LuaStack.Site top = sites[0];
            modSelf.computeIfAbsent(top.owner(), k -> new long[1])[0] += weight;
            int distinct = 0;
            for (int i = 0; i < depth; i++) {
                String owner = sites[i].owner();
                boolean counted = false;
                for (int j = 0; j < distinct; j++) {
                    if (owners[j].equals(owner)) {
                        counted = true;
                        break;
                    }
                }
                if (!counted && distinct < owners.length) {
                    owners[distinct++] = owner;
                    modTotal.computeIfAbsent(owner, k -> new long[1])[0] += weight;
                }
            }
            Stat stat = functions.computeIfAbsent(top, k -> new Stat());
            stat.ns += weight;
            stat.lines.computeIfAbsent(lineNumbers[0], k -> new long[1])[0] += weight;
            entries.computeIfAbsent(sites[depth - 1], k -> new long[1])[0] += weight;
        }
    }

    private void checkFreeze(long now, LuaStack.Site[] sites, int[] lineNumbers, int depth) {
        Thread main;
        Freeze f;
        boolean started = false;
        synchronized (lock) {
            if (lastFrameNs == 0 || now - lastFrameNs < freezeNs) {
                return;
            }
            if (freeze == null) {
                long stalled = now - lastFrameNs;
                freeze = new Freeze(System.currentTimeMillis() - stalled / 1_000_000, lastFrameNs, state);
                freezeCount++;
                started = true;
            } else if (now - freeze.lastCaptureNs < FREEZE_RECAPTURE_NS || freeze.captures.size() >= MAX_FREEZE_CAPTURES) {
                return;
            }
            f = freeze;
            f.lastCaptureNs = now;
            main = mainThread;
        }
        String capture = capture(now - f.startNs, main, sites, lineNumbers, depth, luaProfiling());
        synchronized (lock) {
            f.captures.add(capture);
            if (started) {
                freezes.add(f);
                if (freezes.size() > MAX_FREEZES) {
                    freezes.remove(0);
                }
            }
        }
        // Written straight away: if the game never recovers, this is the last thing in the log.
        monitor.perfNote(System.currentTimeMillis(), "!!!", (started ? "FREEZE: no frame drawn for " : "still frozen after ")
            + seconds(now - f.startNs) + " (" + Monitor.describeState(f.state) + ")\n" + capture);
    }

    private static String capture(long stalledNs, Thread main, LuaStack.Site[] sites, int[] lineNumbers, int depth, boolean luaSampled) {
        StringBuilder b = new StringBuilder();
        b.append("    after ").append(seconds(stalledNs)).append(", the main thread was ");
        if (!luaSampled) {
            b.append("not checked for Lua (the Error Monitor Lua mod isn't running yet).\n");
        } else if (depth > 0) {
            b.append("running Lua:\n");
            for (int i = 0; i < depth && i < 20; i++) {
                b.append("        ").append(sites[i].function).append("  ").append(sites[i].file).append(':').append(lineNumbers[i])
                    .append("  (").append(sites[i].mod == null ? "vanilla" : sites[i].mod).append(")\n");
            }
            if (depth > 20) {
                b.append("        ... ").append(depth - 20).append(" more Lua frames\n");
            }
        } else {
            b.append("not running Lua.\n");
        }
        if (main != null) {
            StackTraceElement[] stack = main.getStackTrace();
            b.append("    Java stack of the main thread:\n");
            int shown = 0;
            for (StackTraceElement e : stack) {
                if (shown++ == 25) {
                    b.append("        ... ").append(stack.length - 25).append(" more\n");
                    break;
                }
                b.append("        ").append(e).append('\n');
            }
        }
        return b.toString().stripTrailing();
    }

    // ---- garbage collection ----

    private void listenForGc() {
        for (GarbageCollectorMXBean gc : ManagementFactory.getGarbageCollectorMXBeans()) {
            collectors.add(gc.getName());
            if (gc instanceof NotificationEmitter emitter) {
                emitter.addNotificationListener(this::onGc, null, null);
            }
        }
    }

    private void onGc(Notification n, Object handback) {
        try {
            if (!GarbageCollectionNotificationInfo.GARBAGE_COLLECTION_NOTIFICATION.equals(n.getType())) {
                return;
            }
            GarbageCollectionNotificationInfo info = GarbageCollectionNotificationInfo.from((CompositeData) n.getUserData());
            GcInfo g = info.getGcInfo();
            long used = 0;
            for (MemoryUsage u : g.getMemoryUsageAfterGc().values()) {
                used += u.getUsed();
            }
            // ZGC and Shenandoah report whole concurrent cycles on a separate bean; those are not pauses.
            String name = info.getGcName();
            boolean pause = !(name.contains("Cycles") || name.contains("Concurrent"));
            synchronized (lock) {
                heapAfterGc = used;
                if (!pause) {
                    return;
                }
                long d = g.getDuration();
                gcEnd[gcNext] = jvmStartWall + g.getEndTime();
                gcDuration[gcNext] = d;
                gcNext = (gcNext + 1) % GC_RING;
                gcPauses++;
                gcPauseMillis += d;
                gcLongestPause = Math.max(gcLongestPause, d);
                windowGcMillis += d;
            }
        } catch (Throwable t) {
            Monitor.agentProblem("GC notification", t);
        }
    }

    // ---- worker thread ----

    void tick(long now) {
        List<String> notes = new ArrayList<>();
        List<Freeze> ended;
        synchronized (lock) {
            long newestSample = ringTime[(ringNext - 1 + RING) % RING];
            for (int i = 0; i < pendingHitches.size(); i++) {
                Hitch h = pendingHitches.get(i);
                if (h.startNs + h.durationNs > newestSample && now - h.startWall < 5000) {
                    continue;
                }
                pendingHitches.remove(i--);
                h.cause = attribute(h);
                hitchCount++;
                windowHitches++;
                if (measuring) {
                    hitchCountMeasured++;
                }
                keepLongest(h);
                notes.add("hitch: one frame took " + Text.count(h.durationNs / 1_000_000) + " ms. " + h.cause);
            }
            ended = new ArrayList<>(endedFreezes);
            endedFreezes.clear();
            if (now - windowStartWall >= WINDOW_MILLIS) {
                closeWindow(now);
            }
        }
        for (String note : notes) {
            monitor.perfRecord(now, note);
        }
        for (Freeze f : ended) {
            monitor.perfNote(now, "!!!", "freeze over: the game was frozen for " + seconds(f.durationNs));
        }
    }

    private void keepLongest(Hitch h) {
        hitches.add(h);
        if (hitches.size() > MAX_HITCHES) {
            int shortest = 0;
            for (int i = 1; i < hitches.size(); i++) {
                if (hitches.get(i).durationNs < hitches.get(shortest).durationNs) {
                    shortest = i;
                }
            }
            hitches.remove(shortest);
        }
    }

    // What the main thread was doing during one long frame, from the samples taken inside it.
    private String attribute(Hitch h) {
        long end = h.startNs + h.durationNs;
        long sampled = 0;
        long inLua = 0;
        Map<String, long[]> byCulprit = new HashMap<>();
        Map<String, long[]> bySite = new HashMap<>();
        for (int i = 0; i < RING; i++) {
            long t = ringTime[i];
            if (t <= h.startNs || t > end) {
                continue;
            }
            long w = ringWeight[i];
            sampled += w;
            if (ringTop[i] == null) {
                continue;
            }
            inLua += w;
            byCulprit.computeIfAbsent(ringCulprit[i], k -> new long[1])[0] += w;
            LuaStack.Site s = ringTop[i];
            bySite.computeIfAbsent(s.function + "  " + s.file + ":" + ringLine[i], k -> new long[1])[0] += w;
        }
        long gc = gcPauseWithin(h.startWall, h.startWall + h.durationNs / 1_000_000);
        StringBuilder b = new StringBuilder();
        if (sampled == 0) {
            b.append("Not sampled.");
        } else if (inLua * 4 < sampled) {
            b.append("Mostly the engine (Java), not Lua");
            if (inLua > 0) {
                b.append("; Lua ").append(Text.count(inLua / 1_000_000)).append(" ms");
            }
            b.append('.');
        } else {
            b.append("Lua ").append(Text.count(inLua / 1_000_000)).append(" ms: ");
            List<Map.Entry<String, long[]>> culprits = top(byCulprit, 2);
            for (int i = 0; i < culprits.size(); i++) {
                b.append(i == 0 ? "" : ", ").append(culprits.get(i).getKey()).append(' ')
                    .append(Text.count(culprits.get(i).getValue()[0] / 1_000_000)).append(" ms");
            }
            List<Map.Entry<String, long[]>> sites = top(bySite, 1);
            if (!sites.isEmpty()) {
                b.append(", mostly in ").append(sites.get(0).getKey());
            }
            b.append('.');
        }
        if (gc > 0) {
            b.append(" GC pauses ").append(gc).append(" ms.");
        }
        return b.toString();
    }

    private long gcPauseWithin(long startWall, long endWall) {
        long total = 0;
        for (int i = 0; i < GC_RING; i++) {
            long e = gcEnd[i];
            if (e == 0) {
                continue;
            }
            long s = e - gcDuration[i];
            if (e >= startWall && s <= endWall) {
                total += gcDuration[i];
            }
        }
        return total;
    }

    static <K> List<Map.Entry<K, long[]>> top(Map<K, long[]> map, int n) {
        List<Map.Entry<K, long[]>> list = new ArrayList<>(map.entrySet());
        list.sort((a, b) -> Long.compare(b.getValue()[0], a.getValue()[0]));
        return list.size() > n ? list.subList(0, n) : list;
    }

    private void closeWindow(long now) {
        long frames = window.frames;
        if (frames > 0 || windowSampledNs > 0) {
            timeline.add(new Row(windowStartWall, state, frames, window.averageMs(), window.percentileMs(0.99), window.maxNs / 1e6,
                windowHitches, frames == 0 ? 0 : windowLuaNs / 1e6 / frames,
                windowSampledNs == 0 ? 0 : (double) windowLuaNs / windowSampledNs, windowGcMillis, heapAfterGc));
            if (timeline.size() > MAX_TIMELINE) {
                timeline.remove(0);
            }
        }
        window.clear();
        windowHitches = 0;
        windowSampledNs = 0;
        windowLuaNs = 0;
        windowGcMillis = 0;
        windowStartWall = now;
    }

    void shutdown(long now) {
        tick(now);
        synchronized (lock) {
            closeWindow(now);
        }
    }

    boolean luaProfiling() {
        return luaReady && !luaBroken;
    }

    static String seconds(long ns) {
        return String.format(java.util.Locale.ROOT, "%.1f s", ns / 1e9);
    }
}
