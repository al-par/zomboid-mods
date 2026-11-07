package errormonitor;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

// perf.txt. Rendered under Perf.lock.
final class PerfReport {
    private static final String RULE = "=".repeat(100);
    private static final int MOD_ROWS = 25;
    private static final int FUNCTION_ROWS = 30;
    private static final int ENTRY_ROWS = 20;
    private static final int TIMELINE_ROWS = 600;

    private PerfReport() {
    }

    static String render(Perf p, Monitor m, long now, String jfrStatus) {
        StringBuilder b = new StringBuilder(32 * 1024);
        synchronized (p.lock) {
            header(b, p, m, now, jfrStatus);
            mods(b, p);
            functions(b, p);
            entries(b, p);
            hitches(b, p);
            freezes(b, p);
            timeline(b, p);
        }
        return b.toString();
    }

    private static void header(StringBuilder b, Perf p, Monitor m, long now, String jfrStatus) {
        b.append("PERFORMANCE   session started ").append(Text.dateTime(m.started)).append("   (updated ").append(Text.clockSeconds(now)).append(")\n")
            .append(RULE).append('\n');
        Perf.Histogram h = p.session;
        b.append("Measured    ");
        if (p.measuredInGame) {
            b.append("in game only, since ").append(Text.clockSeconds(p.measuredSince)).append(". Menus and loading screens are left out.\n");
        } else {
            b.append("the whole session. Once a save is loaded, only time in game counts.\n");
        }
        if (h.frames == 0) {
            b.append("Frames      none measured yet.\n");
        } else {
            b.append("Frames      ").append(fmt1(1000 / h.averageMs())).append(" fps on average over ").append(Text.count(h.frames))
                .append(" frames. Frame time: median ").append(fmt1(h.percentileMs(0.5))).append(" ms, 95% under ")
                .append(fmt1(h.percentileMs(0.95))).append(" ms, 99% under ").append(fmt1(h.percentileMs(0.99)))
                .append(" ms, worst ").append(Text.count(Math.round(h.maxNs / 1e6))).append(" ms.\n");
        }
        b.append("Hitches     ").append(Text.plural(p.hitchCountMeasured, "frame", "frames")).append(" took ")
            .append(p.config.hitchMillis).append(" ms or more");
        if (p.hitchCount != p.hitchCountMeasured) {
            b.append(" (").append(Text.count(p.hitchCount)).append(" counting menus and loading)");
        }
        b.append(".\n");
        b.append("Freezes     ").append(p.freezeCount == 0 ? "none" : Text.plural(p.freezeCount, "time", "times") + " the game drew no frame for "
            + p.config.freezeMillis / 1000.0 + " s or more, see FREEZES").append(".\n");
        if (!p.luaProfiling()) {
            b.append("Lua         not profiled yet. Lua profiling starts when the Error Monitor mod reports from the game,\n")
                .append("            so the mod has to be enabled in the save.\n");
        } else if (p.sampledNs > 0) {
            b.append("Lua         ");
            if (h.frames > 0) {
                b.append(fmt2(p.luaNs / 1e6 / h.frames)).append(" ms per frame on average, ");
            }
            b.append(percent(p.luaNs, p.sampledNs)).append(" of the main thread's time.\n");
        }
        b.append("GC          ").append(String.join(", ", p.collectors)).append(": ").append(Text.plural(p.gcPauses, "pause", "pauses"))
            .append(", ").append(Text.count(p.gcPauseMillis)).append(" ms in total, longest ").append(p.gcLongestPause).append(" ms.");
        if (p.heapAfterGc >= 0) {
            b.append(" Heap after the last GC: ").append(Text.count(p.heapAfterGc >> 20)).append(" MB of ").append(Text.count(p.heapMax >> 20)).append(" MB.");
        }
        b.append('\n');
        b.append("Recording   ").append(jfrStatus).append('\n');
        b.append('\n');
    }

    private static void mods(StringBuilder b, Perf p) {
        if (p.luaNs == 0) {
            return;
        }
        b.append("LUA TIME BY MOD\n").append(RULE).append('\n')
            .append("Main-thread time each mod's Lua takes. \"Own code\" is time inside the mod's functions; \"with calls\"\n")
            .append("adds the vanilla Lua and game functions it called. A mod that wraps a vanilla function gets that\n")
            .append("function's time under \"with calls\".\n\n");
        List<Map.Entry<String, long[]>> rows = Perf.top(p.modTotal, Integer.MAX_VALUE);
        int width = 24;
        for (Map.Entry<String, long[]> row : rows) {
            width = Math.max(width, Math.min(44, row.getKey().length() + 2));
        }
        boolean perFrame = p.session.frames > 0;
        String unit = perFrame ? "ms/frame" : "of Lua";
        b.append("  ").append(Text.pad("Mod", width)).append(Text.padLeft("own code", 12)).append(Text.padLeft("with calls", 12))
            .append(Text.padLeft("share of Lua", 14)).append("   (").append(unit).append(")\n");
        int n = 0;
        for (Map.Entry<String, long[]> row : rows) {
            if (n++ == MOD_ROWS) {
                b.append("  ... ").append(rows.size() - MOD_ROWS).append(" more\n");
                break;
            }
            long[] self = p.modSelf.get(row.getKey());
            long selfNs = self == null ? 0 : self[0];
            b.append("  ").append(Text.pad(Text.clip(row.getKey(), width - 2), width))
                .append(Text.padLeft(amount(p, selfNs), 12)).append(Text.padLeft(amount(p, row.getValue()[0]), 12))
                .append(Text.padLeft(percent(selfNs, p.luaNs), 14)).append('\n');
        }
        b.append('\n');
    }

    private static void functions(StringBuilder b, Perf p) {
        if (p.functions.isEmpty()) {
            return;
        }
        b.append("SLOWEST LUA FUNCTIONS  (own time, not counting functions they call)\n").append(RULE).append('\n');
        List<Map.Entry<LuaStack.Site, Perf.Stat>> rows = new ArrayList<>(p.functions.entrySet());
        rows.sort((x, y) -> Long.compare(y.getValue().ns, x.getValue().ns));
        List<String[]> table = new ArrayList<>();
        for (int i = 0; i < rows.size() && i < FUNCTION_ROWS; i++) {
            LuaStack.Site s = rows.get(i).getKey();
            Perf.Stat st = rows.get(i).getValue();
            Map.Entry<Integer, long[]> line = Perf.top(st.lines, 1).get(0);
            table.add(new String[] { amount(p, st.ns), percent(st.ns, p.luaNs), s.function + "  " + s.file + ":" + line.getKey(),
                s.mod == null ? "vanilla" : s.mod });
        }
        siteTable(b, p, table, "function  file:hottest line");
    }

    private static void entries(StringBuilder b, Perf p) {
        if (p.entries.isEmpty()) {
            return;
        }
        b.append("LUA ENTRY POINTS  (where the game called into Lua: event handlers, UI and timed-action callbacks;\n")
            .append("                  time includes everything they called)\n").append(RULE).append('\n');
        List<String[]> table = new ArrayList<>();
        for (Map.Entry<LuaStack.Site, long[]> e : Perf.top(p.entries, ENTRY_ROWS)) {
            LuaStack.Site s = e.getKey();
            table.add(new String[] { amount(p, e.getValue()[0]), percent(e.getValue()[0], p.luaNs), s.function + "  " + s.file,
                s.mod == null ? "vanilla" : s.mod });
        }
        siteTable(b, p, table, "function  file");
    }

    private static void siteTable(StringBuilder b, Perf p, List<String[]> table, String header) {
        int width = header.length();
        for (String[] row : table) {
            width = Math.max(width, Math.min(80, row[2].length()));
        }
        b.append(Text.padLeft(p.session.frames > 0 ? "ms/frame" : "of Lua", 10)).append(Text.padLeft("of Lua", 8)).append("  ")
            .append(Text.pad(header, width + 3)).append("mod\n");
        for (String[] row : table) {
            b.append(Text.padLeft(row[0], 10)).append(Text.padLeft(row[1], 8)).append("  ").append(Text.pad(Text.clip(row[2], 80), width + 3))
                .append(row[3]).append('\n');
        }
        b.append('\n');
    }

    private static void hitches(StringBuilder b, Perf p) {
        if (p.hitches.isEmpty()) {
            return;
        }
        b.append("HITCHES  (longest ").append(p.hitches.size()).append(" of ").append(Text.count(p.hitchCount)).append(", in order)\n").append(RULE).append('\n');
        List<Perf.Hitch> sorted = new ArrayList<>(p.hitches);
        sorted.sort((x, y) -> Long.compare(x.startWall, y.startWall));
        for (Perf.Hitch h : sorted) {
            b.append("  ").append(Text.clockSeconds(h.startWall)).append(Text.padLeft(Text.count(h.durationNs / 1_000_000) + " ms", 10))
                .append("  ").append(Text.pad(h.state, 10)).append(h.cause).append('\n');
        }
        b.append('\n');
    }

    private static void freezes(StringBuilder b, Perf p) {
        if (p.freezes.isEmpty()) {
            return;
        }
        b.append("FREEZES  (the game drew no frame for ").append(p.config.freezeMillis / 1000.0).append(" s or more)\n").append(RULE).append('\n');
        for (Perf.Freeze f : p.freezes) {
            b.append(Text.clockSeconds(f.startWall)).append("  ").append(Monitor.describeState(f.state)).append(", ")
                .append(f.durationNs < 0 ? "still frozen at the last update" : "lasted " + Perf.seconds(f.durationNs)).append('\n');
            for (String c : f.captures) {
                b.append(c).append('\n');
            }
            b.append('\n');
        }
    }

    private static void timeline(StringBuilder b, Perf p) {
        if (p.timeline.isEmpty()) {
            return;
        }
        b.append("TIMELINE  (one row per minute)\n").append(RULE).append('\n');
        b.append("  time       state         fps   avg ms   99% ms   max ms  hitches  Lua ms/frame  Lua %   GC ms  heap MB\n");
        int start = Math.max(0, p.timeline.size() - TIMELINE_ROWS);
        if (start > 0) {
            b.append("  (").append(start).append(" earlier rows not shown)\n");
        }
        for (int i = start; i < p.timeline.size(); i++) {
            Perf.Row r = p.timeline.get(i);
            b.append("  ").append(Text.pad(Text.clockSeconds(r.startWall()), 10)).append(' ').append(Text.pad(r.state(), 11))
                .append(Text.padLeft(r.avgMs() == 0 ? "-" : fmt1(1000 / r.avgMs()), 7))
                .append(Text.padLeft(fmt1(r.avgMs()), 9)).append(Text.padLeft(fmt1(r.p99Ms()), 9)).append(Text.padLeft(fmt1(r.maxMs()), 9))
                .append(Text.padLeft(Long.toString(r.hitches()), 9)).append(Text.padLeft(fmt2(r.luaMsPerFrame()), 14))
                .append(Text.padLeft(Math.round(r.luaShare() * 100) + "%", 7)).append(Text.padLeft(Long.toString(r.gcMillis()), 8))
                .append(Text.padLeft(r.heapBytes() < 0 ? "-" : Text.count(r.heapBytes() >> 20), 9)).append('\n');
        }
        b.append('\n');
    }

    // ---- status file lines for the Lua half ----

    static void status(StringBuilder b, Perf p) {
        synchronized (p.lock) {
            Perf.Histogram h = p.session;
            b.append("fps=").append(h.frames == 0 ? "" : fmt1(1000 / h.averageMs())).append('\n');
            b.append("frameP99=").append(h.frames == 0 ? "" : fmt1(h.percentileMs(0.99))).append('\n');
            b.append("luaMsPerFrame=").append(h.frames == 0 || p.luaNs == 0 ? "" : fmt2(p.luaNs / 1e6 / h.frames)).append('\n');
            b.append("hitches=").append(p.hitchCountMeasured).append('\n');
            b.append("freezes=").append(p.freezeCount).append('\n');
            List<Map.Entry<String, long[]>> top = Perf.top(p.modSelf, 3);
            for (Map.Entry<String, long[]> e : top) {
                b.append("topMod=").append(Text.oneLine(e.getKey(), 120)).append('\t').append(amount(p, e.getValue()[0])).append('\n');
            }
        }
    }

    private static String amount(Perf p, long ns) {
        if (p.session.frames > 0) {
            return fmt2(ns / 1e6 / p.session.frames);
        }
        return percent(ns, p.luaNs);
    }

    private static String percent(long part, long whole) {
        if (whole <= 0) {
            return "-";
        }
        double v = 100.0 * part / whole;
        return v < 1 && part > 0 ? "<1%" : Math.round(v) + "%";
    }

    private static String fmt1(double v) {
        return String.format(Locale.ROOT, "%.1f", v);
    }

    private static String fmt2(double v) {
        return String.format(Locale.ROOT, "%.2f", v);
    }
}
