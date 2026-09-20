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
