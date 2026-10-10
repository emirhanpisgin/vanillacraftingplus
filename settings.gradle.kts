pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
        maven("https://maven.fabricmc.net/") { name = "FabricMC" }
        maven("https://maven.kikugie.dev/releases") { name = "KikuGie Releases" }
        maven("https://maven.kikugie.dev/snapshots") { name = "KikuGie Snapshots" }
        maven("https://maven.minecraftforge.net/") { name = "MinecraftForge" }
    }
}

plugins {
    // Check the latest version on https://stonecutter.kikugie.dev/blog/changes/0.9
    id("dev.kikugie.stonecutter") version "0.9.7"

    // Cross-compat for 26.1+ and older versions (https://codeberg.org/KikuGie/loom-back-compat)
    id("dev.kikugie.loom-back-compat") version "0.4.2"

    // Auto-downloads missing JDK toolchains (https://github.com/gradle/foojay-toolchains)
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

stonecutter {
    create(rootProject) {
        /**
         * Creates version nodes for multiple loaders.
         *
         * This function will create subprojects named `versions/{project}-{loader}`.
         * Each project has a logical [version], which should match the Minecraft version,
         * whereas [project] is the arbitrary name part of the folder.
         *
         * Each project will also have a separate build script assigned depending on the loader,
         * named `build.{loader}.gradle.kts`.
         */
        fun match(project: String, vararg loaders: String, version: String = project) {
            for (loader in loaders) version("$project-$loader", version)
        }

        // Each loader gets its own build script, named `build.{loader}.gradle.kts`.
        mapBuilds { _, node ->
            "build.${node.project.substringAfterLast('-')}.gradle.kts"
        }

        // One node per loader, kept at the newest supported Minecraft version.
        // Add more `match(...)` lines (and matching sections in stonecutter.properties.toml)
        // to cover older Minecraft versions - see AGENTS.md.
        match("26.2", "fabric")

        match("26.1", "forge")
        match("26.1", "neoforge")

        // Sweep floor nodes (AGENTS.md section 10). Temporary nodes are added and
        // removed one version at a time while walking upward from these floors.
        match("1.16.5", "fabric")
        match("1.16.5", "forge")
        match("1.20.4", "neoforge")

        // Forge runtime-name boundary: <1.20.6 ships SRG-remapped jars, >=1.20.6
        // runs official names (no Forge 1.20.5 exists). One jar cannot cover both.
        match("1.20.6", "forge")

        // NeoForge metadata boundary: 20.4 reads META-INF/mods.toml (FML 2.x),
        // >=20.5 expects neoforge.mods.toml and rejects the old jar.
        match("1.20.6", "neoforge")

        // Fabric API umbrella-id boundary: <=1.18.1's latest API is the monolithic
        // `fabric` mod, 1.18.2's is the modular `fabric-api`.
        match("1.18.2", "fabric")


    }
}

rootProject.name = "VanillaCraftingPlus"
