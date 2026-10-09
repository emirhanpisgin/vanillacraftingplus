package com.kryparnold.vanillacraftingplus;

//? if neoforge && <1.20.5 {
/*import net.neoforged.api.distmarker.Dist;
import net.neoforged.fml.common.Mod;
*///?}
//? if neoforge && >=1.20.5 {
/*import net.neoforged.api.distmarker.Dist;
import net.neoforged.fml.common.EventBusSubscriber;
*///?}

//? if neoforge && <1.20.5 {
/*@Mod.EventBusSubscriber(modid = VanillaCraftingPlus.MOD_ID, value = Dist.CLIENT)
public class VanillaCraftingPlusNeoForgeClient {
*///?}
//? if neoforge && >=1.20.5 && <1.21.6 {
/*@EventBusSubscriber(modid = VanillaCraftingPlus.MOD_ID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.GAME)
public class VanillaCraftingPlusNeoForgeClient {
*///?}
//? if neoforge && >=1.21.6 {
/*@EventBusSubscriber(modid = VanillaCraftingPlus.MOD_ID, value = Dist.CLIENT)
public class VanillaCraftingPlusNeoForgeClient {
*///?}
//? if neoforge {
/*}
*///?}
