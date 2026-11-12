package errormonitor;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Runs an existing DebugLog.txt or console.txt through the same processing as a live session:
//   java -jar ErrorMonitor-agent.jar <log file> [output folder]
// Live sessions see more than a log file holds (silenced subsystems, Lua frames of Java exceptions, mod
// IDs), so a replay is a best effort reconstruction.
public final class Replay {
    private static final Pattern HEADER = Pattern.compile(
        "^(?:\\[(\\d\\d)-(\\d\\d)-(\\d\\d) (\\d\\d):(\\d\\d):(\\d\\d)\\.(\\d{3})\\] )?(LOG|WARN|ERROR|DEBUG|TRACE|NOISE)\\s*:\\s*(\\S+)\\s+([^>]*?)>\\s?(.*)$");
    private static final Pattern EXCEPTION = Pattern.compile("(?s)^(.*?)> ?Exception thrown(.*)$");

    private record Entry(long time, String level, String type, String caller, String message) {
    }

    private Replay() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.out.println("Usage: java -jar ErrorMonitor-agent.jar <DebugLog.txt or console.txt> [output folder]");
            return;
        }
        File input = new File(args[0]);
        String base = input.getName().replaceFirst("\\.[^.]+$", "");
        File out = args.length > 1 ? new File(args[1]) : new File(input.getAbsoluteFile().getParentFile(), base + "-ErrorMonitor");
        out.mkdirs();
        new File(out, Monitor.LOG_FILE).delete();
        new File(out, Monitor.REPORT_FILE).delete();

        List<Entry> entries = parse(new String(Files.readAllBytes(input.toPath()), StandardCharsets.UTF_8), input.lastModified());
        long start = entries.isEmpty() ? input.lastModified() : entries.get(0).time;
        Monitor m = new Monitor(Config.defaults(), out, start, false, null, input.getName());
        long last = start;
        for (Entry e : entries) {
            feed(m, e);
            last = e.time;
        }
        m.shutdown(last);
        System.out.println(Text.plural(m.errors.size(), "error", "errors") + " (" + Text.plural(m.errorTotal, "time", "times") + "), "
            + Text.plural(m.warnings.size(), "warning", "warnings") + " (" + Text.plural(m.warningTotal, "time", "times") + ") from "
            + Text.plural(entries.size(), "log record", "log records"));
        System.out.println("Report: " + new File(out, Monitor.REPORT_FILE).getAbsolutePath());
    }

    private static void feed(Monitor m, Entry e) {
        if (e.level.equals("ERROR") || e.level.equals("WARN")) {
            Matcher ex = EXCEPTION.matcher(e.message);
            if (ex.matches()) {
                String[] contextMessage = new String[1];
                Trace trace = parseException(ex.group(2), contextMessage);
                if (trace != null) {
                    m.exception(e.type, true, trace, contextMessage[0], ex.group(1), e.level, e.time);
                }
            } else if (e.caller != null) {
                m.message(e.type, true, e.level, e.message, e.caller, e.time);
            }
        }
        m.logged(e.type, e.level, e.caller, e.message, e.time);
    }

    // The game prints "<prefix>> Exception thrown", then "\t<exception> at <top frame>.[ Message: <text>]",
    // then "\tStack trace:" and the frames.
    private static Trace parseException(String body, String[] contextMessage) {
        List<String> lines = new ArrayList<>(Arrays.asList(body.split("\r?\n")));
        while (!lines.isEmpty() && lines.get(0).isBlank()) {
            lines.remove(0);
        }
        if (lines.isEmpty()) {
            return null;
        }
        String head = lines.get(0).trim();
        int message = head.indexOf("). Message: ");
        if (message >= 0) {
            contextMessage[0] = head.substring(message + "). Message: ".length());
            head = head.substring(0, message + 1);
        } else if (head.endsWith(").")) {
            head = head.substring(0, head.length() - 1);
        }
        int at = head.lastIndexOf(" at ");
        if (at > 0 && head.endsWith(")")) {
            head = head.substring(0, at);
        }
        lines.set(0, head);
        return Trace.parse(lines);
    }

    private static List<Entry> parse(String text, long fallbackTime) {
        List<Entry> entries = new ArrayList<>();
        String[] lines = text.split("\r?\n", -1);
        long time = fallbackTime;
        String level = null;
        String type = null;
        String caller = null;
        StringBuilder message = null;
        boolean timestamped = false;
        for (String line : lines) {
            Matcher h = HEADER.matcher(line);
            if (h.matches()) {
                if (message != null) {
                    entries.add(new Entry(time, level, type, caller, finish(message, timestamped)));
                }
                timestamped = h.group(1) != null;
                if (timestamped) {
                    time = LocalDateTime.of(2000 + Integer.parseInt(h.group(3)), Integer.parseInt(h.group(2)), Integer.parseInt(h.group(1)),
                        Integer.parseInt(h.group(4)), Integer.parseInt(h.group(5)), Integer.parseInt(h.group(6)), Integer.parseInt(h.group(7)) * 1_000_000)
                        .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
                }
                level = h.group(8);
                type = h.group(9);
                String area = h.group(10);
                int at = area.indexOf(" at ");
                caller = at >= 0 ? area.substring(at + 4).trim() : null;
                message = new StringBuilder(h.group(11));
            } else if (message != null) {
                message.append('\n').append(line);
            }
        }
        if (message != null) {
            entries.add(new Entry(time, level, type, caller, finish(message, timestamped)));
        }
        return entries;
    }

    // DebugLog.txt (the timestamped format) ends every record with a '.' the message did not have.
    private static String finish(StringBuilder message, boolean timestamped) {
        String s = message.toString().stripTrailing();
        return timestamped && s.endsWith(".") ? s.substring(0, s.length() - 1) : s;
    }
}
