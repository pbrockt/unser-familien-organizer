package com.pbrockt.family_planner

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val batteryChannel = "com.pbrockt.family_planner/battery"
    private val widgetChannel = "com.pbrockt.family_planner/widget"
    private val shareChannel = "com.pbrockt.family_planner/share"
    private var shareMethodChannel: MethodChannel? = null
    private var initialSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Geteilten Text beim (Kalt-)Start merken; warme Shares via onNewIntent.
        initialSharedText = extractSharedText(intent)
        shareMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
        shareMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitial" -> {
                    val t = initialSharedText
                    initialSharedText = null
                    result.success(t)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" ->
                        result.success(requestIgnoreBatteryOptimizations())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "diagnose" ->
                        result.success(
                            try {
                                widgetDiagnostics(applicationContext)
                            } catch (e: Throwable) {
                                "Diagnose-Ausnahme: $e"
                            },
                        )
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent)
        if (text != null) shareMethodChannel?.invokeMethod("shared", text)
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action == Intent.ACTION_SEND &&
            intent.type?.startsWith("text") == true
        ) {
            return intent.getStringExtra(Intent.EXTRA_TEXT)
        }
        return null
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        // Bevorzugt der direkte System-Dialog „App von Akku-Optimierung ausnehmen".
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
            true
        } catch (_: Exception) {
            // Fallback: allgemeine Akku-Optimierungs-Einstellungen öffnen.
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
