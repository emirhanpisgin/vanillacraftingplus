package vcp

import groovy.json.JsonOutput
import org.gradle.api.DefaultTask
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.TaskAction

/**
 * Writes the pack.mcmeta for the standalone datapack zip. Minecraft 1.21.9+
 * (pack format 82.0) replaced `pack_format` with `min_format`/`max_format`,
 * which accept `[major, minor]` pairs; `max_format` as a bare integer means
 * "any minor version of that major".
 */
abstract class GenerateDatapackMeta : DefaultTask() {
    @get:Input
    abstract val mcVersion: Property<String>

    @get:Input
    abstract val packFormat: Property<String>

    @get:OutputFile
    abstract val outputFile: RegularFileProperty

    @TaskAction
    fun run() {
        val version = McVersion.parse(mcVersion.get())
        val parts = packFormat.get().trim().split('.')
        val major = parts[0].toInt()
        val minor = parts.getOrNull(1)?.toInt() ?: 0
        val description = "Speed your craftings with this datapack!"
        val pack: Map<String, Any> = if (version.atLeast(1, 21, 9)) {
            linkedMapOf(
                "description" to description,
                "min_format" to if (minor != 0) listOf(major, minor) else major,
                "max_format" to major,
            )
        } else {
            linkedMapOf("description" to description, "pack_format" to major)
        }
        val file = outputFile.get().asFile
        file.parentFile.mkdirs()
        file.writeText(JsonOutput.prettyPrint(JsonOutput.toJson(mapOf("pack" to pack))) + "\n")
    }
}
