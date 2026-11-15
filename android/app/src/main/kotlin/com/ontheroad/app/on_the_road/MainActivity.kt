package com.ontheroad.app.on_the_road

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.ontheroad/document_scanner"
    private val scanRequestCode = 9107
    private var pendingScanResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "captureDocument") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingScanResult != null) {
                    result.error("scan_in_progress", "A document scan is already open.", null)
                    return@setMethodCallHandler
                }

                pendingScanResult = result
                val options = GmsDocumentScannerOptions.Builder()
                    .setGalleryImportAllowed(false)
                    .setPageLimit(1)
                    .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                    .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                    .build()

                GmsDocumentScanning.getClient(options)
                    .getStartScanIntent(this)
                    .addOnSuccessListener { sender ->
                        try {
                            startIntentSenderForResult(sender, scanRequestCode, null, 0, 0, 0)
                        } catch (error: Exception) {
                            finishScanError("scanner_start_failed", error.message)
                        }
                    }
                    .addOnFailureListener { error ->
                        finishScanError("scanner_unavailable", error.message)
                    }
            }
    }

    @Deprecated("The ML Kit scanner currently returns its result through this callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != scanRequestCode) return
        val result = pendingScanResult ?: return
        if (resultCode != Activity.RESULT_OK) {
            pendingScanResult = null
            result.success(null)
            return
        }

        try {
            val scan = GmsDocumentScanningResult.fromActivityResultIntent(data)
            val uri = scan?.pages?.firstOrNull()?.imageUri
            if (uri == null) {
                finishScanError("no_scanned_page", "The scanner returned no page.")
                return
            }
            result.success(copyToCache(uri).absolutePath)
            pendingScanResult = null
        } catch (error: Exception) {
            finishScanError("scan_result_failed", error.message)
        }
    }

    private fun copyToCache(uri: Uri): File {
        val destination = File(cacheDir, "document_${System.currentTimeMillis()}.jpg")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Could not read scanned image." }
            FileOutputStream(destination).use { output -> input.copyTo(output) }
        }
        return destination
    }

    private fun finishScanError(code: String, message: String?) {
        pendingScanResult?.error(code, message ?: "Document scan failed.", null)
        pendingScanResult = null
    }
}
