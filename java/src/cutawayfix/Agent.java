package cutawayfix;

import java.lang.instrument.Instrumentation;

public final class Agent {
    private Agent() {
    }

    public static void premain(String args, Instrumentation inst) {
        Status.begin();
        inst.addTransformer(new Transformer());

        // Loading without initializing runs the transformer now, so the status file is complete before
        // the game's Lua starts, and no game static initializers run early.
        ClassLoader loader = ClassLoader.getSystemClassLoader();
        for (String name : Transformer.TARGET_CLASSES) {
            try {
                Class.forName(name.replace('/', '.'), false, loader);
            } catch (Throwable t) {
                Status.error(name, t);
            }
        }
    }
}
