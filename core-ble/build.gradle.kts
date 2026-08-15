plugins {
    id("com.android.library")
    kotlin("android")
}

android { namespace = "in.meshsetu.ble"; compileSdk = 36
    defaultConfig { minSdk = 29 }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core-model"))
    implementation(project(":core-protocol"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation(kotlin("test"))
}
