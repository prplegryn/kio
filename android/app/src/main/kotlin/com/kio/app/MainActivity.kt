package com.kio.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kio/crash_handler")
            .setMethodCallHandler { call, result ->
                if (call.method == "writeCrashLog") {
                    val fileName = call.argument<String>("fileName") ?: "kio_crash.txt"
                    val content = call.argument<String>("content") ?: "No content"
                    try {
                        result.success(CrashFileWriter.write(this, fileName, content))
                    } catch (error: Throwable) {
                        result.error("CRASH_LOG_WRITE_FAILED", error.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
