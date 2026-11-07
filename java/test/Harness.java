import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

// Runs the agent against the real game classes outside the game. Run with the game's own JRE:
//   java -javaagent:ErrorMonitor-agent.jar -Ddeployment.user.cachedir=<temp> -cp projectzomboid.jar;<this dir> Harness
// Everything is reflective so this compiles without the game jar.
public class Harness {
    static final ClassLoader L = ClassLoader.getSystemClassLoader();
    static final java.io.PrintStream OUT = new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out), true);

    public static void main(String[] args) {
        try {
            run();
        } catch (Throwable t) {
            OUT.println("HARNESS FAILED");
            t.printStackTrace(OUT);
            System.exit(1);
        }
    }

    static void run() throws Exception {
        File cache = new File(System.getProperty("deployment.user.cachedir"), "Zomboid");
        // As MainScreenState.main does before anything logs.
        step("Rand init", () -> {
            for (String r : new String[] { "zombie.core.random.RandStandard", "zombie.core.random.RandLua" }) {
                call(cls(r).getField("INSTANCE").get(null), "init");
            }
        });
        step("DebugLog.init", () -> call(cls("zombie.debug.DebugLog").getMethod("getInstance").invoke(null), "init"));

        Object general = cls("zombie.debug.DebugType").getField("General").get(null);
        Class<?> severity = cls("zombie.debug.LogSeverity");
        Object error = Enum.valueOf((Class) severity, "Error");
        Object warning = Enum.valueOf((Class) severity, "Warning");

        step("error()", () -> general.getClass().getMethod("error", Object.class).invoke(general, "Harness error number 1"));
        step("error() again", () -> general.getClass().getMethod("error", Object.class).invoke(general, "Harness error number 2"));
        step("warn()", () -> general.getClass().getMethod("warn", Object.class).invoke(general, "Harness warning"));
        for (int i = 0; i < 5; i++) {
            step("printException " + i, () -> general.getClass().getMethod("printException", Throwable.class, severity)
                .invoke(general, new IllegalStateException("harness boom"), error));
        }
        step("silenced subsystem", () -> {
            Object mod = cls("zombie.debug.DebugType").getField("Mod").get(null);
            cls("zombie.debug.DebugLog").getMethod("setLogEnabled", cls("zombie.debug.DebugType"), boolean.class).invoke(null, mod, false);
            mod.getClass().getMethod("error", Object.class).invoke(mod, "Harness error from a subsystem that is Off");
        });
        step("stderr printStackTrace", () -> new RuntimeException("harness stderr trace").printStackTrace());

        step("GameWindow links (verifies the patched frameStep)", () -> {
            try {
                Class.forName("zombie.GameWindow", true, L);
            } catch (VerifyError e) {
                throw e;
            } catch (Throwable t) {
                OUT.println("    (static init failed after verification, as expected outside the game: " + t + ")");
            }
        });

        Method frame = cls("errormonitor.Hooks").getMethod("frame");
        Object thread = setUpLua();
        File luaDir = new File(cache, "Lua");
        luaDir.mkdirs();
        Files.writeString(new File(luaDir, "ErrorMonitor_context.txt").toPath(),
            "state=in game\nversion=harness\ndebug=false\nmode=singleplayer\nsave=HarnessSave\nmod=HarnessMod\tHarness Mod\nend\n",
            StandardCharsets.UTF_8);
        Thread.sleep(1000);

        Object closure = cls("se.krka.kahlua.luaj.compiler.LuaCompiler")
            .getMethod("loadstring", String.class, String.class, cls("se.krka.kahlua.vm.KahluaTable"))
            .invoke(null, "function spin(n) local x = 0 for i = 1, n do x = x + i % 7 end return x end\n"
                + "function onTick(n) return spin(n) end\n", "HarnessBusy.lua", luaEnv);
        Method pcall = cls("se.krka.kahlua.vm.KahluaThread").getMethod("pcall", Object.class, Object[].class);
        pcall.invoke(thread, closure, new Object[0]);
        Object onTick = rawget(luaEnv, "onTick");

        long n = calibrate(thread, pcall, onTick);
        OUT.println("    spin(" + n + ") takes about 5 ms");
        for (int i = 0; i < 300; i++) {
            frame.invoke(null);
            pcall.invoke(thread, onTick, new Object[] { (double) n });
            Thread.sleep(8);
        }
        frame.invoke(null);
        Thread.sleep(150);
        OUT.println("    one 150 ms hitch outside Lua");
        frame.invoke(null);
        n = calibrate(thread, pcall, onTick);
        long t0 = System.nanoTime();
        pcall.invoke(thread, onTick, new Object[] { (double) n * 600 });
        OUT.println("    one freeze inside Lua, " + (System.nanoTime() - t0) / 1_000_000 + " ms");
        for (int i = 0; i < 60; i++) {
            frame.invoke(null);
            Thread.sleep(16);
        }
        Thread.sleep(11_000);
        OUT.println("harness done");
        System.exit(0);
    }

    static Object luaEnv;

    static Object setUpLua() throws Exception {
        Object platform = cls("se.krka.kahlua.j2se.J2SEPlatform").getMethod("getInstance").invoke(null);
        luaEnv = platform.getClass().getMethod("newEnvironment").invoke(platform);
        Object thread = cls("se.krka.kahlua.vm.KahluaThread").getConstructor(cls("se.krka.kahlua.vm.Platform"), cls("se.krka.kahlua.vm.KahluaTable"))
            .newInstance(platform, luaEnv);
        // LuaManager.init sets this to the main thread.
        thread.getClass().getField("debugOwnerThread").set(thread, Thread.currentThread());
        Field f = cls("zombie.Lua.LuaManager").getField("thread");
        f.set(null, thread);
        OUT.println("ok   LuaManager.thread set to a standalone KahluaThread");
        return thread;
    }

    static Object rawget(Object table, String key) throws Exception {
        return cls("se.krka.kahlua.vm.KahluaTable").getMethod("rawget", Object.class).invoke(table, key);
    }

    static long calibrate(Object thread, Method pcall, Object fn) throws Exception {
        long n = 10_000;
        while (true) {
            long t = System.nanoTime();
            pcall.invoke(thread, fn, new Object[] { (double) n });
            long ms = (System.nanoTime() - t) / 1_000_000;
            if (ms >= 5 || n > 1_000_000_000L) {
                return Math.max(1, n * 5 / Math.max(1, ms));
            }
            n *= 2;
        }
    }

    interface Step {
        void run() throws Throwable;
    }

    static void step(String name, Step s) {
        try {
            s.run();
            OUT.println("ok   " + name);
        } catch (Throwable t) {
            Throwable c = t instanceof java.lang.reflect.InvocationTargetException && t.getCause() != null ? t.getCause() : t;
            OUT.println("FAIL " + name + ": " + c);
            for (Throwable cause = c.getCause(); cause != null; cause = cause.getCause()) {
                OUT.println("       caused by " + cause);
                StackTraceElement[] st = cause.getStackTrace();
                for (int i = 0; i < Math.min(4, st.length); i++) {
                    OUT.println("         at " + st[i]);
                }
            }
        }
    }

    static Class<?> cls(String name) throws ClassNotFoundException {
        return Class.forName(name, false, L);
    }

    static void call(Object target, String method) throws Exception {
        target.getClass().getMethod(method).invoke(target);
    }
}
