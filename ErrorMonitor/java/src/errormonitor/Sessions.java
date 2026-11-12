package errormonitor;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

// Session folders under Zomboid/ErrorMonitor, one per game launch. session.state says whether the
// session is still running; a session that stays "running" after its process is gone never shut down.
final class Sessions {
    static final String STATE_FILE = "session.state";
    static final String JVM_CRASH_LOG = "jvm-crash.log";
    static final String JVM_CRASH_RECORDING = "jvm-crash.jfr";
    private static final Pattern NAME = Pattern.compile("\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}(_\\d+)?");

    private Sessions() {
    }

    static File create(File root, long now) throws IOException {
        root.mkdirs();
        String base = Text.folderName(now);
        File dir = new File(root, base);
        for (int i = 2; dir.exists(); i++) {
            dir = new File(root, base + "_" + i);
        }
        if (!dir.mkdirs()) {
            throw new IOException("could not create " + dir);
        }
        writeState(dir, "running", now);
        return dir;
    }

    static void writeState(File dir, String status, long time) {
        String text = "pid=" + ProcessHandle.current().pid() + "\nstatus=" + status + "\nupdated=" + Text.dateTime(time) + "\n";
        try {
            Files.writeString(new File(dir, STATE_FILE).toPath(), text, StandardCharsets.UTF_8);
        } catch (IOException e) {
            Monitor.agentProblem("writing " + STATE_FILE, e);
        }
    }

    // Marks sessions that never shut down and returns the newest one's folder name, or null.
    static String markUnfinished(File root, long now) {
        String newest = null;
        for (File dir : list(root)) {
            Map<String, String> state = readState(dir);
            if (!"running".equals(state.get("status"))) {
                continue;
            }
            long pid = parseLong(state.get("pid"));
            if (isGameProcessAlive(pid)) {
                continue;
            }
            boolean crashLog = copyJvmCrashLog(dir, pid);
            try {
                Files.writeString(new File(dir, STATE_FILE).toPath(),
                    "pid=" + pid + "\nstatus=unfinished\nupdated=" + Text.dateTime(now) + "\n", StandardCharsets.UTF_8);
            } catch (IOException e) {
                Monitor.agentProblem("updating " + dir.getName(), e);
            }
            markReport(dir, now, crashLog);
            newest = dir.getName();
        }
        return newest;
    }

    static void prune(File root, int keep) {
        List<File> sessions = list(root);
        for (int i = 0; i < sessions.size() - keep; i++) {
            delete(sessions.get(i));
        }
    }

    // Flight recordings are large, so only the newest few sessions keep theirs.
    static void pruneRecordings(File root, int keep) {
        List<File> sessions = list(root);
        for (int i = 0; i < sessions.size() - keep; i++) {
            new File(sessions.get(i), Jfr.FILE).delete();
            new File(sessions.get(i), JVM_CRASH_RECORDING).delete();
        }
    }

    private static List<File> list(File root) {
        List<File> result = new ArrayList<>();
        File[] children = root.listFiles();
        if (children == null) {
            return result;
        }
        for (File f : children) {
            if (f.isDirectory() && NAME.matcher(f.getName()).matches() && new File(f, STATE_FILE).isFile()) {
                result.add(f);
            }
        }
        result.sort((a, b) -> a.getName().compareTo(b.getName()));
        return result;
    }

    private static Map<String, String> readState(File dir) {
        Map<String, String> state = new HashMap<>();
        try {
            for (String line : Files.readAllLines(new File(dir, STATE_FILE).toPath(), StandardCharsets.UTF_8)) {
                int eq = line.indexOf('=');
                if (eq > 0) {
                    state.put(line.substring(0, eq), line.substring(eq + 1));
                }
            }
        } catch (IOException ignored) {
            // Treated as an empty state: the folder is left alone.
        }
        return state;
    }

    // A reused PID belongs to some other program, so only a live Java or game process counts.
    private static boolean isGameProcessAlive(long pid) {
        if (pid <= 0) {
            return false;
        }
        return ProcessHandle.of(pid).filter(ProcessHandle::isAlive).flatMap(p -> p.info().command())
            .map(cmd -> {
                String c = cmd.toLowerCase();
                return c.contains("java") || c.contains("zomboid");
            }).orElse(false);
    }

    // The JVM writes hs_err_pid<pid>.log into the game's working directory when it crashes natively, and
    // JDK Flight Recorder writes an emergency hs_err_pid<pid>.jfr next to it.
    private static boolean copyJvmCrashLog(File dir, long pid) {
        if (pid <= 0) {
            return false;
        }
        copy(new File(System.getProperty("user.dir", "."), "hs_err_pid" + pid + ".jfr"), new File(dir, JVM_CRASH_RECORDING));
        return copy(new File(System.getProperty("user.dir", "."), "hs_err_pid" + pid + ".log"), new File(dir, JVM_CRASH_LOG));
    }

    private static boolean copy(File from, File to) {
        if (!from.isFile()) {
            return false;
        }
        try {
            Files.copy(from.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING);
            return true;
        } catch (IOException e) {
            Monitor.agentProblem("copying " + from, e);
            return false;
        }
    }

    private static void markReport(File dir, long now, boolean crashLog) {
        String status = Report.STATUS_LABEL + "did not end cleanly: the game crashed, hung and was closed, or the PC shut down"
            + "\n          (noticed at the next launch, " + Text.dateTime(now) + "). The end of session.log shows what was happening."
            + (crashLog ? "\n          The Java runtime wrote a crash report: " + JVM_CRASH_LOG : "");
        File report = new File(dir, Monitor.REPORT_FILE);
        try {
            if (report.isFile()) {
                List<String> lines = Files.readAllLines(report.toPath(), StandardCharsets.UTF_8);
                for (int i = 0; i < lines.size(); i++) {
                    if (lines.get(i).startsWith(Report.STATUS_LABEL)) {
                        lines.set(i, status);
                        break;
                    }
                }
                Files.writeString(report.toPath(), String.join("\n", lines) + "\n", StandardCharsets.UTF_8);
            }
            File log = new File(dir, Monitor.LOG_FILE);
            if (log.isFile()) {
                Files.writeString(log.toPath(), Text.clock(now) + " ===   no clean shutdown: the log ends where the game stopped (noticed at the next launch)\n",
                    StandardCharsets.UTF_8, StandardOpenOption.APPEND);
            }
        } catch (IOException e) {
            Monitor.agentProblem("marking " + dir.getName() + " as unfinished", e);
        }
    }

    private static void delete(File f) {
        File[] children = f.listFiles();
        if (children != null) {
            for (File c : children) {
                delete(c);
            }
        }
        f.delete();
    }

    private static long parseLong(String s) {
        try {
            return s == null ? 0 : Long.parseLong(s.trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
