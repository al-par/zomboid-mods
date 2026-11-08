package errormonitor;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Properties;

final class Config {
    static final String FILE_NAME = "config.properties";

    private static final String DEFAULTS = String.join("\n",
        "# Error Monitor settings. Changes apply the next time the game starts.",
        "",
        "# Session folders to keep. The oldest are deleted at launch.",
        "keepSessions=3",
        "",
        "# A log line that repeats is written in full this many times. After that its copies are",
        "# counted, and session.log gets one summary of the counts every collapseSummarySeconds.",
        "repeatsBeforeCollapse=3",
        "collapseSummarySeconds=60",
        "",
        "# A collapsed line that has not appeared for this many minutes is written in full again.",
        "repeatResetMinutes=10",
        "",
        "# Log lines shown in errors.txt under each problem, leading up to its first occurrence.",
        "contextLines=12",
        "",
        "# Past this size session.log only takes errors, warnings and summaries.",
        "maxSessionLogMB=100",
        "",
        "# Record errors and warnings from subsystems switched Off in debuglog.ini. The game drops",
        "# those without a trace, including from its own log.",
        "captureSilencedSubsystems=true",
        "",
        "# List warnings in errors.txt, below the errors.",
        "reportWarnings=true",
        "",
        "# ---- performance (perf.txt) ----",
        "# Frame times, hitches, freezes, GC, and Lua time by mod and function. The Lua profile comes from",
        "# sampling the Lua call stack on a separate thread every sampleIntervalMs; the game thread only",
        "# reads the clock once per frame.",
        "performanceMonitoring=true",
        "sampleIntervalMs=5",
        "",
        "# A frame this long or longer is a hitch. No frame for freezeSeconds is a freeze; the monitor then",
        "# records where the main thread is stuck, in Lua and Java.",
        "hitchMs=100",
        "freezeSeconds=2",
        "",
        "# JDK Flight Recorder: Java-level CPU, GC, memory and thread data, written to performance.jfr in",
        "# the session folder when the game closes. Open it with JDK Mission Control. Its own overhead is",
        "# about 1%. Recordings are kept for the newest jfrKeepSessions sessions only.",
        "jfr=true",
        "jfrMaxAgeMinutes=30",
        "jfrMaxMB=200",
        "jfrKeepSessions=3",
        "");

    final int keepSessions;
    final int repeatsBeforeCollapse;
    final long collapseSummaryMillis;
    final long repeatResetMillis;
    final int contextLines;
    final long maxSessionLogBytes;
    final boolean captureSilenced;
    final boolean reportWarnings;
    final boolean performance;
    final int sampleMicros;
    final int hitchMillis;
    final int freezeMillis;
    final boolean jfr;
    final int jfrMaxAgeMinutes;
    final long jfrMaxBytes;
    final int jfrKeepSessions;

    private Config(Properties p) {
        keepSessions = intValue(p, "keepSessions", 3, 1, 10000);
        repeatsBeforeCollapse = intValue(p, "repeatsBeforeCollapse", 3, 1, 1000);
        collapseSummaryMillis = intValue(p, "collapseSummarySeconds", 60, 5, 86400) * 1000L;
        repeatResetMillis = intValue(p, "repeatResetMinutes", 10, 1, 1440) * 60_000L;
        contextLines = intValue(p, "contextLines", 12, 0, 200);
        maxSessionLogBytes = intValue(p, "maxSessionLogMB", 100, 1, 100_000) * 1024L * 1024L;
        captureSilenced = boolValue(p, "captureSilencedSubsystems", true);
        reportWarnings = boolValue(p, "reportWarnings", true);
        performance = boolValue(p, "performanceMonitoring", true);
        sampleMicros = intValue(p, "sampleIntervalMs", 5, 1, 1000) * 1000;
        hitchMillis = intValue(p, "hitchMs", 100, 20, 60_000);
        freezeMillis = intValue(p, "freezeSeconds", 2, 1, 3600) * 1000;
        jfr = boolValue(p, "jfr", true);
        jfrMaxAgeMinutes = intValue(p, "jfrMaxAgeMinutes", 30, 1, 1440);
        jfrMaxBytes = intValue(p, "jfrMaxMB", 200, 10, 100_000) * 1024L * 1024L;
        jfrKeepSessions = intValue(p, "jfrKeepSessions", 3, 0, 1000);
    }

    static Config defaults() {
        return new Config(new Properties());
    }

    static Config load(File dir) {
        File file = new File(dir, FILE_NAME);
        Properties p = new Properties();
        try {
            if (!file.exists()) {
                dir.mkdirs();
                Files.writeString(file.toPath(), DEFAULTS, StandardCharsets.UTF_8);
            }
            try (InputStream in = new FileInputStream(file)) {
                p.load(in);
            }
        } catch (IOException e) {
            Monitor.agentProblem("reading " + file, e);
        }
        return new Config(p);
    }

    private static int intValue(Properties p, String key, int fallback, int min, int max) {
        String raw = p.getProperty(key);
        if (raw == null) {
            return fallback;
        }
        try {
            return Math.max(min, Math.min(max, Integer.parseInt(raw.trim())));
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static boolean boolValue(Properties p, String key, boolean fallback) {
        String raw = p.getProperty(key);
        return raw == null ? fallback : Boolean.parseBoolean(raw.trim());
    }
}
