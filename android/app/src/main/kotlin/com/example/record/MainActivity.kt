package com.example.record

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "call_detection"

    private lateinit var callReceiver: BroadcastReceiver

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        MethodChannel(
            flutterEngine!!.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "startCallDetection" -> {
                    startCallDetection()
                    result.success("Call detection started")
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startCallDetection() {

        callReceiver = object : BroadcastReceiver() {

            override fun onReceive(
                context: Context?,
                intent: Intent?
            ) {

                if (intent?.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
                    return
                }

                val state = intent.getStringExtra(
                    TelephonyManager.EXTRA_STATE
                )

                when (state) {

                    TelephonyManager.EXTRA_STATE_RINGING -> {
                        sendCallStatus("INCOMING CALL")
                    }

                    TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                        sendCallStatus("CALL ACTIVE")
                    }

                    TelephonyManager.EXTRA_STATE_IDLE -> {
                        sendCallStatus("CALL ENDED")
                    }
                }
            }
        }

        val filter = IntentFilter(
            TelephonyManager.ACTION_PHONE_STATE_CHANGED
        )

        registerReceiver(callReceiver, filter)
    }

    private fun sendCallStatus(status: String) {

        runOnUiThread {

            flutterEngine
                ?.dartExecutor
                ?.binaryMessenger
                ?.let { messenger ->

                    MethodChannel(
                        messenger,
                        CHANNEL
                    ).invokeMethod(
                        "callStatusChanged",
                        status
                    )
                }
        }
    }

    override fun onDestroy() {

        if (::callReceiver.isInitialized) {
            unregisterReceiver(callReceiver)
        }

        super.onDestroy()
    }
}