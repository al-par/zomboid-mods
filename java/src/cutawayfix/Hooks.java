package cutawayfix;

import java.awt.Rectangle;
import zombie.characters.IsoPlayer;
import zombie.iso.BuildingDef;
import zombie.iso.IsoCamera;
import zombie.iso.IsoGridSquare;
import zombie.iso.areas.IsoRoom;
import zombie.iso.fboRenderChunk.FBORenderCutaways;
import zombie.iso.objects.IsoTree;

// Called from patched game bytecode. Signatures must match the descriptors in Transformer.
public final class Hooks {
    // Masks only change when visibility actually changes, so a recheck that finds nothing new costs no
    // chunk redraws.
    private static final int OCCLUDED_ROOMS_RECHECK_FRAMES = 6;
    private static final int[] framesSinceRecheck = new int[4];

    private Hooks() {
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

    // Reached only after vanilla found no building on or below the square. A floor up there was built by
    // the player, so it hides with the rest of the player's roof instead of with the neighbouring map building.
    public static BuildingDef orphanCheckAssociatedBuilding(IsoGridSquare square) {
        if (square.getZ() > 0 && square.getPlayerBuiltFloor() != null) {
            return null;
        }
        return square.associatedBuilding;
    }

    // Same result as vanilla IsoTree.isPlayerInsideARoom, but a missing IsoRoom counts as "not inside".
    public static boolean isPlayerInsideARoom(IsoTree tree, IsoPlayer player) {
        if (!player.isInARoom()) {
            return false;
        }
        IsoGridSquare playerSquare = player.getSquare();
        IsoRoom room = playerSquare == null ? null : playerSquare.getRoom();
        IsoGridSquare treeSquare = tree.getSquare();
        if (room == null || treeSquare == null) {
            return false;
        }
        Rectangle bounds = room.getRectsBounds();
        if (treeSquare.x < bounds.getX() || treeSquare.y < bounds.getY()) {
            return false;
        }
        if (treeSquare.x <= bounds.getX() + bounds.getWidth() + 8.0 && treeSquare.y <= bounds.getY() + bounds.getHeight() + 8.0) {
            return true;
        }
        float dx = treeSquare.x - IsoCamera.frameState.camCharacterX;
        float dy = treeSquare.y - IsoCamera.frameState.camCharacterY;
        return dx * dx + dy * dy <= 24.0F * 24.0F;
    }
}
