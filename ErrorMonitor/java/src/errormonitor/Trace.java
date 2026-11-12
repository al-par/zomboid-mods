package errormonitor;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;

// One exception and its causes, with each stack frame kept as the text StackTraceElement.toString() gives.
// Lua frames look like "Lua((MOD:Mod Name)).function(File.lua:12)" or "Lua(Vanilla).function(File.lua:12)".
final class Trace {
    private static final int MAX_CAUSES = 6;
    private static volatile Method gameStackTrace;
    private static volatile boolean gameStackTraceMissing;

    final String className;
    final String message;
    final List<String> frames;
    final Trace cause;

    Trace(String className, String message, List<String> frames, Trace cause) {
        this.className = className;
        this.message = message;
        this.frames = frames;
        this.cause = cause;
    }

    static Trace of(Throwable t) {
        return of(t, Collections.newSetFromMap(new IdentityHashMap<>()), 0);
    }

    private static Trace of(Throwable t, java.util.Set<Throwable> seen, int depth) {
        seen.add(t);
        List<String> frames = new ArrayList<>();
        for (StackTraceElement e : stackOf(t)) {
            frames.add(e.toString());
        }
        Throwable c = t.getCause();
        Trace cause = c != null && depth < MAX_CAUSES && !seen.contains(c) ? of(c, seen, depth + 1) : null;
        return new Trace(t.getClass().getName(), t.getMessage(), frames, cause);
    }

    // The stack of the calling thread, with Lua frames merged in, minus the frames of the logging code itself.
    static List<String> callerStack() {
        List<String> frames = new ArrayList<>();
        StackTraceElement[] all = stackOf(new Throwable());
        int start = 0;
        while (start < all.length && isLoggingFrame(all[start].getClassName())) {
            start++;
        }
        for (int i = start; i < all.length; i++) {
            frames.add(all[i].toString());
        }
        return frames;
    }

    // Build 42 only adds Lua frames to a Java stack trace when it prints one, through StackTraceContainer.
    // This has to run while the failing Lua call is still on the stack, which is the case inside the hooks.
    private static StackTraceElement[] stackOf(Throwable t) {
        Method m = gameStackTrace;
        if (m == null && !gameStackTraceMissing) {
            try {
                m = Class.forName("zombie.debug.StackTraceContainer").getMethod("getStackTrace", Throwable.class);
                gameStackTrace = m;
            } catch (Throwable e) {
                gameStackTraceMissing = true;
            }
        }
        if (m != null) {
            try {
                Object result = m.invoke(null, t);
                if (result instanceof StackTraceElement[] elements && elements.length > 0) {
                    return elements;
                }
            } catch (Throwable ignored) {
                // Fall back to the plain Java stack below.
            }
        }
        return t.getStackTrace();
    }

    // Parses "pkg.SomeException: message" followed by frame lines ("at x.y(Z.java:1)" or bare "x.y(Z.java:1)"),
    // with "Caused by: ..." starting a nested exception.
    static Trace parse(List<String> lines) {
        List<Trace> chain = new ArrayList<>();
        String cls = null;
        String msg = null;
        List<String> frames = null;
        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("...") || line.equals("Stack trace:")) {
                continue;
            }
            boolean causedBy = line.startsWith("Caused by: ");
            if (cls == null || causedBy) {
                if (cls != null) {
                    chain.add(new Trace(cls, msg, frames, null));
                }
                String header = causedBy ? line.substring("Caused by: ".length()) : line;
                int colon = header.indexOf(": ");
                String head = colon < 0 ? header : header.substring(0, colon);
                if (looksLikeClassName(head)) {
                    cls = head;
                    msg = colon < 0 ? null : header.substring(colon + 2);
                } else {
                    cls = "unknown";
                    msg = header;
                }
                frames = new ArrayList<>();
                continue;
            }
            frames.add(line.startsWith("at ") ? line.substring(3) : line);
        }
        if (cls != null) {
            chain.add(new Trace(cls, msg, frames, null));
        }
        if (chain.isEmpty()) {
            return null;
        }
        Trace result = null;
        for (int i = chain.size() - 1; i >= 0; i--) {
            Trace t = chain.get(i);
            result = new Trace(t.className, t.message, t.frames, result);
        }
        return result;
    }

    static boolean looksLikeClassName(String s) {
        if (s.isEmpty() || s.indexOf('.') < 0) {
            return false;
        }
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (!(Character.isJavaIdentifierPart(c) || c == '.')) {
                return false;
            }
        }
        return true;
    }

    // ---- frame helpers ----

    static boolean isLua(String frame) {
        return frame.startsWith("Lua(");
    }

    // Mod name of a Lua frame, or null for vanilla Lua and Java frames.
    static String luaMod(String frame) {
        if (!frame.startsWith("Lua((MOD:")) {
            return null;
        }
        int end = frame.indexOf(")).", 9);
        return end < 0 ? null : frame.substring(9, end);
    }

    // "function  File.lua:12" for a Lua frame.
    static String luaShort(String frame) {
        int dot = frame.startsWith("Lua((MOD:") ? frame.indexOf(")).", 9) + 2 : frame.indexOf(").") + 1;
        if (dot <= 0 || dot >= frame.length()) {
            return frame;
        }
        String rest = frame.substring(dot + 1);
        int paren = rest.lastIndexOf('(');
        if (paren < 0 || !rest.endsWith(")")) {
            return rest;
        }
        return rest.substring(0, paren) + "  " + rest.substring(paren + 1, rest.length() - 1);
    }

    static String location(String frame) {
        int paren = frame.lastIndexOf('(');
        return paren >= 0 && frame.endsWith(")") ? frame.substring(paren + 1, frame.length() - 1) : frame;
    }

    static boolean isEngineFrame(String frame) {
        String f = stripModule(frame);
        return f.startsWith("se.krka.kahlua.") || f.startsWith("java.") || f.startsWith("jdk.") || f.startsWith("sun.")
            || f.startsWith("zombie.Lua.Event.") || f.startsWith("zombie.Lua.LuaEventManager.")
            || f.startsWith("zombie.GameWindow.") || f.startsWith("zombie.MainThread.") || f.startsWith("zombie.gameStates.GameStateMachine.");
    }

    private static boolean isLoggingFrame(String cls) {
        return cls.startsWith("errormonitor.") || cls.startsWith("zombie.debug.") || cls.startsWith("zombie.core.logger.")
            || cls.equals("java.lang.Throwable") || cls.equals("java.lang.Thread");
    }

    // Drops the "java.base/" or "app//" prefix StackTraceElement.toString() puts on Java frames.
    static String stripModule(String frame) {
        if (isLua(frame)) {
            return frame;
        }
        int paren = frame.indexOf('(');
        int slash = frame.lastIndexOf('/', paren < 0 ? frame.length() - 1 : paren);
        return slash >= 0 ? frame.substring(slash + 1) : frame;
    }

    // The frames of this trace and all causes, outermost first.
    List<String> allFrames() {
        List<String> all = new ArrayList<>();
        for (Trace t = this; t != null; t = t.cause) {
            all.addAll(t.frames);
        }
        return all;
    }

    Trace root() {
        Trace t = this;
        while (t.cause != null) {
            t = t.cause;
        }
        return t;
    }

    static Map<String, Integer> modsIn(List<String> frames) {
        Map<String, Integer> mods = new java.util.LinkedHashMap<>();
        for (String f : frames) {
            String mod = luaMod(f);
            if (mod != null) {
                mods.merge(mod, 1, Integer::sum);
            }
        }
        return mods;
    }
}
