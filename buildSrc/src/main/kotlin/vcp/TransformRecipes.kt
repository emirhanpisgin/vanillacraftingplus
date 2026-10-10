package vcp

import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import java.io.File

/**
 * Converts the canonical recipe set (stored in the 1.20.4 datapack format) into the
 * format the current Minecraft version expects:
 *
 *  - 1.20.5+: recipe results use `id` instead of `item` (item components update)
 *  - 1.21+:   `data/<ns>/recipes/` is renamed to `data/<ns>/recipe/`
 *  - 1.21.2+: ingredient wrapper objects are removed (`{"item": x}` -> `x`,
 *             `{"tag": x}` -> `#x`)
 *
 * Recipes referencing content that does not exist yet in the target version
 * (raw ore blocks < 1.17, chest boats/mangrove < 1.19, cherry/bamboo < 1.20)
 * are dropped, otherwise the game logs parse errors for unknown items.
 */
abstract class TransformRecipes : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sourceDir: DirectoryProperty

    @get:Input
    abstract val mcVersion: Property<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun run() {
        val version = McVersion.parse(mcVersion.get())
        val source = sourceDir.get().asFile
        val output = outputDir.get().asFile
        output.deleteRecursively()
        val recipeFolder = if (version.atLeast(1, 21)) "recipe" else "recipes"
        val slurper = JsonSlurper()

        source.walkTopDown()
            .filter { it.isFile && it.extension == "json" }
            .forEach { file ->
                if (!included(file.name, version)) return@forEach
                val namespace = file.relativeTo(source).invariantSeparatorsPath.substringBefore('/')
                @Suppress("UNCHECKED_CAST")
                val json = slurper.parse(file) as MutableMap<String, Any?>
                convert(json, version)
                val target = File(output, "data/$namespace/$recipeFolder/${file.name}")
                target.parentFile.mkdirs()
                target.writeText(JsonOutput.prettyPrint(JsonOutput.toJson(json)) + "\n")
            }
    }

    private fun included(name: String, version: McVersion): Boolean {
        if (!version.atLeast(1, 17) && name.contains("_raw_")) return false
        if (!version.atLeast(1, 19) &&
            (name.startsWith("mangrove_") || name.contains("_chest_boat_") || name.contains("_chest_raft_"))
        ) {
            return false
        }
        if (!version.atLeast(1, 20) &&
            (name.startsWith("cherry_") || name.startsWith("bamboo_") || name.contains("_for_bamboo_"))
        ) {
            return false
        }
        return true
    }

    @Suppress("UNCHECKED_CAST")
    private fun convert(json: MutableMap<String, Any?>, version: McVersion) {
        if (version.atLeast(1, 20, 5)) {
            val result = json["result"]
            json["result"] = when (result) {
                is String -> linkedMapOf<String, Any?>("id" to result)
                is MutableMap<*, *> -> {
                    val map = result as MutableMap<String, Any?>
                    map.remove("item")?.let { map["id"] = it }
                    map
                }
                else -> result
            }
        }
        if (version.atLeast(1, 21, 2)) {
            (json["key"] as? Map<*, *>)?.let { key ->
                json["key"] = (key as Map<Any?, Any?>).mapValues { (_, value) -> ingredient(value) }
            }
            (json["ingredients"] as? List<*>)?.let { ingredients ->
                json["ingredients"] = ingredients.map { ingredient(it) }
            }
            if (json.containsKey("ingredient")) json["ingredient"] = ingredient(json["ingredient"])
        }
    }

    private fun ingredient(value: Any?): Any? = when (value) {
        is Map<*, *> -> when {
            value.containsKey("item") -> value["item"]
            value.containsKey("tag") -> "#${value["tag"]}"
            else -> value
        }
        is List<*> -> value.map { ingredient(it) }
        else -> value
    }
}
