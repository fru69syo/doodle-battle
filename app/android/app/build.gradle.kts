import java.io.FileInputStream
import java.util.Base64
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

// Compliance team: AdMob App ID (required meta-data; the Mobile Ads SDK crashes at start
// without it). Taken from the Gradle property or environment variable ADMOB_APP_ID
// (release.yml: GitHub secret), defaulting to Google's official *test* App ID so dev/CI builds
// work. scripts/check_release.sh --require-real-admob rejects the test id for Play uploads.
val admobTestAppId = "ca-app-pub-3940256099942544~3347511713"
val admobAppId: String =
    providers.gradleProperty("ADMOB_APP_ID")
        .orElse(providers.environmentVariable("ADMOB_APP_ID"))
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .getOrElse(admobTestAppId)
require(Regex("^ca-app-pub-[0-9]{16}~[0-9]{10}$").matches(admobAppId)) {
    "ADMOB_APP_ID must look like ca-app-pub-0000000000000000~0000000000 (got '$admobAppId')"
}

// Release team: in-app purchases (SPEC §10.2). The Dart flag IAP_ENABLED (app_config.dart
// kIapEnabled) defaults to off; Flutter passes `--dart-define`s to Gradle as the property
// `dart-defines` (comma-separated, each base64 "KEY=VALUE"). While purchases are off, the
// release build overlays src/noIap/AndroidManifest.xml, which removes the BILLING permission
// that the Play Billing library merges in (scripts/check_release.sh checks it).
fun decodeDartDefines(raw: String?): Map<String, String> {
    val out = mutableMapOf<String, String>()
    for (item in (raw ?: "").split(",")) {
        if (item.isBlank()) continue
        val kv: String =
            try {
                String(Base64.getDecoder().decode(item), Charsets.UTF_8)
            } catch (e: IllegalArgumentException) {
                continue
            }
        val i = kv.indexOf('=')
        if (i > 0) out[kv.substring(0, i)] = kv.substring(i + 1)
    }
    return out
}
val dartDefines: Map<String, String> = decodeDartDefines(findProperty("dart-defines") as String?)
val iapEnabled = dartDefines["IAP_ENABLED"] == "true"

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
        // Compliance team: see admobAppId above (AndroidManifest.xml ${admobAppId}).
        manifestPlaceholders["admobAppId"] = admobAppId
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

    sourceSets {
        if (!iapEnabled) {
            getByName("release").manifest.srcFile("src/noIap/AndroidManifest.xml")
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
