package com.kio.app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

object CrashFileWriter {
    fun write(context: Context, fileName: String, content: String): String {
        return try {
            writeToDownloads(context, fileName, content)
        } catch (error: Throwable) {
            writeToAppFiles(context, fileName, content)
        }
    }

    fun writeExportZip(context: Context, fileName: String, bytes: ByteArray): String {
        return try {
            writeBytesToDownloads(context, fileName, bytes, "application/zip", "kio_exports")
        } catch (error: Throwable) {
            writeBytesToAppFiles(context, fileName, bytes, "kio_exports")
        }
    }

    private fun writeToDownloads(context: Context, fileName: String, content: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/kio_crash_logs")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Unable to create crash log in Downloads")
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(content.toByteArray(Charsets.UTF_8))
            } ?: throw IOException("Unable to open crash log stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Downloads/kio_crash_logs/$fileName"
        }

        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val directory = File(downloads, "kio_crash_logs")
        if (!directory.exists()) directory.mkdirs()
        val file = File(directory, fileName)
        file.writeText(content, Charsets.UTF_8)
        return file.absolutePath
    }

    private fun writeToAppFiles(context: Context, fileName: String, content: String): String {
        val directory = File(context.getExternalFilesDir(null), "kio_crash_logs")
        if (!directory.exists()) directory.mkdirs()
        val file = File(directory, fileName)
        file.writeText(content, Charsets.UTF_8)
        return file.absolutePath
    }

    private fun writeBytesToDownloads(
        context: Context,
        fileName: String,
        bytes: ByteArray,
        mimeType: String,
        folder: String
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/$folder")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Unable to create export in Downloads")
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
            } ?: throw IOException("Unable to open export stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Downloads/$folder/$fileName"
        }

        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val directory = File(downloads, folder)
        if (!directory.exists()) directory.mkdirs()
        val file = File(directory, fileName)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun writeBytesToAppFiles(context: Context, fileName: String, bytes: ByteArray, folder: String): String {
        val directory = File(context.getExternalFilesDir(null), folder)
        if (!directory.exists()) directory.mkdirs()
        val file = File(directory, fileName)
        file.writeBytes(bytes)
        return file.absolutePath
    }
}
