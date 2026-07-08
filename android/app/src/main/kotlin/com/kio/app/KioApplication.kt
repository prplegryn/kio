package com.kio.app

import android.app.Application
import android.os.Build
import java.io.PrintWriter
import java.io.StringWriter
import java.time.LocalDateTime

class KioApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val writer = StringWriter()
                throwable.printStackTrace(PrintWriter(writer))
                val timestamp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    LocalDateTime.now().toString().replace(':', '-')
                } else {
                    System.currentTimeMillis().toString()
                }
                val content = buildString {
                    appendLine("kio native crash report")
                    appendLine("thread: ${thread.name}")
                    appendLine("time: $timestamp")
                    appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL}")
                    appendLine("android: ${Build.VERSION.RELEASE} (${Build.VERSION.SDK_INT})")
                    appendLine()
                    appendLine(writer.toString())
                }
                CrashFileWriter.write(this, "kio_native_crash_$timestamp.txt", content)
            } catch (_: Throwable) {
                // Avoid recursive crashes while logging a crash.
            } finally {
                previousHandler?.uncaughtException(thread, throwable)
            }
        }
    }
}
