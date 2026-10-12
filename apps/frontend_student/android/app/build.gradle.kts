import java.util.Properties

val releasePropertiesFile = rootProject.file("key.properties")
val releaseProperties = Properties()
if (releasePropertiesFile.isFile) {
    releasePropertiesFile.inputStream().use(releaseProperties::load)
}
val releaseSigningReady = listOf(
    "storeFile", "storePassword", "keyAlias", "keyPassword",
).all { releaseProperties.getProperty(it)?.isNotBlank() == true }

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Opt in only for local x64 emulator checks. Distributable APKs remain arm64.
val emulatorTestAbi = System.getenv("EMULATOR_TEST_ABI") == "true"

android {
    namespace = "com.example.frontend_student"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.smartattendance.mobile.v2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Flutter's current Android baseline satisfies secure storage's API 23 requirement.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The Android package targets arm64 phones, which include the native
        // MediaPipe and ONNX libraries used by face verification.
        ndk {
            abiFilters.clear()
            abiFilters += if (emulatorTestAbi) "x86_64" else "arm64-v8a"
        }
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    packaging {
        jniLibs {
            excludes += if (emulatorTestAbi) {
                setOf("**/armeabi-v7a/**", "**/x86/**", "**/arm64-v8a/**")
            } else {
                setOf("**/armeabi-v7a/**", "**/x86/**", "**/x86_64/**")
            }
        }
    }

}

dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}

gradle.taskGraph.whenReady {
    val requestsReleaseArtifact = allTasks.any {
        it.project == project &&
            (it.name.startsWith("assemble") ||
                it.name.startsWith("bundle") ||
                it.name.startsWith("package")) &&
            it.name.contains("Release")
    }
    if (requestsReleaseArtifact && !releaseSigningReady) {
        throw GradleException(
            "Release signing is required. Create android/key.properties from android/key.properties.example.",
        )
    }
}

flutter {
    source = "../.."
}
