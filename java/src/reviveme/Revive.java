package reviveme;

import java.io.File;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.debug.DebugLog;
import zombie.util.PZSQLUtils;

/** Called from advice inlined into PlayerDBHelper, so everything here must stay public. */
public final class Revive {

    public static final String MOD_ID = "ReviveMe";
    public static final int MAIN_PLAYER_ID = 1;
    public static final String PENDING_GEAR_KEY = "ReviveMePendingGear";

    /** ZombieBuddy keeps the jar loaded from the main-menu mod list, even for saves that don't enable the mod. */
    public static boolean enabledForLoadedMods() {
        for (String id : ZomboidFileSystem.instance.getModIDs()) {
            if (id.equals(MOD_ID) || id.endsWith("\\" + MOD_ID)) return true;
        }
        return false;
    }

    public static boolean mainPlayerExists(String saveDir) {
        if (Core.getInstance().isNoSave() || !enabledForLoadedMods()) return false;
        File dbFile = new File(saveDir + File.separator + "players.db");
        if (!dbFile.exists()) return false;
        try (Connection connection = PZSQLUtils.getConnection(dbFile.getAbsolutePath());
             PreparedStatement pstmt = connection.prepareStatement("SELECT id FROM localPlayers WHERE id=?")) {
            pstmt.setInt(1, MAIN_PLAYER_ID);
            try (ResultSet rs = pstmt.executeQuery()) {
                if (!rs.next()) return false;
            }
        } catch (Exception e) {
            DebugLog.log("[ReviveMe] couldn't read " + dbFile + ": " + e);
            return false;
        }
        DebugLog.log("[ReviveMe] treating the dead main player in " + saveDir + " as alive");
        return true;
    }

    /** getPlayers returns flat triples: id (Double), name, isDead (Boolean). */
    public static void markMainPlayerAlive(ArrayList<Object> players) {
        if (players == null) return;
        for (int i = 0; i + 2 < players.size(); i += 3) {
            if (players.get(i) instanceof Double id && id.intValue() == MAIN_PLAYER_ID) {
                players.set(i + 2, Boolean.FALSE);
            }
        }
    }

    /** PlayerDB.loadPlayer zeroes a dead player's health; undo that before the first update kills him. */
    public static void healIfDead(IsoPlayer player) {
        if (player == null || !player.isDead() || !enabledForLoadedMods()) return;
        player.getBodyDamage().RestoreToFullHealth();
        player.setHealth(1.0f);
        player.getModData().rawset(PENDING_GEAR_KEY, Boolean.TRUE);
        DebugLog.log("[ReviveMe] revived " + player.getDescriptor().getForename() + " " + player.getDescriptor().getSurname());
    }

    private Revive() {}
}
