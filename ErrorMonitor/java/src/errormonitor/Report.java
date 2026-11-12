package errormonitor;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// errors.txt, and the status file the Lua half reads. Both are rendered under Monitor.lock.
final class Report {
    static final String STATUS_LABEL = "Status    ";
    private static final String RULE = "=".repeat(100);
    private static final String THIN = "-".repeat(100);
    private static final String INDENT = "    ";
    private static final String LABEL_GAP = "            ";
    private static final int MAX_DETAILED = 300;
    private static final int MAX_LUA_FRAMES = 20;
    private static final int MAX_JAVA_FRAMES = 10;
    private static final int MAX_CAUSE_FRAMES = 8;
    private static final int MAX_TEXT_LINES = 30;
    private static final int MAX_STATUS_PROBLEMS = 300;

    private Report() {
    }

    static String render(Monitor m, long now) {
        StringBuilder b = new StringBuilder(32 * 1024);
        header(b, m, now);
        summary(b, m);
        section(b, m, "ERRORS", m.errors);
        if (m.config.reportWarnings) {
            section(b, m, "WARNINGS", m.warnings);
        }
        gameState(b, m);
        mods(b, m);
        itself(b, m);
        return b.toString();
    }

    // ---- header ----

    private static void header(StringBuilder b, Monitor m, long now) {
        b.append("ERROR MONITOR   ").append(m.source == null ? "session started " : "log starts ").append(Text.dateTime(m.started)).append('\n').append(RULE).append('\n');
        if (m.source != null) {
            b.append(STATUS_LABEL).append("replay of ").append(m.source).append('\n');
        } else if (m.ended != 0) {
            b.append(STATUS_LABEL).append("ended normally at ").append(Text.dateTime(m.ended)).append(" after ").append(duration(m.ended - m.started)).append('\n');
        } else {
            b.append(STATUS_LABEL).append("running. This file updates while the game runs (last update ").append(Text.clockSeconds(now)).append(")\n");
        }
        Monitor.Context c = m.context;
        if (m.live) {
            if (c.version == null) {
                b.append("Game      not reported yet. The Error Monitor mod has to be enabled for the game details and mod list.\n");
            } else {
                List<String> parts = new ArrayList<>();
                parts.add(c.version);
                if ("true".equals(c.debug)) {
                    parts.add("debug mode");
                }
                if (c.mode != null) {
                    parts.add(c.mode);
                }
                if (c.gameMode != null) {
                    parts.add(c.gameMode);
                }
                b.append("Game      ").append(String.join(", ", parts)).append('\n');
                if (c.save != null && !c.save.isEmpty()) {
                    b.append("Save      ").append(c.save).append('\n');
                }
            }
        }
        b.append("Log       ").append(Monitor.LOG_FILE).append(" in this folder has the whole session in order. Lines that repeat are\n")
            .append("          collapsed into counts (").append(Text.plural(m.collapsedTotal(), "line", "lines")).append(" so far).\n");
        if (m.perf != null) {
            b.append("Perf      ").append(Perf.REPORT_FILE).append(" in this folder: frame times, hitches, freezes, and Lua time by mod.\n");
        }
        if (m.previousCrash != null) {
            b.append("Previous  session ").append(m.previousCrash).append(" did not end cleanly. Its folder has the log up to where it stopped.\n");
        }
        if (m.live) {
            hooks(b, m);
        }
        if (!m.silencedSubsystems.isEmpty()) {
            b.append("Silenced  Caught from subsystems that debuglog.ini switches Off, which the game's own log drops:\n")
                .append("          ").append(String.join(", ", m.silencedSubsystems)).append('\n');
        }
        b.append('\n');
    }

    private static void hooks(StringBuilder b, Monitor m) {
        List<String> missing = new ArrayList<>();
        int off = 0;
        for (Map.Entry<String, String> e : m.hooks.entrySet()) {
            if (e.getValue().startsWith("off")) {
                off++;
            } else if (!e.getValue().equals("applied")) {
                missing.add(e.getKey() + " (" + e.getValue() + ")");
            }
        }
        int total = Transformer.HOOKS.length - off;
        if (m.hooks.size() - off < total) {
            b.append("Hooks     ").append(m.hooks.size() - off).append(" of ").append(total).append(" installed so far\n");
        } else if (missing.isEmpty()) {
            b.append("Hooks     all ").append(total).append(" active\n");
        } else {
            b.append("Hooks     ").append(total - missing.size()).append(" of ").append(total)
                .append(" active. A game update changed the code behind: ").append(String.join(", ", missing)).append('\n');
        }
    }

    // ---- summary ----

    private static void summary(StringBuilder b, Monitor m) {
        b.append("SUMMARY\n").append(RULE).append('\n');
        if (m.errors.isEmpty() && m.warnings.isEmpty()) {
            b.append("No errors or warnings so far.\n\n");
            return;
        }
        b.append(Text.plural(m.errors.size(), "error", "different errors")).append(", ").append(Text.plural(m.errorTotal, "time", "times")).append(" in total. ")
            .append(Text.plural(m.warnings.size(), "warning", "different warnings")).append(", ").append(Text.plural(m.warningTotal, "time", "times")).append(".\n");
        if (m.overflowTotal > 0) {
            b.append("Another ").append(Text.count(m.overflowTotal)).append(" occurrences came after the limit of tracked problems; they are in session.log.\n");
        }
        Map<String, long[]> bySource = new LinkedHashMap<>();
        for (Problem p : m.errors) {
            long[] row = bySource.computeIfAbsent(p.source(), k -> new long[4]);
            row[0]++;
            row[1] += p.count;
        }
        for (Problem p : m.warnings) {
            long[] row = bySource.computeIfAbsent(p.source(), k -> new long[4]);
            row[2]++;
            row[3] += p.count;
        }
        List<Map.Entry<String, long[]>> rows = new ArrayList<>(bySource.entrySet());
        rows.sort((x, y) -> {
            int c = Long.compare(y.getValue()[0], x.getValue()[0]);
            return c != 0 ? c : Long.compare(y.getValue()[1], x.getValue()[1]);
        });
        int width = 24;
        for (Map.Entry<String, long[]> row : rows) {
            width = Math.max(width, Math.min(48, row.getKey().length() + 2));
        }
        b.append('\n').append(Text.pad("  Source", width + 2)).append("  errors     times  warnings     times\n");
        for (Map.Entry<String, long[]> row : rows) {
            long[] v = row.getValue();
            b.append("  ").append(Text.pad(Text.clip(sourceName(m, row.getKey()), width), width))
                .append(Text.padLeft(Text.count(v[0]), 8)).append(Text.padLeft(Text.count(v[1]), 10))
                .append(Text.padLeft(Text.count(v[2]), 10)).append(Text.padLeft(Text.count(v[3]), 10)).append('\n');
        }
        b.append('\n');
    }

    // ---- problems ----

    private static void section(StringBuilder b, Monitor m, String title, List<Problem> problems) {
        if (problems.isEmpty()) {
            return;
        }
        b.append(title).append('\n').append(RULE).append('\n');
        for (int i = 0; i < problems.size(); i++) {
            Problem p = problems.get(i);
            if (i < MAX_DETAILED) {
                problem(b, m, p);
            } else {
                b.append(Text.pad(p.id, 6)).append(Text.padLeft(Text.count(p.count), 8)).append("x  ").append(p.source()).append(": ").append(p.title).append('\n');
            }
        }
        b.append('\n');
    }

    private static void problem(StringBuilder b, Monitor m, Problem p) {
        b.append(Text.pad(p.id, 4)).append(p.title).append('\n');
        field(b, "Happened", Text.plural(p.count, "time", "times") + ", " + (p.count == 1 ? "at " + Text.clock(p.first)
            : "first " + Text.clock(p.first) + ", last " + Text.clock(p.last)) + (p.stateAtFirst == null ? "" : " (first " + p.stateAtFirst + ")"));
        if (p.mod != null) {
            field(b, "Mod", modName(m, p.mod));
            if (p.failedOutsideMod) {
                b.append(INDENT).append(LABEL_GAP).append("It failed in vanilla Lua that this mod called.\n");
            }
        } else {
            field(b, "Mod", "none in the stack");
        }
        if (p.modsInStack.size() > 1) {
            List<String> others = new ArrayList<>();
            for (String mod : p.modsInStack.keySet()) {
                if (!mod.equals(p.mod)) {
                    others.add(mod);
                }
            }
            field(b, "Also in stack", String.join(", ", others));
        }
        if (p.where != null) {
            field(b, "Where", p.where);
        }
        if (p.exceptionClass != null) {
            field(b, "Exception", p.exceptionClass);
        }
        field(b, "Logged by", p.subsystem + (p.silenced ? " (Off in debuglog.ini, so the game's own log dropped this)" : ""));
        if (p.contextMessage != null) {
            field(b, "Note", Text.oneLine(p.contextMessage, 300));
        }
        String text = p.text == null ? "" : p.text.stripTrailing();
        if (text.contains("\n") || text.length() > p.title.length()) {
            b.append(INDENT).append("Full text\n");
            lines(b, text, MAX_TEXT_LINES);
        }
        if (!p.examples.isEmpty()) {
            b.append(INDENT).append("Other variants\n");
            for (String e : p.examples) {
                b.append(INDENT).append(INDENT).append(e).append('\n');
            }
        }
        luaStack(b, p.stack);
        callers(b, p);
        if (p.trace != null) {
            javaStack(b, "Java stack", p.trace.frames, MAX_JAVA_FRAMES);
            for (Trace c = p.trace.cause; c != null; c = c.cause) {
                b.append(INDENT).append("Caused by ").append(c.className).append(c.message == null ? "" : ": " + Text.oneLine(c.message, 300)).append('\n');
                javaStack(b, null, c.frames, MAX_CAUSE_FRAMES);
            }
        } else if (!p.stack.isEmpty()) {
            javaStack(b, "Java stack", p.stack, MAX_JAVA_FRAMES);
        }
        if (!p.before.isEmpty()) {
            b.append(INDENT).append("Before the first one\n");
            for (String line : p.before) {
                b.append(INDENT).append(INDENT).append(line).append('\n');
            }
        }
        b.append(THIN).append('\n');
    }

    private static void field(StringBuilder b, String label, String value) {
        b.append(INDENT).append(Text.pad(label, LABEL_GAP.length())).append(value).append('\n');
    }

    private static void lines(StringBuilder b, String text, int max) {
        String[] lines = text.split("\r?\n");
        for (int i = 0; i < lines.length && i < max; i++) {
            b.append(INDENT).append(INDENT).append(lines[i].replace("\t", "    ")).append('\n');
        }
        if (lines.length > max) {
            b.append(INDENT).append(INDENT).append("... ").append(lines.length - max).append(" more lines in session.log\n");
        }
    }

    private static void luaStack(StringBuilder b, List<String> frames) {
        List<String> lua = new ArrayList<>();
        for (String f : frames) {
            if (Trace.isLua(f)) {
                lua.add(f);
            }
        }
        if (lua.isEmpty()) {
            return;
        }
        int width = 0;
        for (int i = 0; i < lua.size() && i < MAX_LUA_FRAMES; i++) {
            width = Math.max(width, Trace.luaShort(lua.get(i)).length());
        }
        width = Math.min(width + 3, 70);
        b.append(INDENT).append("Lua stack\n");
        for (int i = 0; i < lua.size() && i < MAX_LUA_FRAMES; i++) {
            String f = lua.get(i);
            String mod = Trace.luaMod(f);
            b.append(INDENT).append(INDENT).append(Text.pad(Trace.luaShort(f), width)).append(mod == null ? "vanilla" : mod).append('\n');
        }
        if (lua.size() > MAX_LUA_FRAMES) {
            b.append(INDENT).append(INDENT).append("... ").append(lua.size() - MAX_LUA_FRAMES).append(" more Lua frames\n");
        }
    }

    // The Lua stack above is from the first occurrence; this shows every path the failing function was called from.
    private static void callers(StringBuilder b, Problem p) {
        if (p.callers.size() + (p.otherCallers > 0 ? 1 : 0) < 2) {
            return;
        }
        int width = 0;
        for (String c : p.callers.keySet()) {
            width = Math.max(width, c.length());
        }
        width = Math.min(width + 3, 90);
        b.append(INDENT).append("Called from\n");
        for (Map.Entry<String, Long> e : p.callers.entrySet()) {
            b.append(INDENT).append(INDENT).append(Text.pad(e.getKey(), width)).append(Text.count(e.getValue())).append("x\n");
        }
        if (p.otherCallers > 0) {
            b.append(INDENT).append(INDENT).append(Text.pad("other places", width)).append(Text.count(p.otherCallers)).append("x\n");
        }
    }

    // Kahlua VM, JDK, event-dispatch and main-loop frames are the same for most errors, so only their count is shown.
    private static void javaStack(StringBuilder b, String label, List<String> frames, int max) {
        List<String> shown = new ArrayList<>();
        int hidden = 0;
        for (String f : frames) {
            if (Trace.isLua(f)) {
                continue;
            }
            if (Trace.isEngineFrame(f) || shown.size() >= max) {
                hidden++;
            } else {
                shown.add(Trace.stripModule(f));
            }
        }
        if (shown.isEmpty() && hidden == 0) {
            return;
        }
        if (label != null) {
            b.append(INDENT).append(label);
            if (hidden > 0) {
                b.append("  (").append(Text.plural(hidden, "engine or library frame", "engine, library or deeper frames")).append(" not shown)");
            }
            b.append('\n');
        }
        for (String f : shown) {
            b.append(INDENT).append(INDENT).append(f).append('\n');
        }
    }

    // ---- context ----

    private static void gameState(StringBuilder b, Monitor m) {
        if (m.contextHistory.isEmpty()) {
            return;
        }
        b.append("GAME STATE\n").append(RULE).append('\n');
        for (String line : m.contextHistory) {
            b.append(line).append('\n');
        }
        b.append('\n');
    }

    private static void mods(StringBuilder b, Monitor m) {
        if (!m.live) {
            return;
        }
        Monitor.Context c = m.context;
        b.append("ACTIVE MODS\n").append(RULE).append('\n');
        if (c.reportedAt == 0) {
            b.append("Not reported yet. The list comes from the Error Monitor mod once the game reaches the main menu.\n\n");
            return;
        }
        b.append("Load order as of ").append(Text.clockSeconds(c.reportedAt)).append(" (").append(c.describe()).append(")\n");
        int n = 1;
        for (String[] mod : c.mods) {
            b.append(Text.padLeft(Integer.toString(n++), 4)).append(". ").append(mod[1]);
            if (!mod[1].equals(mod[0])) {
                b.append("  (").append(mod[0]).append(')');
            }
            b.append('\n');
        }
        b.append('\n');
    }

    private static void itself(StringBuilder b, Monitor m) {
        List<String> early = Monitor.earlyProblems();
        if (m.internalCount == 0 && early.isEmpty()) {
            return;
        }
        b.append("ERROR MONITOR ITSELF\n").append(RULE).append('\n');
        for (String line : early) {
            b.append("at startup  ").append(line).append('\n');
        }
        for (String line : m.internal) {
            b.append(line).append('\n');
        }
        if (m.internalCount > m.internal.size()) {
            b.append("... ").append(m.internalCount - m.internal.size()).append(" more\n");
        }
        b.append('\n');
    }

    private static String modName(Monitor m, String name) {
        String id = m.context.modId(name);
        return id == null || id.equals(name) ? name : name + " (" + id + ")";
    }

    private static String sourceName(Monitor m, String source) {
        return source.equals("vanilla Lua") || source.equals("game (Java)") ? source : modName(m, source);
    }

    private static String duration(long millis) {
        long minutes = Math.max(0, millis / 60_000);
        return minutes < 60 ? Text.plural(minutes, "minute", "minutes") : (minutes / 60) + " h " + (minutes % 60) + " min";
    }

    // ---- status file for the Lua half ----

    static String status(Monitor m, long now) {
        StringBuilder b = new StringBuilder(4096);
        b.append("heartbeat=").append(now).append('\n');
        b.append("session=").append(m.dir.getName()).append('\n');
        b.append("folder=").append(m.dir.getAbsolutePath()).append('\n');
        b.append("previousCrash=").append(m.previousCrash == null ? "" : m.previousCrash).append('\n');
        b.append("errors=").append(m.errors.size()).append('\n');
        b.append("errorCount=").append(m.errorTotal).append('\n');
        b.append("warnings=").append(m.warnings.size()).append('\n');
        b.append("warningCount=").append(m.warningTotal).append('\n');
        if (m.perf != null) {
            PerfReport.status(b, m.perf);
        }
        int n = 0;
        for (List<Problem> list : List.of(m.errors, m.warnings)) {
            for (Problem p : list) {
                if (n++ >= MAX_STATUS_PROBLEMS) {
                    break;
                }
                b.append("problem=").append(p.id).append('\t').append(p.error ? "error" : "warning").append('\t').append(p.count).append('\t')
                    .append(clean(p.mod == null ? "" : p.mod)).append('\t').append(clean(p.where == null ? "" : p.where)).append('\t')
                    .append(clean(p.title)).append('\n');
            }
        }
        b.append("end\n");
        return b.toString();
    }

    private static String clean(String s) {
        return Text.oneLine(s, 240);
    }
}
