# R8 keep rules for the release build (Release team). Flutter's own rules
# (flutter_proguard_rules.pro) and the AARs' consumer rules are applied as well;
# these cover what is reached from native code / reflection and is not covered there.

# --- Crash reports (Crashlytics, Play Console vitals) -----------------------
# Keep file/line info so de-obfuscated stack traces stay useful (mapping.txt is
# uploaded with every release, see .github/workflows/release.yml).
-keepattributes SourceFile,LineNumberTable,Signature,*Annotation*,InnerClasses,EnclosingMethod
-renamesourcefileattribute SourceFile
-keep public class * extends java.lang.Exception

# --- ARCore (com.google.ar:core) --------------------------------------------
# The native ARCore runtime calls back into these classes via JNI.
-keep class com.google.ar.core.** { *; }
-keep class com.google.ar.core.exceptions.** { *; }
-keep class com.google.vr.dynamite.** { *; }
-keep class com.google.ar.sceneform.** { *; }
-dontwarn com.google.ar.sceneform.**

# --- Filament / gltfio / SceneView (io.github.sceneview:arsceneview) ----------
# Filament's JNI layer looks up Java classes, fields and methods by name.
-keep class com.google.android.filament.** { *; }
-keepclassmembers class com.google.android.filament.** { native <methods>; }
-keep class io.github.sceneview.** { *; }
-dontwarn io.github.sceneview.**

# --- App AR platform view (Kotlin) ------------------------------------------
-keep class com.fru69syo.doodle_battle.ar.** { *; }

# --- Flutter deferred components ------------------------------------------
# Flutter's embedding references Play Core split-install classes that are not
# on the classpath (the app does not use deferred components).
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# --- Firebase / Play services -------------------------------------------------
# Firebase and Google Play services ship consumer rules in their AARs; nothing
# extra is needed. Keep model classes here if the app ever uses Firestore
# toObject()/POJO mapping from Kotlin/Java (the Dart SDK does not).
