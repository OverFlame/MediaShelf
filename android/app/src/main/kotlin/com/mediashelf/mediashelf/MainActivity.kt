package com.mediashelf.mediashelf

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "mediashelf/playback"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        PlaybackService.channel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAllFilesAccess" ->
                    result.success(hasAllFilesAccess())

                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        openAllFilesAccessSettings()
                    } else {
                        // Android 10 及以下走 READ_EXTERNAL_STORAGE 运行时权限
                        ActivityCompat.requestPermissions(
                            this, arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), 201
                        )
                    }
                    result.success(null)
                }

                "checkNotificationPermission" ->
                    result.success(
                        Build.VERSION.SDK_INT < 33 ||
                            ContextCompat.checkSelfPermission(
                                this, Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                    )

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        ActivityCompat.requestPermissions(
                            this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 200
                        )
                    }
                    result.success(null)
                }

                "startPlaybackService" -> {
                    startPlaybackService()
                    result.success(null)
                }

                "updateNotification" -> {
                    @Suppress("UNCHECKED_CAST")
                    PlaybackService.refresh(call.arguments as? Map<String, Any?>)
                    result.success(null)
                }

                "stopPlaybackService" -> {
                    stopPlaybackService()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= 30) return Environment.isExternalStorageManager()
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.READ_EXTERNAL_STORAGE
        ) == PackageManager.PERMISSION_GRANTED
    }

    /** 跳转到系统「所有文件访问」授权页 */
    private fun openAllFilesAccessSettings() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (e: Exception) {
            // 兜底：跳转到通用授权列表
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            } catch (_: Exception) {
            }
        }
    }

    private fun startPlaybackService() {
        val intent = Intent(this, PlaybackService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopPlaybackService() {
        stopService(Intent(this, PlaybackService::class.java))
    }
}
