package com.matty.nas.nas_app

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The phone's time zone, for quiet hours on its own clock (lib/time_zone.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nas/timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "get") result.success(TimeZone.getDefault().id)
                else result.notImplemented()
            }
    }

    override fun onStart() {
        super.onStart()
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
        }
    }
}
