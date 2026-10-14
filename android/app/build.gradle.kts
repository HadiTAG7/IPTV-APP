import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: CI (or a local release build) writes android/key.properties with
// storeFile (relative to android/app), storePassword, keyAlias and keyPassword.
// Without it, release builds fall back to the debug key so they still install for testing.
// Read as UTF-8: Properties.load(InputStream) decodes ISO-8859-1 and garbles non-ASCII passwords.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) }
        }
    }
val hasReleaseKey = keystorePropertiesFile.exists()

fun keystoreValue(name: String): String =
    requireNotNull(keystoreProperties.getProperty(name)) { "android/key.properties is missing $name" }

// Non-split Flutter builds keep abiFilters at every default ABI (x86_64 included), so the
// universal APK would carry plugins' x86_64 libraries (libmpv) without libflutter.so and
// crash on x86_64 devices. Package only the ABIs passed with --target-platform instead.
// Split builds (--split-per-abi) use splits.abi, which AGP refuses to combine with abiFilters.
val flutterPlatformAbis =
    mapOf("android-arm" to "armeabi-v7a", "android-arm64" to "arm64-v8a", "android-x64" to "x86_64")

fun booleanProperty(name: String): Boolean = findProperty(name)?.toString()?.toBoolean() ?: false

val targetAbis =
    findProperty("target-platform")
        ?.toString()
        ?.split(",")
        ?.mapNotNull { flutterPlatformAbis[it.trim()] }
        .orEmpty()
val filterTargetAbis =
    targetAbis.isNotEmpty() && !booleanProperty("split-per-abi") && !booleanProperty("disable-abi-filtering")

// Escape hatch for boxes whose GPU drivers misrender under Impeller: `-PimpellerOff=true`
// merges src/impellerOff/AndroidManifest.xml (EnableImpeller=false) into release builds,
// which CI ships as the optional -compat APK. Default builds carry no flag and keep the
// engine's own renderer choice.
val impellerOff = booleanProperty("impellerOff")

android {
    namespace = "io.github.haditag7.iptv_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Never change: it identifies the installed app, and changing it means a reinstall.
        applicationId = "io.github.haditag7.iptv_player"
        // Android 7.0+ (API 24); older boxes and Fire OS 5 are unsupported.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // CI passes `-P force-version-code-ignoring-abi=true` so every APK of a build shares
        // one versionCode (the build.yml run number).
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        if (filterTargetAbis) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreValue("storeFile"))
                storePassword = keystoreValue("storePassword")
                keyAlias = keystoreValue("keyAlias")
                keyPassword = keystoreValue("keyPassword")
            }
        }
    }

    if (impellerOff) {
        sourceSets.getByName("release").manifest.srcFile("src/impellerOff/AndroidManifest.xml")
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
