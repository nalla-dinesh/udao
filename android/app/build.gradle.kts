import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing inputs, in priority order:
//   1. Environment variables (CI):
//      UDAO_KEYSTORE_PATH, UDAO_KEY_ALIAS, UDAO_STORE_PASSWORD, UDAO_KEY_PASSWORD
//   2. android/key.properties (local): storeFile, keyAlias, storePassword, keyPassword
// Keystores and key.properties are NEVER committed (.gitignore).
// When neither is present, release builds fall back to debug signing so
// local machine builds keep working (Phase 08 wires real signing).
// ---------------------------------------------------------------------------
data class SigningInput(
    val storeFilePath: String,
    val keyAlias: String,
    val storePassword: String,
    val keyPassword: String,
)

fun signingInputFromEnv(): SigningInput? {
    val path = System.getenv("UDAO_KEYSTORE_PATH") ?: return null
    val alias = System.getenv("UDAO_KEY_ALIAS") ?: return null
    val storePassword = System.getenv("UDAO_STORE_PASSWORD") ?: return null
    val keyPassword = System.getenv("UDAO_KEY_PASSWORD") ?: return null
    return SigningInput(path, alias, storePassword, keyPassword)
}

fun signingInputFromProperties(properties: Properties): SigningInput? {
    if (properties.isEmpty) {
        return null
    }
    val path = properties.getProperty("storeFile") ?: return null
    val alias = properties.getProperty("keyAlias") ?: return null
    val storePassword = properties.getProperty("storePassword") ?: return null
    val keyPassword = properties.getProperty("keyPassword") ?: return null
    return SigningInput(path, alias, storePassword, keyPassword)
}

val keystoreProperties = Properties().also { properties ->
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { properties.load(it) }
    }
}

val releaseSigningInput: SigningInput? =
    signingInputFromEnv() ?: signingInputFromProperties(keystoreProperties)

android {
    namespace = "in.udao.app"

    // Flutter 3.41's plugin layer (jni) requires this NDK — NDK
    // versions are backward compatible, so the highest wins. If not
    // installed, AGP auto-installs it when licenses are accepted
    // (flutter doctor --android-licenses), or grab it from SDK Manager
    // → SDK Tools → NDK (Side by side) → 28.2.13676358.
    ndkVersion = "28.2.13676358"

    // compileSdk / targetSdk follow the user's Flutter tool version
    // (Flutter 3.41 → 36). Flutter's Gradle plugin provides the values.
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        // MainActivity reads BuildConfig.FLAVOR to report the build
        // flavor over the udao/platform MethodChannel.
        buildConfig = true
    }

    defaultConfig {
        applicationId = "in.udao.app"
        // Android 8.0 — the floor for our 18–28 audience (Phase 05+ FGS
        // behaviors assume modern APIs).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseSigningInput?.let { input ->
                storeFile = file(input.storeFilePath)
                keyAlias = input.keyAlias
                storePassword = input.storePassword
                keyPassword = input.keyPassword
            }
        }
    }

    // One dimension, two distributions (ADR-0002):
    //   play  → Google Play, notification capture only, NO SMS, NO INTERNET
    //   power → sideload (GitHub/F-Droid), adds bank-SMS capture
    // Same applicationId: power is the same app, distributed outside Play
    // (signing differs anyway — Play App Signing vs local keystore).
    flavorDimensions += "dist"
    productFlavors {
        create("play") {
            dimension = "dist"
            versionNameSuffix = "-play"
        }
        create("power") {
            dimension = "dist"
            versionNameSuffix = "-power"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (releaseSigningInput != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // NormalTheme (android:theme meta-data on MainActivity) parents to
    // Theme.Material3.DayNight.NoActionBar, which lives here.
    implementation("com.google.android.material:material:1.12.0") // verify-latest

    // Phase 03: HealthPinger watchdog scheduling (deferred work that
    // survives process death). Cadence wiring arrives in Phase 05.
    implementation("androidx.work:work-runtime-ktx:2.9.1") // verify-latest

    // Phase 06: on-device Gemma inference (MediaPipe GenAI LLM
    // Inference — text + vision sessions over .task model files).
    // 0.10.35 verified on maven.google.com (Apr-2026 latest stable).
    implementation("com.google.mediapipe:tasks-genai:0.10.35")
    // tasks-genai's LlmInferenceSession.addImage() references
    // MPImage, but the framework.image classes (MPImage,
    // BitmapImageBuilder) ship in tasks-core — which tasks-genai
    // does NOT pull transitively (verified against its POM). Vision
    // needs this on the classpath.
    implementation("com.google.mediapipe:tasks-core:0.10.35")

    // Local JVM unit tests for the pure Kotlin helpers (Phase 04:
    // SmsGate). The real org.json artifact is on the unit-test
    // classpath because the android.jar stub throws "not mocked".
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303") // verify-latest
}
