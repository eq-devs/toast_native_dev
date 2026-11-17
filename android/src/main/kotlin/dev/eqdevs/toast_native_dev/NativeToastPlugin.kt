package dev.eqdevs.toast_native_dev

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityManager
import android.widget.FrameLayout
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.platform.ComposeView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.findViewTreeSavedStateRegistryOwner
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

    // Toasts on screen (including ones playing their exit animation).
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

    // Standalone owner for hosts whose DecorView has no ViewTree owners:
    // FlutterActivity extends plain Activity, not ComponentActivity. Its state
    // mirrors the real activity so Compose pauses while the app is in the
    // background.
    private class OverlayOwner : SavedStateRegistryOwner {
        private val lifecycleRegistry = LifecycleRegistry(this)
        private val controller = SavedStateRegistryController.create(this)

        override val lifecycle: Lifecycle get() = lifecycleRegistry
        override val savedStateRegistry: SavedStateRegistry
            get() = controller.savedStateRegistry

        init {
            controller.performRestore(null)
        }

        fun handle(event: Lifecycle.Event) {
            if (lifecycleRegistry.currentState == Lifecycle.State.DESTROYED) return
            lifecycleRegistry.handleLifecycleEvent(event)
        }

        fun resume() = handle(Lifecycle.Event.ON_RESUME)

        fun destroy() {
            // A registry that never left INITIALIZED cannot move to DESTROYED.
            if (lifecycleRegistry.currentState == Lifecycle.State.INITIALIZED) return
            handle(Lifecycle.Event.ON_DESTROY)
        }
    }

    private val overlayOwner = OverlayOwner()
    private var observedLifecycle: Lifecycle? = null
    private val activityObserver = LifecycleEventObserver { _, event ->
        // The owner outlives a single activity (config changes), so it only
        // dies with the engine.
        if (event != Lifecycle.Event.ON_DESTROY) overlayOwner.handle(event)
    }

    // Which DecorView owners this plugin set, so teardown clears only those.
    private var stampedLifecycleOwner = false
    private var stampedSavedStateOwner = false

    // ─── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "toast_native_dev/channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        overlayOwner.destroy()
    }

    // ─── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attach(binding.activity)
    }

    override fun onDetachedFromActivity() {
        detach()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attach(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detach()
    }

    // The overlay itself is created lazily by the first toast, so apps pay no
    // Compose start-up cost until they actually show one.
    private fun attach(act: Activity) {
        activity = act
        val lifecycle = (act as? LifecycleOwner)?.lifecycle
        if (lifecycle != null) {
            observedLifecycle = lifecycle
            lifecycle.addObserver(activityObserver)
        } else {
            overlayOwner.resume()
        }
    }

    private fun detach() {
        teardownOverlay()
        observedLifecycle?.removeObserver(activityObserver)
        observedLifecycle = null
        activity = null
    }

    // ─── Overlay lifecycle ────────────────────────────────────────────────────

    private fun ensureOverlay(): ComposeView? {
        composeView?.let { return it }
        val act = activity ?: return null
        val decorView = act.window?.decorView as? ViewGroup ?: return null

        // WindowRecomposer looks for a LifecycleOwner starting from the window
        // root (DecorView). Hosts based on ComponentActivity already provide
        // one; only stamp ours when nothing is there.
        if (decorView.findViewTreeLifecycleOwner() == null) {
            decorView.setViewTreeLifecycleOwner(overlayOwner)
            stampedLifecycleOwner = true
        }
        if (decorView.findViewTreeSavedStateRegistryOwner() == null) {
            decorView.setViewTreeSavedStateRegistryOwner(overlayOwner)
            stampedSavedStateOwner = true
        }

        val view = ComposeView(act).apply {
            setContent {
                ToastOverlay(
                    toasts = toasts,
                    onDismiss = ::dismissById,
                    onRemoved = ::removeById,
                    onHold = ::pauseTimer,
                    onRelease = ::resumeTimer,
                )
            }
        }

        // On windows that are not edge-to-edge the DecorView consumes the
        // navigation-bar inset before its children see it, so Compose would
        // draw bottom toasts under the bar. Pad the view by whatever part of
        // the system bars was consumed above us; Compose handles the rest.
        ViewCompat.setOnApplyWindowInsetsListener(view) { v, insets ->
            val types = WindowInsetsCompat.Type.systemBars() or
                WindowInsetsCompat.Type.displayCutout()
            val root = ViewCompat.getRootWindowInsets(v)?.getInsets(types)
            if (root != null) {
                val given = insets.getInsets(types)
                v.setPadding(
                    (root.left - given.left).coerceAtLeast(0),
                    (root.top - given.top).coerceAtLeast(0),
                    (root.right - given.right).coerceAtLeast(0),
                    (root.bottom - given.bottom).coerceAtLeast(0),
                )
            }
            insets
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
        return view
    }

    private fun teardownOverlay() {
        activeTimers.values.forEach { mainHandler.removeCallbacks(it.runnable) }
        activeTimers.clear()
        pausedRemaining.clear()

        composeView?.let { view ->
            val parent = view.parent as? ViewGroup
            parent?.removeView(view)
            // Clear only the owners this plugin set, and only if they are
            // still ours, so a host-provided owner is never removed.
            if (stampedLifecycleOwner && parent?.findViewTreeLifecycleOwner() === overlayOwner) {
                parent.setViewTreeLifecycleOwner(null)
            }
            if (stampedSavedStateOwner &&
                parent?.findViewTreeSavedStateRegistryOwner() === overlayOwner
            ) {
                parent.setViewTreeSavedStateRegistryOwner(null)
            }
        }
        stampedLifecycleOwner = false
        stampedSavedStateOwner = false
        composeView = null
        toasts.clear()
    }

    // ─── MethodCallHandler ────────────────────────────────────────────────────

    // MethodChannel callbacks already arrive on the main thread.
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "showToast" -> {
                val args = call.arguments as? Map<*, *> ?: run {
                    result.error("INVALID_ARGS", "Arguments must be a map", null)
                    return
                }
                val request = ToastRequest.from(args)
                if (request.shouldShow) show(request)
                result.success(null)
            }
            "dismissToast" -> {
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String ?: run {
                    result.error("INVALID_ARGS", "Expected a string id", null)
                    return
                }
                dismissById(id)
                result.success(null)
            }
            "dismissAll" -> {
                toasts.map { it.id }.forEach(::dismissById)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ─── Toast management ─────────────────────────────────────────────────────

    private fun show(request: ToastRequest) {
        // Same id already on screen: update it in place and restart its timer.
        val idx = toasts.indexOfFirst { it.id == request.id }
        if (idx >= 0) {
            cancelTimer(request.id)
            toasts[idx] = request.toData(epoch = toasts[idx].epoch + 1)
            startTimer(request)
            return
        }
        present(request)
    }

    private fun present(request: ToastRequest) {
        val view = ensureOverlay() ?: return
        view.visibility = View.VISIBLE
        toasts.add(request.toData(epoch = 0))
        startTimer(request)
    }

    private fun ToastRequest.toData(epoch: Int) = ToastData(
        id = id,
        type = type,
        title = title,
        subtitle = subtitle,
        position = position,
        dismissDirection = dismissDirection,
        color = color,
        textColor = textColor,
        icon = icon,
        iconColor = iconColor,
        closeButton = closeButton,
        animateIcon = iconAnimation,
        epoch = epoch,
    )

    private fun startTimer(request: ToastRequest) {
        if (request.durationMs > 0) {
            scheduleTimer(request.id, accessibleDuration(request))
        }
    }

    // Honors the system "time to take action" accessibility setting, which
    // screen-reader and switch users rely on for timed messages.
    private fun accessibleDuration(request: ToastRequest): Long {
        val manager = activity?.getSystemService(Context.ACCESSIBILITY_SERVICE)
            as? AccessibilityManager ?: return request.durationMs
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var flags = AccessibilityManager.FLAG_CONTENT_TEXT or
                AccessibilityManager.FLAG_CONTENT_ICONS
            if (request.closeButton) flags = flags or AccessibilityManager.FLAG_CONTENT_CONTROLS
            val original = request.durationMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            return manager.getRecommendedTimeoutMillis(original, flags).toLong()
        }
        return if (manager.isTouchExplorationEnabled) {
            maxOf(request.durationMs, SCREEN_READER_MIN_MS)
        } else {
            request.durationMs
        }
    }

    private fun scheduleTimer(id: String, durationMs: Long) {
        val runnable = Runnable { dismissById(id) }
        activeTimers[id] = TimerInfo(runnable, SystemClock.elapsedRealtime(), durationMs)
        mainHandler.postDelayed(runnable, durationMs)
    }

    private fun cancelTimer(id: String) {
        activeTimers.remove(id)?.let { mainHandler.removeCallbacks(it.runnable) }
        pausedRemaining.remove(id)
    }

    private fun pauseTimer(id: String) {
        val info = activeTimers.remove(id) ?: return
        mainHandler.removeCallbacks(info.runnable)
        val elapsed = SystemClock.elapsedRealtime() - info.startMs
        pausedRemaining[id] = (info.totalDurationMs - elapsed).coerceAtLeast(0L)
    }

    private fun resumeTimer(id: String) {
        val remaining = pausedRemaining.remove(id) ?: return
        // After a touch (hold or cancelled swipe) the toast stays long enough
        // that letting go never looks like it dismissed the toast.
        scheduleTimer(id, remaining.coerceAtLeast(RESUME_GRACE_MS))
    }

    private fun dismissById(id: String) {
        cancelTimer(id)
        val idx = toasts.indexOfFirst { it.id == id }
        if (idx < 0 || !toasts[idx].visible) return
        toasts[idx] = toasts[idx].copy(visible = false)
        // Removal happens in removeById once the exit animation reports completion.
    }

    private fun removeById(id: String) {
        toasts.removeAll { it.id == id }
        if (toasts.isEmpty()) {
            // Nothing to draw: take the full-screen view out of layout and
            // touch dispatch until the next toast.
            composeView?.visibility = View.GONE
        }
    }

    private companion object {
        const val RESUME_GRACE_MS = 1_500L
        const val SCREEN_READER_MIN_MS = 6_000L
    }
}
