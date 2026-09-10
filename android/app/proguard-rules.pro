# ProGuard rules for 5Birr release build
# Keep Supabase and Flutter dependencies
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.supabase.** { *; }
-dontwarn io.flutter.embedding.**
