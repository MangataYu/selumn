import com.android.build.api.variant.ResValue
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.reader(Charsets.UTF_8).use { localProperties.load(it) }
}

// Keep local data separate when a release build connects to a test service.
val selumnEnvironments = (project.findProperty("dart-defines") as? String)
    .orEmpty()
    .split(',')
    .filter { it.isNotEmpty() }
    .map { encoded ->
        try {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        } catch (error: IllegalArgumentException) {
            throw GradleException("Invalid Flutter dart-defines encoding.", error)
        }
    }
    .filter { it == "SELUMN_ENVIRONMENT" || it.startsWith("SELUMN_ENVIRONMENT=") }
require(selumnEnvironments.size <= 1) { "SELUMN_ENVIRONMENT must be specified only once." }
val selumnEnvironment = selumnEnvironments.singleOrNull()
    ?.substringAfter('=', "") ?: "production"
require(selumnEnvironment in setOf("production", "staging", "development")) {
    "SELUMN_ENVIRONMENT must be production, staging, or development."
}
val selumnApplicationIdSuffix = if (selumnEnvironment == "production") "" else ".$selumnEnvironment"
val selumnAppName = when (selumnEnvironment) {
    "staging" -> "Selume Staging"
    "development" -> "Selume Development"
    else -> "Selume"
}

val releaseKeystore = file("key.jks")
val releaseStorePassword = System.getenv("ANDROID_STORE_PASSWORD")
    ?: localProperties.getProperty("storePassword")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
    ?: localProperties.getProperty("keyPassword")
val hasReleaseSigning = releaseKeystore.isFile &&
    !releaseStorePassword.isNullOrBlank() && !releaseKeyPassword.isNullOrBlank()

// AGP may emit an unsigned APK when a signing config is incomplete.
val verifyProductionReleaseSigning = tasks.register("verifyProductionReleaseSigning") {
    doLast {
        check(hasReleaseSigning) {
            "Production release signing requires app/key.jks, ANDROID_STORE_PASSWORD " +
                "and ANDROID_KEY_PASSWORD (or storePassword/keyPassword in local.properties)."
        }
    }
}
tasks.matching { it.name == "preProductionReleaseBuild" }.configureEach {
    dependsOn(verifyProductionReleaseSigning)
}

android {
    namespace = "cn.yooss.moodiary"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // Channel and server environment both contribute to the generated app name.
    buildFeatures {
        resValues = true
    }

    signingConfigs {
        create("config") {
            storeFile = releaseKeystore
            storePassword = releaseStorePassword
            keyPassword = releaseKeyPassword
            keyAlias = "key0"
            enableV3Signing = true
        }
    }

    defaultConfig {
        applicationId = "com.aerieyarrowy.selume"
        // 28 起才认 DT_ANDROID_RELR；native_toolchain_rust 把 apiTarget 硬编码成 35，26/27 会静默跳过全部重定位
        minSdk = 28
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    flavorDimensions += "channel"
    productFlavors {
        create("production") {
            dimension = "channel"
            // A production release must never fall back to a debug certificate.
            signingConfig = signingConfigs.getByName("config")
        }
        create("alpha") {
            dimension = "channel"
            applicationIdSuffix = ".alpha"
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "config" else "debug",
            )
        }
    }

    buildTypes {
        release {
            if (selumnApplicationIdSuffix.isNotEmpty()) {
                applicationIdSuffix = selumnApplicationIdSuffix
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = "$selumnApplicationIdSuffix.debug"
            versionNameSuffix = "-debug"
        }
        maybeCreate("profile").apply {
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = "$selumnApplicationIdSuffix.profile"
        }
    }
}

androidComponents {
    onVariants(selector().all()) { variant ->
        val isAlpha = variant.productFlavors.any { it.first == "channel" && it.second == "alpha" }
        val appName = buildString {
            append(selumnAppName)
            if (isAlpha) append(" Alpha")
            when (variant.buildType) {
                "debug" -> append(" Debug")
                "profile" -> if (isAlpha || selumnApplicationIdSuffix.isNotEmpty()) append(" Profile")
            }
        }
        variant.resValues.put(
            variant.makeResValueKey("string", "app_name"),
            ResValue(appName, "Selume channel and server environment"),
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.material:material:1.14.0")
}
