# WorkManager — R8 strips the generated Room/WorkDatabase_Impl constructor in release builds
-keep class androidx.work.impl.** { *; }
