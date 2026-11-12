package errormonitor;

import java.lang.instrument.Instrumentation;

public final class Agent {
    private Agent() {
    }

    // An exception escaping premain would stop the game from launching, so everything is caught.
    public static void premain(String args, Instrumentation inst) {
        try {
            Monitor.start();
            if (Monitor.instance == null) {
                return;
            }
            inst.addTransformer(new Transformer());
            // Loading without initializing runs the transformer now, before the game logs anything, and
            // runs no game static initializers early.
            ClassLoader loader = ClassLoader.getSystemClassLoader();
            for (String name : Transformer.TARGET_CLASSES) {
                try {
                    Class.forName(name.replace('/', '.'), false, loader);
                } catch (Throwable t) {
                    Monitor.agentProblem("loading " + name, t);
                }
            }
        } catch (Throwable t) {
            System.out.println("[ErrorMonitor] failed to start: " + t);
        }
    }
}
