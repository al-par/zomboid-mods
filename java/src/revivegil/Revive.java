package revivegil;

import java.io.File;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import zombie.core.Core;
import zombie.debug.DebugLog;
import zombie.util.PZSQLUtils;

/** Called from advice inlined into PlayerDBHelper, so everything here must stay public. */
public final class Revive {

    public static final int MAIN_PLAYER_ID = 1;

    public static boolean mainPlayerExists(String saveDir) {
        if (Core.getInstance().isNoSave()) return false;
        File dbFile = new File(saveDir + File.separator + "players.db");
        if (!dbFile.exists()) return false;
        try (Connection connection = PZSQLUtils.getConnection(dbFile.getAbsolutePath());
             PreparedStatement pstmt = connection.prepareStatement("SELECT id FROM localPlayers WHERE id=?")) {
            pstmt.setInt(1, MAIN_PLAYER_ID);
            try (ResultSet rs = pstmt.executeQuery()) {
                if (!rs.next()) return false;
            }
        } catch (Exception e) {
            DebugLog.log("[ReviveGil] couldn't read " + dbFile + ": " + e);
            return false;
        }
        DebugLog.log("[ReviveGil] treating the dead main player in " + saveDir + " as alive");
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

    private Revive() {}
}
