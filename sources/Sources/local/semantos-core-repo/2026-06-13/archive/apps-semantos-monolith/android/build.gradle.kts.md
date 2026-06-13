---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/android/build.gradle.kts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.848698+00:00
---

# archive/apps-semantos-monolith/android/build.gradle.kts

```kts
// D-O5m.followup-9 Phase C — Firebase + google-services classpath.
// The google-services plugin parses app/google-services.json at
// build time and synthesises the Firebase resource entries used by
// firebase_core / firebase_messaging.  See
// docs/operator-runbooks/push-notification-setup.md for how the real
// tenant-scoped google-services.json swaps in at deploy time.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

```
