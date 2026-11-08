package sensiblemods.refrigeration;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.inventory.types.Food;

/**
 * Vanilla Food.updateFreezing() freezes food only in a powered freezer and thaws it everywhere
 * else, every time the item updates (every frame while its container is shown). Lua can only
 * undo that afterwards, so frozen food visibly thaws between its passes. These hooks make
 * vanilla's own freeze/thaw decision follow the air temperature at the food's square instead.
 * Both only change the answer; the original method always runs.
 */
public final class Patches {

    @Patch(className = "zombie.inventory.types.Food", methodName = "isThawing")
    public static final class NoThawInColdAir {
        @Patch.OnExit
        public static void exit(@Patch.This Food self, @Patch.Return(readOnly = false) boolean thawing) {
            if (thawing && Rules.keepsFrozen(self)) thawing = false;
        }
    }

    @Patch(className = "zombie.inventory.types.Food", methodName = "isFreezing")
    public static final class FreezeInFreezingAir {
        @Patch.OnExit
        public static void exit(@Patch.This Food self, @Patch.Return(readOnly = false) boolean freezing) {
            if (!freezing && self.canBeFrozen() && self.getFreezingTime() < 100.0f && Rules.freezes(self)) {
                freezing = true;
            }
        }
    }

    private Patches() {}
}
