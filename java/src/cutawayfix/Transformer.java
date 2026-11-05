package cutawayfix;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldInsnNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.InsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.VarInsnNode;

// Every patch checks that the bytecode still looks exactly like Build 42.21's before touching it. If a
// game update changes a method, that patch is skipped and the vanilla code runs.
final class Transformer implements ClassFileTransformer {
    static final String CUTAWAYS = "zombie/iso/fboRenderChunk/FBORenderCutaways";
    static final String ORPHANS = CUTAWAYS + "$OrphanStructures";
    static final String TREE = "zombie/iso/objects/IsoTree";
    static final String[] TARGET_CLASSES = { CUTAWAYS, ORPHANS, TREE };

    private static final String CHUNK_LEVEL_DATA = CUTAWAYS + "$ChunkLevelData";
    private static final String PER_PLAYER_DATA = CUTAWAYS + "$PerPlayerData";
    private static final String SQUARE = "zombie/iso/IsoGridSquare";
    private static final String PLAYER = "zombie/characters/IsoPlayer";
    private static final String BUILDING_DEF = "zombie/iso/BuildingDef";
    private static final String HOOKS = "cutawayfix/Hooks";

    static final String SOUTH_EDGE = "south_edge_invalidation";
    static final String OCCLUDED_ROOMS = "occluded_rooms_recheck";
    static final String ATTACHED_ROOFS = "attached_room_roofs";
    static final String TREE_ROOM_CRASH = "tree_room_crash";

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> redefining, ProtectionDomain domain, byte[] bytes) {
        if (className == null) {
            return null;
        }
        try {
            if (className.equals(CUTAWAYS)) {
                return patch(bytes, this::patchCutaways);
            }
            if (className.equals(ORPHANS)) {
                return patch(bytes, this::patchOrphans);
            }
            if (className.equals(TREE)) {
                return patch(bytes, this::patchTree);
            }
        } catch (Throwable t) {
            Status.error(className, t);
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
        // No branches are added and no local types change, so the existing stack map frames stay valid
        // and ASM never has to load game classes to recompute them.
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        node.accept(writer);
        return writer.toByteArray();
    }

    private boolean patchCutaways(ClassNode node) {
        boolean southEdge = fixSouthEdgeFlag(findMethod(node, "doCutawayVisitSquares", "(ILjava/util/ArrayList;)V"));
        boolean occluded = addOccludedRoomsRecheck(findMethod(node, "checkOccludedRooms", "(ILjava/util/ArrayList;)Z"));
        return southEdge || occluded;
    }

    private boolean patchOrphans(ClassNode node) {
        return treatAttachedRoofsAsOrphans(findMethod(node, "calculateOrphanStructureSquare", "(L" + SQUARE + ";)Z"));
    }

    // Vanilla stores the north-edge result into hasCutawayWestWallsOnSouthEdge, so the chunk to the south
    // is not redrawn when cutaway walls along that edge change.
    private boolean fixSouthEdgeFlag(MethodNode method) {
        if (method == null) {
            Status.skipped(SOUTH_EDGE, "method not found");
            return false;
        }
        for (AbstractInsnNode insn = method.instructions.getFirst(); insn != null; insn = insn.getNext()) {
            if (!isField(insn, Opcodes.GETFIELD, CHUNK_LEVEL_DATA, "hasCutawayWestWallsOnSouthEdge")) {
                continue;
            }
            AbstractInsnNode levelData = previous(insn);
            AbstractInsnNode southValue = previous(levelData);
            if (!isVar(levelData, Opcodes.ALOAD) || !isVar(southValue, Opcodes.ILOAD)) {
                break;
            }
            for (AbstractInsnNode next = insn.getNext(); next != null; next = next.getNext()) {
                if (isField(next, Opcodes.PUTFIELD, CHUNK_LEVEL_DATA, "hasCutawayWestWallsOnSouthEdge")) {
                    AbstractInsnNode storedValue = previous(next);
                    if (!isVar(storedValue, Opcodes.ILOAD)) {
                        break;
                    }
                    int south = ((VarInsnNode) southValue).var;
                    if (((VarInsnNode) storedValue).var == south) {
                        Status.skipped(SOUTH_EDGE, "already correct in this game version");
                        return false;
                    }
                    ((VarInsnNode) storedValue).var = south;
                    Status.applied(SOUTH_EDGE);
                    return true;
                }
            }
            break;
        }
        Status.skipped(SOUTH_EDGE, "bytecode did not match");
        return false;
    }

    // Vanilla only recalculates which wall squares hide a visible room when the player steps onto a new
    // square, using line-of-sight data that is still catching up. Standing still left stale cutaways.
    private boolean addOccludedRoomsRecheck(MethodNode method) {
        if (method == null || (method.access & Opcodes.ACC_STATIC) != 0) {
            Status.skipped(OCCLUDED_ROOMS, "method not found");
            return false;
        }
        boolean usesCheckSquare = false;
        for (AbstractInsnNode insn = method.instructions.getFirst(); insn != null; insn = insn.getNext()) {
            if (isField(insn, Opcodes.GETFIELD, PER_PLAYER_DATA, "checkSquare")) {
                usesCheckSquare = true;
                break;
            }
        }
        if (!usesCheckSquare) {
            Status.skipped(OCCLUDED_ROOMS, "bytecode did not match");
            return false;
        }
        InsnList hook = new InsnList();
        hook.add(new VarInsnNode(Opcodes.ALOAD, 0));
        hook.add(new VarInsnNode(Opcodes.ILOAD, 1));
        hook.add(new MethodInsnNode(Opcodes.INVOKESTATIC, HOOKS, "beforeCheckOccludedRooms", "(L" + CUTAWAYS + ";I)V", false));
        method.instructions.insert(hook);
        Status.applied(OCCLUDED_ROOMS);
        return true;
    }

    // Rooms built onto a map building are never turned into a building of their own, and any square within
    // a tile of the map building counts as "associated" with it. Vanilla excludes associated squares from
    // orphan structures, so those roof tiles stayed drawn over the player while the rest of the roof hid.
    private boolean treatAttachedRoofsAsOrphans(MethodNode method) {
        if (method == null) {
            Status.skipped(ATTACHED_ROOFS, "method not found");
            return false;
        }
        AbstractInsnNode match = null;
        for (AbstractInsnNode insn = method.instructions.getFirst(); insn != null; insn = insn.getNext()) {
            if (isField(insn, Opcodes.GETFIELD, SQUARE, "associatedBuilding") && isVar(previous(insn), Opcodes.ALOAD)
                && ((VarInsnNode) previous(insn)).var == 1) {
                if (match != null) {
                    match = null;
                    break;
                }
                match = insn;
            }
        }
        if (match == null) {
            Status.skipped(ATTACHED_ROOFS, "bytecode did not match");
            return false;
        }
        method.instructions.set(match,
            new MethodInsnNode(Opcodes.INVOKESTATIC, HOOKS, "orphanCheckAssociatedBuilding", "(L" + SQUARE + ";)L" + BUILDING_DEF + ";", false));
        Status.applied(ATTACHED_ROOFS);
        return true;
    }

    private boolean patchTree(ClassNode node) {
        return replaceTreeRoomCheck(findMethod(node, "isPlayerInsideARoom", "(L" + PLAYER + ";)Z"));
    }

    // Vanilla throws when the player counts as "in a room" but that square has no IsoRoom. The exception
    // aborts the rest of the frame's world rendering, every frame, while the player stands there.
    private boolean replaceTreeRoomCheck(MethodNode method) {
        if (method == null || (method.access & Opcodes.ACC_STATIC) != 0) {
            Status.skipped(TREE_ROOM_CRASH, "method not found");
            return false;
        }
        boolean usesRoomBounds = false;
        for (AbstractInsnNode insn = method.instructions.getFirst(); insn != null; insn = insn.getNext()) {
            if (insn instanceof MethodInsnNode call && call.name.equals("getRectsBounds")) {
                usesRoomBounds = true;
                break;
            }
        }
        if (!usesRoomBounds) {
            Status.skipped(TREE_ROOM_CRASH, "bytecode did not match");
            return false;
        }
        // The replacement body is straight-line code, so it needs no stack map frames or locals table.
        InsnList body = new InsnList();
        body.add(new VarInsnNode(Opcodes.ALOAD, 0));
        body.add(new VarInsnNode(Opcodes.ALOAD, 1));
        body.add(new MethodInsnNode(Opcodes.INVOKESTATIC, HOOKS, "isPlayerInsideARoom", "(L" + TREE + ";L" + PLAYER + ";)Z", false));
        body.add(new InsnNode(Opcodes.IRETURN));
        method.instructions.clear();
        method.instructions.add(body);
        method.tryCatchBlocks.clear();
        if (method.localVariables != null) {
            method.localVariables.clear();
        }
        Status.applied(TREE_ROOM_CRASH);
        return true;
    }

    private static MethodNode findMethod(ClassNode node, String name, String desc) {
        for (MethodNode method : node.methods) {
            if (method.name.equals(name) && method.desc.equals(desc)) {
                return method;
            }
        }
        return null;
    }

    private static AbstractInsnNode previous(AbstractInsnNode insn) {
        AbstractInsnNode prev = insn == null ? null : insn.getPrevious();
        while (prev != null && prev.getOpcode() == -1) {
            prev = prev.getPrevious();
        }
        return prev;
    }

    private static boolean isField(AbstractInsnNode insn, int opcode, String owner, String name) {
        return insn instanceof FieldInsnNode field && insn.getOpcode() == opcode && field.owner.equals(owner) && field.name.equals(name);
    }

    private static boolean isVar(AbstractInsnNode insn, int opcode) {
        return insn instanceof VarInsnNode && insn.getOpcode() == opcode;
    }
}
