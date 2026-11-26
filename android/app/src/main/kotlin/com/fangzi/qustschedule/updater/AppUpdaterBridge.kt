package com.fangzi.qustschedule.updater

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal object UpdaterWorker {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "qust-updater-worker")
    }

    fun execute(task: Runnable) {
        executor.execute(task)
    }
}

class AppUpdaterBridge(
    context: Context,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.fangzi.qustschedule/updater"
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    @Volatile
    private var disposed = false

    fun attach() {
        disposed = false
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    fun dispose() {
        disposed = true
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun postReply(block: () -> Unit) {
        mainHandler.post {
            if (!disposed) block()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canRequestPackageInstalls" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    result.success(appContext.packageManager.canRequestPackageInstalls())
                } else {
                    result.success(true)
                }
            }
            "openInstallSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${appContext.packageName}"),
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        appContext.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_FAILED", e.message, null)
                    }
                } else {
                    result.success(true)
                }
            }
            "installApk" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath.isNullOrBlank()) {
                    result.error("INVALID_PATH", "APK 文件路径为空", null)
                    return
                }

                UpdaterWorker.execute {
                    if (disposed) return@execute
                    try {
                        val apkFile = File(filePath)
                        if (!apkFile.exists() || !apkFile.isFile) {
                            postReply {
                                result.error("FILE_NOT_FOUND", "未找到 APK 文件: $filePath", null)
                            }
                            return@execute
                        }

                        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            FileProvider.getUriForFile(
                                appContext,
                                "${appContext.packageName}.fileprovider",
                                apkFile,
                            )
                        } else {
                            Uri.fromFile(apkFile)
                        }

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        postReply {
                            try {
                                appContext.startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        }
                    } catch (e: Exception) {
                        postReply {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
