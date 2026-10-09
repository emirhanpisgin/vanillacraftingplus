package com.kryparnold.vanillacraftingplus;

//? if neoforge {
/*import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
*///?}
//? if neoforge && <1.20.5 {
/*import net.neoforged.fml.common.Mod;
*///?}
//? if neoforge && >=1.20.5 {
/*import net.neoforged.fml.common.EventBusSubscriber;
*///?}
//? if neoforge {
/*import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
*///?}

//? if neoforge && <1.20.5 {
/*@Mod.EventBusSubscriber(modid = VanillaCraftingPlus.MOD_ID, value = Dist.CLIENT, bus = Mod.EventBusSubscriber.Bus.MOD)
public class VanillaCraftingPlusNeoForgeClientSetup {
*///?}
//? if neoforge && >=1.20.5 && <1.21.6 {
/*@EventBusSubscriber(modid = VanillaCraftingPlus.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.MOD)
public class VanillaCraftingPlusNeoForgeClientSetup {
*///?}
//? if neoforge && >=1.21.6 {
/*@EventBusSubscriber(modid = VanillaCraftingPlus.MOD_ID, value = Dist.CLIENT)
public class VanillaCraftingPlusNeoForgeClientSetup {
*///?}
//? if neoforge {
/*    @SubscribeEvent
    public static void onClientSetup(FMLClientSetupEvent event) {
        VanillaCraftingPlus.LOGGER.info("Client setup complete!");
    }
}
*///?}
