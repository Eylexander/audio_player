package com.eylexander.audio_cutter

import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var bridge: MediaBridge? = null
    private var pickCallback: ((Uri?) -> Unit)? = null
    private var deleteCallback: ((Boolean) -> Unit)? = null

    // Activity result launchers have to be registered before the activity starts.
    private val openDocument = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        pickCallback?.invoke(uri)
        pickCallback = null
    }

    private val confirmDelete = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        deleteCallback?.invoke(result.resultCode == RESULT_OK)
        deleteCallback = null
    }

    private var permissionCallback: ((Boolean) -> Unit)? = null
    private val permissionRequest = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissionCallback?.invoke(granted)
        permissionCallback = null
    }

    fun requestPermission(permission: String, callback: (Boolean) -> Unit) {
        permissionCallback?.invoke(false)
        permissionCallback = callback
        permissionRequest.launch(permission)
    }

    fun pickDocument(mimeTypes: Array<String>, callback: (Uri?) -> Unit) {
        pickCallback?.invoke(null)
        pickCallback = callback
        openDocument.launch(mimeTypes)
    }

    fun requestDeleteConfirmation(sender: IntentSender, callback: (Boolean) -> Unit) {
        deleteCallback?.invoke(false)
        deleteCallback = callback
        confirmDelete.launch(IntentSenderRequest.Builder(sender).build())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = MediaBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.handleIntent(intent)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.dispose()
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bridge?.handleIntent(intent)
    }
}
