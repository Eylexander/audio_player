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
    private var consentCallback: ((Boolean) -> Unit)? = null

    // Activity result launchers have to be registered before the activity starts.
    private val openDocument = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        pickCallback?.invoke(uri)
        pickCallback = null
    }

    private val askConsent = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        consentCallback?.invoke(result.resultCode == RESULT_OK)
        consentCallback = null
    }

    private var returnCallback: (() -> Unit)? = null
    private val openForResult = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        returnCallback?.invoke()
        returnCallback = null
    }

    /** Opens [intent] (e.g. a settings screen) and calls [callback] when the user comes back. */
    fun openAndWait(intent: Intent, callback: () -> Unit) {
        returnCallback?.invoke()
        returnCallback = callback
        openForResult.launch(intent)
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

    /** Shows a system confirmation (delete or write access to files). The callback gets whether the user agreed. */
    fun requestConsent(sender: IntentSender, callback: (Boolean) -> Unit) {
        consentCallback?.invoke(false)
        consentCallback = callback
        askConsent.launch(IntentSenderRequest.Builder(sender).build())
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
