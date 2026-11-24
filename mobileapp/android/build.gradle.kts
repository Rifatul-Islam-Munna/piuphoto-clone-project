plugins {
    id("org.jetbrains.kotlin.android") apply false
}

// The AVIF plugin targets Java 11, but Flutter's Kotlin integration can
// default to the JDK running Gradle (21). Keep both compiler targets equal.
project(":flutter_avif_android") {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        // flutter_avif_android 3.1.0 ships the same plugin class in Java and
        // Kotlin. Its original Android build uses the Java implementation.
        exclude("**/FlutterAvifPlugin.kt")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
subprojects {
    plugins.withId("com.android.library") {
        dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.3.0")
    }
    plugins.withId("com.android.application") {
        dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.3.0")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
