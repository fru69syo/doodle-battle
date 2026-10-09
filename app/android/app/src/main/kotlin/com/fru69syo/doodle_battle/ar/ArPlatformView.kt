package com.fru69syo.doodle_battle.ar

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Flutter platform view that hosts SceneView's Compose `ARSceneView`.
 *
 * Per-view channel `doodle_battle/ar_view_<id>`:
 *  Dart → native: placeAt{x,y} (physical px) → Boolean, setTransform{scale,yaw},
 *                 setPlanesVisible{visible}, capture → JPEG bytes.
 *  native → Dart: onEvent{type, ...} (planes, tracking, placed, modelLoaded,
 *                 sessionFailed).
 */
class ArPlatformView(
    context: Context,
    activity: Activity?,
    messenger: BinaryMessenger,
    viewId: Int,
    glbPath: String?,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "doodle_battle/ar_view_$viewId")
    private val main = Handler(Looper.getMainLooper())
    private val owner = ArViewLifecycleOwner()
    private val activityLifecycle: Lifecycle? = (activity as? LifecycleOwner)?.lifecycle
    private val lifecycleObserver = LifecycleEventObserver { _, event ->
        owner.moveTo(event.targetState)
    }
    private val state = ArSceneState(glbPath) { type, data -> emit(type, data) }
    private var disposed = false

    private val composeView = ComposeView(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        setViewTreeLifecycleOwner(owner)
        setViewTreeSavedStateRegistryOwner(owner)
        setViewTreeViewModelStoreOwner(owner)
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnLifecycleDestroyed(owner))
        setContent { DoodleArScene(state) }
    }

    init {
        channel.setMethodCallHandler(this)
        if (activityLifecycle != null) {
            activityLifecycle.addObserver(lifecycleObserver)
        } else {
            owner.moveTo(Lifecycle.State.RESUMED)
        }
    }

    override fun getView(): View = composeView

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        activityLifecycle?.removeObserver(lifecycleObserver)
        composeView.disposeComposition()
        owner.destroy()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "placeAt" -> {
                val x = (call.argument<Number>("x") ?: 0).toFloat()
                val y = (call.argument<Number>("y") ?: 0).toFloat()
                result.success(state.placeAt(x, y))
            }
            "setTransform" -> {
                state.scale = (call.argument<Number>("scale") ?: 1).toFloat()
                state.yawDegrees = (call.argument<Number>("yaw") ?: 0).toFloat()
                result.success(null)
            }
            "setPlanesVisible" -> {
                state.showPlanes = call.argument<Boolean>("visible") ?: true
                result.success(null)
            }
            "capture" -> capture(result)
            else -> result.notImplemented()
        }
    }

    /** Grabs the rendered camera + 3D frame from SceneView's TextureView. */
    private fun capture(result: MethodChannel.Result) {
        val textureView = findTextureView(composeView)
        val bitmap: Bitmap? = try {
            textureView?.takeIf { it.isAvailable }?.bitmap
        } catch (e: Exception) {
            null
        }
        if (bitmap == null) {
            result.error("capture_failed", "AR surface not ready", null)
            return
        }
        encoder.execute {
            val bytes = try {
                ByteArrayOutputStream().use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)
                    out.toByteArray()
                }
            } catch (e: Exception) {
                null
            } finally {
                bitmap.recycle()
            }
            main.post {
                if (bytes != null) result.success(bytes)
                else result.error("capture_failed", "JPEG encoding failed", null)
            }
        }
    }

    private fun findTextureView(view: View): TextureView? {
        if (view is TextureView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findTextureView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun emit(type: String, data: Map<String, Any?>) {
        if (disposed) return
        val payload = HashMap<String, Any?>(data).apply { put("type", type) }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            channel.invokeMethod("onEvent", payload)
        } else {
            main.post { if (!disposed) channel.invokeMethod("onEvent", payload) }
        }
    }

    companion object {
        private val encoder = Executors.newSingleThreadExecutor()
    }
}
