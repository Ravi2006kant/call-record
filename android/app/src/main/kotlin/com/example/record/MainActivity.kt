package com.example.record

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "storage_access")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdk" -> result.success(Build.VERSION.SDK_INT)
                    "hasAccess" -> result.success(hasAllFilesAccess())
                    "requestAccess" -> {
                        requestAllFilesAccess()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT < 30) return false
        return Environment.isExternalStorageManager()
    }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT < 30) return
        try {
            val i = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            i.data = Uri.parse("package:$packageName")
            startActivity(i)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }
}