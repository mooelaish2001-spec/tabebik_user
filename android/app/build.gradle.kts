import com.android.build.api.dsl.ApplicationExtension
import com.flutter.gradle.FlutterExtension
import org.gradle.api.JavaVersion
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // AGP 9 provides built-in Kotlin; do not apply kotlin-android.
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterExtension = extensions.getByType<FlutterExtension>()

extensions.configure<ApplicationExtension>("android") {
    namespace = "com.tabebik.tabebik_user"
    compileSdk = flutterExtension.compileSdkVersion
    ndkVersion = flutterExtension.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.tabebik.tabebik_user"
        // Preserve the existing passkey-compatible minimum API level.
        minSdk = maxOf(flutterExtension.minSdkVersion, 28)
        targetSdk = flutterExtension.targetSdkVersion
        versionCode = flutterExtension.versionCode
        versionName = flutterExtension.versionName
    }

    signingConfigs {
        create("release") {
            if (System.getenv("CI") == "true") {
                storeFile = file(
                    requireNotNull(System.getenv("CM_KEYSTORE_PATH")) {
                        "CM_KEYSTORE_PATH is missing. Check Codemagic android_signing configuration."
                    }
                )
                storePassword = requireNotNull(System.getenv("CM_KEYSTORE_PASSWORD")) {
                    "CM_KEYSTORE_PASSWORD is missing from Codemagic."
                }
                keyAlias = requireNotNull(System.getenv("CM_KEY_ALIAS")) {
                    "CM_KEY_ALIAS is missing from Codemagic."
                }
                keyPassword = requireNotNull(System.getenv("CM_KEY_PASSWORD")) {
                    "CM_KEY_PASSWORD is missing from Codemagic."
                }
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (System.getenv("CI") == "true") {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

// Enable Google Services when the Firebase config file exists.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
