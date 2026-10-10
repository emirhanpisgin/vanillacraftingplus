import org.gradle.api.tasks.compile.JavaCompile

plugins {
    // This plugin applies the correct loom variant based on the Minecraft version
    id("dev.kikugie.loom-back-compat")
    id("vcp-recipes")
}

recipeData {
    mcVersion.set(sc.current.version)
}

// DO NOT set group = ...!
version = "${property("mod.version")}+${sc.current.version}"
base.archivesName = "${property("mod.id") as String}-fabric"

val requiredJava: JavaVersion = when {
    sc.current.parsed >= "26.1" -> JavaVersion.VERSION_25
    sc.current.parsed >= "1.20.5" -> JavaVersion.VERSION_21
    sc.current.parsed >= "1.18" -> JavaVersion.VERSION_17
    else -> JavaVersion.VERSION_1_8
}

dependencies {
    /**
     * Fetches only the required Fabric API modules to not waste time downloading all of them for each version.
     * @see <a href="https://github.com/FabricMC/fabric">List of Fabric API modules</a>
     */
    fun fapi(vararg modules: String) {
        for (it in modules) modImplementation(fabricApi.module(it, sc.properties["deps.fabric_api"]))
    }

    minecraft("com.mojang:minecraft:${sc.current.version}")
    // Applies Mojang Mappings on obfuscated versions
    loomx.applyMojangMappings()

    // Use `mod{dependency type}` even on 26.1+ - loom-back-compat converts them
    modImplementation("net.fabricmc:fabric-loader:${property("deps.fabric_loader")}")
    if (sc.current.parsed >= "1.17") {
        // Only the resource loader is needed: it is what exposes the mod's data/
        // (recipes) and assets/ (icon) to the game.
        fapi("fabric-resource-loader-v0")
    } else {
        // Fabric API was a single artifact before the module split (1.17).
        val fabricApiVersion: String = sc.properties["deps.fabric_api"]
        modImplementation("net.fabricmc.fabric-api:fabric-api:$fabricApiVersion")
    }
}

loom {
    fabricModJsonPath = rootProject.file("src/main/resources/fabric.mod.json") // Useful for interface injection

    runConfigs.all {
        preferGradleTask = true
        generateRunConfig = true
        runDirectory = rootProject.file("run") // Shares the run directory between versions
    }
}

java {
    withSourcesJar()
}

// Compile with the current JDK but target the Java version each Minecraft version requires.
// A toolchain would force foojay to download a JDK, which failed on this machine.
tasks.withType<JavaCompile>().configureEach {
    options.release.set(requiredJava.majorVersion.toInt())
}

tasks {
    processResources {
        fun MutableMap<String, String>.register(key: String, property: String) {
            val value: String = sc.properties[property]
            inputs.property(key, value)
            set(key, value)
        }

        val props = buildMap {
            register("id", "mod.id")
            register("name", "mod.name")
            register("version", "mod.version")
            register("minecraft", "mod.mc_compat")
            register("pack_fields", "pack_fields")
            set("java", requiredJava.majorVersion)
        }

        // The dependency list differs per era (umbrella `fabric` before the
        // module split, individual modules from 1.17). The raw file keeps a
        // valid placeholder key so Loom can parse it for interface injection;
        // it is replaced with the node's fragment during processing.
        val apiDeps: String = sc.properties["fabric_api_deps"]
        inputs.property("fabric_api_deps", apiDeps)

        filesMatching("fabric.mod.json") {
            expand(props)
            filter { line: String -> if (line.contains("\"fabric-api-deps\"")) "    $apiDeps" else line }
        }
        filesMatching("pack.mcmeta") { expand(props) }

        exclude("META-INF/mods.toml", "META-INF/neoforge.mods.toml")
    }

    register<Copy>("buildAndCollect") {
        group = "build"
        description = "Builds mod jars and copies results to `build/libs/{mod version}/`"

        inputs.property("version", project.property("mod.version"))
        // loomx.mod(Sources)Jar returns the jar task for the applied loom variant
        from(loomx.modJar.flatMap { it.archiveFile }, loomx.modSourcesJar.flatMap { it.archiveFile })
        into(rootProject.layout.buildDirectory.file("libs/${project.property("mod.version")}"))
    }
}

