package com.eylexander.audio_cutter.data

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.IntentSender
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/** The device's audio files through MediaStore. All calls are blocking. */
class AudioLibrary(context: Context) {

    companion object {
        /** Where cuts are saved. */
        val CUTS_PATH = "${Environment.DIRECTORY_MUSIC}/AudioCutter"

        private val ALBUM_ART_BASE: Uri = Uri.parse("content://media/external/audio/albumart")

        fun albumArtUri(albumId: Long): Uri? = if (albumId > 0) ContentUris.withAppendedId(ALBUM_ART_BASE, albumId) else null
    }

    private val resolver = context.contentResolver
    private val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)

    /**
     * Every audio file except system sounds (ringtones, alarms, notifications). Files that
     * weren't scanned yet have NULL flags, hence "IS NOT 1" rather than "= 0".
     */
    fun tracks(): List<Map<String, Any?>> = query(
        "${MediaStore.Audio.Media.IS_RINGTONE} IS NOT 1 AND ${MediaStore.Audio.Media.IS_ALARM} IS NOT 1 AND " +
            "${MediaStore.Audio.Media.IS_NOTIFICATION} IS NOT 1",
        emptyArray(),
    )

    /** The files this app created, newest first. */
    fun savedCuts(): List<Map<String, Any?>> =
        query("${MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?", arrayOf("$CUTS_PATH/%"))
            .sortedByDescending { it["dateAddedMs"] as Long }

    private fun query(selection: String, args: Array<String>): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.RELATIVE_PATH,
        )
        val items = mutableListOf<Map<String, Any?>>()
        resolver.query(collection, projection, selection, args, null)?.use { c ->
            val id = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val duration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val track = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val size = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val added = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val name = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val path = c.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
            fun text(index: Int) = c.getString(index)?.takeIf { it.isNotBlank() && it != MediaStore.UNKNOWN_STRING }
            while (c.moveToNext()) {
                val displayName = c.getString(name).orEmpty()
                items += mapOf(
                    "uri" to ContentUris.withAppendedId(collection, c.getLong(id)).toString(),
                    "title" to (text(title) ?: displayName.substringBeforeLast('.')),
                    "artist" to text(artist),
                    "album" to text(album),
                    "albumId" to c.getLong(albumId),
                    "durationMs" to c.getLong(duration),
                    "trackNumber" to c.getInt(track),
                    "sizeBytes" to c.getLong(size),
                    "dateAddedMs" to c.getLong(added) * 1000,
                    "displayName" to displayName,
                    "folder" to c.getString(path).orEmpty().trimEnd('/'),
                )
            }
        }
        return items
    }

    /** Copies [source] into Music/AudioCutter as "[baseName].[extension]". Returns the stored uri and real file name. */
    fun save(source: File, baseName: String, extension: String): Pair<Uri, String> {
        val values = ContentValues().apply {
            // No MIME type on purpose: MediaStore derives it from the extension, which keeps the name intact.
            put(MediaStore.Audio.Media.DISPLAY_NAME, "$baseName.$extension")
            put(MediaStore.Audio.Media.RELATIVE_PATH, CUTS_PATH)
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("Couldn't create the output file")
        try {
            val output = resolver.openOutputStream(uri) ?: throw IOException("Couldn't write the output file")
            output.use { out -> source.inputStream().use { it.copyTo(out) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }
        val storedName = resolver.query(uri, arrayOf(MediaStore.Audio.Media.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
        return uri to (storedName ?: "$baseName.$extension")
    }

    /**
     * Deletes [uri]. Returns null when done, or an [IntentSender] asking the user for confirmation
     * when the file doesn't belong to this app.
     */
    fun delete(uri: Uri): IntentSender? = try {
        resolver.delete(uri, null, null)
        null
    } catch (e: SecurityException) {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                MediaStore.createDeleteRequest(resolver, listOf(uri)).intentSender
            e is RecoverableSecurityException -> e.userAction.actionIntent.intentSender
            else -> throw e
        }
    }

    /** Embedded cover art of an audio file as JPEG, or null if it has none. */
    fun artwork(uri: Uri, sizePx: Int): ByteArray? = try {
        val bitmap = resolver.loadThumbnail(uri, Size(sizePx, sizePx), null)
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            bitmap.recycle()
            out.toByteArray()
        }
    } catch (_: IOException) {
        null
    }
}
