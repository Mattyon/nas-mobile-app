# WorkManager — R8 strips the generated Room/WorkDatabase_Impl constructor in release builds
-keep class androidx.work.impl.** { *; }

# Car App Library
-keep class androidx.car.app.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
