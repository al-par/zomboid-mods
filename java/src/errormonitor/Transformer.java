package errormonitor;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.VarInsnNode;

// Each hook is one static call inserted at the very start of a game method. The inserted code has no
// branches and leaves the stack and locals as it found them, so the method's stack map frames stay valid.
// If a game update changes a method's signature, that hook is skipped and the game runs unpatched.
final class Transformer implements ClassFileTransformer {
    static final String DEBUG_LOG = "zombie/debug/DebugLog";
    static final String LOG_STREAM = "zombie/debug/DebugLogStream";
    static final String GAME_WINDOW = "zombie/GameWindow";
    static final String[] TARGET_CLASSES = { DEBUG_LOG, LOG_STREAM, GAME_WINDOW };

    private static final String HOOKS_CLASS = "errormonitor/Hooks";
    private static final String ECHO_DESC = "(Lzombie/debug/DebugType;Lzombie/debug/LogSeverity;Ljava/lang/String;Ljava/lang/String;)V";
    private static final String LOGGED_DESC = "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;Ljava/lang/String;)V";

    static final String LOG_LINES = "log_lines";
    static final String TRACE_LINES = "stack_trace_lines";
    static final String EXCEPTIONS = "exceptions";
    static final String MESSAGES = "error_and_warning_calls";
    static final String FRAMES = "frame_timing";
    static final String[] HOOKS = { LOG_LINES, TRACE_LINES, EXCEPTIONS, MESSAGES, FRAMES };

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> redefining, ProtectionDomain domain, byte[] bytes) {
        if (className == null) {
            return null;
        }
        try {
            if (className.equals(DEBUG_LOG)) {
                return patch(bytes, this::patchDebugLog);
            }
            if (className.equals(LOG_STREAM)) {
                return patch(bytes, this::patchLogStream);
            }
            if (className.equals(GAME_WINDOW)) {
                if (Perf.instance == null) {
                    report(FRAMES, "off (performanceMonitoring=false)");
                    return null;
                }
                return patch(bytes, node -> insert(node, FRAMES, "frameStep", "()V", true, List.of(), call("frame", "()V")));
            }
        } catch (Throwable t) {
            Monitor.agentProblem("patching " + className, t);
        }
        return null;
    }

    private interface ClassPatch {
        boolean apply(ClassNode node);
    }

    private static byte[] patch(byte[] bytes, ClassPatch classPatch) {
        ClassReader reader = new ClassReader(bytes);
        ClassNode node = new ClassNode();
        reader.accept(node, 0);
        if (!classPatch.apply(node)) {
            return null;
        }
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        node.accept(writer);
        return writer.toByteArray();
    }

    private boolean patchDebugLog(ClassNode node) {
        boolean lines = insert(node, LOG_LINES, "echoToLogFiles", ECHO_DESC,
            load(Opcodes.ALOAD, 1, 2, 3, 4), call("logged", LOGGED_DESC));
        // The third argument is a label ("StackTrace"), not a caller prefix.
        boolean traces = insert(node, TRACE_LINES, "echoExceptionLineToLogFiles", ECHO_DESC,
            concat(load(Opcodes.ALOAD, 1, 2), List.of(new LdcInsnNode("")), load(Opcodes.ALOAD, 4)), call("logged", LOGGED_DESC));
        return lines || traces;
    }

    private boolean patchLogStream(ClassNode node) {
        boolean exceptions = insert(node, EXCEPTIONS, "printException",
            "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/LogSeverity;)V",
            load(Opcodes.ALOAD, 0, 1, 2, 3, 4),
            call("exception", "(Ljava/lang/Object;Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Object;)V"));
        boolean messages = insert(node, MESSAGES, "writeWithCallerPrefixln",
            "(Ljava/io/PrintStream;Lzombie/debug/LogSeverity;IZLjava/lang/Object;[Ljava/lang/Object;)V",
            load(Opcodes.ALOAD, 0, 2, 5, 6),
            call("message", "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;[Ljava/lang/Object;)V"));
        return exceptions || messages;
    }

    private static boolean insert(ClassNode node, String hook, String name, String desc, List<AbstractInsnNode> args, AbstractInsnNode call) {
        return insert(node, hook, name, desc, false, args, call);
    }

    private static boolean insert(ClassNode node, String hook, String name, String desc, boolean isStatic, List<AbstractInsnNode> args,
                                  AbstractInsnNode call) {
        MethodNode method = null;
        for (MethodNode m : node.methods) {
            if (m.name.equals(name) && m.desc.equals(desc)) {
                method = m;
                break;
            }
        }
        if (method == null || ((method.access & Opcodes.ACC_STATIC) != 0) != isStatic || method.instructions.size() == 0) {
            report(hook, "method not found");
            return false;
        }
        InsnList list = new InsnList();
        for (AbstractInsnNode insn : args) {
            list.add(insn);
        }
        list.add(call);
        method.instructions.insert(list);
        report(hook, "applied");
        return true;
    }

    private static List<AbstractInsnNode> load(int opcode, int... slots) {
        List<AbstractInsnNode> list = new ArrayList<>();
        for (int slot : slots) {
            list.add(new VarInsnNode(opcode, slot));
        }
        return list;
    }

    @SafeVarargs
    private static List<AbstractInsnNode> concat(List<? extends AbstractInsnNode>... parts) {
        List<AbstractInsnNode> list = new ArrayList<>();
        for (List<? extends AbstractInsnNode> part : parts) {
            list.addAll(part);
        }
        return list;
    }

    private static AbstractInsnNode call(String name, String desc) {
        return new MethodInsnNode(Opcodes.INVOKESTATIC, HOOKS_CLASS, name, desc, false);
    }

    private static void report(String hook, String status) {
        Monitor m = Monitor.instance;
        if (m != null) {
            m.hookStatus(hook, status);
        }
        System.out.println("[ErrorMonitor] hook " + hook + ": " + status);
    }
}
