# UDAO ProGuard / R8 rules.
#
# R8 safety notes:
#  * Flutter platform channels dispatch by string names, not reflection —
#    but the Kotlin classes holding handler code are kept anyway so name
#    minification can never break stack-trace triage from the in-app
#    diagnostics bundle (Phase 08 exports symbolicated-looking traces).
#  * All Dart-side models are hand-written with manual toJson/fromJson
#    (ADR-0003) — no annotation processors, nothing reflective.
#  * sqflite / sqlcipher_flutter_libs ship their own consumer rules.

# UDAO app classes (MainActivity, future services/receivers, channels).
-keep class in.udao.app.** { *; }

# Flutter embedding + plugin surface.
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep signatures/inner-class metadata for readable traces.
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*

# Transitive JNI/VM noise from SQLCipher/BoringSSL — safe to ignore.
-dontwarn javax.naming.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# MediaPipe Tasks (phase-06 on-device AI): the tasks-genai / tasks-core
# AARs bind through JNI and their option builders are touched from our
# bridge only — R8 has no visibility, so keep the whole surface.
# tasks-core ships consumer rules, but an explicit keep is cheap
# insurance against a model-load crash in the release build only.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Flutter embedding ships Play Core (deferred components / dynamic
# feature delivery) references that are only invoked when an app opts
# into deferred Dart components — udao does not. AGP 8+ turned
# missing-classes warnings into R8 errors; these paths are dead code
# here, so the references are safe to ignore.
-dontwarn com.google.android.play.core.**

# google_mlkit_text_recognition references the optional script
# recognizers (chinese / japanese / korean / devanagari) that live in
# separate ML Kit artifacts. We ship the default (latin) recognizer —
# the plugin only touches these classes when Dart requests those
# scripts, which this app never does.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# SQLCipher (sqflite_sqlcipher + sqlcipher_flutter_libs): the Java
# wrapper classes net.sqlcipher.** are reached from the plugin's
# native/JNI side — R8 sees no direct references and strips them,
# which silently breaks EVERY database call in release builds
# (observed live: "txn.page failed (cause: Null check operator used
# on a null value)" — DB never opens). The sqflite_sqlcipher README
# marks this rule REQUIRED for release APKs.
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**
