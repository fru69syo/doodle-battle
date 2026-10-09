package com.fru69syo.doodle_battle

import com.fru69syo.doodle_battle.ar.ArPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // AR team: in-app plugin for ARCore availability + AR platform view.
        flutterEngine.plugins.add(ArPlugin())
    }
}
