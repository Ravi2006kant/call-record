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
