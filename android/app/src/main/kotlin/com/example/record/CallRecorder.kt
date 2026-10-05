package com.example.record

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log

private const val TAG = "CallRecorderApp"

// ---------------------------------------------------------------------------
// Database: one row per manually-recorded call.
// ---------------------------------------------------------------------------
class CallDb(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "calls.db", null, 3) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE calls (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                "number TEXT, name TEXT, start_time INTEGER, " +
                "duration INTEGER, direction TEXT, recording TEXT, status TEXT)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS calls")
        onCreate(db)
    }

    fun insert(
        number: String,
        name: String?,
        startTime: Long,
        duration: Long,
        direction: String,
        recording: String?,
        status: String
    ) {
        val v = ContentValues()
        v.put("number", number)
        v.put("name", name)
        v.put("start_time", startTime)
        v.put("duration", duration)
        v.put("direction", direction)
        v.put("recording", recording)
        v.put("status", status)
        writableDatabase.insert("calls", null, v)
    }

    fun all(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val c = readableDatabase.rawQuery(
            "SELECT id, number, name, start_time, duration, direction, recording, status " +
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
                        "recording" to (if (it.isNull(6)) null else it.getString(6)),
                        "status" to (if (it.isNull(7)) "unknown" else it.getString(7))
                    )
                )
            }
        }
        return out
    }
}

// ---------------------------------------------------------------------------
// Foreground service: records the microphone. Only ever started while the
// app is in the foreground (the user just tapped Start), so the Android 14
// "can't start a mic service from the background" rule does not apply here.
// ---------------------------------------------------------------------------
class RecordingService : Service() {

    companion object {
        /** Absolute path of the file currently being recorded, if any. */
        var currentPath: String? = null
            private set
    }

    private var recorder: MediaRecorder? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val path = intent?.getStringExtra("path")
        if (path == null || !startInForeground()) {
            Log.w(TAG, "RecordingService could not start in foreground")
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
                .setContentTitle("Recording in progress")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .build()

            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(1, notification)
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "startInForeground failed", e)
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
            currentPath = path
            Log.d(TAG, "recording started at $path")
        } catch (e: Exception) {
            Log.e(TAG, "recorder start failed", e)
            try {
                r?.release()
            } catch (ignored: Exception) {
            }
            recorder = null
            currentPath = null
            stopSelf()
        }
    }

    override fun onDestroy() {
        recorder?.let {
            try {
                it.stop()
            } catch (e: Exception) {
                Log.w(TAG, "stop() threw — likely nothing was captured", e)
            }
            it.release()
        }
        recorder = null
        currentPath = null
        super.onDestroy()
    }
}