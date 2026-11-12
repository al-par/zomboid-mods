package cutawayfix;

import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.fboRenderChunk.FBORenderCutaways;

public final class Patches {

    // Vanilla stores the north-edge result into hasCutawayWestWallsOnSouthEdge, so the chunk to the south
    // is not redrawn when cutaway walls along that edge change.
    @Patch(className = "zombie.iso.fboRenderChunk.FBORenderCutaways", methodName = "doCutawayVisitSquares")
    public static final class SouthEdge {
        @Patch.OnExit
        public static void exit(@Patch.This FBORenderCutaways self, @Patch.Argument(0) int playerIndex,
                                @Patch.Argument(1) ArrayList<IsoChunk> onScreenChunks) {
            Hooks.fixSouthEdges(self, playerIndex, onScreenChunks);
        }
    }

    // Vanilla only recalculates which wall squares hide a visible room when the player steps onto a new
    // square, using line-of-sight data that is still catching up. Standing still left stale cutaways.
    @Patch(className = "zombie.iso.fboRenderChunk.FBORenderCutaways", methodName = "checkOccludedRooms")
    public static final class OccludedRooms {
        @Patch.OnEnter
        public static void enter(@Patch.This FBORenderCutaways self, @Patch.Argument(0) int playerIndex,
                                 @Patch.Argument(1) ArrayList<IsoChunk> onScreenChunks) {
            Hooks.beforeCheckOccludedRooms(self, playerIndex);
        }
    }

    // Rooms built onto a map building are never turned into a building of their own, and any square within
    // a tile of the map building counts as "associated" with it. Vanilla excludes associated squares from
    // orphan structures, so those roof tiles stayed drawn over the player while the rest of the roof hid.
    @Patch(className = "zombie.iso.fboRenderChunk.FBORenderCutaways$OrphanStructures", methodName = "calculateOrphanStructureSquare")
    public static final class AttachedRoofs {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) IsoGridSquare square, @Patch.Return(readOnly = false) boolean orphan) {
            if (!orphan && Hooks.isAttachedPlayerFloor(square)) orphan = true;
        }
    }

    private Patches() {}
}
