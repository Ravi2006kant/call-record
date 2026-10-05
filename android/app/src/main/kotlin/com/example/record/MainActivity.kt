package com.example.record

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.CallLog
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "call_recorder"
    private val reqCode = 42

    private var channel: MethodChannel? = null
    private var player: MediaPlayer? = null
    private var pendingResult: MethodChannel.Result? = null
    private var recordingStartedAt: Long = 0

    private fun hasPerm(perm: String): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> result.success(hasCorePermissions())
                "requestPermissions" -> requestPermissionsFromUser(result)
                "startRecording" -> {
                    result.success(startRecording())
                }
                "stopRecording" -> {
                    stopRecording()
                    result.success(null)
                }
                "isRecording" -> result.success(RecordingService.currentPath != null)
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
        return hasPerm(Manifest.permission.RECORD_AUDIO) &&
            hasPerm(Manifest.permission.READ_CALL_LOG)
    }

    private fun requestPermissionsFromUser(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 23) {
            result.success(true)
            return
        }
        val list = mutableListOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_CALL_LOG
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

    // ---------------- recording (manual, foreground-triggered) ----------------

    private fun startRecording(): Boolean {
        if (!hasCorePermissions()) return false
        val dir = getExternalFilesDir("recordings") ?: File(filesDir, "recordings")
        dir.mkdirs()
        val now = System.currentTimeMillis()
        val file = File(dir, "call_$now.m4a")
        recordingStartedAt = now

        val svc = Intent(this, RecordingService::class.java)
            .putExtra("path", file.absolutePath)
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(svc)
        } else {
            startService(svc)
        }
        return true
    }

    private fun stopRecording() {
        val path = RecordingService.currentPath
        val startedAt = recordingStartedAt
        stopService(Intent(this, RecordingService::class.java))

        // Give the recorder a moment to finish writing, then save + match call log.
        Thread {
            try {
                Thread.sleep(800)
            } catch (ignored: InterruptedException) {
            }
            saveCall(path, startedAt, System.currentTimeMillis())
        }.start()
    }

    private fun saveCall(recPath: String?, startedAt: Long, endedAt: Long) {
        var number = "Unknown"
        var name: String? = null
        var start = startedAt
        var duration = (endedAt - startedAt) / 1000
        var direction = "unknown"

        if (hasPerm(Manifest.permission.READ_CALL_LOG)) {
            try {
                val cursor = contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.CACHED_NAME,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION,
                        CallLog.Calls.TYPE
                    ),
                    null,
                    null,
                    CallLog.Calls.DATE + " DESC"
                )
                cursor?.use { c ->
                    if (c.moveToFirst()) {
                        val date = c.getLong(2)
                        // Accept a call-log entry from shortly before we started
                        // recording to shortly after we stopped.
                        if (date >= startedAt - 180_000 && date <= endedAt + 10_000) {
                            val n = c.getString(0)
                            if (!n.isNullOrEmpty()) number = n
                            name = c.getString(1)
                            start = date
                            val d = c.getLong(3)
                            if (d > 0) duration = d
                            when (c.getInt(4)) {
                                CallLog.Calls.INCOMING_TYPE -> direction = "incoming"
                                CallLog.Calls.OUTGOING_TYPE -> direction = "outgoing"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // fall back to what we already have
            }
        }

        var recording: String? = null
        var status: String
        if (recPath == null) {
            status = "not_started"
        } else {
            val f = File(recPath)
            if (!f.exists()) {
                status = "file_missing"
            } else if (f.length() < 1024) {
                status = "silent_or_empty"
                f.delete()
            } else {
                recording = recPath
                status = "ok"
            }
        }

        CallDb(this).insert(number, name, start, duration, direction, recording, status)
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