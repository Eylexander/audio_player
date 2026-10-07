package com.eylexander.audio_cutter.media

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** What a cut of a given source turns into. */
enum class OutputFormat(val extension: String, val copiesOriginal: Boolean) {
    M4A("m4a", true),
    MP3("mp3", true),
    OPUS("ogg", true),
    FLAC("flac", false),
    WAV("wav", false),
}

/**
 * Cuts a part out of an audio or video file without losing any quality:
 *
 * - AAC, MP3 and Opus audio is copied frame by frame. Nothing is re-encoded, so the result is
 *   bit-for-bit the original audio.
 * - Everything else (FLAC, WAV, Vorbis, AC-3...) is decoded and stored as FLAC, which is
 *   lossless. The cut is sample-accurate in that case.
 *
 * Video tracks are always dropped.
 */
class AudioCutter(private val context: Context) {

    companion object {
        private const val TIMEOUT_US = 10_000L

        fun outputFormatFor(audioMime: String?): OutputFormat = when (audioMime) {
            MediaFormat.MIMETYPE_AUDIO_AAC -> OutputFormat.M4A
            MediaFormat.MIMETYPE_AUDIO_MPEG -> OutputFormat.MP3
            MediaFormat.MIMETYPE_AUDIO_OPUS -> OutputFormat.OPUS
            else -> OutputFormat.FLAC
        }
    }

    /** Writes [startMs]..[endMs] of [source] to a temporary file. [onProgress] receives 0-100. */
    suspend fun cut(source: Uri, startMs: Long, endMs: Long, onProgress: (Int) -> Unit): Pair<File, OutputFormat> =
        withContext(Dispatchers.IO) {
            val dir = File(context.cacheDir, "exports").apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() }

            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(context, source, null)
                val track = (0 until extractor.trackCount).firstOrNull {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                } ?: throw IOException("No audio track")
                extractor.selectTrack(track)
                val format = extractor.getTrackFormat(track)
                val range = Range(startMs * 1000, endMs * 1000, onProgress)

                when (val output = outputFormatFor(format.getString(MediaFormat.KEY_MIME))) {
                    OutputFormat.M4A, OutputFormat.OPUS -> {
                        val file = File(dir, "cut.${output.extension}")
                        val container = if (output == OutputFormat.M4A) {
                            MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
                        } else {
                            MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG
                        }
                        copyWithMuxer(extractor, format, range, file, container)
                        file to output
                    }

                    OutputFormat.MP3 -> {
                        val file = File(dir, "cut.mp3")
                        copyMp3Frames(extractor, format, range, file)
                        file to output
                    }

                    else -> decodeToLossless(extractor, format, range, dir)
                }
            } finally {
                extractor.release()
            }
        }

    private class Range(val startUs: Long, val endUs: Long, private val onProgress: (Int) -> Unit) {
        private var lastReported = -1

        fun report(timeUs: Long) {
            val percent = ((timeUs - startUs) * 100 / (endUs - startUs).coerceAtLeast(1)).toInt().coerceIn(0, 100)
            if (percent != lastReported) {
                lastReported = percent
                onProgress(percent)
            }
        }
    }

    private fun sampleBuffer(format: MediaFormat): ByteBuffer =
        ByteBuffer.allocateDirect(format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 1 shl 20).coerceAtLeast(64 * 1024))

    /** Calls [onSample] with every compressed frame of the selection, in order. */
    private suspend fun forEachSample(
        extractor: MediaExtractor,
        format: MediaFormat,
        range: Range,
        onSample: (buffer: ByteBuffer, size: Int, timeUs: Long, flags: Int) -> Unit,
    ) = withContext(Dispatchers.IO) {
        val buffer = sampleBuffer(format)
        extractor.seekTo(range.startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        var copied = 0
        while (true) {
            ensureActive()
            val size = extractor.readSampleData(buffer, 0)
            val timeUs = extractor.sampleTime
            if (size < 0 || timeUs >= range.endUs) break
            if (timeUs >= range.startUs) {
                onSample(buffer, size, timeUs, extractor.sampleFlags)
                copied++
                range.report(timeUs)
            }
            extractor.advance()
        }
        if (copied == 0) throw IOException("The selected part contains no audio")
    }

    private suspend fun copyWithMuxer(extractor: MediaExtractor, format: MediaFormat, range: Range, file: File, container: Int) {
        val muxer = MediaMuxer(file.absolutePath, container)
        var started = false
        try {
            val track = muxer.addTrack(format)
            muxer.start()
            started = true
            val info = MediaCodec.BufferInfo()
            var firstUs = -1L
            forEachSample(extractor, format, range) { buffer, size, timeUs, flags ->
                if (firstUs < 0) firstUs = timeUs
                val keyFrame = if (flags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                info.set(0, size, timeUs - firstUs, keyFrame)
                muxer.writeSampleData(track, buffer, info)
            }
            muxer.stop()
        } finally {
            if (!started) runCatching { file.delete() }
            runCatching { muxer.release() }
        }
    }

    /** MP3 has no container: a file is just its frames one after the other (each frame carries its own header). */
    private suspend fun copyMp3Frames(extractor: MediaExtractor, format: MediaFormat, range: Range, file: File) {
        FileOutputStream(file).channel.use { channel ->
            forEachSample(extractor, format, range) { buffer, size, _, _ ->
                buffer.position(0)
                buffer.limit(size)
                while (buffer.hasRemaining()) channel.write(buffer)
                buffer.clear()
            }
        }
    }

    /** Decodes the selection and keeps it as FLAC (or WAV if the device has no FLAC encoder). */
    private suspend fun decodeToLossless(
        extractor: MediaExtractor,
        format: MediaFormat,
        range: Range,
        dir: File,
    ): Pair<File, OutputFormat> = withContext(Dispatchers.IO) {
        val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        var sink: PcmSink? = null
        try {
            // Decoders hand out 16-bit samples by default, which would throw away the extra
            // resolution of 24-bit sources: ask for float samples instead. Not for raw PCM (WAV,
            // and .flac files, which the platform extractor already decodes): that "decoder" only
            // passes samples through, already in float for hi-res sources, and would mislabel them.
            val isRawPcm = format.getString(MediaFormat.KEY_MIME) == MediaFormat.MIMETYPE_AUDIO_RAW
            val floatConfigured = !isRawPcm && runCatching {
                val floatFormat = MediaFormat(format).apply {
                    setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_FLOAT)
                }
                decoder.configure(floatFormat, null, null, 0)
            }.isSuccess
            if (!floatConfigured) {
                decoder.reset()
                decoder.configure(format, null, null, 0)
            }
            decoder.start()
            extractor.seekTo(range.startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE, 44_100)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT, 2)
            var floatPcm = format.getInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT) ==
                AudioFormat.ENCODING_PCM_FLOAT
            val info = MediaCodec.BufferInfo()
            var inputDone = false

            while (true) {
                ensureActive()
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val size = extractor.readSampleData(decoder.getInputBuffer(inIndex)!!, 0)
                        val timeUs = extractor.sampleTime
                        if (size < 0 || timeUs >= range.endUs) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, timeUs, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val output = decoder.outputFormat
                    sampleRate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                    channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT, channels)
                    floatPcm = output.getInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT) ==
                        AudioFormat.ENCODING_PCM_FLOAT
                } else if (outIndex >= 0) {
                    if (info.size > 0) {
                        // Keep only the frames inside the selection: the cut is sample-accurate.
                        val bytesPerFrame = channels * if (floatPcm) 4 else 2
                        val frames = info.size / bytesPerFrame
                        val first = framesUntil(range.startUs - info.presentationTimeUs, sampleRate).coerceIn(0, frames)
                        val last = framesUntil(range.endUs - info.presentationTimeUs, sampleRate).coerceIn(0, frames)
                        if (last > first) {
                            val pcm = decoder.getOutputBuffer(outIndex)!!
                            pcm.limit(info.offset + last * bytesPerFrame)
                            pcm.position(info.offset + first * bytesPerFrame)
                            val target = sink ?: openSink(dir, sampleRate, channels, floatPcm).also { sink = it }
                            target.write(pcm)
                        }
                        range.report(info.presentationTimeUs)
                    }
                    decoder.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            val done = sink ?: throw IOException("The selected part contains no audio")
            done.finish()
            sink = null
            done.file to done.format
        } finally {
            sink?.abort()
            runCatching { decoder.stop() }
            runCatching { decoder.release() }
        }
    }

    private fun framesUntil(deltaUs: Long, sampleRate: Int): Int =
        if (deltaUs <= 0) 0 else ((deltaUs * sampleRate + 999_999) / 1_000_000).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()

    private fun openSink(dir: File, sampleRate: Int, channels: Int, floatPcm: Boolean): PcmSink =
        try {
            FlacSink(File(dir, "cut.flac"), sampleRate, channels, floatPcm)
        } catch (_: Exception) {
            WavSink(File(dir, "cut.wav"), sampleRate, channels, floatPcm)
        }

    private abstract class PcmSink(val file: File, val format: OutputFormat) {
        abstract fun write(pcm: ByteBuffer)
        abstract fun finish()
        abstract fun abort()
    }

    /** Encodes PCM to FLAC with the platform encoder and writes a standalone .flac file. */
    private class FlacSink(file: File, private val sampleRate: Int, channels: Int, floatPcm: Boolean) :
        PcmSink(file, OutputFormat.FLAC) {

        private val bytesPerFrame = channels * if (floatPcm) 4 else 2
        private val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_FLAC)
        private val out = RandomAccessFile(file, "rw")
        private val info = MediaCodec.BufferInfo()
        private var framesIn = 0L
        private var headerWritten = false

        init {
            try {
                val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_FLAC, sampleRate, channels).apply {
                    setInteger(MediaFormat.KEY_FLAC_COMPRESSION_LEVEL, 5)
                    setInteger(
                        MediaFormat.KEY_PCM_ENCODING,
                        if (floatPcm) AudioFormat.ENCODING_PCM_FLOAT else AudioFormat.ENCODING_PCM_16BIT,
                    )
                }
                encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()
                out.setLength(0)
            } catch (e: Exception) {
                encoder.release()
                out.close()
                file.delete()
                throw e
            }
        }

        private fun timeUs() = framesIn * 1_000_000 / sampleRate

        override fun write(pcm: ByteBuffer) {
            while (pcm.hasRemaining()) {
                val index = encoder.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    val input = encoder.getInputBuffer(index)!!
                    input.clear()
                    val size = minOf(input.remaining() / bytesPerFrame * bytesPerFrame, pcm.remaining())
                    val chunk = pcm.duplicate()
                    chunk.limit(pcm.position() + size)
                    input.put(chunk)
                    pcm.position(pcm.position() + size)
                    encoder.queueInputBuffer(index, 0, size, timeUs(), 0)
                    framesIn += size / bytesPerFrame
                }
                drain(untilEndOfStream = false)
            }
        }

        override fun finish() {
            while (true) {
                val index = encoder.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) {
                    encoder.queueInputBuffer(index, 0, 0, timeUs(), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drain(untilEndOfStream = false)
            }
            drain(untilEndOfStream = true)
            encoder.stop()
            encoder.release()
            writeTotalSamples()
            out.close()
        }

        override fun abort() {
            runCatching { encoder.stop() }
            runCatching { encoder.release() }
            runCatching { out.close() }
            file.delete()
        }

        private fun drain(untilEndOfStream: Boolean) {
            while (true) {
                val index = encoder.dequeueOutputBuffer(info, if (untilEndOfStream) TIMEOUT_US else 0)
                if (index == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (untilEndOfStream) continue else return
                }
                if (index < 0) continue // Output format changed: nothing to do.
                val buffer = encoder.getOutputBuffer(index)!!
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    if (!headerWritten && info.size > 0) writeHeader(buffer)
                } else if (info.size > 0) {
                    if (!headerWritten) writeHeader(encoder.outputFormat.getByteBuffer("csd-0") ?: ByteBuffer.allocate(0))
                    out.channel.write(buffer)
                }
                encoder.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            }
        }

        /** The encoder hands out the "fLaC" marker and the metadata blocks as codec config data. */
        private fun writeHeader(header: ByteBuffer) {
            val bytes = ByteArray(header.remaining()).also { header.get(it) }
            if (!(bytes.size >= 4 && String(bytes, 0, 4, Charsets.US_ASCII) == "fLaC")) {
                out.write("fLaC".toByteArray(Charsets.US_ASCII))
            }
            out.write(bytes)
            headerWritten = true
        }

        /**
         * A streaming encoder can't go back to fill in the stream length, but players need it for
         * the duration and seeking. STREAMINFO starts right after "fLaC" + its 4-byte block header,
         * and the total sample count is the low 36 bits of its bytes 10..17.
         */
        private fun writeTotalSamples() {
            if (out.length() < 8 + 18) return
            out.seek(0)
            val magic = ByteArray(5).also { out.readFully(it) }
            if (String(magic, 0, 4, Charsets.US_ASCII) != "fLaC" || magic[4].toInt() and 0x7F != 0) return
            out.seek(8 + 10)
            val packed = out.readLong()
            val updated = (packed and 0xFFFFFFF000000000uL.toLong()) or (framesIn and 0xFFFFFFFFFL)
            out.seek(8 + 10)
            out.writeLong(updated)
        }
    }

    /** Fallback for devices without a FLAC encoder: plain PCM WAV, lossless as well. */
    private class WavSink(file: File, sampleRate: Int, private val channels: Int, private val floatPcm: Boolean) :
        PcmSink(file, OutputFormat.WAV) {

        private val out = RandomAccessFile(file, "rw")
        private var dataBytes = 0L

        init {
            out.setLength(0)
            val bits = if (floatPcm) 32 else 16
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
                put("RIFF".toByteArray()); putInt(0); put("WAVE".toByteArray())
                put("fmt ".toByteArray()); putInt(16)
                putShort((if (floatPcm) 3 else 1).toShort())
                putShort(channels.toShort())
                putInt(sampleRate)
                putInt(sampleRate * channels * bits / 8)
                putShort((channels * bits / 8).toShort())
                putShort(bits.toShort())
                put("data".toByteArray()); putInt(0)
            }
            out.write(header.array())
        }

        override fun write(pcm: ByteBuffer) {
            dataBytes += pcm.remaining()
            while (pcm.hasRemaining()) out.channel.write(pcm)
        }

        override fun finish() {
            val sizes = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            out.seek(4)
            out.write(sizes.putInt(0, (36 + dataBytes).toInt()).array())
            out.seek(40)
            out.write(sizes.putInt(0, dataBytes.toInt()).array())
            out.close()
        }

        override fun abort() {
            runCatching { out.close() }
            file.delete()
        }
    }
}
