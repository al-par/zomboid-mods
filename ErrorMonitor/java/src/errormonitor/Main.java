package errormonitor;

// ZombieBuddy runs this when it loads the mod's jar, and applies the hooks in Patches itself.
public final class Main {
    private Main() {
    }

    public static void main(String[] args) {
        try {
            if (Monitor.instance != null) {
                return;
            }
            Monitor.start();
            Monitor m = Monitor.instance;
            if (m == null) {
                return;
            }
            for (String hook : Hooks.ALL) {
                boolean off = hook.equals(Hooks.FRAMES) && Perf.instance == null;
                m.hookStatus(hook, off ? "off (performanceMonitoring=false)" : "applied");
            }
        } catch (Throwable t) {
            System.out.println("[ErrorMonitor] failed to start: " + t);
        }
    }
}
