package sensiblemods.refrigeration;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.inventory.types.Food;

/**
 * Vanilla Food.updateFreezing() thaws food everywhere outside a powered freezer, every time the
 * item updates (every frame while its container is shown). Lua can only undo that afterwards, so
 * frozen food visibly thaws between its passes. This hook keeps frozen food frozen in cold air.
 * Freezing itself stays with the Lua model, which follows the HoursToFreeze option.
 * The hook only changes the answer; the original method always runs.
 */
public final class Patches {

    @Patch(className = "zombie.inventory.types.Food", methodName = "isThawing")
    public static final class NoThawInColdAir {
        @Patch.OnExit
        public static void exit(@Patch.This Food self, @Patch.Return(readOnly = false) boolean thawing) {
            if (thawing && Rules.keepsFrozen(self)) thawing = false;
        }
    }

    private Patches() {}
}
