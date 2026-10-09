package com.fru69syo.doodle_battle.ar

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ArPlatformViewFactory(
    private val activityProvider: () -> Activity?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    var messenger: BinaryMessenger? = null

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = (args as? Map<*, *>) ?: emptyMap<String, Any?>()
        // Prefer the Activity as context: ARCore and Compose both expect one.
        val ctx: Context = activityProvider() ?: context
        return ArPlatformView(
            context = ctx,
            activity = activityProvider(),
            messenger = checkNotNull(messenger) { "ArPlugin not attached" },
            viewId = viewId,
            glbPath = params["glbPath"] as? String,
        )
    }
}
