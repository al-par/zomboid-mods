package debughotkeysfix;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.network.GameClient;

/**
 * In debug mode, NetworkPlayerAI.checkDebugInput runs every tick and, while Left Ctrl is held, turns
 * A, D, R, S, V and Z into multiplayer test hotkeys (spawn a bull, set health to 0, repair a vehicle,
 * reset network state, add a vehicle, spawn a horde). In single player the server commands throw on
 * the missing connection, and IngameState then copies the whole world to a _crash save. Left Ctrl is
 * the default Aim key, so aiming while walking sets them off. Multiplayer clients keep them.
 */
public final class Patches {

    @Patch(className = "zombie.characters.NetworkPlayerAI", methodName = "checkDebugInput")
    public static final class NoDebugHotkeysInSinglePlayer {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter() {
            return !GameClient.client;
        }
    }

    private Patches() {}
}
