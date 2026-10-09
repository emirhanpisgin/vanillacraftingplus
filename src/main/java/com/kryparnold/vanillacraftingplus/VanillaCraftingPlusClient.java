package com.kryparnold.vanillacraftingplus;

//? if fabric {
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.api.EnvType;
import net.fabricmc.api.Environment;
//?}

//? if fabric {
@Environment(EnvType.CLIENT)
public class VanillaCraftingPlusClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        VanillaCraftingPlus.LOGGER.info("Initializing VanillaCrafting+ client!");
    }
}
//?}
