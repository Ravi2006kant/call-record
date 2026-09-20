package com.example.record

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "call_detection"

    override fun onCreate(savedInstanceState: Bundle?) {
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
        // Call detection will be added here next.
    }
}