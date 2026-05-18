package dev.eqdevs.toast_native_dev

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.UUID
import kotlinx.coroutines.launch

const val ToastAnimationMs = 450
private val ToastSlideDistance   = 72.dp
private val ToastDismissThreshold = 56.dp

private val EaseInCubic       = CubicBezierEasing(0.32f, 0f, 0.67f, 0f)
private val SmoothEnterEasing = FastOutSlowInEasing

data class ToastData(
    val id: String = UUID.randomUUID().toString(),
    val type: String,
    val message: String,
    val position: String,
    val dismissDirection: String,
    val color: Long?,
    val icon: String,
    val iconColor: Long?,
    val visible: Boolean = true,
)

@Composable
fun ToastOverlay(
    toasts: List<ToastData>,
    onDismiss: (id: String) -> Unit,
    onHold: (id: String) -> Unit,
    onRelease: (id: String) -> Unit,
) {
    // Enter: smooth ease-in-out for a natural arrival. Exit: accelerating ease-in.
    // Fade and slide share the same curve in each phase so they move in lockstep.
    val enterFadeSpec  = tween<Float>(ToastAnimationMs, easing = SmoothEnterEasing)
    val enterSlideSpec = tween<IntOffset>(ToastAnimationMs, easing = SmoothEnterEasing)
    val exitFadeSpec   = tween<Float>(ToastAnimationMs, easing = EaseInCubic)
    val exitSlideSpec  = tween<IntOffset>(ToastAnimationMs, easing = EaseInCubic)

    // Resolve dp → px once at the composable level so the slide distance is consistent
    // across screen densities (was previously hard-coded raw pixels).
    val slideDistancePx = with(LocalDensity.current) { ToastSlideDistance.roundToPx() }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 64.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            toasts.filter { it.position == "top" }.forEach { toast ->
                key(toast.id) {
                    ToastSlot(
                        toast = toast,
                        verticalOffset = { height -> -maxOf(height, slideDistancePx) },
                        enterFadeSpec = enterFadeSpec,
                        enterSlideSpec = enterSlideSpec,
                        exitFadeSpec = exitFadeSpec,
                        exitSlideSpec = exitSlideSpec,
                        onDismiss = onDismiss,
                        onHold = onHold,
                        onRelease = onRelease,
                    )
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 64.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Reversed so newest toast is closest to the bottom edge
            toasts.filter { it.position == "bottom" }.reversed().forEach { toast ->
                key(toast.id) {
                    ToastSlot(
                        toast = toast,
                        verticalOffset = { height -> maxOf(height, slideDistancePx) },
                        enterFadeSpec = enterFadeSpec,
                        enterSlideSpec = enterSlideSpec,
                        exitFadeSpec = exitFadeSpec,
                        exitSlideSpec = exitSlideSpec,
                        onDismiss = onDismiss,
                        onHold = onHold,
                        onRelease = onRelease,
                    )
                }
            }
        }
    }
}

@Composable
private fun ToastSlot(
    toast: ToastData,
    verticalOffset: (Int) -> Int,
    enterFadeSpec: FiniteAnimationSpec<Float>,
    enterSlideSpec: FiniteAnimationSpec<IntOffset>,
    exitFadeSpec: FiniteAnimationSpec<Float>,
    exitSlideSpec: FiniteAnimationSpec<IntOffset>,
    onDismiss: (id: String) -> Unit,
    onHold: (id: String) -> Unit,
    onRelease: (id: String) -> Unit,
) {
    // initialState = false so the first transition plays as an enter animation.
    // targetState is rebound every composition from toast.visible, so a dismiss
    // (visible = false) drives the exit transition without an empty-frame stutter.
    val visibilityState = remember { MutableTransitionState(initialState = false) }
    visibilityState.targetState = toast.visible

    AnimatedVisibility(
        visibleState = visibilityState,
        enter = fadeIn(enterFadeSpec) +
                slideInVertically(enterSlideSpec, initialOffsetY = verticalOffset),
        exit  = fadeOut(exitFadeSpec) +
                slideOutVertically(exitSlideSpec, targetOffsetY = verticalOffset),
    ) {
        ToastItem(
            toast = toast,
            onDismiss = { onDismiss(toast.id) },
            onHold = { onHold(toast.id) },
            onRelease = { onRelease(toast.id) },
        )
    }
}

@Composable
fun ToastItem(
    toast: ToastData,
    onDismiss: () -> Unit,
    onHold: () -> Unit,
    onRelease: () -> Unit,
) {
    val bgColor = Color(
        toast.color ?: when (toast.type) {
            "success" -> 0xFF1B8918
            "error"   -> 0xFFFF3B30
            else      -> 0xFFCC8E12
        }
    )
    val iconColor = Color(toast.iconColor ?: 0xFFFFFFFF)
    val dismissDir = toast.dismissDirection

    // Plain mutable float for the live drag position — written directly during
    // pointer events, avoiding a coroutine launch per frame.
    var dragOffset by remember { mutableFloatStateOf(0f) }
    // Animatable used only for the spring-back; its animateTo block writes back
    // into dragOffset so a single state still drives graphicsLayer.
    val springBack = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()

    // Golden ratio (φ ≈ 1.618), base unit = 12dp:
    //   vertical(12)   = base
    //   horizontal(20) = base × φ ≈ 19.4
    //   icon(20)       = horizontal padding (visual unity with edge)
    //   gap(12)        = vertical padding   (visual unity with edge)
    //   icon/gap = horizontal/vertical = 20/12 ≈ φ
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer { translationY = dragOffset }
            .shadow(elevation = 6.dp, shape = RoundedCornerShape(16.dp))
            .background(bgColor, RoundedCornerShape(16.dp))
            .padding(horizontal = 20.dp, vertical = 12.dp)
            // Hold detection: fires immediately on finger-down, pauses the auto-dismiss timer.
            // Keyed on toast.id so the gesture pipeline is set up once and survives recomposition.
            .pointerInput(toast.id) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    onHold()
                    // Wait until every pointer is lifted before resuming.
                    do {
                        val event = awaitPointerEvent()
                    } while (event.changes.any { it.pressed })
                    onRelease()
                }
            }
            // Drag: moves the toast visually; dismisses past threshold or springs back.
            // Keyed on toast.id + dismissDir — both stable for this slot.
            .pointerInput(toast.id, dismissDir) {
                var totalDrag = 0f
                detectVerticalDragGestures(
                    onDragStart = {
                        // Stop any ongoing spring-back so the view follows the finger cleanly.
                        scope.launch { springBack.stop() }
                    },
                    onDragEnd = {
                        val threshold = ToastDismissThreshold.toPx()
                        if ((dismissDir == "up" && totalDrag < -threshold) ||
                            (dismissDir == "down" && totalDrag > threshold)
                        ) {
                            onDismiss()
                        } else {
                            scope.launch {
                                springBack.snapTo(dragOffset)
                                springBack.animateTo(
                                    targetValue = 0f,
                                    animationSpec = spring(
                                        dampingRatio = Spring.DampingRatioMediumBouncy,
                                        stiffness = Spring.StiffnessMediumLow,
                                    ),
                                ) { dragOffset = value }
                            }
                        }
                        totalDrag = 0f
                    },
                    onDragCancel = {
                        scope.launch {
                            springBack.snapTo(dragOffset)
                            springBack.animateTo(0f, spring()) { dragOffset = value }
                        }
                        totalDrag = 0f
                    },
                ) { _, dragAmount ->
                    totalDrag += dragAmount
                    // Direct state write — no per-event coroutine. Clamped so
                    // the toast can only travel toward its dismiss edge.
                    dragOffset = if (dismissDir == "up") {
                        (dragOffset + dragAmount).coerceAtMost(0f)
                    } else {
                        (dragOffset + dragAmount).coerceAtLeast(0f)
                    }
                }
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (toast.icon != "none") {
            ToastIcon(type = toast.icon, color = iconColor)
            Spacer(modifier = Modifier.width(12.dp))  // 20 / φ ≈ 12.36
        }
        Text(
            text = toast.message,
            color = Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun ToastIcon(type: String, color: Color) {
    Canvas(modifier = Modifier.size(20.dp)) {
        val strokeWidth = 2.4.dp.toPx()
        val stroke = Stroke(width = strokeWidth, cap = StrokeCap.Round)
        val center = this.center
        val radius = size.minDimension / 2 - strokeWidth / 2

        drawCircle(color = color, radius = radius, center = center, style = stroke)

        when (type) {
            "success" -> {
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.28f, size.height * 0.52f),
                    end = Offset(size.width * 0.43f, size.height * 0.68f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.43f, size.height * 0.68f),
                    end = Offset(size.width * 0.73f, size.height * 0.35f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
            }

            "error" -> {
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.35f, size.height * 0.35f),
                    end = Offset(size.width * 0.65f, size.height * 0.65f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = Offset(size.width * 0.65f, size.height * 0.35f),
                    end = Offset(size.width * 0.35f, size.height * 0.65f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
            }

            else -> {
                drawLine(
                    color = color,
                    start = Offset(center.x, size.height * 0.42f),
                    end = Offset(center.x, size.height * 0.70f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
                drawCircle(color = color, radius = strokeWidth / 2, center = Offset(center.x, size.height * 0.30f))
            }
        }
    }
}
