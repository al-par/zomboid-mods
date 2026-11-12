package errormonitor;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;
import java.util.WeakHashMap;

// Reads the main Lua thread's call stack from another thread, the way se.krka.kahlua.profiler.Sampler does.
// The fields are read without synchronization, so now and then a frame is stale or the read throws; the
// caller drops that sample. Only the sampler thread uses this class.
final class LuaStack {
    // One Lua function. The same function loaded again after a Lua reload maps to the same Site.
    static final class Site {
        final String function;
        final String file;
        final String mod;

        Site(String function, String file, String mod) {
            this.function = function;
            this.file = file;
            this.mod = mod;
        }

        String owner() {
            return mod == null ? Perf.VANILLA : mod;
        }
    }

    private Field managerThread;
    private Field currentCoroutine;
    private Method callframeStack;
    private Method callframeTop;
    private Method parent;
    private Field closure;
    private Field pc;
    private Field prototype;
    private Field lines;
    private Method toStackTraceElement;

    private final Map<Object, Site> byPrototype = new WeakHashMap<>();
    private final Map<String, Site> interned = new HashMap<>();

    // Must not run before the game has initialized LuaManager: reading its static field would run the
    // class initializer on this thread.
    void resolve() throws ReflectiveOperationException {
        ClassLoader loader = ClassLoader.getSystemClassLoader();
        Class<?> manager = Class.forName("zombie.Lua.LuaManager", false, loader);
        Class<?> thread = Class.forName("se.krka.kahlua.vm.KahluaThread", false, loader);
        Class<?> coroutine = Class.forName("se.krka.kahlua.vm.Coroutine", false, loader);
        Class<?> frame = Class.forName("se.krka.kahlua.vm.LuaCallFrame", false, loader);
        Class<?> luaClosure = Class.forName("se.krka.kahlua.vm.LuaClosure", false, loader);
        Class<?> proto = Class.forName("se.krka.kahlua.vm.Prototype", false, loader);
        managerThread = manager.getField("thread");
        currentCoroutine = thread.getField("currentCoroutine");
        callframeStack = coroutine.getMethod("getCallframeStack");
        callframeTop = coroutine.getMethod("getCallframeTop");
        parent = coroutine.getMethod("getParent");
        closure = frame.getField("closure");
        pc = frame.getField("pc");
        prototype = luaClosure.getField("prototype");
        lines = proto.getField("lines");
        toStackTraceElement = luaClosure.getMethod("toStackTraceElement", int.class);
    }

    // Fills `sites` and `lineNumbers` innermost first and returns the depth; 0 when no Lua is running.
    int read(Site[] sites, int[] lineNumbers) throws ReflectiveOperationException {
        Object thread = managerThread.get(null);
        if (thread == null) {
            return 0;
        }
        int n = 0;
        Object co = currentCoroutine.get(thread);
        for (int guard = 0; co != null && guard < 32 && n < sites.length; guard++) {
            Object[] frames = (Object[]) callframeStack.invoke(co);
            int top = Math.min(frames.length, (Integer) callframeTop.invoke(co));
            for (int i = top - 1; i >= 0 && n < sites.length; i--) {
                Object f = frames[i];
                Object c = f == null ? null : closure.get(f);
                if (c == null) {
                    continue;
                }
                int framePc = pc.getInt(f);
                Object p = prototype.get(c);
                Site site = byPrototype.get(p);
                if (site == null) {
                    site = describe(c, framePc);
                    byPrototype.put(p, site);
                }
                int[] l = (int[]) lines.get(p);
                int index = framePc - 1;
                sites[n] = site;
                lineNumbers[n] = l != null && index >= 0 && index < l.length ? l[index] : 0;
                n++;
            }
            co = parent.invoke(co);
        }
        return n;
    }

    // The game's own naming, as in its stack traces: "Lua((MOD:Name)).function(File.lua:12)".
    private Site describe(Object luaClosure, int framePc) throws ReflectiveOperationException {
        StackTraceElement e = (StackTraceElement) toStackTraceElement.invoke(luaClosure, framePc);
        String function = e.getMethodName() == null || e.getMethodName().isEmpty() ? "?" : e.getMethodName();
        String file = e.getFileName() == null ? "?" : e.getFileName();
        String mod = Trace.luaMod(e.toString());
        String key = (mod == null ? "" : mod) + '|' + function + '|' + file;
        return interned.computeIfAbsent(key, k -> new Site(function, file, mod));
    }
}
