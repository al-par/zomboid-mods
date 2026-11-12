package errormonitor;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

// Everything the hooks see ends up here. All state is guarded by `lock`; nothing in this class may log
// through the game, because the game's logging is what calls it.
final class Monitor {
    static volatile Monitor instance;

    static final String STATUS_FILE = "ErrorMonitor_status.txt";
    static final String CONTEXT_FILE = "ErrorMonitor_context.txt";
    static final String LOG_FILE = "session.log";
    static final String REPORT_FILE = "errors.txt";

    // Records the game writes around every Lua error, in addition to the exception itself.
    private static final String[] DUMP_PREFIXES = { "dumping Lua stack trace", "Lua fail. Message:", "DEBUG-MODE STACK TRACE" };
    private static final int MAX_PROBLEMS = 2000;
    private static final int RECENT_LINES = 80;
    private static final int MAX_INTERNAL = 20;
    private static final long TICK_MILLIS = 250;
    private static final long REPORT_INTERVAL = 3000;
    private static final long STATUS_INTERVAL = 2000;
    private static final long STDERR_TRACE_WAIT = 500;
    private static final long PERF_INTERVAL = 10_000;

    private static final List<String> earlyProblems = Collections.synchronizedList(new ArrayList<>());

    final Config config;
    final File dir;
    final long started;
    final boolean live;
    final File luaDir;
    final String source;
    String previousCrash;

    final Object lock = new Object();
    private final SessionLog log;
    private final Map<String, Problem> byKey = new HashMap<>();
    final List<Problem> errors = new ArrayList<>();
    final List<Problem> warnings = new ArrayList<>();
    long errorTotal;
    long warningTotal;
    long overflowTotal;
    final Map<String, String> hooks = new LinkedHashMap<>();
    final List<String> internal = new ArrayList<>();
    long internalCount;
    final Context context = new Context();
    final List<String> contextHistory = new ArrayList<>();
    final Set<String> silencedSubsystems = new TreeSet<>();
    long ended;
    Perf perf;
    private long lastPerfAt;

    private final ArrayDeque<RecentLine> recent = new ArrayDeque<>();
    private List<String> stderrLines;
    private long stderrAt;
    private boolean reportDirty = true;
    private boolean reportUrgent;
    private boolean statusDirty = true;
    private long lastReportAt;
    private long lastStatusAt;
    private long contextModified;
    private boolean closed;

    // The exception and message hooks run just before the game writes the same thing as a log record.
    // Remembering which problem that was lets the record be shortened when the problem is a repeat.
    private Problem pending;
    private long pendingThread;
    private String pendingLevel;

    private record RecentLine(long time, String level, String type, String text, boolean dump) {
    }

    static final class Context {
        String state = "starting";
        String version;
        String debug;
        String mode;
        String gameMode;
        String save;
        long reportedAt;
        final List<String[]> mods = new ArrayList<>();

        String describe() {
            return state.equals("in game") && save != null && !save.isEmpty() ? "in game, save " + save : describeState(state);
        }

        String modId(String name) {
            for (String[] mod : mods) {
                if (mod[1].equals(name)) {
                    return mod[0];
                }
            }
            return null;
        }
    }

    static String describeState(String state) {
        return switch (state) {
            case "in game" -> "in game";
            case "main menu" -> "at the main menu or loading a save";
            case "starting" -> "while the game was starting";
            default -> state;
        };
    }

    Monitor(Config config, File dir, long started, boolean live, File luaDir, String source) throws IOException {
        this.config = config;
        this.dir = dir;
        this.started = started;
        this.live = live;
        this.luaDir = luaDir;
        this.source = source;
        this.log = new SessionLog(new File(dir, LOG_FILE), config, started);
        log.note(started, "===", source == null ? "Error Monitor started recording" : "Error Monitor replay of " + source);
    }

    private long collapsedAtSnapshot;

    // A frozen copy of what Report reads, taken under `lock` so the report can be rendered without it:
    // every game thread that logs waits on `lock`, and rendering thousands of problems takes a while.
    private Monitor(Monitor m) {
        config = m.config;
        dir = m.dir;
        started = m.started;
        live = m.live;
        luaDir = m.luaDir;
        source = m.source;
        previousCrash = m.previousCrash;
        log = null;
        collapsedAtSnapshot = m.collapsedTotal();
        for (Problem p : m.errors) {
            errors.add(p.snapshot());
        }
        for (Problem p : m.warnings) {
            warnings.add(p.snapshot());
        }
        errorTotal = m.errorTotal;
        warningTotal = m.warningTotal;
        overflowTotal = m.overflowTotal;
        hooks.putAll(m.hooks);
        internal.addAll(m.internal);
        internalCount = m.internalCount;
        Context c = m.context;
        context.state = c.state;
        context.version = c.version;
        context.debug = c.debug;
        context.mode = c.mode;
        context.gameMode = c.gameMode;
        context.save = c.save;
        context.reportedAt = c.reportedAt;
        context.mods.addAll(c.mods);
        contextHistory.addAll(m.contextHistory);
        silencedSubsystems.addAll(m.silencedSubsystems);
        ended = m.ended;
        perf = m.perf;
    }

    // ---- startup ----

    static void start() {
        try {
            File cache = cacheDir();
            File root = new File(cache, "ErrorMonitor");
            Config config = Config.load(root);
            long now = System.currentTimeMillis();
            String crashed = Sessions.markUnfinished(root, now);
            File dir = Sessions.create(root, now);
            Sessions.prune(root, config.keepSessions);
            File luaDir = new File(cache, "Lua");
            new File(luaDir, CONTEXT_FILE).delete();
            Monitor m = new Monitor(config, dir, now, true, luaDir, null);
            m.previousCrash = crashed;
            if (crashed != null) {
                m.log.note(now, "===", "the previous session (" + crashed + ") did not end cleanly");
            }
            instance = m;
            if (config.performance) {
                Perf perf = new Perf(m, config, now);
                m.perf = perf;
                Perf.instance = perf;
                perf.start();
            }
            if (config.jfr) {
                Jfr.startInBackground(dir, config);
            }
            Sessions.pruneRecordings(root, config.jfrKeepSessions);

            Thread worker = new Thread(m::runWorker, "ErrorMonitor");
            worker.setDaemon(true);
            worker.start();
            Runtime.getRuntime().addShutdownHook(new Thread(() -> m.shutdown(System.currentTimeMillis()), "ErrorMonitor-shutdown"));
            System.out.println("[ErrorMonitor] recording to " + dir);
        } catch (Throwable t) {
            agentProblem("starting", t);
            System.out.println("[ErrorMonitor] could not start: " + t);
        }
    }

    static File cacheDir() {
        String dir = System.getProperty("deployment.user.cachedir");
        if (dir == null || dir.isEmpty()) {
            dir = System.getProperty("user.home");
        }
        return new File(dir, "Zomboid");
    }

    // Problems inside Error Monitor. Never thrown back into the game.
    static void agentProblem(String where, Throwable t) {
        Monitor m = instance;
        String line = where + ": " + t;
        if (m == null) {
            if (earlyProblems.size() < MAX_INTERNAL) {
                earlyProblems.add(line);
            }
            return;
        }
        synchronized (m.lock) {
            m.internalCount++;
            if (m.internal.size() < MAX_INTERNAL) {
                m.internal.add(Text.clock(System.currentTimeMillis()) + "  " + line);
            }
            m.reportDirty = true;
        }
    }

    // From Perf, which holds no lock of its own while calling these.
    void perfNote(long time, String mark, String text) {
        synchronized (lock) {
            if (!closed) {
                log.note(time, mark, text);
            }
        }
    }

    void perfRecord(long time, String text) {
        synchronized (lock) {
            if (!closed) {
                log.record(time, "PERF", "Perf", null, text, null, false);
            }
        }
    }

    void hookStatus(String hook, String status) {
        synchronized (lock) {
            hooks.put(hook, status);
            reportDirty = true;
        }
    }

    // ---- entry points from Hooks (and Replay) ----

    void logged(String type, String level, String prefix, String message, long time) {
        if (message == null) {
            return;
        }
        synchronized (lock) {
            if (closed) {
                return;
            }
            if (type.equals("stderr") && collectStderrTrace(message, time)) {
                return;
            }
            flushStderrTrace();
            Problem p = pending;
            if (p != null && level.equals(pendingLevel) && Thread.currentThread().getId() == pendingThread) {
                pending = null;
                if (p.count > 1) {
                    String line = again(p);
                    remember(time, level, type, line);
                    log.record(time, level, type, null, line, null, false);
                    return;
                }
                remember(time, level, type, p.id + ": " + p.title);
                log.record(time, level, type, prefix, message, null, false);
                return;
            }
            remember(time, level, type, message);
            log.record(time, level, type, prefix, message, null, !type.equals("stderr") && level.equals("ERROR") && isDump(message));
        }
    }

    private static String again(Problem p) {
        return p.id + " again: " + Text.oneLine(p.title, 160);
    }

    private void expect(Problem p, String level) {
        pending = p;
        pendingThread = Thread.currentThread().getId();
        pendingLevel = level;
    }

    void exception(String type, boolean enabled, Throwable t, String contextMessage, String prefix, String level, long time) {
        if (!enabled && !config.captureSilenced) {
            return;
        }
        exception(type, enabled, Trace.of(t), contextMessage, prefix, level, time);
    }

    Problem exception(String type, boolean enabled, Trace trace, String contextMessage, String prefix, String level, long time) {
        boolean error = level.equals("ERROR");
        synchronized (lock) {
            if (closed) {
                return null;
            }
            String key = exceptionKey(trace);
            Problem p = byKey.get(key);
            if (p != null) {
                p.seen(time, null);
                counted(p);
            } else if (error || config.reportWarnings) {
                String title = trace.message == null || trace.message.isBlank() ? trace.className : Text.oneLine(Text.firstLine(trace.message), 240);
                p = add(key, new Problem(nextId(error), error, type, title, trace.message, trace.className,
                    blankToNull(contextMessage), trace, trace.allFrames(), prefix, !enabled, before(), stateNow(), time));
            }
            if (p != null) {
                p.calledFrom(trace.allFrames());
            }
            if (!enabled) {
                silencedSubsystems.add(type);
                log.record(time, level, type, prefix, p != null && p.count > 1 ? again(p) : renderTrace(trace, contextMessage), "[silenced]", false);
            } else if (p != null) {
                expect(p, level);
            }
            return p;
        }
    }

    private String stateNow() {
        return live ? context.describe() : null;
    }

    void message(String type, boolean enabled, String level, String text, String caller, long time) {
        if (text == null || (!enabled && !config.captureSilenced)) {
            return;
        }
        boolean error = level.equals("ERROR");
        String first = Text.firstLine(text).trim();
        boolean dump = isDump(text);
        String key = "M|" + level + '|' + type + '|' + Text.normalize(first, 300);
        synchronized (lock) {
            if (closed) {
                return;
            }
            if (!enabled) {
                silencedSubsystems.add(type);
                log.record(time, level, type, caller, text, "[silenced]", false);
            }
            if (dump || (!error && !config.reportWarnings)) {
                return;
            }
            if (repeated(key, first, time, enabled, level)) {
                return;
            }
        }
        List<String> stack = live ? Trace.callerStack() : List.of();
        synchronized (lock) {
            if (closed || repeated(key, first, time, enabled, level)) {
                return;
            }
            Problem p = add(key, new Problem(nextId(error), error, type, Text.oneLine(first, 240), text, null, null, null, stack, caller,
                !enabled, before(), stateNow(), time));
            if (p != null && enabled) {
                expect(p, level);
            }
        }
    }

    private boolean repeated(String key, String first, long time, boolean enabled, String level) {
        Problem p = byKey.get(key);
        if (p == null) {
            return false;
        }
        p.seen(time, Text.oneLine(first, 240));
        counted(p);
        if (enabled) {
            expect(p, level);
        }
        return true;
    }

    // ---- problems ----

    private Problem add(String key, Problem p) {
        if (byKey.size() >= MAX_PROBLEMS) {
            overflowTotal++;
            return null;
        }
        byKey.put(key, p);
        (p.error ? errors : warnings).add(p);
        if (p.error) {
            errorTotal++;
        } else {
            warningTotal++;
        }
        StringBuilder note = new StringBuilder(p.error ? "NEW ERROR " : "NEW WARNING ").append(p.id).append("  ");
        if (p.mod != null) {
            note.append('[').append(p.mod).append("] ");
        }
        note.append(p.title);
        if (p.where != null) {
            note.append("  at ").append(p.where);
        }
        log.note(p.first, ">>>", note.toString());
        reportDirty = true;
        reportUrgent = true;
        statusDirty = true;
        return p;
    }

    private void counted(Problem p) {
        if (p.error) {
            errorTotal++;
        } else {
            warningTotal++;
        }
        reportDirty = true;
    }

    private String nextId(boolean error) {
        return (error ? "E" : "W") + ((error ? errors.size() : warnings.size()) + 1);
    }

    // A Lua error is identified by the line that failed, not by the path that led there, so callers are not
    // part of the key. The first mod in the stack is, so a vanilla function failing for two mods is two problems.
    private static String exceptionKey(Trace t) {
        StringBuilder k = new StringBuilder("X|").append(t.className).append('|')
            .append(Text.normalize(t.message == null ? "" : t.message, 300));
        boolean lua = false;
        for (String f : t.allFrames()) {
            if (!Trace.isLua(f)) {
                continue;
            }
            if (!lua) {
                k.append('|').append(f);
                lua = true;
            }
            if (Trace.luaMod(f) != null) {
                k.append("|mod|").append(Trace.luaMod(f));
                break;
            }
        }
        if (!lua) {
            int n = 0;
            for (String f : t.frames) {
                k.append('|').append(Trace.stripModule(f));
                if (++n == 4) {
                    break;
                }
            }
        }
        Trace root = t.root();
        if (root != t) {
            k.append("|cause|").append(root.className).append('|').append(Text.normalize(root.message == null ? "" : root.message, 200));
        }
        return k.toString();
    }

    private static boolean isDump(String text) {
        String first = Text.firstLine(text);
        if (first.isBlank() || Character.isWhitespace(first.charAt(0))) {
            return true;
        }
        for (String prefix : DUMP_PREFIXES) {
            if (first.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }

    private static String renderTrace(Trace trace, String contextMessage) {
        StringBuilder b = new StringBuilder();
        if (contextMessage != null && !contextMessage.isBlank()) {
            b.append(contextMessage).append('\n');
        }
        for (Trace t = trace; t != null; t = t.cause) {
            b.append(t == trace ? "\t" : "\tCaused by: ").append(t.className);
            if (t.message != null) {
                b.append(": ").append(t.message);
            }
            b.append('\n');
            for (String f : t.frames) {
                b.append("\t\t").append(f).append('\n');
            }
        }
        return b.toString().stripTrailing();
    }

    // ---- recent lines, shown under each problem ----

    private void remember(long time, String level, String type, String message) {
        recent.addLast(new RecentLine(time, level, type, Text.oneLine(Text.firstLine(message), 200), isDump(message)));
        if (recent.size() > RECENT_LINES) {
            recent.removeFirst();
        }
    }

    private List<String> before() {
        List<String> lines = new ArrayList<>();
        if (config.contextLines == 0) {
            return lines;
        }
        RecentLine previous = null;
        int repeats = 0;
        List<String> reversed = new ArrayList<>();
        for (Iterator<RecentLine> it = recent.descendingIterator(); it.hasNext() && reversed.size() < config.contextLines; ) {
            RecentLine line = it.next();
            if (line.level.equals("ERROR") && (line.text.isEmpty() || line.dump)) {
                continue;
            }
            if (previous != null && previous.level.equals(line.level) && previous.type.equals(line.type) && previous.text.equals(line.text)) {
                repeats++;
                continue;
            }
            if (previous != null) {
                reversed.add(formatRecent(previous, repeats));
            }
            previous = line;
            repeats = 0;
        }
        if (previous != null && reversed.size() < config.contextLines) {
            reversed.add(formatRecent(previous, repeats));
        }
        for (int i = reversed.size() - 1; i >= 0; i--) {
            lines.add(reversed.get(i));
        }
        return lines;
    }

    private static String formatRecent(RecentLine line, int repeats) {
        String text = Text.clock(line.time) + " " + Text.pad(line.level, 5) + " " + Text.pad(line.type, 8) + " " + line.text;
        return repeats > 0 ? text + "   (x" + (repeats + 1) + ")" : text;
    }

    // ---- e.printStackTrace() arrives on System.err one line per record; put the trace back together ----

    private boolean collectStderrTrace(String message, long time) {
        String first = Text.firstLine(message);
        if (isExceptionHeader(first)) {
            flushStderrTrace();
            stderrLines = new ArrayList<>();
            stderrLines.add(first.startsWith("Exception in thread ") ? first.substring(first.indexOf("\" ") + 2) : first);
            stderrAt = time;
            return true;
        }
        if (stderrLines != null && (first.startsWith("\tat ") || first.startsWith("\t... ") || first.startsWith("Caused by: ")
            || first.startsWith("\tCaused by: ") || first.startsWith("\tSuppressed: "))) {
            stderrLines.add(first);
            return true;
        }
        return false;
    }

    private static boolean isExceptionHeader(String line) {
        String s = line.startsWith("Exception in thread \"") && line.indexOf("\" ") > 0 ? line.substring(line.indexOf("\" ") + 2) : line;
        int colon = s.indexOf(": ");
        String head = colon < 0 ? s.trim() : s.substring(0, colon);
        return Trace.looksLikeClassName(head) && (head.endsWith("Exception") || head.endsWith("Error") || head.endsWith("Throwable"));
    }

    private void flushStderrTrace() {
        List<String> lines = stderrLines;
        if (lines == null) {
            return;
        }
        stderrLines = null;
        String text = String.join("\n", lines);
        Trace trace = Trace.parse(lines);
        if (trace == null || trace.frames.isEmpty()) {
            remember(stderrAt, "LOG", "stderr", text);
            log.record(stderrAt, "LOG", "stderr", null, text, null, false);
            return;
        }
        Problem p = exception("stderr", true, trace, null, null, "ERROR", stderrAt);
        pending = null;
        String line = p == null ? text : p.count > 1 ? again(p) : null;
        remember(stderrAt, "ERROR", "stderr", line == null ? p.id + ": " + p.title : line);
        log.record(stderrAt, "ERROR", "stderr", null, line == null ? text : line, null, false);
    }

    // ---- state reported by the Lua half ----

    private void readContext(long now) {
        File file = new File(luaDir, CONTEXT_FILE);
        long modified = file.lastModified();
        if (modified == 0 || modified == contextModified) {
            return;
        }
        List<String> lines;
        try {
            lines = Files.readAllLines(file.toPath(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return;
        }
        // Lua writes "end" last; without it the file was read mid-write, so try again next tick.
        if (lines.isEmpty() || !lines.get(lines.size() - 1).equals("end")) {
            return;
        }
        contextModified = modified;
        synchronized (lock) {
            String oldState = context.state;
            String oldSave = context.save;
            context.mods.clear();
            context.save = null;
            context.gameMode = null;
            for (String line : lines) {
                int eq = line.indexOf('=');
                if (eq < 0) {
                    continue;
                }
                String key = line.substring(0, eq);
                String value = line.substring(eq + 1);
                switch (key) {
                    case "state" -> context.state = value;
                    case "version" -> context.version = value;
                    case "debug" -> context.debug = value;
                    case "mode" -> context.mode = value;
                    case "gamemode" -> context.gameMode = value;
                    case "save" -> context.save = value;
                    case "mod" -> {
                        int tab = value.indexOf('\t');
                        context.mods.add(tab < 0 ? new String[] { value, value } : new String[] { value.substring(0, tab), value.substring(tab + 1) });
                    }
                    default -> {
                    }
                }
            }
            context.reportedAt = now;
            if (perf != null) {
                perf.stateChanged(context.state);
            }
            if (!context.state.equals(oldState) || !java.util.Objects.equals(context.save, oldSave)) {
                String line = context.describe() + " (" + Text.plural(context.mods.size(), "mod", "mods") + " active)";
                contextHistory.add(Text.clockSeconds(now) + "  " + line);
                log.note(now, "===", "game: " + line);
            }
            reportDirty = true;
            statusDirty = true;
        }
    }

    // ---- background work ----

    private void runWorker() {
        while (true) {
            try {
                Thread.sleep(TICK_MILLIS);
                tick(System.currentTimeMillis());
            } catch (InterruptedException e) {
                return;
            } catch (Throwable t) {
                agentProblem("background writer", t);
            }
        }
    }

    void tick(long now) {
        if (perf != null) {
            perf.tick(now);
            if (now - lastPerfAt >= PERF_INTERVAL) {
                writePerf(now);
            }
        }
        synchronized (lock) {
            if (closed) {
                return;
            }
            if (stderrLines != null && now - stderrAt > STDERR_TRACE_WAIT) {
                flushStderrTrace();
            }
            log.maybeSummarize(now);
            log.flush();
        }
        if (live) {
            readContext(now);
        }
        boolean writeReport;
        boolean writeStatus;
        synchronized (lock) {
            writeReport = reportUrgent || (reportDirty && now - lastReportAt >= REPORT_INTERVAL);
            writeStatus = live && (statusDirty || now - lastStatusAt >= STATUS_INTERVAL);
        }
        if (writeReport) {
            writeReport(now);
        }
        if (writeStatus) {
            writeStatus(now);
        }
    }

    void shutdown(long now) {
        if (perf != null) {
            perf.shutdown(now);
            writePerf(now);
        }
        synchronized (lock) {
            if (closed) {
                return;
            }
            flushStderrTrace();
            log.summarize(now);
            log.note(now, "===", live ? "session ended" : "end of replayed log");
            ended = now;
            closed = true;
            log.close();
        }
        writeReport(now);
        if (live) {
            Sessions.writeState(dir, "ended", now);
            synchronized (writeLock) {
                new File(luaDir, STATUS_FILE).delete();
            }
        }
    }

    // The worker and the shutdown hook both write files. Each write snapshots, renders and moves under
    // writeLock, so the later writer always renders the later state and the .tmp files never collide.
    private final Object writeLock = new Object();

    private void writeReport(long now) {
        synchronized (writeLock) {
            Monitor frozen;
            synchronized (lock) {
                frozen = new Monitor(this);
                reportDirty = false;
                reportUrgent = false;
                lastReportAt = now;
            }
            String text = Report.render(frozen, now);
            try {
                writeAtomically(new File(dir, REPORT_FILE), text);
            } catch (IOException e) {
                agentProblem("writing errors.txt", e);
            }
        }
    }

    private void writePerf(long now) {
        synchronized (writeLock) {
            lastPerfAt = now;
            try {
                writeAtomically(new File(dir, Perf.REPORT_FILE), PerfReport.render(perf, this, now, Jfr.status));
            } catch (IOException e) {
                agentProblem("writing " + Perf.REPORT_FILE, e);
            }
        }
    }

    private void writeStatus(long now) {
        synchronized (writeLock) {
            writeStatusLocked(now);
        }
    }

    private void writeStatusLocked(long now) {
        String text;
        synchronized (lock) {
            if (closed) {
                return;
            }
            text = Report.status(this, now);
            statusDirty = false;
            lastStatusAt = now;
        }
        try {
            luaDir.mkdirs();
            writeAtomically(new File(luaDir, STATUS_FILE), text);
        } catch (IOException e) {
            agentProblem("writing " + STATUS_FILE, e);
        }
    }

    static List<String> earlyProblems() {
        synchronized (earlyProblems) {
            return new ArrayList<>(earlyProblems);
        }
    }

    long collapsedTotal() {
        return log == null ? collapsedAtSnapshot : log.collapsedTotal();
    }

    static void writeAtomically(File file, String text) throws IOException {
        File tmp = new File(file.getPath() + ".tmp");
        Files.writeString(tmp.toPath(), text, StandardCharsets.UTF_8);
        try {
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
    }
}
