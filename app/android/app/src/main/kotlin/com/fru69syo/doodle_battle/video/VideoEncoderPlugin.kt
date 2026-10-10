package com.fru69syo.doodle_battle.video

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/**
 * Video team: H.264/MP4 encoder for the Before/After video (docs/VIDEO.md §4).
 *
 * Channel `doodle_battle/video_encoder` (contract in lib/features/video_export/video_encoder.dart):
 *  - start {path, width, height, fps, bitrate} -> null
 *  - addFrame {rgba: ByteArray}                 -> null, after the frame was encoded
 *  - finish                                     -> {path, bytes, durationUs, frames}
 *  - cancel                                     -> null (deletes the partial file)
 * Errors: size_unsupported, unavailable, not_started, failed.
 *
 * All calls run serially on a background task queue, so encoding never blocks the
 * platform (UI) thread. Uses only the framework's MediaCodec + MediaMuxer: no native
 * libraries (16 KB page alignment unaffected) and no permissions.
 */
class VideoEncoderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var session: EncoderSession? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        channel = MethodChannel(
            messenger,
            CHANNEL,
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        session?.cancel()
        session = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    session?.cancel()
                    session = null
                    session = EncoderSession.start(
                        path = call.argument<String>("path")!!,
                        width = call.argument<Int>("width")!!,
                        height = call.argument<Int>("height")!!,
                        fps = call.argument<Int>("fps")!!,
                        bitrate = call.argument<Int>("bitrate")!!,
                    )
                    result.success(null)
                }
                "addFrame" -> {
                    val s = session
                    if (s == null) {
                        result.error(NOT_STARTED, "no encode running", null)
                        return
                    }
                    s.addFrame(call.argument<ByteArray>("rgba")!!)
                    result.success(null)
                }
                "finish" -> {
                    val s = session
                    if (s == null) {
                        result.error(NOT_STARTED, "no encode running", null)
                        return
                    }
                    session = null
                    result.success(s.finish())
                }
                "cancel" -> {
                    session?.cancel()
                    session = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: EncoderSession.SizeUnsupported) {
            result.error(SIZE_UNSUPPORTED, e.message, null)
        } catch (e: EncoderSession.NoEncoder) {
            result.error(UNAVAILABLE, e.message, null)
        } catch (e: Exception) {
            session?.cancel()
            session = null
            result.error(FAILED, e.toString(), null)
        }
    }

    companion object {
        const val CHANNEL = "doodle_battle/video_encoder"
        const val SIZE_UNSUPPORTED = "size_unsupported"
        const val UNAVAILABLE = "unavailable"
        const val NOT_STARTED = "not_started"
        const val FAILED = "failed"
    }
}
