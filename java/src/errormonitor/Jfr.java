package errormonitor;

import java.io.File;
import java.time.Duration;
import jdk.jfr.Configuration;
import jdk.jfr.Recording;

// A continuous JDK Flight Recorder recording, kept on disk with an age and size limit and written into the
// session folder when the JVM exits. JFR's "default" settings are the ones meant to stay on in production.
final class Jfr {
    static final String FILE = "performance.jfr";
    static volatile String status = "JDK Flight Recorder is off (jfr=false in config.properties).";

    private Jfr() {
    }

    static void startInBackground(File dir, Config config) {
        status = "JDK Flight Recorder is starting.";
        Thread t = new Thread(() -> start(dir, config), "ErrorMonitor-jfr");
        t.setDaemon(true);
        t.start();
    }

    private static void start(File dir, Config config) {
        try {
            Recording r = new Recording(Configuration.getConfiguration("default"));
            r.setName("ErrorMonitor");
            r.setToDisk(true);
            r.setMaxAge(Duration.ofMinutes(config.jfrMaxAgeMinutes));
            r.setMaxSize(config.jfrMaxBytes);
            r.setDestination(new File(dir, FILE).toPath());
            r.setDumpOnExit(true);
            r.start();
            status = FILE + " in this folder is written when the game closes: JDK Flight Recorder data (CPU, GC,\n"
                + "            memory, threads, file I/O) for the last " + config.jfrMaxAgeMinutes + " minutes. Open it with JDK Mission Control.";
        } catch (Throwable t) {
            status = "JDK Flight Recorder could not start: " + t;
            Monitor.agentProblem("starting JDK Flight Recorder", t);
        }
    }
}
