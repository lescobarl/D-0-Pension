import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Con AGP 9 el Flutter Gradle Plugin gestiona el plugin de Kotlin; aquí no
    // se declara 'kotlin-android'. El Flutter Gradle Plugin va después.
    id("dev.flutter.flutter-gradle-plugin")
    // Procesa android/app/google-services.json (Firebase Analytics).
    id("com.google.gms.google-services")
}

// Credenciales de firma de release (keystore.properties NO se versiona).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/keystore.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.pensiones.ley73"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // ID único definitivo para Play Store.
        applicationId = "com.pensiones.ley73"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Firma con la keystore de upload (keystore.properties) en local/release
            // real; en CI (sin keystore.properties) cae a firma debug para poder
            // compilar/validar el release. La firma debug nunca se publica.
            signingConfig = if (keystorePropertiesFile.exists()) {
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

dependencies {
    // Requisito de Play Console (>= 2026-08-30): Google Play Billing 8.0.0 o posterior.
    // in_app_purchase_android 0.5.0 ya la incluye; se fija aquí para garantizar que el
    // AAB resuelva >= 8.0.0 y que Google Play detecte la versión correcta.
    implementation("com.android.billingclient:billing:8.0.0")
}
