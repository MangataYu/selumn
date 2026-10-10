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

android {
    namespace = "cn.yooss.moodiary"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // AGP 9 起 buildFeatures 默认全关；debug buildType 用 resValue 注入 app_name，必须显式打开。
    buildFeatures {
        resValues = true
    }

    signingConfigs {
        create("config") {
            storeFile = file("key.jks")
            storePassword = System.getenv("ANDROID_STORE_PASSWORD")
                ?: localProperties.getProperty("storePassword")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                ?: localProperties.getProperty("keyPassword")
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

    buildTypes {
        release {
            if (selumnApplicationIdSuffix.isNotEmpty()) {
                applicationIdSuffix = selumnApplicationIdSuffix
                resValue("string", "app_name", selumnAppName)
            }
            signingConfig = signingConfigs.getByName("config")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            resValue("string", "app_name", "$selumnAppName Debug")
            applicationIdSuffix = "$selumnApplicationIdSuffix.debug"
            versionNameSuffix = "-debug"
        }
        maybeCreate("profile").apply {
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = "$selumnApplicationIdSuffix.profile"
            if (selumnApplicationIdSuffix.isNotEmpty()) {
                resValue("string", "app_name", "$selumnAppName Profile")
            }
        }
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
