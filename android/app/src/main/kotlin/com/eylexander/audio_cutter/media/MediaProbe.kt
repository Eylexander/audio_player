package com.eylexander.audio_cutter.media

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns

data class MediaInfo(
    val uri: Uri,
    val displayName: String,
    val sizeBytes: Long?,
    val durationMs: Long,
    val hasVideo: Boolean,
    val hasAudio: Boolean,
    /** Codec of the first audio track, e.g. "audio/mpeg". */
    val audioMime: String?,
)

object MediaProbe {

    /** Reads name, size, duration and track types. Blocking: call off the main thread. */
    fun probe(context: Context, uri: Uri): MediaInfo {
        var name: String? = null
        var size: Long? = null
        runCatching {
            context.contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
                }
            }
        }

        val tracks = runCatching { probeWithRetriever(context, uri) }.getOrNull()
            ?.takeIf { it.durationMs > 0 }
            ?: probeWithExtractor(context, uri)

        return MediaInfo(
            uri = uri,
            displayName = name ?: uri.lastPathSegment?.substringAfterLast('/') ?: "audio",
            sizeBytes = size,
            durationMs = tracks.durationMs,
            hasVideo = tracks.hasVideo,
            hasAudio = tracks.hasAudio,
            audioMime = runCatching { audioMime(context, uri) }.getOrNull(),
        )
    }

    private fun audioMime(context: Context, uri: Uri): String? {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            return (0 until extractor.trackCount)
                .mapNotNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME) }
                .firstOrNull { it.startsWith("audio/") }
        } finally {
            extractor.release()
        }
    }

    private class Tracks(val durationMs: Long, val hasVideo: Boolean, val hasAudio: Boolean)

    private fun probeWithRetriever(context: Context, uri: Uri): Tracks {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            return Tracks(
                durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0,
                hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes",
                hasAudio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes",
            )
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun probeWithExtractor(context: Context, uri: Uri): Tracks {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            var durationUs = 0L
            var hasVideo = false
            var hasAudio = false
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/")) hasVideo = true
                if (mime.startsWith("audio/")) hasAudio = true
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationUs = maxOf(durationUs, format.getLong(MediaFormat.KEY_DURATION))
                }
            }
            return Tracks(durationUs / 1000, hasVideo, hasAudio)
        } finally {
            extractor.release()
        }
    }
}
