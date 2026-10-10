package vcp

import org.gradle.api.provider.Property

abstract class RecipeDataExtension {
    abstract val mcVersion: Property<String>
}
