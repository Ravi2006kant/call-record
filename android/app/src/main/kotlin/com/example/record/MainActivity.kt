package com.example.record

import android.Manifest
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "call_recorder"
    private val reqCode = 42

    private var channel: MethodChannel? = null
    private var player: MediaPlayer? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> result.success(hasCorePermissions())
                "requestPermissions" -> requestPermissionsFromUser(result)
                "getCalls" -> result.success(CallDb(this).all())
                "batteryOk" -> result.success(isBatteryUnrestricted())
                "requestBatteryExemption" -> {
                    requestBatteryExemption()
                    result.success(null)
                }
                "play" -> play(call.argument<String>("path"), result)
                "stop" -> {
                    stopPlayer()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------------- permissions ----------------

    private fun hasCorePermissions(): Boolean {
        return hasPerm(this, Manifest.permission.READ_PHONE_STATE) &&
            hasPerm(this, Manifest.permission.READ_CALL_LOG) &&
            hasPerm(this, Manifest.permission.RECORD_AUDIO)
    }

    private fun requestPermissionsFromUser(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 23) {
            result.success(true)
            return
        }
        val list = mutableListOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.RECORD_AUDIO
        )
        if (Build.VERSION.SDK_INT >= 33) {
            list.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        pendingResult = result
        requestPermissions(list.toTypedArray(), reqCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqCode) {
            pendingResult?.success(hasCorePermissions())
            pendingResult = null
        }
    }

    // ---------------- battery optimisation ----------------

    private fun isBatteryUnrestricted(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryExemption() {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            i.data = Uri.parse("package:$packageName")
            startActivity(i)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    // ---------------- playback ----------------

    private fun play(path: String?, result: MethodChannel.Result) {
        stopPlayer()
        if (path == null) {
            result.error("NO_PATH", "No recording path", null)
            return
        }
        val p = MediaPlayer()
        try {
            p.setDataSource(path)
            p.prepare()
            p.setOnCompletionListener {
                stopPlayer()
                channel?.invokeMethod("playbackDone", null)
            }
            p.start()
            player = p
            result.success(true)
        } catch (e: Exception) {
            p.release()
            result.error("PLAY_FAILED", e.message, null)
        }
    }

    private fun stopPlayer() {
        player?.let {
            try {
                it.stop()
            } catch (e: Exception) {
            }
            it.release()
        }
        player = null
    }

    override fun onDestroy() {
        stopPlayer()
        super.onDestroy()
    }
}
