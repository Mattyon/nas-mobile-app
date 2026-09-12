# WorkManager — R8 strips the generated Room/WorkDatabase_Impl constructor in release builds
-keep class androidx.work.impl.** { *; }

# Car App Library
-keep class androidx.car.app.** { *; }

# Our app classes (car screens, service, API client)
-keep class com.matty.nas.nas_app.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
