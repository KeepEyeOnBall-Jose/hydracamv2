plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.amaia23.hydracam.spike.preview"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.amaia23.hydracam.spike.preview"
        // S7 edge runs Android 8.0 (API 26).
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "h8-spike-1"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Spike only: signed with the debug key so it installs without a keystore.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    // Only the transport modules: no RootEncoder camera/encoder/GL code is used.
    implementation("com.github.pedroSG94.RootEncoder:srt:2.8.1")
    implementation("com.github.pedroSG94.RootEncoder:rtmp:2.8.1")
    implementation("androidx.annotation:annotation:1.9.1")
}
