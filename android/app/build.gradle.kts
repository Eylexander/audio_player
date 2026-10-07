plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.eylexander.audio_cutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.eylexander.audio_cutter"
        // Android 10+: scoped storage / MediaStore lets us save into Music/ without any permission.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release key: .secrets/release.p12 + .secrets/password.txt (git-ignored, on the dev PC), or the
    // RELEASE_KEYSTORE / RELEASE_KEYSTORE_PASS env vars in CI. Every published APK must use this key,
    // or phones refuse the update. Without it, release builds fall back to the debug key.
    val secrets = rootProject.file("../.secrets")
    val releaseKeystore = System.getenv("RELEASE_KEYSTORE")?.let(::file) ?: secrets.resolve("release.p12")
    val releasePassword = System.getenv("RELEASE_KEYSTORE_PASS")
        ?: secrets.resolve("password.txt").takeIf { it.exists() }?.readText()?.trim()

    signingConfigs {
        if (releaseKeystore.exists() && releasePassword != null) {
            create("release") {
                storeFile = releaseKeystore
                storeType = "PKCS12"
                storePassword = releasePassword
                keyAlias = "release"
                keyPassword = releasePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    val media3 = "1.8.0"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-session:$media3")
    implementation("androidx.media3:media3-common:$media3")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
