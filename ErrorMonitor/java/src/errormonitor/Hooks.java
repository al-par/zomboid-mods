package errormonitor;

import java.lang.reflect.Method;

// Called from the advice in Patches, inlined into game methods. Nothing here may throw back into the game,
// and a hook that triggers more logging on the same thread is ignored.
public final class Hooks {
    static final String LOG_LINES = "log_lines";
    static final String TRACE_LINES = "stack_trace_lines";
    static final String EXCEPTIONS = "exceptions";
    static final String MESSAGES = "error_and_warning_calls";
    static final String FRAMES = "frame_timing";
    static final String[] ALL = { LOG_LINES, TRACE_LINES, EXCEPTIONS, MESSAGES, FRAMES };

    private static final ThreadLocal<boolean[]> busy = ThreadLocal.withInitial(() -> new boolean[1]);
    private static volatile Method isLogEnabled;
    private static volatile Method getDebugType;
    private static volatile boolean reflectionFailed;

    private Hooks() {
    }

    // DebugLog.echoToLogFiles / echoExceptionLineToLogFiles: every line that reaches the game's log file.
    public static void logged(Object type, Object severity, String prefix, String message) {
        Monitor m = Monitor.instance;
        if (m == null) {
            return;
        }
        boolean[] b = busy.get();
        if (b[0]) {
            return;
        }
        b[0] = true;
        try {
            m.logged(typeName(type), level(severity), prefix, message, System.currentTimeMillis());
        } catch (Throwable t) {
            Monitor.agentProblem("log line hook", t);
        } finally {
            b[0] = false;
        }
    }

    // DebugLogStream.printException(Throwable, message, callerPrefix, severity), before its enabled check.
    public static void exception(Object stream, Throwable t, String message, String prefix, Object severity) {
        Monitor m = Monitor.instance;
        if (m == null || t == null || severity == null) {
            return;
        }
        boolean[] b = busy.get();
        if (b[0]) {
            return;
        }
        b[0] = true;
        try {
            m.exception(typeName(debugType(stream)), enabled(stream, severity), t, message, prefix, level(severity), System.currentTimeMillis());
        } catch (Throwable e) {
            Monitor.agentProblem("exception hook", e);
        } finally {
            b[0] = false;
        }
    }

    // DebugLogStream.writeWithCallerPrefixln, which error() and warn() go through, before its enabled check.
    public static void message(Object stream, Object severity, Object format, Object[] args) {
        Monitor m = Monitor.instance;
        if (m == null || severity == null) {
            return;
        }
        String level = level(severity);
        if (!level.equals("ERROR") && !level.equals("WARN")) {
            return;
        }
        boolean[] b = busy.get();
        if (b[0]) {
            return;
        }
        b[0] = true;
        try {
            m.message(typeName(debugType(stream)), enabled(stream, severity), level, format(format, args), null, System.currentTimeMillis());
        } catch (Throwable e) {
            Monitor.agentProblem("message hook", e);
        } finally {
            b[0] = false;
        }
    }

    // GameWindow.frameStep, once per frame on the main thread.
    public static void frame() {
        Perf p = Perf.instance;
        if (p == null) {
            return;
        }
        try {
            p.frame();
        } catch (Throwable t) {
            Monitor.agentProblem("frame hook", t);
        }
    }

    static String level(Object severity) {
        String name = severity instanceof Enum<?> e ? e.name() : String.valueOf(severity);
        return switch (name) {
            case "Error" -> "ERROR";
            case "Warning" -> "WARN";
            case "General" -> "LOG";
            case "Debug" -> "DEBUG";
            case "Trace" -> "TRACE";
            case "Noise" -> "NOISE";
            default -> name.toUpperCase();
        };
    }

    // System.err is a log stream without a subsystem.
    private static String typeName(Object type) {
        if (type == null) {
            return "stderr";
        }
        return type instanceof Enum<?> e ? e.name() : String.valueOf(type);
    }

    private static String format(Object format, Object[] args) {
        String text = String.valueOf(format);
        if (args == null || args.length == 0) {
            return text;
        }
        try {
            return String.format(text, args);
        } catch (Throwable t) {
            return text;
        }
    }

    private static Object debugType(Object stream) {
        if (!resolve()) {
            return null;
        }
        try {
            return getDebugType.invoke(stream);
        } catch (Throwable t) {
            return null;
        }
    }

    private static boolean enabled(Object stream, Object severity) {
        if (!resolve()) {
            return true;
        }
        try {
            return Boolean.TRUE.equals(isLogEnabled.invoke(stream, severity));
        } catch (Throwable t) {
            return true;
        }
    }

    private static boolean resolve() {
        if (getDebugType != null) {
            return true;
        }
        if (reflectionFailed) {
            return false;
        }
        try {
            Class<?> stream = Class.forName("zombie.debug.DebugLogStream");
            isLogEnabled = stream.getMethod("isLogEnabled", Class.forName("zombie.debug.LogSeverity"));
            getDebugType = stream.getMethod("getDebugType");
            return true;
        } catch (Throwable t) {
            reflectionFailed = true;
            Monitor.agentProblem("looking up DebugLogStream methods", t);
            return false;
        }
    }
}
