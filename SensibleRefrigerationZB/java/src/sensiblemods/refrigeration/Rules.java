package sensiblemods.refrigeration;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.Food;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoWorldInventoryObject;
import zombie.iso.weather.ClimateManager;
import zombie.characters.IsoGameCharacter;
import zombie.vehicles.BaseVehicle;

/**
 * Thresholds come from Sensible Refrigeration's Lua (its sandbox options), which stays the
 * source of truth for spoilage. Until Lua configures them, every patch leaves vanilla alone.
 */
public final class Rules {
    private static volatile boolean configured;
    private static volatile float coldBelow;
    private static volatile float freezeBelow;

    /** Called from Lua; its presence also tells Lua that the Java part loaded. */
    @LuaMethod(name = "SensibleRefrigerationZB_configure", global = true)
    public static boolean configure(double cold, double freeze) {
        coldBelow = (float) cold;
        freezeBelow = (float) freeze;
        configured = true;
        return true;
    }

    /** Public because the patches' advice is inlined into Food, outside this package. */
    public static boolean keepsFrozen(Food food) {
        if (!configured) return false;
        IsoGridSquare square = worldSquare(food);
        return square != null && ClimateManager.getInstance().getAirTemperatureForSquare(square) < coldBelow;
    }

    public static boolean freezes(Food food) {
        if (!configured) return false;
        IsoGridSquare square = worldSquare(food);
        return square != null && ClimateManager.getInstance().getAirTemperatureForSquare(square) < freezeBelow;
    }

    /**
     * The square whose air the food sits in, or null when vanilla's own rules apply: carried,
     * in a vehicle, or in a container with its own temperature (powered fridge or freezer, lit stove).
     * Mirrors locate() and vanillaControlsTemperature() in AmbientColdStorage.lua.
     */
    private static IsoGridSquare worldSquare(Food food) {
        ItemContainer container = food.getOutermostContainer();
        if (container == null) {
            return squareOf(food.getWorldItem());
        }
        if (Math.abs(container.getTemperature() - 1.0f) > 0.001f) return null;
        InventoryItem bag = container.getContainingItem();
        if (bag != null) {
            return squareOf(bag.getWorldItem());
        }
        IsoObject parent = container.getParent();
        if (parent == null || parent instanceof IsoGameCharacter || parent instanceof BaseVehicle) return null;
        return parent.getSquare();
    }

    private static IsoGridSquare squareOf(IsoWorldInventoryObject worldItem) {
        return worldItem == null ? null : worldItem.getSquare();
    }

    private Rules() {}
}
