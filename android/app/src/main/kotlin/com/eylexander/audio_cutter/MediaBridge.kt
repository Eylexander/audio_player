package com.eylexander.audio_cutter

import android.Manifest
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import androidx.core.net.toUri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.eylexander.audio_cutter.data.AudioLibrary
import com.eylexander.audio_cutter.media.AudioCutter
import com.eylexander.audio_cutter.media.MediaProbe
import com.eylexander.audio_cutter.media.WaveformExtractor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Connects the Flutter UI to the Android media stack.
 *
 * Methods go through the `audio_cutter/media` channel. Anything that happens over time
 * (waveform, cut progress, preview position, player state, files opened from other apps) is
 * pushed as `{type: ..., ...}` maps on the `audio_cutter/events` channel.
 */
class MediaBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val context = activity.applicationContext
    private val scope = MainScope()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "audio_cutter/media")
    private val events = EventChannel(messenger, "audio_cutter/events")
    private var sink: EventChannel.EventSink? = null

    private val cutter = AudioCutter(context)
    private val library = AudioLibrary(context)
    private val player = PlayerBridge(context, scope, ::emit)

    /** A file another app sent us: "edit" (shared) or "play" (opened). */
    private var incoming: Pair<String, Uri>? = null
    /** One waveform job per slot: "editor" (the cutter) and "player" (the now-playing seek bar). */
    private val waveformJobs = mutableMapOf<String, Job>()
    private var cutJob: Job? = null

    private var preview: ExoPlayer? = null
    private var previewUri: String? = null
    private var previewJob: Job? = null
    private var previewEndMs = 0L

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        player.connect()
    }

    fun dispose() {
        scope.cancel()
        player.release()
        preview?.release()
        preview = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    fun handleIntent(intent: Intent?) {
        val received = when (intent?.action) {
            Intent.ACTION_SEND -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { "edit" to it }
            Intent.ACTION_VIEW -> intent.data?.let { "play" to it }
            else -> null
        } ?: return
        incoming = received
        emit(mapOf("type" to "incoming"))
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Event sinks must be used on the main thread. */
    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { sink?.success(event) }
    }

    private fun hasLibraryPermission(): Boolean = ContextCompat.checkSelfPermission(context, libraryPermission) ==
        PackageManager.PERMISSION_GRANTED

    private val libraryPermission =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (player.handle(call, result)) return
        when (call.method) {
            "pickFile" -> {
                val types = when (call.argument<String>("kind")) {
                    "video" -> arrayOf("video/*")
                    "playlist" -> arrayOf(
                        "audio/x-mpegurl", "audio/mpegurl", "application/x-mpegurl",
                        "application/vnd.apple.mpegurl", "text/plain", "application/octet-stream",
                    )
                    else -> arrayOf("audio/*")
                }
                activity.pickDocument(types) { uri -> result.success(uri?.toString()) }
            }

            "readPlaylists" -> io(result) {
                synchronized(playlistsLock) {
                    mapOf(
                        "main" to playlistsFile.takeIf { it.exists() }?.readText(),
                        "backup" to playlistsBackup.takeIf { it.exists() }?.readText(),
                    )
                }
            }
            "writePlaylists" -> io(result) {
                // One write at a time. The new content is fully written and synced to a temp file,
                // the current file is kept as a backup, then the temp file atomically replaces it:
                // whatever happens, a complete copy of the playlists stays on disk.
                synchronized(playlistsLock) {
                    val tmp = File(playlistsFile.path + ".tmp")
                    FileOutputStream(tmp).use { out ->
                        out.write(call.argument<String>("json")!!.toByteArray(Charsets.UTF_8))
                        out.fd.sync()
                    }
                    if (playlistsFile.exists()) {
                        Files.copy(playlistsFile.toPath(), playlistsBackup.toPath(), StandardCopyOption.REPLACE_EXISTING)
                    }
                    Files.move(tmp.toPath(), playlistsFile.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
                }
                null
            }

            "readTextFile" -> io(result) {
                val uri = call.argument<String>("uri")!!.toUri()
                val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { if (it.moveToFirst()) it.getString(0) else null }
                val text = context.contentResolver.openInputStream(uri)?.use { input ->
                    val bytes = input.readNBytesCompat(4 shl 20)
                    String(bytes, Charsets.UTF_8)
                }
                mapOf("name" to name, "text" to text)
            }

            "takeIncoming" -> {
                result.success(incoming?.let { (action, uri) -> mapOf("action" to action, "uri" to uri.toString()) })
                incoming = null
            }

            "getPrefs" -> result.success(prefs.all.filterValues { it is String })
            "setPref" -> {
                val key = call.argument<String>("key")!!
                val value = call.argument<String>("value")!!
                prefs.edit().putString(key, value).apply()
                if (key == "theme") applyNightMode(value)
                result.success(null)
            }

            "accentColor" -> result.success(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) activity.getColor(android.R.color.system_accent1_500) else null
            )

            "hasLibraryPermission" -> result.success(hasLibraryPermission())
            "requestLibraryPermission" -> {
                if (hasLibraryPermission()) result.success(true)
                else activity.requestPermission(libraryPermission) { granted -> result.success(granted) }
            }

            "openAppSettings" -> {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                )
                result.success(null)
            }

            "listTracks" -> io(result) { library.tracks() }
            "listSaved" -> io(result) { library.savedCuts() }
            "artwork" -> io(result) {
                library.artwork(call.argument<String>("uri")!!.toUri(), call.argument<Int>("size") ?: 256)
            }

            "deleteFile" -> scope.launch {
                try {
                    val sender = withContext(Dispatchers.IO) { library.delete(call.argument<String>("uri")!!.toUri()) }
                    if (sender == null) result.success(true)
                    else activity.requestDeleteConfirmation(sender) { deleted -> result.success(deleted) }
                } catch (e: Exception) {
                    result.error("delete_failed", e.message, null)
                }
            }

            "shareFile" -> {
                val uri = call.argument<String>("uri")!!.toUri()
                val send = Intent(Intent.ACTION_SEND)
                    .setType(context.contentResolver.getType(uri) ?: "audio/*")
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                activity.startActivity(Intent.createChooser(send, null))
                result.success(null)
            }

            "probe" -> io(result, errorCode = "read_failed") {
                val info = MediaProbe.probe(context, call.argument<String>("uri")!!.toUri())
                val output = AudioCutter.outputFormatFor(info.audioMime)
                mapOf(
                    "name" to info.displayName,
                    "sizeBytes" to info.sizeBytes,
                    "durationMs" to info.durationMs,
                    "hasVideo" to info.hasVideo,
                    "hasAudio" to info.hasAudio,
                    "outputExtension" to output.extension,
                    "copiesOriginal" to output.copiesOriginal,
                )
            }

            "startWaveform" -> startWaveform(call, result)
            "cancelWaveform" -> {
                waveformJobs.remove(call.argument<String>("slot") ?: "editor")?.cancel()
                result.success(null)
            }

            "cut" -> cut(call, result)
            "cancelCut" -> {
                cutJob?.cancel()
                result.success(null)
            }

            "previewPrepare" -> {
                ensurePreview(call.argument<String>("uri")!!)
                result.success(null)
            }
            "previewStart" -> {
                startPreview(call.argument<String>("uri")!!, call.longArg("startMs"), call.longArg("endMs"))
                result.success(null)
            }
            "previewSetEnd" -> {
                previewEndMs = call.longArg("endMs")
                result.success(null)
            }
            "previewStop" -> {
                stopPreview()
                result.success(null)
            }
            "previewRelease" -> {
                stopPreview()
                preview?.release()
                preview = null
                previewUri = null
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun MethodCall.longArg(name: String): Long = (argument<Number>(name) ?: 0).toLong()

    private val prefs get() = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /**
     * Android 12+ remembers a night mode per app and uses it for the splash screen and the window
     * background, so a dark theme chosen in the app doesn't start with a white flash.
     */
    private fun applyNightMode(theme: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val uiModes = context.getSystemService(UiModeManager::class.java) ?: return
        uiModes.setApplicationNightMode(
            when (theme) {
                "light" -> UiModeManager.MODE_NIGHT_NO
                "dark" -> UiModeManager.MODE_NIGHT_YES
                else -> UiModeManager.MODE_NIGHT_AUTO
            }
        )
    }

    private val playlistsFile get() = File(context.filesDir, "playlists.json")
    private val playlistsBackup get() = File(context.filesDir, "playlists.json.bak")
    private val playlistsLock = Any()

    /** Reads at most [limit] bytes (playlist files are tiny; this just guards against picking a huge file). */
    private fun InputStream.readNBytesCompat(limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (out.size() < limit) {
            val read = read(buffer, 0, minOf(buffer.size, limit - out.size()))
            if (read < 0) break
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    /** Runs [block] off the main thread and replies with its value. */
    private fun io(result: MethodChannel.Result, errorCode: String = "failed", block: () -> Any?) {
        scope.launch {
            try {
                result.success(withContext(Dispatchers.IO) { block() })
            } catch (e: Exception) {
                result.error(errorCode, e.message, null)
            }
        }
    }

    private fun startWaveform(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")!!.toUri()
        val token = call.argument<Int>("token")!!
        val durationMs = call.longArg("durationMs")
        val buckets = call.argument<Int>("buckets") ?: 1000
        val slot = call.argument<String>("slot") ?: "editor"
        waveformJobs[slot]?.cancel()
        waveformJobs[slot] = scope.launch {
            val ok = try {
                WaveformExtractor.extract(context, uri, durationMs, buckets) { levels ->
                    emit(mapOf("type" to "waveform", "token" to token, "levels" to DoubleArray(levels.size) { levels[it].toDouble() }))
                }
                true
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                false // Codec not decodable here: the UI simply keeps a flat waveform.
            }
            emit(mapOf("type" to "waveformDone", "token" to token, "ok" to ok))
        }
        result.success(null)
    }

    private fun cut(call: MethodCall, result: MethodChannel.Result) {
        if (cutJob?.isActive == true) {
            result.error("busy", "A cut is already being saved", null)
            return
        }
        val uri = call.argument<String>("uri")!!.toUri()
        val baseName = call.argument<String>("name")!!
        stopPreview()
        cutJob = scope.launch {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            try {
                val (file, format) = cutter.cut(uri, call.longArg("startMs"), call.longArg("endMs")) { progress ->
                    emit(mapOf("type" to "cutProgress", "progress" to progress))
                }
                val (savedUri, savedName) = withContext(Dispatchers.IO) {
                    try {
                        library.save(file, baseName, format.extension)
                    } finally {
                        file.delete()
                    }
                }
                result.success(mapOf("uri" to savedUri.toString(), "name" to savedName))
            } catch (e: CancellationException) {
                result.error("cancelled", null, null)
                throw e
            } catch (e: Exception) {
                result.error("cut_failed", e.message, e.javaClass.simpleName)
            } finally {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    @OptIn(UnstableApi::class)
    private fun ensurePreview(uri: String): ExoPlayer {
        preview?.takeIf { previewUri == uri }?.let { return it }
        preview?.release()
        return ExoPlayer.Builder(context)
            // Taking audio focus pauses the music player while previewing.
            .setAudioAttributes(AudioAttributes.DEFAULT, /* handleAudioFocus = */ true)
            .build()
            .apply {
                trackSelectionParameters = trackSelectionParameters.buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true)
                    .build()
                setMediaItem(MediaItem.fromUri(uri))
                prepare()
            }.also {
                preview = it
                previewUri = uri
            }
    }

    /** Plays [startMs]..[endMs] and reports the position until the end is reached. */
    private fun startPreview(uri: String, startMs: Long, endMs: Long) {
        previewJob?.cancel()
        val p = ensurePreview(uri)
        previewEndMs = endMs
        if (p.playbackState == Player.STATE_IDLE) p.prepare()
        p.seekTo(startMs)
        p.play()
        previewJob = scope.launch {
            while (true) {
                delay(40)
                val position = p.currentPosition
                if (position >= previewEndMs || p.playbackState == Player.STATE_ENDED || p.playerError != null) break
                emit(mapOf("type" to "preview", "positionMs" to position))
            }
            p.pause()
            emit(mapOf("type" to "previewEnded"))
        }
    }

    private fun stopPreview() {
        previewJob?.cancel()
        previewJob = null
        preview?.pause()
    }
}
