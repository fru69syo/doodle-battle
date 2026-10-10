package com.fru69syo.doodle_battle.video

import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import java.io.File

/**
 * One H.264 encode: RGBA frames -> YUV 4:2:0 (BT.709, limited range) written through
 * MediaCodec's flexible [Image] input (works for both planar and semi-planar encoders)
 * -> MediaMuxer MP4. Synchronous mode, driven from the plugin's background queue.
 */
class EncoderSession private constructor(
    private val file: File,
    private val codec: MediaCodec,
    private val muxer: MediaMuxer,
    private val width: Int,
    private val height: Int,
    private val fps: Int,
) {
    class SizeUnsupported(message: String) : Exception(message)
    class NoEncoder(message: String) : Exception(message)

    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var muxerStarted = false
    private var frames = 0
    private var lastPtsUs = 0L
    private var released = false
    private val yRow = ByteArray(width)

    private fun ptsUs(frame: Int): Long = frame * 1_000_000L / fps

    fun addFrame(rgba: ByteArray) {
        require(rgba.size == width * height * 4) {
            "frame has ${rgba.size} bytes, expected ${width * height * 4}"
        }
        val index = dequeueInput()
        val image = codec.getInputImage(index)
            ?: throw IllegalStateException("encoder gave no input image")
        writeYuv(image, rgba)
        // Raw 4:2:0 frame size; the encoder reads the layout from the Image (calling
        // getInputBuffer here would invalidate it).
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, ptsUs(frames), 0)
        frames++
        drain(endOfStream = false)
    }

    fun finish(): Map<String, Any> {
        val index = dequeueInput()
        codec.queueInputBuffer(index, 0, 0, ptsUs(frames), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(endOfStream = true)
        release()
        if (!muxerStarted) throw IllegalStateException("no video data was written")
        return mapOf(
            "path" to file.path,
            "bytes" to file.length(),
            "durationUs" to (lastPtsUs + 1_000_000L / fps),
            "frames" to frames,
        )
    }

    fun cancel() {
        release()
        file.delete()
    }

    private fun release() {
        if (released) return
        released = true
        try {
            codec.stop()
        } catch (_: Exception) {
        }
        codec.release()
        try {
            if (muxerStarted) muxer.stop()
        } catch (_: Exception) {
        }
        muxer.release()
    }

    private fun dequeueInput(): Int {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (true) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) return index
            drain(endOfStream = false)
            if (System.nanoTime() > deadline) throw IllegalStateException("encoder input timeout")
        }
    }

    private fun drain(endOfStream: Boolean) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) return
                    if (System.nanoTime() > deadline) throw IllegalStateException("encoder drain timeout")
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(!muxerStarted) { "format changed twice" }
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxerStarted = true
                }
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (buffer != null && info.size > 0 && muxerStarted) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buffer, info)
                        if (info.presentationTimeUs > lastPtsUs) lastPtsUs = info.presentationTimeUs
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /** RGBA -> Y'CbCr BT.709 limited range, chroma averaged over 2x2 blocks. */
    private fun writeYuv(image: Image, rgba: ByteArray) {
        val planes = image.planes
        val yPlane = planes[0]
        val yBuf = yPlane.buffer
        val yStride = yPlane.rowStride
        for (y in 0 until height) {
            var i = y * width * 4
            for (x in 0 until width) {
                val r = rgba[i].toInt() and 0xff
                val g = rgba[i + 1].toInt() and 0xff
                val b = rgba[i + 2].toInt() and 0xff
                yRow[x] = (16 + ((47 * r + 157 * g + 16 * b + 128) shr 8)).toByte()
                i += 4
            }
            if (yPlane.pixelStride == 1) {
                yBuf.position(y * yStride)
                yBuf.put(yRow, 0, width)
            } else {
                for (x in 0 until width) yBuf.put(y * yStride + x * yPlane.pixelStride, yRow[x])
            }
        }
        val uPlane = planes[1]
        val vPlane = planes[2]
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        val cw = width / 2
        val ch = height / 2
        for (cy in 0 until ch) {
            val row0 = cy * 2 * width * 4
            val row1 = row0 + width * 4
            for (cx in 0 until cw) {
                val a = row0 + cx * 8
                val c = row1 + cx * 8
                val r = ((rgba[a].toInt() and 0xff) + (rgba[a + 4].toInt() and 0xff) +
                    (rgba[c].toInt() and 0xff) + (rgba[c + 4].toInt() and 0xff)) shr 2
                val g = ((rgba[a + 1].toInt() and 0xff) + (rgba[a + 5].toInt() and 0xff) +
                    (rgba[c + 1].toInt() and 0xff) + (rgba[c + 5].toInt() and 0xff)) shr 2
                val b = ((rgba[a + 2].toInt() and 0xff) + (rgba[a + 6].toInt() and 0xff) +
                    (rgba[c + 2].toInt() and 0xff) + (rgba[c + 6].toInt() and 0xff)) shr 2
                val u = 128 + ((-26 * r - 87 * g + 112 * b + 128) shr 8)
                val v = 128 + ((112 * r - 102 * g - 10 * b + 128) shr 8)
                uBuf.put(cy * uPlane.rowStride + cx * uPlane.pixelStride, u.coerceIn(16, 240).toByte())
                vBuf.put(cy * vPlane.rowStride + cx * vPlane.pixelStride, v.coerceIn(16, 240).toByte())
            }
        }
    }

    companion object {
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC

        fun start(path: String, width: Int, height: Int, fps: Int, bitrate: Int): EncoderSession {
            require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) {
                "bad size ${width}x$height"
            }
            val name = pickEncoder(width, height)
            val format = MediaFormat.createVideoFormat(MIME, width, height).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                    setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                    setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                }
            }
            val file = File(path)
            file.parentFile?.mkdirs()
            file.delete()
            val codec = MediaCodec.createByCodecName(name)
            try {
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                codec.start()
            } catch (e: Exception) {
                codec.release()
                throw e
            }
            val muxer = try {
                MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            } catch (e: Exception) {
                codec.stop()
                codec.release()
                throw e
            }
            return EncoderSession(file, codec, muxer, width, height, fps)
        }

        /** First (hardware-preferred) AVC encoder that accepts the size and flexible YUV. */
        private fun pickEncoder(width: Int, height: Int): String {
            val encoders = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
                info.isEncoder && info.supportedTypes.any { it.equals(MIME, ignoreCase = true) }
            }
            if (encoders.isEmpty()) throw NoEncoder("no H.264 encoder")
            val usable = encoders.filter { info ->
                try {
                    val caps = info.getCapabilitiesForType(MIME)
                    caps.videoCapabilities.isSizeSupported(width, height) &&
                        caps.colorFormats.contains(
                            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
                        )
                } catch (_: Exception) {
                    false
                }
            }
            val preferred = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                usable.sortedBy { if (it.isHardwareAccelerated) 0 else 1 }
            } else {
                usable
            }
            return preferred.firstOrNull()?.name
                ?: throw SizeUnsupported("no H.264 encoder for ${width}x$height")
        }
    }
}
