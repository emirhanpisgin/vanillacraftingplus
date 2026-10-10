import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.bundling.Zip
import vcp.GenerateDatapackMeta
import vcp.RecipeDataExtension
import vcp.TransformRecipes

// Recipes are kept once, in the old datapack's 1.20.4 format, under `recipes/data`.
// This plugin converts them to the node's Minecraft era and feeds the result into
// the mod's resources, and can also package them as a standalone datapack zip.
// The node must set `recipeData.mcVersion` and declare `data_pack_format` in
// stonecutter.properties.toml.

val recipeData = extensions.create("recipeData", RecipeDataExtension::class.java)

val transformRecipes = tasks.register<TransformRecipes>("transformRecipes") {
    group = "build"
    description = "Converts the canonical recipes to this node's Minecraft format"
    sourceDir.set(rootProject.layout.projectDirectory.dir("recipes/data"))
    mcVersion.set(recipeData.mcVersion)
    outputDir.set(layout.buildDirectory.dir("processed-recipes"))
}

extensions.getByType(SourceSetContainer::class.java).named("main") {
    resources.srcDir(transformRecipes)
}

val generateDatapackMeta = tasks.register<GenerateDatapackMeta>("generateDatapackMeta") {
    group = "build"
    description = "Generates the pack.mcmeta for the standalone datapack zip"
    mcVersion.set(recipeData.mcVersion)
    packFormat.set(providers.provider { project.property("data_pack_format").toString() })
    outputFile.set(layout.buildDirectory.file("datapack-meta/pack.mcmeta"))
}

val datapackZip = tasks.register<Zip>("datapackZip") {
    group = "build"
    description = "Packages the transformed recipes as a standalone datapack zip"
    from(transformRecipes)
    from(generateDatapackMeta)
    from(rootProject.layout.projectDirectory.file("recipes/pack.png"))
    archiveFileName.set(
        providers.provider {
            "${project.property("mod.id")}-${project.property("mod.version")}-${recipeData.mcVersion.get()}.zip"
        }
    )
    destinationDirectory.set(rootProject.layout.buildDirectory.dir("libs/${project.property("mod.version")}"))
}

tasks.matching { it.name == "buildAndCollect" }.configureEach {
    dependsOn(datapackZip)
}
