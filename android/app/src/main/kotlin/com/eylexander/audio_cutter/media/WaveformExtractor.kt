package com.eylexander.audio_cutter.media

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.SystemClock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Decodes the first audio track and reduces it to [bucketCount] loudness levels (RMS) spread
 * evenly over [durationMs]. Partial results are pushed to [onUpdate] while decoding runs, so
 * long files fill in progressively.
 */
object WaveformExtractor {

    private const val TIMEOUT_US = 5_000L
    private const val PUBLISH_INTERVAL_MS = 150L

    /** Look at every Nth audio frame: plenty for a visual overview and a lot cheaper. */
    private const val FRAME_STRIDE = 4

    suspend fun extract(
        context: Context,
        uri: Uri,
        durationMs: Long,
        bucketCount: Int,
        onUpdate: (levels: FloatArray) -> Unit,
    ) = withContext(Dispatchers.Default) {
        val sums = DoubleArray(bucketCount)
        val counts = IntArray(bucketCount)
        fun levels() = FloatArray(bucketCount) { if (counts[it] > 0) sqrt(sums[it] / counts[it]).toFloat() else 0f }

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(context, uri, null)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio track")
            extractor.selectTrack(track)
            val inputFormat = extractor.getTrackFormat(track)

            val codec = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder = codec
            codec.configure(inputFormat, null, null, 0)
            codec.start()

            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE, 44_100)
            var channels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT, 2)
            var floatPcm = false
            val durationUs = durationMs * 1000.0
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var lastPublish = SystemClock.elapsedRealtime()

            while (true) {
                ensureActive()
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val size = extractor.readSampleData(codec.getInputBuffer(inIndex)!!, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val format = codec.outputFormat
                    sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                    channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT, channels)
                    floatPcm = format.getInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT) ==
                        AudioFormat.ENCODING_PCM_FLOAT
                } else if (outIndex >= 0) {
                    if (info.size > 0 && channels > 0 && sampleRate > 0) {
                        val buffer = codec.getOutputBuffer(outIndex)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val pcm = buffer.slice().order(ByteOrder.nativeOrder())
                        accumulate(pcm, floatPcm, channels, sampleRate, info.presentationTimeUs, durationUs, sums, counts)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break

                    val now = SystemClock.elapsedRealtime()
                    if (now - lastPublish >= PUBLISH_INTERVAL_MS) {
                        lastPublish = now
                        onUpdate(levels())
                    }
                }
            }
            onUpdate(levels())
        } finally {
            decoder?.let {
                runCatching { it.stop() }
                runCatching { it.release() }
            }
            extractor.release()
        }
    }

    private fun accumulate(
        pcm: ByteBuffer,
        floatPcm: Boolean,
        channels: Int,
        sampleRate: Int,
        startUs: Long,
        durationUs: Double,
        sums: DoubleArray,
        counts: IntArray,
    ) {
        val bucketCount = sums.size
        val floats = if (floatPcm) pcm.asFloatBuffer() else null
        val shorts = if (floatPcm) null else pcm.asShortBuffer()
        val frameCount = (floats?.limit() ?: shorts!!.limit()) / channels
        var frame = 0
        while (frame < frameCount) {
            val timeUs = startUs + frame * 1_000_000L / sampleRate
            val bucket = (timeUs / durationUs * bucketCount).toInt()
            if (bucket in 0 until bucketCount) {
                var peak = 0f
                val base = frame * channels
                for (c in 0 until channels) {
                    val value = if (floats != null) abs(floats.get(base + c)) else abs(shorts!!.get(base + c) / 32768f)
                    if (value > peak) peak = value
                }
                sums[bucket] += (peak * peak).toDouble()
                counts[bucket]++
            }
            frame += FRAME_STRIDE
        }
    }
}
