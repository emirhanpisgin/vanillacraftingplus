import { createCanvas, GlobalFonts, loadImage } from "@napi-rs/canvas";
import type { Canvas, Image } from "@napi-rs/canvas";
import { GIFEncoder, applyPalette, quantize } from "gifenc";
import { decompressFrames, parseGIF } from "gifuct-js";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

type Ingredient = { item?: string; tag?: string };

type Recipe = {
    name: string;
    type: string;
    pattern?: string[];
    key?: Record<string, Ingredient>;
    result?: { item: string; count?: number };
};

const TAGS: Record<string, string[]> = {
    "minecraft:logs": [
        "minecraft:acacia_log",
        "minecraft:acacia_wood",
        "minecraft:birch_log",
        "minecraft:birch_wood",
        "minecraft:cherry_log",
        "minecraft:cherry_wood",
        "minecraft:dark_oak_log",
        "minecraft:dark_oak_wood",
        "minecraft:jungle_log",
        "minecraft:jungle_wood",
        "minecraft:mangrove_log",
        "minecraft:mangrove_wood",
        "minecraft:oak_log",
        "minecraft:oak_wood",
        "minecraft:spruce_log",
        "minecraft:spruce_wood",
        "minecraft:stripped_acacia_log",
        "minecraft:stripped_acacia_wood",
        "minecraft:stripped_birch_log",
        "minecraft:stripped_birch_wood",
        "minecraft:stripped_cherry_log",
        "minecraft:stripped_cherry_wood",
        "minecraft:stripped_dark_oak_log",
        "minecraft:stripped_dark_oak_wood",
        "minecraft:stripped_jungle_log",
        "minecraft:stripped_jungle_wood",
        "minecraft:stripped_mangrove_log",
        "minecraft:stripped_mangrove_wood",
        "minecraft:stripped_oak_log",
        "minecraft:stripped_oak_wood",
        "minecraft:stripped_spruce_log",
        "minecraft:stripped_spruce_wood",
    ],
    "minecraft:cherry_logs": [
        "minecraft:cherry_log",
        "minecraft:cherry_wood",
        "minecraft:stripped_cherry_log",
        "minecraft:stripped_cherry_wood",
    ],
    "minecraft:birch_logs": [
        "minecraft:birch_log",
        "minecraft:birch_wood",
        "minecraft:stripped_birch_log",
        "minecraft:stripped_birch_wood",
    ],
    "minecraft:warped_stems": [
        "minecraft:stripped_warped_hyphae",
        "minecraft:stripped_warped_stem",
        "minecraft:warped_hyphae",
        "minecraft:warped_stem",
    ],
    "minecraft:crimson_stems": [
        "minecraft:crimson_hyphae",
        "minecraft:crimson_stem",
        "minecraft:stripped_crimson_hyphae",
        "minecraft:stripped_crimson_stem",
    ],
    "minecraft:spruce_logs": [
        "minecraft:stripped_spruce_log",
        "minecraft:stripped_spruce_wood",
        "minecraft:spruce_log",
        "minecraft:spruce_wood",
    ],
    "minecraft:acacia_logs": [
        "minecraft:stripped_acacia_log",
        "minecraft:stripped_acacia_wood",
        "minecraft:acacia_log",
        "minecraft:acacia_wood",
    ],
    "minecraft:oak_logs": [
        "minecraft:stripped_oak_log",
        "minecraft:stripped_oak_wood",
        "minecraft:oak_log",
        "minecraft:oak_wood",
    ],
    "minecraft:mangrove_logs": [
        "minecraft:stripped_mangrove_log",
        "minecraft:stripped_mangrove_wood",
        "minecraft:mangrove_log",
        "minecraft:mangrove_wood",
    ],
    "minecraft:dark_oak_logs": [
        "minecraft:stripped_dark_oak_log",
        "minecraft:stripped_dark_oak_wood",
        "minecraft:dark_oak_log",
        "minecraft:dark_oak_wood",
    ],
    "minecraft:bamboo_blocks": ["minecraft:bamboo_block", "minecraft:stripped_bamboo_block"],
    "minecraft:jungle_logs": [
        "minecraft:jungle_log",
        "minecraft:jungle_wood",
        "minecraft:stripped_jungle_log",
        "minecraft:stripped_jungle_wood",
    ],
};

const GRID_ORIGIN = [7 * 2, 7 * 2];
const RESULT_ORIGIN = [97 * 2, 21 * 2];
const GRID_SIZE = 32;
const GRID_BLOCK_SIZE = 3;
const GAP_SIZE = 4;

const ROOT = import.meta.dir;
const RECIPE_DIR = join(ROOT, "../../recipes/data/crafting/recipes/");
const ICON_DIR = join(ROOT, "icons/");
const OUTPUT_DIR = join(ROOT, "output/");
const COMBINED_OUTPUT_DIR = join(ROOT, "combined_outputs/");
const FONT_PATH = join(ROOT, "Minecraftia-Regular.ttf");
const TABLE_PATH = join(ROOT, "crafting_table.png");

const iconCache = new Map<string, Promise<Image>>();
let tableImage: Promise<Image> | undefined;

function loadIcon(item: string): Promise<Image> {
    const name = item.replace("minecraft:", "");
    let icon = iconCache.get(name);
    if (!icon) {
        icon = loadImage(join(ICON_DIR, `${name}.png`));
        iconCache.set(name, icon);
    }
    return icon;
}

function loadTable(): Promise<Image> {
    return (tableImage ??= loadImage(TABLE_PATH));
}

function getRecipes(): Recipe[] {
    return readdirSync(RECIPE_DIR)
        .filter((file) => file.endsWith(".json"))
        .map((file) => {
            const recipe = JSON.parse(readFileSync(join(RECIPE_DIR, file), "utf8")) as Recipe;
            recipe.name = file.replace(".json", "");
            return recipe;
        });
}

async function generateRecipeImage(recipe: Recipe): Promise<Canvas> {
    const table = await loadTable();

    const tableCanvas = createCanvas(table.width * 2, table.height * 2);
    const tableContext = tableCanvas.getContext("2d");
    tableContext.imageSmoothingEnabled = false;
    tableContext.drawImage(table, 0, 0, tableCanvas.width, tableCanvas.height);

    const gridSize = GRID_SIZE * GRID_BLOCK_SIZE + GAP_SIZE * (GRID_BLOCK_SIZE - 1);
    const gridCanvas = createCanvas(gridSize, gridSize);
    const gridContext = gridCanvas.getContext("2d");
    gridContext.imageSmoothingEnabled = false;

    const pattern = [...(recipe.pattern ?? [])];
    while (pattern.length < 3) pattern.unshift("   ");

    for (let y = 0; y < pattern.length; y++) {
        for (let x = 0; x < pattern[y].length; x++) {
            const key = pattern[y][x];
            if (key === " ") continue;
            const ingredient = recipe.key?.[key]?.item;
            if (!ingredient) continue;
            const icon = await loadIcon(ingredient);
            gridContext.drawImage(icon, GRID_SIZE * x + GAP_SIZE * x, GRID_SIZE * y + GAP_SIZE * y);
        }
    }

    const resultCanvas = createCanvas(48, 48);
    const resultContext = resultCanvas.getContext("2d");
    resultContext.imageSmoothingEnabled = false;
    const rawResult = await loadIcon(recipe.result?.item ?? "");
    resultContext.drawImage(rawResult, 8, 8);

    const count = recipe.result?.count ?? 1;
    if (count > 1) {
        const text = String(count);
        resultContext.font = "16px Minecraftia";
        resultContext.textBaseline = "top";
        const metrics = resultContext.measureText(text);
        const textWidth = metrics.width;
        const textHeight = metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent;
        const textX = 48 - textWidth - 8;
        const textY = 48 - (textHeight + 1) * 2 - 8;
        resultContext.fillStyle = "#3e3e3e";
        resultContext.fillText(text, textX + 2, textY + 2);
        resultContext.fillStyle = "white";
        resultContext.fillText(text, textX, textY);
    }

    tableContext.drawImage(gridCanvas, GRID_ORIGIN[0], GRID_ORIGIN[1]);
    tableContext.drawImage(resultCanvas, RESULT_ORIGIN[0], RESULT_ORIGIN[1]);

    const finalCanvas = createCanvas(tableCanvas.width * 2, tableCanvas.height * 2);
    const finalContext = finalCanvas.getContext("2d");
    finalContext.imageSmoothingEnabled = false;
    finalContext.drawImage(tableCanvas, 0, 0, finalCanvas.width, finalCanvas.height);
    return finalCanvas;
}

function encodeGif(frames: Canvas[], path: string, delay = 1000): void {
    const gif = GIFEncoder();
    for (const frame of frames) {
        const { width, height } = frame;
        const data = frame.getContext("2d").getImageData(0, 0, width, height).data;
        const palette = quantize(data, 256);
        const index = applyPalette(data, palette);
        gif.writeFrame(index, width, height, { palette, delay });
    }
    gif.finish();
    writeFileSync(path, gif.bytes());
}

async function generateImages(): Promise<void> {
    const recipes = getRecipes();

    for (const recipe of recipes) {
        if (recipe.type !== "minecraft:crafting_shaped" || !recipe.key) continue;

        let tag: string | undefined;
        let tagKey: string | undefined;
        const plainKeys: Record<string, Ingredient> = {};

        for (const [key, value] of Object.entries(recipe.key)) {
            if (value.item) plainKeys[key] = { item: value.item };
            if (value.tag) {
                tag = value.tag;
                tagKey = key;
            }
        }

        if (!tag) {
            const image = await generateRecipeImage(recipe);
            writeFileSync(join(OUTPUT_DIR, `${recipe.name}.png`), await image.encode("png"));
            continue;
        }

        const frames: Canvas[] = [];
        for (const icon of TAGS[tag] ?? []) {
            frames.push(
                await generateRecipeImage({
                    ...recipe,
                    key: { ...plainKeys, [tagKey as string]: { item: icon } },
                }),
            );
        }

        if (frames.length > 0) {
            encodeGif(frames, join(OUTPUT_DIR, `${recipe.name}.gif`));
        }
    }
}

const COMBININGS: Record<string, string[]> = {
    chest_boat: [
        "acacia_chest_boat_from_chest.png",
        "acacia_chest_boat_from_logs.gif",
        "bamboo_chest_raft_from_chest.png",
        "birch_chest_boat_from_chest.png",
        "birch_chest_boat_from_logs.gif",
        "cherry_chest_boat_from_chest.png",
        "cherry_chest_boat_from_logs.gif",
        "dark_oak_chest_boat_from_chest.png",
        "dark_oak_chest_boat_from_logs.gif",
        "jungle_chest_boat_from_chest.png",
        "jungle_chest_boat_from_logs.gif",
        "mangrove_chest_boat_from_chest.png",
        "mangrove_chest_boat_from_logs.gif",
        "oak_chest_boat_from_chest.png",
        "oak_chest_boat_from_logs.gif",
        "spruce_chest_boat_from_chest.png",
        "spruce_chest_boat_from_logs.gif",
    ],
    slab: [
        "acacia_slab.gif",
        "bamboo_slab.gif",
        "birch_slab.gif",
        "cherry_slab.gif",
        "crimson_slab.gif",
        "dark_oak_slab.gif",
        "jungle_slab.gif",
        "mangrove_slab.gif",
        "oak_slab.gif",
        "spruce_slab.gif",
        "warped_slab.gif",
    ],
    stairs: [
        "acacia_stairs.gif",
        "bamboo_stairs.gif",
        "birch_stairs.gif",
        "cherry_stairs.gif",
        "crimson_stairs.gif",
        "dark_oak_stairs.gif",
        "jungle_stairs.gif",
        "mangrove_stairs.gif",
        "oak_stairs.gif",
        "spruce_stairs.gif",
        "warped_stairs.gif",
    ],
    trapdoor: [
        "acacia_trapdoor.gif",
        "bamboo_trapdoor.gif",
        "birch_trapdoor.gif",
        "cherry_trapdoor.gif",
        "crimson_trapdoor.gif",
        "dark_oak_trapdoor.gif",
        "jungle_trapdoor.gif",
        "mangrove_trapdoor.gif",
        "oak_trapdoor.gif",
        "spruce_trapdoor.gif",
        "warped_trapdoor.gif",
    ],
    bone_block: ["bone_block_from_bone.png", "bone_block_from_more_bone.png"],
    chest: ["chests.gif", "chests_for_crimson_stems.gif", "chests_for_warped_stems.gif", "chests_for_bamboo_blocks.gif"],
    stick: ["sticks.gif", "sticks_for_crimson_stems.gif", "sticks_for_warped_stems.gif", "sticks_for_bamboo_blocks.gif"],
};

async function loadFrames(file: string): Promise<Canvas[]> {
    const path = join(OUTPUT_DIR, file);

    if (!file.endsWith(".gif")) {
        const image = await loadImage(path);
        const canvas = createCanvas(image.width, image.height);
        canvas.getContext("2d").drawImage(image, 0, 0);
        return [canvas];
    }

    const buffer = readFileSync(path);
    const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
    return decompressFrames(parseGIF(arrayBuffer), true).map((frame) => {
        const canvas = createCanvas(frame.dims.width, frame.dims.height);
        const context = canvas.getContext("2d");
        const imageData = context.createImageData(frame.dims.width, frame.dims.height);
        imageData.data.set(frame.patch);
        context.putImageData(imageData, 0, 0);
        return canvas;
    });
}

async function combineImages(): Promise<void> {
    for (const [name, files] of Object.entries(COMBININGS)) {
        const frames: Canvas[] = [];
        for (const file of files) {
            frames.push(...(await loadFrames(file)));
        }
        encodeGif(frames, join(COMBINED_OUTPUT_DIR, `${name}.gif`));
    }
}

GlobalFonts.registerFromPath(FONT_PATH, "Minecraftia");
mkdirSync(OUTPUT_DIR, { recursive: true });
mkdirSync(COMBINED_OUTPUT_DIR, { recursive: true });

await generateImages();
await combineImages();
console.log("Generated recipe images in", OUTPUT_DIR);
console.log("Generated combined images in", COMBINED_OUTPUT_DIR);
