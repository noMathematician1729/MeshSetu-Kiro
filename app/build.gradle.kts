plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "in.meshsetu.app"
    compileSdk = 36
    defaultConfig { applicationId = "in.meshsetu.app"; minSdk = 29; targetSdk = 36; versionCode = 1; versionName = "0.1.0" }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core-model"))
    implementation(project(":core-protocol"))
    implementation(project(":core-ble"))
}

