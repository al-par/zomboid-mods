package reviveme;

import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;

/**
 * Single player only ever plays localPlayers row 1. When that character dies, players.db keeps the
 * row with isDead set, and every reader of the flag treats the save as having no player: the load
 * screen lists none and IsoWorld.init goes to character creation. These hooks make row 1 read as
 * alive. PlayerDB.loadPlayer still loads him at 0 health; the Lua side heals him in OnCreatePlayer.
 */
public final class Patches {

    @Patch(className = "zombie.savefile.PlayerDBHelper", methodName = "isPlayerAlive")
    public static final class MainPlayerAlive {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String saveDir, @Patch.Argument(1) int sqlId,
                                @Patch.Return(readOnly = false) boolean alive) {
            if (!alive && sqlId == Revive.MAIN_PLAYER_ID && Revive.mainPlayerExists(saveDir)) alive = true;
        }
    }

    @Patch(className = "zombie.savefile.PlayerDBHelper", methodName = "getPlayers")
    public static final class MainPlayerListedAlive {
        @Patch.OnExit
        public static void exit(@Patch.Return ArrayList<Object> players) {
            Revive.markMainPlayerAlive(players);
        }
    }

    @Patch(className = "zombie.savefile.PlayerDB", methodName = "loadLocalPlayer")
    public static final class HealLoadedMainPlayer {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int sqlId, @Patch.Return boolean loaded) {
            if (loaded && sqlId == Revive.MAIN_PLAYER_ID) Revive.healIfDead(IsoPlayer.getInstance());
        }
    }

    private Patches() {}
}
