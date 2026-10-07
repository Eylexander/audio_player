package com.eylexander.audio_cutter

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.core.content.ContextCompat
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.eylexander.audio_cutter.data.AudioLibrary
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Controls [PlaybackService] for the Flutter UI and reports its state as `{type: "player", ...}`
 * events: on every change, and a few times per second while playing so the position moves.
 */
class PlayerBridge(
    private val context: Context,
    private val scope: CoroutineScope,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private var future: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private val pending = mutableListOf<(MediaController) -> Unit>()
    private var ticker: Job? = null

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            emitState()
            updateTicker()
        }
    }

    fun connect() {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val connecting = MediaController.Builder(context, token).buildAsync()
        future = connecting
        connecting.addListener({
            val c = runCatching { connecting.get() }.getOrNull() ?: return@addListener
            controller = c
            c.addListener(listener)
            pending.forEach { it(c) }
            pending.clear()
            emitState()
            updateTicker()
        }, ContextCompat.getMainExecutor(context))
    }

    fun release() {
        ticker?.cancel()
        controller?.removeListener(listener)
        controller = null
        future?.let { MediaController.releaseFuture(it) }
        future = null
    }

    private fun withController(block: (MediaController) -> Unit) {
        controller?.let(block) ?: pending.add(block)
    }

    /** Handles the `player*` methods. Returns false for anything else. */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "playerPlay" -> {
                val items = call.argument<List<Map<String, Any?>>>("items").orEmpty().map(::toMediaItem)
                val index = call.argument<Int>("index") ?: 0
                val shuffle = call.argument<Boolean>("shuffle") ?: false
                withController {
                    it.shuffleModeEnabled = shuffle
                    it.setMediaItems(items, index.coerceIn(0, (items.size - 1).coerceAtLeast(0)), 0)
                    it.prepare()
                    it.play()
                }
            }

            "playerToggle" -> withController {
                if (it.isPlaying) {
                    it.pause()
                } else {
                    if (it.playbackState == Player.STATE_IDLE) it.prepare()
                    if (it.playbackState == Player.STATE_ENDED) it.seekToDefaultPosition(0)
                    it.play()
                }
            }

            "playerNext" -> withController { it.seekToNext() }
            "playerPrevious" -> withController { it.seekToPrevious() }
            "playerSeek" -> withController { it.seekTo((call.argument<Number>("positionMs") ?: 0).toLong()) }
            "playerSkipTo" -> withController { it.seekToDefaultPosition(call.argument<Int>("index") ?: 0) }
            "playerSetShuffle" -> withController { it.shuffleModeEnabled = call.argument<Boolean>("enabled") ?: false }
            "playerSetRepeat" -> withController { it.repeatMode = call.argument<Int>("mode") ?: Player.REPEAT_MODE_OFF }

            "playerAddNext", "playerAddToQueue" -> {
                val item = toMediaItem(call.argument<Map<String, Any?>>("item")!!)
                withController {
                    when {
                        it.mediaItemCount == 0 -> {
                            it.setMediaItem(item)
                            it.prepare()
                            it.play()
                        }
                        call.method == "playerAddNext" -> it.addMediaItem(it.currentMediaItemIndex + 1, item)
                        else -> it.addMediaItem(item)
                    }
                }
            }

            "playerQueue" -> {
                withController { c ->
                    result.success((0 until c.mediaItemCount).map { i ->
                        val item = c.getMediaItemAt(i)
                        mapOf(
                            "uri" to item.mediaId,
                            "title" to (item.mediaMetadata.title?.toString() ?: Uri.parse(item.mediaId).lastPathSegment.orEmpty()),
                            "artist" to item.mediaMetadata.artist?.toString(),
                            "albumId" to (item.mediaMetadata.extras?.getLong("albumId") ?: 0L),
                        )
                    })
                }
                return true
            }

            "playerRefresh" -> emitState()
            else -> return false
        }
        result.success(null)
        return true
    }

    private fun toMediaItem(track: Map<String, Any?>): MediaItem {
        val uri = track["uri"] as String
        val albumId = (track["albumId"] as? Number)?.toLong() ?: 0L
        return MediaItem.Builder()
            .setMediaId(uri)
            .setUri(uri)
            .setRequestMetadata(MediaItem.RequestMetadata.Builder().setMediaUri(Uri.parse(uri)).build())
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(track["title"] as String?)
                    .setArtist(track["artist"] as String?)
                    .setAlbumTitle(track["album"] as String?)
                    .setArtworkUri(AudioLibrary.albumArtUri(albumId))
                    .setExtras(Bundle().apply { putLong("albumId", albumId) })
                    .build()
            )
            .build()
    }

    private fun emitState() {
        val c = controller ?: return
        val item = c.currentMediaItem
        val metadata = item?.mediaMetadata
        emit(
            mapOf(
                "type" to "player",
                "uri" to item?.mediaId,
                "title" to metadata?.title?.toString(),
                "artist" to metadata?.artist?.toString(),
                "album" to metadata?.albumTitle?.toString(),
                "albumId" to (metadata?.extras?.getLong("albumId") ?: 0L),
                "index" to c.currentMediaItemIndex,
                "count" to c.mediaItemCount,
                "isPlaying" to c.isPlaying,
                "buffering" to (c.playbackState == Player.STATE_BUFFERING),
                "positionMs" to c.currentPosition,
                "durationMs" to c.duration.takeIf { it != C.TIME_UNSET }?.coerceAtLeast(0),
                "shuffle" to c.shuffleModeEnabled,
                "repeat" to c.repeatMode,
            )
        )
    }

    private fun updateTicker() {
        val playing = controller?.isPlaying == true
        if (playing && ticker?.isActive != true) {
            ticker = scope.launch {
                while (isActive) {
                    delay(250)
                    emitState()
                }
            }
        } else if (!playing) {
            ticker?.cancel()
            ticker = null
        }
    }
}
