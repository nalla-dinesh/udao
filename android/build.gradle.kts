// Top-level UDAO android build file — the structure of the official
// Flutter template (3.24+), kept verbatim. Every piece of this file
// exists for a reason we have already paid for:
//
//  * allprojects repositories — the Flutter Gradle plugin adds its
//    engine-artifact repo at PROJECT level; a settings-level
//    dependencyResolutionManagement (PREFER_SETTINGS) silently ignored
//    it and broke io.flutter:* resolution (report §8).
//
//  * the build-directory redirect below puts all Android outputs under
//    <repo>/build/ — the flutter TOOL expects the APK exactly there.
//    Without it the Gradle build succeeds but `flutter run` fails with
//    "Gradle build failed to produce an .apk file" (report §10).
//
//  * evaluationDependsOn(":app") orders plugin evaluation after the
//    Flutter plugin has configured the app project.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
