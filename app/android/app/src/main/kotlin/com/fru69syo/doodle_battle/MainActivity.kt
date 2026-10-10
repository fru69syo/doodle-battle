package com.fru69syo.doodle_battle

import com.fru69syo.doodle_battle.ar.ArPlugin
import com.fru69syo.doodle_battle.video.VideoEncoderPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // AR team: in-app plugin for ARCore availability + AR platform view.
        flutterEngine.plugins.add(ArPlugin())
        // Video team: MediaCodec H.264 encoder for the Before/After video.
        flutterEngine.plugins.add(VideoEncoderPlugin())
    }
}
