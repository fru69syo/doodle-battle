import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // AR team: Compose compiler (SceneView's ARSceneView is a composable).
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release team: upload-key signing. `android/key.properties` (git-ignored) is written by
// release.yml from GitHub secrets, or by hand for local signed builds (see docs/RELEASE.md).
// Without it, release builds fall back to the debug key so `flutter run --release` still works;
// such builds cannot be uploaded to Play (scripts/check_release.sh rejects them in CI).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }
val hasReleaseKey = keystorePropertiesFile.exists()

android {
    namespace = "com.fru69syo.doodle_battle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fru69syo.doodle_battle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // AR team: needed for the ARSceneView composable hosted in a platform view.
    buildFeatures {
        compose = true
    }

    // Release team: versionCode/versionName come from `--build-number`/`--build-name`
    // (scripts/version_from_tag.sh), see docs/RELEASE.md §versioning.
    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            // R8 + resource shrinking (Flutter enables these by default; stated explicitly so
            // `--no-shrink` cannot silently ship an unshrunk build). Keep rules: proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// AR team: ARCore + SceneView (Filament) for features/ar. See docs/AR.md.
dependencies {
    implementation("io.github.sceneview:arsceneview:4.34.0")
    implementation("com.google.ar:core:1.54.0")
    implementation(platform("androidx.compose:compose-bom:2026.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
}
