package com.fru69syo.doodle_battle.ar

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import io.github.sceneview.SurfaceType
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberModelInstance
import io.github.sceneview.rememberModelLoader
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/** Observable state shared between the platform view (channel) and Compose. */
class ArSceneState(
    val glbPath: String?,
    private val emit: (String, Map<String, Any?>) -> Unit,
) {
    /** First anchor; creates the AnchorNode. Later placements move that node. */
    var firstAnchor by mutableStateOf<Anchor?>(null)
    var anchorNode: AnchorNode? = null
    var scale by mutableFloatStateOf(1f)
    var yawDegrees by mutableFloatStateOf(0f)
    var showPlanes by mutableStateOf(true)

    private var lastFrame: Frame? = null
    private var session: Session? = null
    private var frameCount = 0
    private var hasPlane = false
    private var modelReported = false

    fun onSession(session: Session) {
        this.session = session
    }

    fun onFrame(session: Session, frame: Frame) {
        this.session = session
        lastFrame = frame
        // Plane discovery is cheap to poll every few frames.
        if (++frameCount % 10 == 0) {
            val found = session.getAllTrackables(Plane::class.java).any {
                it.trackingState == TrackingState.TRACKING &&
                    it.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    it.subsumedBy == null
            }
            if (found != hasPlane) {
                hasPlane = found
                emit("planes", mapOf("detected" to found))
            }
        }
    }

    fun onModelLoaded(ok: Boolean) {
        if (modelReported) return
        modelReported = true
        emit(if (ok) "modelLoaded" else "modelFailed", emptyMap())
    }

    fun emitEvent(type: String, data: Map<String, Any?>) = emit(type, data)

    /**
     * Hit-tests a horizontal plane at the given view pixel and anchors the
     * character there, turned to face the camera.
     */
    fun placeAt(x: Float, y: Float): Boolean {
        val frame = lastFrame ?: return false
        if (frame.camera.trackingState != TrackingState.TRACKING) return false
        val hit = try {
            frame.hitTest(x, y).firstOrNull { h ->
                val plane = h.trackable as? Plane
                plane != null &&
                    plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                    plane.isPoseInPolygon(h.hitPose)
            }
        } catch (e: Exception) {
            null
        } ?: return false

        val p = hit.hitPose
        val cam = frame.camera.pose
        val yaw = atan2(cam.tx() - p.tx(), cam.tz() - p.tz())
        val pose = Pose(
            floatArrayOf(p.tx(), p.ty(), p.tz()),
            floatArrayOf(0f, sin(yaw / 2), 0f, cos(yaw / 2))
        )
        val anchor = try {
            hit.trackable.createAnchor(pose)
        } catch (e: Exception) {
            return false
        }
        val node = anchorNode
        if (node != null) {
            node.anchor = anchor // detaches the previous anchor
        } else {
            firstAnchor = anchor
        }
        emit("placed", emptyMap())
        return true
    }
}

@Composable
fun DoodleArScene(state: ArSceneState) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    ARSceneView(
        modifier = Modifier.fillMaxSize(),
        // TextureView: renders inline (works with Flutter's platform view
        // composition) and can be read back for the shutter.
        surfaceType = SurfaceType.TextureSurface,
        engine = engine,
        modelLoader = modelLoader,
        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL,
        // Standees use unlit materials; skip HDR light estimation.
        sessionConfiguration = { _, config ->
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED
        },
        planeRenderer = state.showPlanes,
        onSessionCreated = { state.onSession(it) },
        onSessionUpdated = { session, frame -> state.onFrame(session, frame) },
        onTrackingFailureChanged = { reason ->
            state.emitEvent("tracking", mapOf("reason" to reason?.name))
        },
        onSessionFailed = { e ->
            state.emitEvent("sessionFailed", mapOf("message" to e.toString()))
        },
        // Gestures are handled in Flutter and forwarded over the channel.
        onGestureListener = null,
        // Permission and ARCore install are handled in Dart before this view
        // is created; hide SceneView's built-in (English) overlays.
        permissionHandler = null,
        cameraPermissionOverlay = null,
        arCoreAvailabilityOverlay = null,
    ) {
        val path = state.glbPath
        val instance = if (path != null) {
            rememberModelInstance(modelLoader, fileLocation = "file://$path")
        } else {
            null
        }
        LaunchedEffect(instance) {
            if (instance != null) state.onModelLoaded(true)
        }
        val anchor = state.firstAnchor
        if (anchor != null && instance != null) {
            AnchorNode(anchor = anchor, apply = { state.anchorNode = this }) {
                ModelNode(
                    modelInstance = instance,
                    autoAnimate = true,
                    animationLoop = true,
                    scale = Scale(state.scale),
                    rotation = Rotation(y = state.yawDegrees),
                )
            }
        }
    }
}
