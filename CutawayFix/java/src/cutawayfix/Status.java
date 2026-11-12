package cutawayfix;

import java.io.File;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.LinkedHashMap;
import java.util.Map;

// Read by the Lua half of the mod. The file only exists while a JVM with the agent is running, so a
// leftover file from an earlier launch can't make Lua report the patch as active.
final class Status {
    static final String FILE_NAME = "CutawayFix_status.txt";

    private static final Map<String, String> results = new LinkedHashMap<>();
    private static File file;

    private Status() {
    }

    static synchronized void begin() {
        file = new File(new File(cacheDir(), "Lua"), FILE_NAME);
        file.deleteOnExit();
        write();
        log("agent loaded, status file " + file);
    }

    static synchronized void applied(String patch) {
        results.put(patch, "applied");
        write();
        log(patch + ": applied");
    }

    static synchronized void skipped(String patch, String reason) {
        results.put(patch, "skipped");
        write();
        log(patch + ": SKIPPED (" + reason + ")");
    }

    static synchronized void error(String where, Throwable t) {
        results.put("error", where + ": " + t);
        write();
        StringWriter trace = new StringWriter();
        t.printStackTrace(new PrintWriter(trace));
        log("ERROR in " + where + "\n" + trace);
    }

    private static File cacheDir() {
        String dir = System.getProperty("deployment.user.cachedir");
        if (dir == null || dir.isEmpty()) {
            dir = System.getProperty("user.home");
        }
        return new File(dir, "Zomboid");
    }

    private static void write() {
        if (file == null) {
            return;
        }
        StringBuilder text = new StringBuilder("agent=loaded\n");
        for (Map.Entry<String, String> entry : results.entrySet()) {
            text.append(entry.getKey()).append('=').append(entry.getValue()).append('\n');
        }
        try {
            file.getParentFile().mkdirs();
            Files.writeString(file.toPath(), text, StandardCharsets.UTF_8);
        } catch (IOException e) {
            log("could not write " + file + ": " + e);
        }
    }

    private static void log(String message) {
        System.out.println("[CutawayFix] " + message);
    }
}
