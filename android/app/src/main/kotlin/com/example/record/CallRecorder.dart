package com.example.record

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.provider.CallLog
import android.telephony.TelephonyManager
import java.io.File

/** True if the runtime permission is granted (always true below Android 6). */
fun hasPerm(ctx: Context, perm: String): Boolean {
    if (Build.VERSION.SDK_INT < 23) return true
    return ctx.checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
}

// ---------------------------------------------------------------------------
// Database: one row per call
// ---------------------------------------------------------------------------
class CallDb(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "calls.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE calls (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                "number TEXT, name TEXT, start_time INTEGER, " +
                "duration INTEGER, direction TEXT, recording TEXT)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    fun insert(
        number: String,
        name: String?,
        startTime: Long,
        duration: Long,
        direction: String,
        recording: String?
    ) {
        val v = ContentValues()
        v.put("number", number)
        v.put("name", name)
        v.put("start_time", startTime)
        v.put("duration", duration)
        v.put("direction", direction)
        v.put("recording", recording)
        writableDatabase.insert("calls", null, v)
    }

    fun all(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val c = readableDatabase.rawQuery(
            "SELECT id, number, name, start_time, duration, direction, recording " +
                "FROM calls ORDER BY start_time DESC",
            null
        )
        c.use {
            while (it.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to it.getLong(0),
                        "number" to (if (it.isNull(1)) null else it.getString(1)),
                        "name" to (if (it.isNull(2)) null else it.getString(2)),
                        "startTime" to it.getLong(3),
                        "duration" to it.getLong(4),
                        "direction" to (if (it.isNull(5)) null else it.getString(5)),
                        "recording" to (if (it.isNull(6)) null else it.getString(6))
                    )
                )
            }
        }
        return out
    }
}

// ---------------------------------------------------------------------------
// Receiver: wakes up on every phone-state change, even if the app is closed
// ---------------------------------------------------------------------------
class CallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return

        @Suppress("DEPRECATION")
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        val prefs = context.getSharedPreferences("call_state", Context.MODE_PRIVATE)
        val prev = prefs.getString("state", TelephonyManager.EXTRA_STATE_IDLE)
        val now = System.currentTimeMillis()

        // Android often sends the same state twice (second time with the number)
        if (state == prev) {
            if (state == TelephonyManager.EXTRA_STATE_RINGING && !number.isNullOrEmpty()) {
                prefs.edit().putString("number", number).apply()
            }
            return
        }

        if (state == TelephonyManager.EXTRA_STATE_RINGING) {
            prefs.edit()
                .putString("state", state)
                .putString("number", number ?: "")
                .apply()
            return
        }

        if (state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
            // Call connected (answered, or an outgoing call started)
            val incoming = prev == TelephonyManager.EXTRA_STATE_RINGING
            val path = startRecording(context, now)
            val e = prefs.edit()
                .putString("state", state)
                .putBoolean("incoming", incoming)
                .putLong("offhook_time", now)
                .putString("rec_path", path ?: "")
            if (!incoming) e.putString("number", "")
            e.apply()
            return
        }

        if (state == TelephonyManager.EXTRA_STATE_IDLE) {
            val wasConnected = prev == TelephonyManager.EXTRA_STATE_OFFHOOK
            val incoming = prefs.getBoolean("incoming", true)
            val offhookTime = prefs.getLong("offhook_time", now)
            val recPath = prefs.getString("rec_path", "") ?: ""
            val bNumber = prefs.getString("number", "") ?: ""
            prefs.edit().putString("state", state).apply()

            if (!wasConnected) return // missed or rejected call: nothing to store

            context.stopService(Intent(context, RecordingService::class.java))

            // The system writes the call log a moment after the call ends
            val pending = goAsync()
            val appCtx = context.applicationContext
            Thread {
                try {
                    Thread.sleep(2500)
                    saveCall(appCtx, incoming, offhookTime, System.currentTimeMillis(), recPath, bNumber)
                } catch (e: Exception) {
                    // ignore
                } finally {
                    pending.finish()
                }
            }.start()
        }
    }

    private fun startRecording(context: Context, now: Long): String? {
        if (!hasPerm(context, Manifest.permission.RECORD_AUDIO)) return null
        return try {
            val dir = context.getExternalFilesDir("recordings")
                ?: File(context.filesDir, "recordings")
            dir.mkdirs()
            val file = File(dir, "call_$now.m4a")
            val svc = Intent(context, RecordingService::class.java)
                .putExtra("path", file.absolutePath)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(svc)
            } else {
                context.startService(svc)
            }
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun saveCall(
        ctx: Context,
        incoming: Boolean,
        offhookTime: Long,
        endTime: Long,
        recPath: String,
        broadcastNumber: String
    ) {
        var number = broadcastNumber
        var name: String? = null
        var start = offhookTime
        var duration = (endTime - offhookTime) / 1000
        var direction = if (incoming) "incoming" else "outgoing"

        // Best source for number / name / exact duration: the system call log
        if (hasPerm(ctx, Manifest.permission.READ_CALL_LOG)) {
            try {
                val cursor = ctx.contentResolver.query(
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
                        // Make sure this log entry belongs to the call that just ended
                        if (date >= offhookTime - 120_000 && date <= endTime + 5_000) {
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
                // fall back to the values we already have
            }
        }

        var recording: String? = null
        if (recPath.isNotEmpty()) {
            val f = File(recPath)
            if (f.exists() && f.length() > 1024) recording = recPath else f.delete()
        }

        CallDb(ctx).insert(
            if (number.isEmpty()) "Unknown" else number,
            name,
            start,
            duration,
            direction,
            recording
        )
    }
}

// ---------------------------------------------------------------------------
// Foreground service: records the microphone while a call is active
// ---------------------------------------------------------------------------
class RecordingService : Service() {

    private var recorder: MediaRecorder? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val path = intent?.getStringExtra("path")
        if (path == null || !startInForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        startRecording(path)
        return START_NOT_STICKY
    }

    private fun startInForeground(): Boolean {
        return try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val builder: Notification.Builder
            if (Build.VERSION.SDK_INT >= 26) {
                nm.createNotificationChannel(
                    NotificationChannel("rec", "Call recording", NotificationManager.IMPORTANCE_LOW)
                )
                builder = Notification.Builder(this, "rec")
            } else {
                @Suppress("DEPRECATION")
                builder = Notification.Builder(this)
            }
            val notification = builder
                .setContentTitle("Recording call")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .build()

            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(1, notification)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun newRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()
    }

    private fun startRecording(path: String) {
        var r: MediaRecorder? = null
        try {
            r = newRecorder()
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioEncodingBitRate(96000)
            r.setAudioSamplingRate(44100)
            r.setOutputFile(path)
            r.prepare()
            r.start()
            recorder = r
        } catch (e: Exception) {
            try {
                r?.release()
            } catch (ignored: Exception) {
            }
            recorder = null
            stopSelf()
        }
    }

    override fun onDestroy() {
        recorder?.let {
            try {
                it.stop()
            } catch (e: Exception) {
                // stop() throws if nothing was recorded
            }
            it.release()
        }
        recorder = null
        super.onDestroy()
    }
}
