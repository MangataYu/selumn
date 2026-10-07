allprojects {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    project.layout.buildDirectory.value(newBuildDir.dir(project.name))
    afterEvaluate {
        if (plugins.hasPlugin("com.android.application") ||
            plugins.hasPlugin("com.android.library")
        ) {
            (extensions.getByName("android") as com.android.build.gradle.BaseExtension).apply {
                compileSdkVersion(36)
                buildToolsVersion = "36.0.0"
            }
        }
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions.jvmTarget.set(
                    project.provider {
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(
                            android.compileOptions.targetCompatibility.toString(),
                        )
                    },
                )
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
