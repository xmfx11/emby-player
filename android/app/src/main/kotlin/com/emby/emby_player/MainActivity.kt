package com.emby.emby_player

import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.emby.emby_player/volume"

    private lateinit var audioManager: AudioManager
    private var originalBrightness: Float = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVolume" -> {
                        val vol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        result.success(vol.toDouble())
                    }
                    "getMaxVolume" -> {
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        result.success(max.toDouble())
                    }
                    "setVolume" -> {
                        val vol = (call.argument<Number>("volume") ?: 0).toInt()
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val clamped = vol.coerceIn(0, max)
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            clamped,
                            0
                        )
                        result.success(null)
                    }
                    // --- 系统屏幕亮度 ---
                    "getScreenBrightness" -> {
                        try {
                            // 返回系统亮度模式：-1=自动，0=手动
                            val mode = Settings.System.getInt(
                                contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS_MODE
                            )
                            val brightness = Settings.System.getInt(
                                contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS
                            )
                            // 返回 0.0~1.0 的亮度值
                            result.success(brightness.toDouble() / 255.0)
                        } catch (e: Exception) {
                            result.success(0.5)
                        }
                    }
                    "setScreenBrightness" -> {
                        val value = (call.argument<Number>("brightness") ?: 0.5).toFloat()
                        val clamped = value.coerceIn(0.0f, 1.0f)
                        try {
                            val attrs = window.attributes
                            // 保存原始亮度（仅第一次）
                            if (originalBrightness == WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE) {
                                originalBrightness = attrs.screenBrightness
                            }
                            attrs.screenBrightness = clamped
                            window.attributes = attrs
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("BRIGHTNESS_ERROR", e.message, null)
                        }
                    }
                    "resetScreenBrightness" -> {
                        try {
                            val attrs = window.attributes
                            attrs.screenBrightness = originalBrightness
                            window.attributes = attrs
                            originalBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("BRIGHTNESS_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
