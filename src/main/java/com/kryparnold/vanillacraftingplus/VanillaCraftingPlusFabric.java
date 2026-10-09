package com.kryparnold.vanillacraftingplus;

//? if fabric {
import net.fabricmc.api.ModInitializer;
//?}

//? if fabric {
public class VanillaCraftingPlusFabric implements ModInitializer {
    @Override
    public void onInitialize() {
        VanillaCraftingPlus.LOGGER.info("Initializing VanillaCrafting+!");
    }
}
//?}
