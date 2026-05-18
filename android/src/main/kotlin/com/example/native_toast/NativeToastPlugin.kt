package com.example.native_toast

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.platform.ComposeView
import androidx.core.view.ViewCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class NativeToastPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var composeView: ComposeView? = null
    private val toasts = mutableStateListOf<ToastData>()

    // ─── Timer state ──────────────────────────────────────────────────────────

    private data class TimerInfo(
        val runnable: Runnable,
        val startMs: Long,
        val totalDurationMs: Long,
    )

    // Timers currently counting down.
    private val activeTimers = mutableMapOf<String, TimerInfo>()
    // Remaining ms for timers that were paused (e.g. user is holding the toast).
    private val pausedRemaining = mutableMapOf<String, Long>()

    // ─── Lifecycle owner ─────────────────────────────────────────────────────

    // Standalone owner because FlutterActivity extends plain Activity,
    // not ComponentActivity, so the DecorView has no ViewTree owners set.
    private val toastOwner = object : SavedStateRegistryOwner {
        private val lifecycleRegistry = LifecycleRegistry(this)
        private val controller = SavedStateRegistryController.create(this)

        override val lifecycle: Lifecycle = lifecycleRegistry
        override val savedStateRegistry: SavedStateRegistry
            get() = controller.savedStateRegistry

        init {
            controller.performRestore(null)
            lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        }

        fun destroy() {
            lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        }
    }

    // ─── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.yourapp/native_toast")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        toastOwner.destroy()
    }

    // ─── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        setupOverlay()
    }

    override fun onDetachedFromActivity() {
        teardownOverlay()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        setupOverlay()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        teardownOverlay()
        activity = null
    }

    // ─── Overlay lifecycle ────────────────────────────────────────────────────

    private fun setupOverlay() {
        val act = activity ?: return
        mainHandler.post {
            if (composeView != null) return@post
            val decorView = act.window.decorView as? ViewGroup ?: return@post

            // WindowRecomposer looks for LifecycleOwner starting from the window root (DecorView).
            // FlutterActivity extends plain Activity (not ComponentActivity), so nothing sets this —
            // we must stamp it on the DecorView ourselves before adding the ComposeView.
            decorView.setViewTreeLifecycleOwner(toastOwner)
            decorView.setViewTreeSavedStateRegistryOwner(toastOwner)

            val view = ComposeView(act).apply {
                setContent {
                    ToastOverlay(
                        toasts = toasts,
                        onDismiss = ::dismissById,
                        onHold = ::pauseTimer,
                        onRelease = ::resumeTimer,
                    )
                }
            }

            ViewCompat.setZ(view, 100f)
            decorView.addView(
                view,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                )
            )
            composeView = view
        }
    }

    private fun teardownOverlay() {
        mainHandler.post {
            activeTimers.values.forEach { mainHandler.removeCallbacks(it.runnable) }
            activeTimers.clear()
            pausedRemaining.clear()

            composeView?.let { view ->
                val parent = view.parent as? ViewGroup
                parent?.removeView(view)
                // Clear the ViewTree owners we stamped on the DecorView so we don't
                // leak `toastOwner` across activity-detach cycles.
                parent?.setViewTreeLifecycleOwner(null)
                parent?.setViewTreeSavedStateRegistryOwner(null)
            }
            composeView = null
            toasts.clear()
        }
    }

    // ─── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method != "showToast") {
            result.notImplemented()
            return
        }
        val args = call.arguments as? Map<*, *> ?: run {
            result.error("INVALID_ARGS", "Arguments must be a map", null)
            return
        }
        val type = args["type"] as? String ?: "success"
        val message = args["message"] as? String ?: ""
        val position = args["position"] as? String ?: "top"
        val length = args["length"] as? String ?: "short"
        val durationMs = (args["durationMs"] as? Number)?.toLong() ?: durationFor(length)
        val color = (args["color"] as? Number)?.toLong()
        val icon = args["icon"] as? String ?: type
        val iconColor = (args["iconColor"] as? Number)?.toLong()
        val dismissDirection = args["dismissDirection"] as? String
            ?: if (position == "top") "up" else "down"

        mainHandler.post { addToast(type, message, position, durationMs, color, icon, iconColor, dismissDirection) }
        result.success(null)
    }

    // ─── Toast management ─────────────────────────────────────────────────────

    private fun addToast(
        type: String,
        message: String,
        position: String,
        durationMs: Long,
        color: Long?,
        icon: String,
        iconColor: Long?,
        dismissDirection: String,
    ) {
        val toast = ToastData(
            type = type,
            message = message,
            position = position,
            dismissDirection = dismissDirection,
            color = color,
            icon = icon,
            iconColor = iconColor,
        )
        toasts.add(toast)

        if (durationMs > 0) {
            scheduleTimer(toast.id, durationMs)
        }
    }

    private fun scheduleTimer(id: String, durationMs: Long) {
        val runnable = Runnable { dismissById(id) }
        activeTimers[id] = TimerInfo(runnable, System.currentTimeMillis(), durationMs)
        mainHandler.postDelayed(runnable, durationMs)
    }

    private fun pauseTimer(id: String) {
        val info = activeTimers.remove(id) ?: return
        mainHandler.removeCallbacks(info.runnable)
        val elapsed = System.currentTimeMillis() - info.startMs
        val remaining = (info.totalDurationMs - elapsed).coerceAtLeast(200L)
        pausedRemaining[id] = remaining
    }

    private fun resumeTimer(id: String) {
        val remaining = pausedRemaining.remove(id) ?: return
        scheduleTimer(id, remaining)
    }

    private fun dismissById(id: String) {
        activeTimers.remove(id)?.let { mainHandler.removeCallbacks(it.runnable) }
        pausedRemaining.remove(id)
        val idx = toasts.indexOfFirst { it.id == id }
        if (idx < 0) return
        toasts[idx] = toasts[idx].copy(visible = false)
        // +50ms buffer past the nominal exit-animation length so the toast isn't
        // pulled from the list mid-animation under JVM/GC jitter.
        mainHandler.postDelayed({ toasts.removeAll { it.id == id } }, ToastAnimationMs + 50L)
    }

    private fun durationFor(length: String): Long = when (length) {
        "short"  -> 2_000L
        "medium" -> 4_000L
        "long"   -> 6_000L
        "ages"   -> 10_000L
        "never"  -> -1L
        else     -> 2_000L
    }
}
