plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.brokoskokoli.ramuri"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.brokoskokoli.ramuri"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 31
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // WP30: Release-Signatur nur aus der Umgebung (tool/build_signed.sh), nie aus Dateien des Repos. Sind nicht alle
    // vier Variablen gesetzt, bleibt es bei der Debug-Signatur (Gate und lokale Builds ohne Schlüssel).
    val signingEnv = listOf("SIGNING_STORE_FILE", "SIGNING_STORE_PASSWORD", "SIGNING_KEY_ALIAS", "SIGNING_KEY_PASSWORD")
        .associateWith { System.getenv(it) }
    val hasReleaseSigning = signingEnv.values.all { !it.isNullOrEmpty() }
    if (hasReleaseSigning) {
        signingConfigs.create("release") {
            storeFile = file(signingEnv.getValue("SIGNING_STORE_FILE")!!)
            storePassword = signingEnv.getValue("SIGNING_STORE_PASSWORD")
            keyAlias = signingEnv.getValue("SIGNING_KEY_ALIAS")
            keyPassword = signingEnv.getValue("SIGNING_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
