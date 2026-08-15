plugins {
    kotlin("jvm")
    id("com.google.protobuf")
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core-model"))
    implementation("com.google.protobuf:protobuf-javalite:4.31.1")
    testImplementation(kotlin("test"))
}

tasks.test { useJUnitPlatform() }

protobuf {
    protoc { artifact = "com.google.protobuf:protoc:4.31.1" }
    generateProtoTasks {
        all().configureEach { builtins { named("java") { option("lite") } } }
    }
}
