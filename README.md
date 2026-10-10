# VanillaCrafting+

VanillaCrafting+ makes vanilla crafting a lot faster by adding alternative recipes.
It doesn't add any advantage to vanilla gameplay — every added recipe is a shortcut to
something you could already craft.

Ships as a mod for **Fabric, Forge and NeoForge**, and as a standalone **datapack**.
Built from one shared codebase with [Stonecutter](https://stonecutter.kikugie.dev/).

Read **[AGENTS.md](AGENTS.md)** for the full operational guide (node system, long-running
decompile builds, dev-run directories, known traps, and notes for AI coding agents).

## Recipes

### Logs/Stems/Bamboos To Chests
![Logs/Stems/Bamboos To Chests](https://cdn.modrinth.com/data/DfbZLvZG/images/25cad210375ca3a88f3a0edde43687a585c70c02.gif)

### Logs/Stems/Bamboos To Stairs
![Logs/Stems/Bamboos To Stairs](https://cdn.modrinth.com/data/DfbZLvZG/images/ae3031a4711bc914d84719e66e39f50b3fbca59e.gif)

### Logs/Stems/Bamboos To Trapdoors
![Logs/Stems/Bamboos To Trapdoors](https://cdn.modrinth.com/data/DfbZLvZG/images/17b46ddec4994de2b8c8c756534858a160632de5.gif)

### Logs/Stems/Bamboos To Sticks
![Logs/Stems/Bamboos To Sticks](https://cdn.modrinth.com/data/DfbZLvZG/images/8a15a440f415627557dbc4727d3b339379e47d26.gif)

### Logs/Stems/Chests To Chest Boat
![Logs/Stems/Chests To Chest Boat](https://cdn.modrinth.com/data/DfbZLvZG/images/c0d2e56c55771a0cef9f109f743e180c9b3dd413.gif)

### Logs/Stems and Iron To Hopper
![Logs/Stems and Iron To Hopper](https://cdn.modrinth.com/data/DfbZLvZG/images/3a69c32593a1386114e89c83b036047949346a2a.gif)

### Bones To Bone Blocks
![Bones To Bone Blocks](https://cdn.modrinth.com/data/DfbZLvZG/images/dca83868a8e25dfa8db6e65a472f4a71c4d505ae.gif)

### Glowstone Dust and Redstone To Redstone Lamp
![Glowstone Dust and Redstone To Redstone Lamp](https://cdn.modrinth.com/data/DfbZLvZG/images/8b36849f4afeb882a5b7d58e8bfda36fd5ca5487.png)

## Recipe pipeline

Recipes are stored once, in the old datapack's 1.20.4 format, under
`recipes/data/<namespace>/recipes/`. The `vcp-recipes` plugin in `buildSrc/` converts
them to whatever format the node's Minecraft version expects at build time:

- 1.20.5+: recipe results use `id` instead of `item`
- 1.21+: `data/<ns>/recipes/` is renamed to `data/<ns>/recipe/`
- 1.21.2+: ingredient wrapper objects become item IDs / `#tag` strings
- content that does not exist yet in the target version (raw ore blocks, chest boats,
  mangrove, cherry, bamboo) is dropped

The converted recipes are fed into the mod's resources, and `datapackZip` packages the
same output (plus an era-correct `pack.mcmeta`) as a standalone datapack zip.

## Requirements

- **JDK 25** to run the Gradle daemon (all nodes)
- Game run JDKs (8 / 17 / 21 / 25, depending on the Minecraft era) are downloaded
  automatically via Gradle toolchains

## Building

```powershell
.\gradlew.bat --no-daemon --no-configuration-cache :26.2-fabric:buildAndCollect
.\gradlew.bat --no-daemon --no-configuration-cache :26.1-forge:buildAndCollect
.\gradlew.bat --no-daemon --no-configuration-cache :26.1-neoforge:buildAndCollect
```

`buildAndCollect` builds the mod jars, packages the standalone datapack zip, and copies
everything into `build/libs/<mod version>/`. A single node can also be built with
`datapackZip` alone.

## Nodes

| Node              | Loader   | Range claimed      | Why this boundary |
|-------------------|----------|--------------------|-------------------|
| `1.16.5-fabric`   | Fabric   | `>=1.16.5 <1.18.2` | Floor; monolithic Fabric API (`fabric` mod id) |
| `1.18.2-fabric`   | Fabric   | `>=1.18.2 <26.2`   | Modular Fabric API (`fabric-api` id) from 1.18.2 |
| `26.2-fabric`     | Fabric   | `>=26.2`           | Newest |
| `1.16.5-forge`    | Forge    | `>=1.16.5 <1.20.6` | Floor; SRG runtime names, reobfuscated jar |
| `1.20.6-forge`    | Forge    | `>=1.20.6 <26.1`   | Official runtime names from 1.20.6 (no Forge 1.20.5) |
| `26.1-forge`      | Forge    | `>=26.1`           | Newest |
| `1.20.4-neoforge` | NeoForge | `>=1.20.4 <1.20.6` | Floor; `META-INF/mods.toml` metadata (FML 2.x) |
| `1.20.6-neoforge` | NeoForge | `>=1.20.6 <26.1`   | `neoforge.mods.toml` metadata from 20.5/1.20.6 |
| `26.1-neoforge`   | NeoForge | `>=26.1`           | Newest |

The three era boundaries (Fabric API id, Forge runtime names, NeoForge metadata) were
each found by running the production tests below — see
[AGENTS.md section 10](AGENTS.md#10-gradual-version-development-finding-era-boundaries).

## Production tests

`scripts/e2e-prod.ps1` installs a real loader (no Gradle dev runtime) into
`build/prod/<node>@<mc>/`, boots a dedicated server with the built jar, and asserts
that the mod initialized and that no recipes failed to parse. The `-Mc` argument may
differ from the node to test a jar at the end of its claimed range:

```powershell
.\scripts\e2e-prod.ps1 -Node 1.16.5-forge -Mc 1.20.4
.\scripts\e2e-prod.ps1 -Node 26.1-forge -Mc 26.3
```

Reports are written to `build/prod/<node>@<mc>.log`. `scripts/validate-jars.ps1`
statically checks every collected jar's embedded range, loader metadata, pack.mcmeta
schema, entrypoints and bytecode level against `stonecutter.properties.toml`:

```powershell
.\scripts\validate-jars.ps1 -Version 1.0.2
```

## Recipe images

`scripts/imagegen/` regenerates the recipe GIFs/PNGs used in the gallery (Bun):

```powershell
cd scripts\imagegen
bun install
bun run main.ts
```

Outputs land in `scripts/imagegen/output/` and `scripts/imagegen/combined_outputs/`.

## Dev runs

```powershell
.\gradlew.bat --no-daemon --no-configuration-cache :26.2-fabric:runClient
.\gradlew.bat --no-daemon --no-configuration-cache :26.1-forge:runServer
```

Fabric and Forge share the root `run/` directory; NeoForge nodes use
`versions/<node>/run`. See AGENTS.md section 5 for details.

## Publishing

```powershell
$env:MODRINTH_TOKEN = "<token>"
.\scripts\publish-modrinth.ps1 -Loader neoforge -IncludeSources
.\scripts\publish-modrinth.ps1 -Loader datapack
```

Each loader publishes one jar per era boundary (nine nodes in total); the datapack
channel publishes one zip per data-format era. Dry-run without a token by adding
`-DryRun`.

## License

MIT, see [LICENSE](LICENSE).
