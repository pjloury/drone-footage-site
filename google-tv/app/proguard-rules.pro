# WebView JS interface — keep class names intact
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep Activity
-keep class com.pjloury.dronefootage.** { *; }
