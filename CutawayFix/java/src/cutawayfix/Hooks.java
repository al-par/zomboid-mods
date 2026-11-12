package cutawayfix;

import java.util.ArrayList;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.core.math.PZMath;
import zombie.iso.IsoCamera;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.areas.IsoBuilding;
import zombie.iso.fboRenderChunk.FBORenderCutaways;

// Called from the advice in Patches, which is inlined into game classes, so everything here is public.
public final class Hooks {
    // Masks only change when visibility actually changes, so a recheck that finds nothing new costs no
    // chunk redraws.
    private static final int OCCLUDED_ROOMS_RECHECK_FRAMES = 6;
    private static final int[] framesSinceRecheck = new int[4];
    private static final byte CUTAWAY_WEST = 2;
    private static final long INVALIDATE_CUTAWAYS = 2048L;

    private Hooks() {
    }

    /** Lets the Lua half tell whether the Java part loaded. */
    @LuaMethod(name = "CutawayFix_active", global = true)
    public static boolean active() {
        return true;
    }

    public static void beforeCheckOccludedRooms(FBORenderCutaways cutaways, int playerIndex) {
        if (playerIndex < 0 || playerIndex >= framesSinceRecheck.length) {
            return;
        }
        if (++framesSinceRecheck[playerIndex] < OCCLUDED_ROOMS_RECHECK_FRAMES) {
            return;
        }
        framesSinceRecheck[playerIndex] = 0;
        cutaways.squareChanged(null);
    }

    // Recomputes the south-edge flag the way vanilla computes the other three edges, and redraws the chunk
    // to the south when it changed. Vanilla's own (wrong) store happens first, inside the method.
    public static void fixSouthEdges(FBORenderCutaways cutaways, int playerIndex, ArrayList<IsoChunk> onScreenChunks) {
        if (onScreenChunks == null || cutaways.cell == null) {
            return;
        }
        int z = PZMath.fastfloor(IsoCamera.frameState.camCharacterZ);
        IsoChunkMap chunkMap = cutaways.cell.chunkMap[playerIndex];
        for (int i = 0; i < onScreenChunks.size(); i++) {
            IsoChunk chunk = onScreenChunks.get(i);
            if (chunk == null || z < chunk.minLevel || z > chunk.maxLevel) {
                continue;
            }
            FBORenderCutaways.ChunkLevelData data = chunk.getCutawayData().getDataForLevel(z);
            if (data == null) {
                continue;
            }
            boolean south = hasWestCutawayOnSouthEdge(playerIndex, chunk, z);
            if (south == data.hasCutawayWestWallsOnSouthEdge) {
                continue;
            }
            data.hasCutawayWestWallsOnSouthEdge = south;
            IsoChunk below = chunkMap.getChunk(chunk.wx - chunkMap.getWorldXMin(), chunk.wy + 1 - chunkMap.getWorldYMin());
            if (below != null) {
                below.getRenderLevels(playerIndex).invalidateLevel(z, INVALIDATE_CUTAWAYS);
            }
        }
    }

    private static boolean hasWestCutawayOnSouthEdge(int playerIndex, IsoChunk chunk, int z) {
        for (int x = 0; x <= 7; x++) {
            IsoGridSquare square = chunk.getGridSquare(x, 7, z);
            if (square != null && (square.getPlayerCutawayFlag(playerIndex, 0L) & CUTAWAY_WEST) != 0) {
                return true;
            }
        }
        return false;
    }

    // Vanilla returns false for these only because the square is "associated" with the neighbouring map
    // building. A floor up there was built by the player, so it hides with the rest of the player's roof.
    public static boolean isAttachedPlayerFloor(IsoGridSquare square) {
        if (square == null || square.getZ() <= 0 || square.associatedBuilding == null || square.getPlayerBuiltFloor() == null) {
            return false;
        }
        IsoBuilding building = square.getBuilding();
        if (building == null) {
            building = square.roofHideBuilding;
        }
        for (int z = square.getZ() - 1; z >= 0 && building == null; z--) {
            IsoGridSquare below = square.getCell().getGridSquare(square.x, square.y, z);
            if (below == null) {
                continue;
            }
            building = below.getBuilding();
            if (building == null) {
                building = below.roofHideBuilding;
            }
        }
        return building == null;
    }
}
