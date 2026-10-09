package com.fru69syo.doodle_battle.ar

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * In-app plugin for the AR feature (owned by the AR team).
 *
 * - Method channel `doodle_battle/ar`: ARCore availability check and install
 *   request (see `lib/features/ar/ar_support.dart`).
 * - Platform view `doodle_battle/ar_view`: the ARCore + SceneView scene
 *   (see [ArPlatformView]).
 *
 * Registered from MainActivity.configureFlutterEngine.
 */
class ArPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var appContext: android.content.Context? = null
    private val factory = ArPlatformViewFactory { activity }
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        factory.messenger = binding.binaryMessenger
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, factory)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        pendingPermission?.success("denied")
        pendingPermission = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> checkAvailability(result, attempt = 0)
            "requestInstall" -> requestInstall(call.argument<Boolean>("userRequested") ?: true, result)
            "cameraPermission" -> result.success(cameraPermissionStatus())
            "requestCameraPermission" -> requestCameraPermission(result)
            "openAppSettings" -> openAppSettings(result)
            else -> result.notImplemented()
        }
    }

    /**
     * ArCoreApk.checkAvailability may return a transient UNKNOWN_CHECKING
     * while it queries Play services; poll for up to ~3 s.
     */
    private fun checkAvailability(result: MethodChannel.Result, attempt: Int) {
        val context = activity ?: appContext ?: return result.success("unknown")
        // SceneView/Filament needs OpenGL ES 3.0 (not required in the manifest
        // so the app still installs on older GPUs).
        val am = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
        if ((am?.deviceConfigurationInfo?.reqGlEsVersion ?: 0) < 0x30000) {
            return result.success("unsupported")
        }
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(context)
        } catch (e: Exception) {
            return result.success("unknown")
        }
        if (availability.isTransient && attempt < 15) {
            main.postDelayed({ checkAvailability(result, attempt + 1) }, 200)
            return
        }
        result.success(
            when (availability) {
                ArCoreApk.Availability.SUPPORTED_INSTALLED -> "supported"
                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> "needsInstall"
                ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> "unsupported"
                else -> "unknown"
            }
        )
    }

    /**
     * Asks Google Play Services for AR to install/update. Returns
     * `installed`, `requested` (Play Store UI shown; call again with
     * userRequested=false after the app resumes), `declined` or `error`.
     */
    private fun requestInstall(userRequested: Boolean, result: MethodChannel.Result) {
        val act = activity ?: return result.success("error")
        try {
            when (ArCoreApk.getInstance().requestInstall(act, userRequested)) {
                ArCoreApk.InstallStatus.INSTALLED -> result.success("installed")
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> result.success("requested")
            }
        } catch (e: UnavailableUserDeclinedInstallationException) {
            result.success("declined")
        } catch (e: Exception) {
            result.success("error")
        }
    }

    private fun hasCamera(): Boolean {
        val ctx = activity ?: appContext ?: return false
        return ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private fun cameraPermissionStatus(): String = if (hasCamera()) "granted" else "denied"

    /**
     * Returns `granted`, `denied` or `permanentlyDenied` (the system will not
     * show the dialog any more; the user must use the app settings).
     */
    private fun requestCameraPermission(result: MethodChannel.Result) {
        val act = activity ?: return result.success("denied")
        if (hasCamera()) return result.success("granted")
        if (pendingPermission != null) return result.error("busy", "request in progress", null)
        pendingPermission = result
        act.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val act = activity
        result.success(
            when {
                granted -> "granted"
                // No rationale after a denial means "don't ask again" (or policy).
                act != null && !act.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) ->
                    "permanentlyDenied"
                else -> "denied"
            }
        )
        return true
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val ctx = activity ?: appContext ?: return result.success(false)
        try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", ctx.packageName, null)
            )
            if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 0x4152 // "AR"
        const val CHANNEL = "doodle_battle/ar"
        const val VIEW_TYPE = "doodle_battle/ar_view"
    }
}
