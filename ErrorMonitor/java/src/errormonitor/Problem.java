package errormonitor;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

// One distinct error or warning, however many times it happened.
final class Problem {
    static final int MAX_EXAMPLES = 3;

    final String id;
    final boolean error;
    final String subsystem;
    final String title;
    final String text;
    final String exceptionClass;
    final String contextMessage;
    final Trace trace;
    final List<String> stack;
    final String caller;
    final boolean silenced;
    final List<String> before;
    final String stateAtFirst;
    final long first;

    final String mod;
    final boolean failedOutsideMod;
    final Map<String, Integer> modsInStack;
    final String where;

    long last;
    long count = 1;
    final List<String> examples = new ArrayList<>();
    final Map<String, Long> callers = new LinkedHashMap<>();
    long otherCallers;

    Problem(String id, boolean error, String subsystem, String title, String text, String exceptionClass, String contextMessage,
            Trace trace, List<String> stack, String caller, boolean silenced, List<String> before, String stateAtFirst, long first) {
        this.id = id;
        this.error = error;
        this.subsystem = subsystem;
        this.title = title;
        this.text = text;
        this.exceptionClass = exceptionClass;
        this.contextMessage = contextMessage;
        this.trace = trace;
        this.stack = stack;
        this.caller = caller;
        this.silenced = silenced;
        this.before = before;
        this.stateAtFirst = stateAtFirst;
        this.first = first;
        this.last = first;

        // The topmost mod frame is the likeliest culprit. The error itself may have been raised further up,
        // in vanilla Lua or Java that the mod called.
        String firstLua = null;
        String modFrame = null;
        for (String f : stack) {
            if (!Trace.isLua(f)) {
                continue;
            }
            if (firstLua == null) {
                firstLua = f;
            }
            if (Trace.luaMod(f) != null) {
                modFrame = f;
                break;
            }
        }
        this.mod = modFrame == null ? null : Trace.luaMod(modFrame);
        this.failedOutsideMod = modFrame != null && modFrame != firstLua;
        this.modsInStack = Trace.modsIn(stack);
        this.where = describeWhere(firstLua, stack, caller);
    }

    private static String describeWhere(String firstLua, List<String> stack, String caller) {
        if (firstLua != null) {
            String origin = Trace.luaMod(firstLua) == null ? "vanilla Lua" : Trace.luaMod(firstLua);
            return Trace.luaShort(firstLua) + "  (" + origin + ")";
        }
        for (String f : stack) {
            if (!Trace.isEngineFrame(f)) {
                return Trace.stripModule(f);
            }
        }
        if (caller != null && !caller.isBlank()) {
            return caller.trim();
        }
        return stack.isEmpty() ? null : Trace.stripModule(stack.get(0));
    }

    // A copy whose counters no longer change, for rendering the report without holding Monitor.lock.
    private Problem(Problem p) {
        id = p.id;
        error = p.error;
        subsystem = p.subsystem;
        title = p.title;
        text = p.text;
        exceptionClass = p.exceptionClass;
        contextMessage = p.contextMessage;
        trace = p.trace;
        stack = p.stack;
        caller = p.caller;
        silenced = p.silenced;
        before = p.before;
        stateAtFirst = p.stateAtFirst;
        first = p.first;
        mod = p.mod;
        failedOutsideMod = p.failedOutsideMod;
        modsInStack = p.modsInStack;
        where = p.where;
        last = p.last;
        count = p.count;
        examples.addAll(p.examples);
        callers.putAll(p.callers);
        otherCallers = p.otherCallers;
    }

    Problem snapshot() {
        return new Problem(this);
    }

    String source() {
        if (mod != null) {
            return mod;
        }
        for (String f : stack) {
            if (Trace.isLua(f)) {
                return "vanilla Lua";
            }
        }
        return "game (Java)";
    }

    void seen(long time, String example) {
        count++;
        last = time;
        if (example != null && examples.size() < MAX_EXAMPLES && !example.equals(title) && !examples.contains(example)) {
            examples.add(example);
        }
    }

    // The Lua function that called the one that failed. One bug is often reached along several paths.
    void calledFrom(List<String> frames) {
        String caller = null;
        boolean top = true;
        for (String f : frames) {
            if (!Trace.isLua(f)) {
                continue;
            }
            if (top) {
                top = false;
                continue;
            }
            caller = Trace.luaShort(f) + "  (" + (Trace.luaMod(f) == null ? "vanilla" : Trace.luaMod(f)) + ")";
            break;
        }
        if (caller == null) {
            return;
        }
        if (callers.containsKey(caller) || callers.size() < MAX_CALLERS) {
            callers.merge(caller, 1L, Long::sum);
        } else {
            otherCallers++;
        }
    }

    static final int MAX_CALLERS = 8;
}
