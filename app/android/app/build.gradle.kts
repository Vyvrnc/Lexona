plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.orailnoor.droiddesk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        aidl = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "io.github.vyvrnc.lexona"
        minSdk = 28  // Downgraded to 28 to bypass W^X (Write XOR Execute) restrictions on app data
        // 28 lets the app exec programs from its data dir; 36 (needed for new installs on
        // Android 16, Play Protect) starts them through linker64 (NativeExec, socket hook).
        // flutter build apk --android-project-arg=lexona.targetSdk=36
        targetSdk = (project.findProperty("lexona.targetSdk") as String?)?.toInt() ?: 28
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "Lexona"

        ndk {
            // ARM64 only — all modern Android phones
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        // Debug builds install next to the release app (own data, own Debian), so a test build
        // never replaces or breaks the installation in daily use.
        debug {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "Lexona Dev"
        }
        release {
            // GitHub-distributed testing builds intentionally use Android's
            // debug key so release APKs are directly installable.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Enable native (C/C++) build support for wlroots integration
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        jniLibs.useLegacyPackaging = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // .xz images for droiddesk-usb flash.
    implementation("org.tukaani:xz:1.12")
    // USB serial adapters (FTDI, CP210x, CH34x, PL2303, CDC-ACM) for droiddesk-serial; MIT.
    implementation("com.github.mik3y:usb-serial-for-android:3.11.0")
    // In-app terminal (TerminalActivity): Termux's terminal emulator and view, Apache-2.0.
    implementation("com.github.termux.termux-app:terminal-view:v0.118.1")
}
