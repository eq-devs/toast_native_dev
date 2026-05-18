package com.example.native_toast

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.UUID
import kotlinx.coroutines.launch

const val ToastAnimationMs = 450
private const val ToastSlideFraction = 1.0f
private val ToastDismissThreshold = 56.dp

// easeOutCubic (decelerating) for enter; its time-reversed mirror for exit.
// Together they make the exit look like the enter played backwards.
private val EaseOutCubic = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)
private val EaseInCubic  = CubicBezierEasing(0.32f, 0f, 0.67f, 0f)

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
    // Single curve drives both fade and slide; enter = curve forward, exit = curve in reverse.
    val enterFadeSpec  = tween<Float>(ToastAnimationMs, easing = EaseInCubic)
    val enterSlideSpec = tween<IntOffset>(ToastAnimationMs, easing = EaseInCubic)
    val exitFadeSpec   = tween<Float>(ToastAnimationMs, easing = EaseOutCubic)
    val exitSlideSpec  = tween<IntOffset>(ToastAnimationMs, easing = EaseOutCubic)

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 64.dp, start = 16.dp, end = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            toasts.filter { it.position == "top" }.forEach { toast ->
                key(toast.id) {
                    val verticalOffset: (Int) -> Int = { height ->
                        val travel = (height * ToastSlideFraction).toInt()
                        -travel
                    }
                    AnimatedVisibility(
                        visible = toast.visible,
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
                    val verticalOffset: (Int) -> Int = { height ->
                        val travel = (height * ToastSlideFraction).toInt()
                        travel
                    }
                    AnimatedVisibility(
                        visible = toast.visible,
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
            }
        }
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

    val dragOffset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer { translationY = dragOffset.value }
            .shadow(elevation = 8.dp, shape = RoundedCornerShape(14.dp))
            .background(bgColor, RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp)
            // Hold detection: fires immediately on finger-down, pauses the auto-dismiss timer.
            .pointerInput(onHold, onRelease) {
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
            .pointerInput(dismissDir, onDismiss) {
                var totalDrag = 0f
                detectVerticalDragGestures(
                    onDragStart = {
                        // Stop any ongoing spring-back so the view follows the finger cleanly.
                        scope.launch { dragOffset.stop() }
                    },
                    onDragEnd = {
                        val threshold = ToastDismissThreshold.toPx()
                        if ((dismissDir == "up" && totalDrag < -threshold) ||
                            (dismissDir == "down" && totalDrag > threshold)
                        ) {
                            onDismiss()
                        } else {
                            scope.launch {
                                dragOffset.animateTo(
                                    targetValue = 0f,
                                    animationSpec = spring(
                                        dampingRatio = Spring.DampingRatioMediumBouncy,
                                        stiffness = Spring.StiffnessMediumLow,
                                    ),
                                )
                            }
                        }
                        totalDrag = 0f
                    },
                    onDragCancel = {
                        scope.launch { dragOffset.animateTo(0f, spring()) }
                        totalDrag = 0f
                    },
                ) { _, dragAmount ->
                    totalDrag += dragAmount
                    // Clamp to dismiss direction — resist dragging the "wrong" way.
                    val newOffset = if (dismissDir == "up") {
                        (dragOffset.value + dragAmount).coerceAtMost(0f)
                    } else {
                        (dragOffset.value + dragAmount).coerceAtLeast(0f)
                    }
                    scope.launch { dragOffset.snapTo(newOffset) }
                }
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (toast.icon != "none") {
            ToastIcon(type = toast.icon, color = iconColor)
            Spacer(modifier = Modifier.width(10.dp))
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
    Canvas(modifier = Modifier.size(24.dp)) {
        val strokeWidth = 2.4.dp.toPx()
        val stroke = Stroke(width = strokeWidth, cap = StrokeCap.Round)
        val center = this.center
        val radius = size.minDimension / 2 - strokeWidth / 2

        drawCircle(color = color, radius = radius, center = center, style = stroke)

        when (type) {
            "success" -> {
                drawLine(
                    color = color,
                    start = androidx.compose.ui.geometry.Offset(size.width * 0.28f, size.height * 0.52f),
                    end = androidx.compose.ui.geometry.Offset(size.width * 0.43f, size.height * 0.68f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = androidx.compose.ui.geometry.Offset(size.width * 0.43f, size.height * 0.68f),
                    end = androidx.compose.ui.geometry.Offset(size.width * 0.73f, size.height * 0.35f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
            }

            "error" -> {
                drawLine(
                    color = color,
                    start = androidx.compose.ui.geometry.Offset(size.width * 0.35f, size.height * 0.35f),
                    end = androidx.compose.ui.geometry.Offset(size.width * 0.65f, size.height * 0.65f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = color,
                    start = androidx.compose.ui.geometry.Offset(size.width * 0.65f, size.height * 0.35f),
                    end = androidx.compose.ui.geometry.Offset(size.width * 0.35f, size.height * 0.65f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
            }

            else -> {
                drawLine(
                    color = color,
                    start = androidx.compose.ui.geometry.Offset(center.x, size.height * 0.42f),
                    end = androidx.compose.ui.geometry.Offset(center.x, size.height * 0.70f),
                    strokeWidth = strokeWidth,
                    cap = StrokeCap.Round,
                )
                drawCircle(color = color, radius = strokeWidth / 2, center = androidx.compose.ui.geometry.Offset(center.x, size.height * 0.30f))
            }
        }
    }
}
