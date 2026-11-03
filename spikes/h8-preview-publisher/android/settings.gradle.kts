// Standalone spike build (H8 preview publisher). Not part of the HydraCam app build.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // RootEncoder is only published on JitPack. Production must vendor or mirror it.
        maven("https://jitpack.io") {
            content { includeGroup("com.github.pedroSG94.RootEncoder") }
        }
    }
}

rootProject.name = "h8-preview-publisher"
include(":app")
