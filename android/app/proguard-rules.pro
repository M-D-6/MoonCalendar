# Flutter / plugins ship their own consumer rules; these only silence optional references.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
# Widget code is looked up by RemoteViews through reflection (setLayoutDirection, setFormat12Hour, ...).
-keepclassmembers class * extends android.widget.RemoteViews { *; }
# (The old blanket "-keep class com.md6.mooncalendar.**" is gone: it stopped R8 from shrinking, optimising and
# renaming the app's own code. Manifest components are kept automatically by the AGP/aapt rules.)
# Reference app: strip debug/info logging from release builds.
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** i(...);
    public static *** v(...);
}
