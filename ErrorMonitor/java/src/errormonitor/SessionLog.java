package errormonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// session.log: every line the game logs, in order, except that a line repeating more than
// repeatsBeforeCollapse times is replaced by periodic counts. Not thread-safe; Monitor holds its lock.
final class SessionLog {
    private static final int MAX_TRACKED_LINES = 20_000;
    private static final int SUMMARY_ROWS = 15;
    private static final String GUTTER = "                   ";

    private final Config config;
    private final Writer out;
    private long bytes;
    private boolean capped;
    private boolean failed;
    private int nextRepeatId = 1;
    private long windowStart;
    private long collapsedTotal;
    private final List<Repeat> collapsing = new ArrayList<>();
    private final Repeat dumps = new Repeat();
    private final Map<String, Repeat> repeats = new LinkedHashMap<>(1024, 0.75f, true) {
        @Override
        protected boolean removeEldestEntry(Map.Entry<String, Repeat> eldest) {
            return size() > MAX_TRACKED_LINES;
        }
    };

    private static final class Repeat {
        int id;
        int seen;
        long lastSeen;
        long sinceSummary;
        boolean inWindow;
        String preview;
    }

    SessionLog(File file, Config config, long start) throws IOException {
        this.config = config;
        this.out = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(file, true), StandardCharsets.UTF_8), 64 * 1024);
        this.windowStart = start;
    }

    long collapsedTotal() {
        return collapsedTotal;
    }

    // `dump` marks the stack dumps the game prints around every Lua error. Past their first copies they are
    // counted together, since they only repeat what the error record already says.
    void record(long time, String level, String type, String prefix, String message, String tag, boolean dump) {
        maybeSummarize(time);
        Repeat r = repeats.computeIfAbsent(key(level, type, prefix, message), k -> new Repeat());
        // A second copy of an identical stack trace adds nothing, so those are written once.
        int limit = message.indexOf('\n') >= 0 ? 1 : config.repeatsBeforeCollapse;
        if (counted(r, time) <= limit) {
            write(time, level, type, prefix, message, tag);
            return;
        }
        int threshold = limit + 1;
        if (dump) {
            r = dumps;
            threshold = 1;
            if (counted(r, time) == 1 && r.id == 0) {
                r.id = nextRepeatId++;
                r.preview = "ERROR          stack dumps the game prints around each Lua error (first copies are above)";
            }
        } else if (r.id == 0) {
            r.id = nextRepeatId++;
            r.preview = Text.pad(level, 5) + " " + Text.pad(type, 8) + " " + Text.oneLine(Text.firstLine(message), 150);
        }
        if (r.seen == threshold) {
            note(time, "~~~", "[R" + r.id + "] keeps repeating; further copies are counted in the next collapse summary");
        }
        r.sinceSummary++;
        collapsedTotal++;
        if (!r.inWindow) {
            r.inWindow = true;
            collapsing.add(r);
        }
    }

    // Copies seen so far, starting over after a quiet spell so a line that comes back later is shown again.
    private int counted(Repeat r, long time) {
        if (r.seen > 0 && time - r.lastSeen > config.repeatResetMillis) {
            r.seen = 0;
        }
        r.lastSeen = time;
        return ++r.seen;
    }

    // Lines from the monitor itself (new problems, game state changes). Written even after the size cap.
    void note(long time, String mark, String text) {
        append(Text.clock(time) + " " + Text.pad(mark, 5) + " " + text + "\n", true);
    }

    void maybeSummarize(long now) {
        if (now - windowStart >= config.collapseSummaryMillis) {
            summarize(now);
        }
    }

    void summarize(long now) {
        if (!collapsing.isEmpty()) {
            collapsing.sort((a, b) -> Long.compare(b.sinceSummary, a.sinceSummary));
            long total = 0;
            for (Repeat r : collapsing) {
                total += r.sinceSummary;
            }
            StringBuilder b = new StringBuilder();
            b.append(Text.clock(now)).append(" ~~~   collapsed in the last ").append(duration(now - windowStart)).append(": ")
                .append(Text.plural(total, "line", "lines")).append('\n');
            for (int i = 0; i < collapsing.size(); i++) {
                Repeat r = collapsing.get(i);
                if (i < SUMMARY_ROWS) {
                    b.append(GUTTER).append(Text.padLeft(Text.count(r.sinceSummary), 9)).append("x  ")
                        .append(Text.pad("[R" + r.id + "]", 8)).append(r.preview).append('\n');
                }
                r.sinceSummary = 0;
                r.inWindow = false;
            }
            if (collapsing.size() > SUMMARY_ROWS) {
                b.append(GUTTER).append("          and ").append(collapsing.size() - SUMMARY_ROWS).append(" more repeating lines\n");
            }
            collapsing.clear();
            append(b.toString(), true);
        }
        windowStart = now;
    }

    void flush() {
        if (failed) {
            return;
        }
        try {
            out.flush();
        } catch (IOException e) {
            failed = true;
            Monitor.agentProblem("writing session.log", e);
        }
    }

    void close() {
        try {
            out.close();
        } catch (IOException ignored) {
            // Nothing left to write it to.
        }
    }

    private void write(long time, String level, String type, String prefix, String message, String tag) {
        boolean important = level.equals("ERROR") || level.equals("WARN");
        if (capped && !important) {
            return;
        }
        String p = prefix == null ? "" : prefix.trim();
        StringBuilder b = new StringBuilder(48 + p.length() + message.length());
        b.append(Text.clock(time)).append(' ').append(Text.pad(level, 5)).append(' ').append(Text.pad(type, 8)).append(' ');
        if (tag != null) {
            b.append(tag).append(' ');
        }
        if (!p.isEmpty()) {
            b.append(p).append(" > ");
        }
        b.append(message.indexOf('\r') >= 0 ? message.replace("\r\n", "\n") : message).append('\n');
        append(b.toString(), level.equals("ERROR"));
    }

    private void append(String text, boolean flushNow) {
        if (failed) {
            return;
        }
        try {
            out.write(text);
            bytes += text.length();
            if (!capped && bytes > config.maxSessionLogBytes) {
                capped = true;
                out.write(GUTTER + "session.log reached its size limit (maxSessionLogMB). From here on only errors, warnings and\n"
                    + GUTTER + "Error Monitor notes are written. errors.txt still counts everything.\n");
            }
            if (flushNow) {
                out.flush();
            }
        } catch (IOException e) {
            failed = true;
            Monitor.agentProblem("writing session.log", e);
        }
    }

    // Lines count as copies when they match after numbers and addresses in the first line are masked and
    // everything after the first line (usually a stack trace) is identical.
    private static String key(String level, String type, String prefix, String message) {
        int nl = message.indexOf('\n');
        String first = nl < 0 ? message : message.substring(0, nl);
        int hash = 0;
        int restLength = 0;
        if (nl >= 0) {
            for (int i = nl + 1; i < message.length(); i++) {
                hash = 31 * hash + message.charAt(i);
            }
            restLength = message.length() - nl - 1;
        }
        return level + '|' + type + '|' + (prefix == null ? "" : prefix.trim()) + '|' + Text.normalize(first, 400) + '|' + restLength + ':' + hash;
    }

    private static String duration(long millis) {
        long seconds = Math.max(1, Math.round(millis / 1000.0));
        if (seconds < 120) {
            return seconds + " s";
        }
        long minutes = Math.round(seconds / 60.0);
        return minutes < 120 ? minutes + " min" : Math.round(minutes / 60.0) + " h";
    }
}
