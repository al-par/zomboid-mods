package errormonitor;

import java.io.PrintStream;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.debug.DebugLogStream;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

// Each hook runs at the very start of a game method and hands its arguments to Hooks, which never throws.
// The argument types select the overload: ZombieBuddy matches methods by them.
public final class Patches {

    // Every line that reaches the game's log file.
    @Patch(className = "zombie.debug.DebugLog", methodName = "echoToLogFiles")
    public static final class LogLines {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) DebugType type, @Patch.Argument(1) LogSeverity severity,
                                 @Patch.Argument(2) String prefix, @Patch.Argument(3) String message) {
            Hooks.logged(type, severity, prefix, message);
        }
    }

    // The third argument is a label ("StackTrace"), not a caller prefix.
    @Patch(className = "zombie.debug.DebugLog", methodName = "echoExceptionLineToLogFiles")
    public static final class TraceLines {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) DebugType type, @Patch.Argument(1) LogSeverity severity,
                                 @Patch.Argument(2) String label, @Patch.Argument(3) String message) {
            Hooks.logged(type, severity, "", message);
        }
    }

    // printException(Throwable, message, callerPrefix, severity), before its enabled check.
    @Patch(className = "zombie.debug.DebugLogStream", methodName = "printException")
    public static final class Exceptions {
        @Patch.OnEnter
        public static void enter(@Patch.This DebugLogStream stream, @Patch.Argument(0) Throwable t, @Patch.Argument(1) String message,
                                 @Patch.Argument(2) String prefix, @Patch.Argument(3) LogSeverity severity) {
            Hooks.exception(stream, t, message, prefix, severity);
        }
    }

    // writeWithCallerPrefixln(PrintStream, severity, int, boolean, format, args...), which error() and warn() go through.
    @Patch(className = "zombie.debug.DebugLogStream", methodName = "writeWithCallerPrefixln")
    public static final class Messages {
        @Patch.OnEnter
        public static void enter(@Patch.This DebugLogStream stream, @Patch.Argument(0) PrintStream out, @Patch.Argument(1) LogSeverity severity,
                                 @Patch.Argument(4) Object format, @Patch.Argument(5) Object[] args) {
            Hooks.message(stream, severity, format, args);
        }
    }

    // Once per frame on the main thread.
    @Patch(className = "zombie.GameWindow", methodName = "frameStep")
    public static final class Frames {
        @Patch.OnEnter
        public static void enter() {
            Hooks.frame();
        }
    }

    private Patches() {}
}
