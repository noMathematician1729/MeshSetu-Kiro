plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "in.meshsetu.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "in.meshsetu.app"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        // The key is intentionally empty by default: a relay still works offline and
        // can fetch public details, while deployments opt in to gateway upload with -PmeshsetuGatewayKey=….
        manifestPlaceholders["meshsetuGatewayUrl"] = providers.gradleProperty("meshsetuGatewayUrl").orElse("https://sih26-1xdevs.onrender.com").get()
        manifestPlaceholders["meshsetuGatewayKey"] = providers.gradleProperty("meshsetuGatewayKey").orElse("").get()
        manifestPlaceholders["meshsetuUserUid"] = providers.gradleProperty("meshsetuUserUid").orElse("").get()
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core-model"))
    implementation(project(":core-protocol"))
    implementation(project(":core-ble"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
