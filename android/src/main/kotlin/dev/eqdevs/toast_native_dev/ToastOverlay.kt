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
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
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
    val title: String,
    val subtitle: String,
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
    onRemoved: (id: String) -> Unit,
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
                .statusBarsPadding()
                .padding(top = 14.dp, start = 14.dp, end = 14.dp),
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
                        onRemoved = onRemoved,
                        onHold = onHold,
                        onRelease = onRelease,
                    )
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 14.dp, start = 14.dp, end = 14.dp),
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
                        onRemoved = onRemoved,
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
    onRemoved: (id: String) -> Unit,
    onHold: (id: String) -> Unit,
    onRelease: (id: String) -> Unit,
) {
    // initialState = false so the first transition plays as an enter animation.
    // targetState is rebound every composition from toast.visible, so a dismiss
    // (visible = false) drives the exit transition without an empty-frame stutter.
    val visibilityState = remember { MutableTransitionState(initialState = false) }
    visibilityState.targetState = toast.visible

    // Remove the toast from the backing list exactly when the exit animation
    // finishes (idle while settled hidden) — no fixed-delay guess.
    LaunchedEffect(visibilityState.isIdle, visibilityState.currentState) {
        if (visibilityState.isIdle && !visibilityState.currentState) {
            onRemoved(toast.id)
        }
    }

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
            "success" -> 0xFF18A957
            "error"   -> 0xFFFB2C36
            "info"    -> 0xFF969696
            else      -> 0xFFF8B632
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

    // Toast content metrics are kept in sync with the iOS renderer.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer { translationY = dragOffset }
            .shadow(
                elevation = 2.dp,
                shape = RoundedCornerShape(16.dp),
                ambientColor = Color(0x1A000000),
                spotColor = Color(0x1A000000),
            )
            .background(bgColor, RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp)
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
            ToastIcon(type = toast.icon, iconColor = iconColor, glyphColor = bgColor)
            Spacer(modifier = Modifier.width(12.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            if (toast.title.isNotEmpty()) {
                BasicText(text = toast.title, style = toastTitleStyle)
            }
            if (toast.subtitle.isNotEmpty()) {
                BasicText(text = toast.subtitle, style = toastSubtitleStyle)
            }
        }
    }
}

private val toastTitleStyle = TextStyle(
    color = Color.White,
    fontSize = 14.sp,
    fontWeight = FontWeight.SemiBold,
    lineHeight = 18.sp,
    textAlign = TextAlign.Start,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(
        alignment = LineHeightStyle.Alignment.Center,
        trim = LineHeightStyle.Trim.Both,
    ),
)

private val toastSubtitleStyle = TextStyle(
    color = Color.White,
    fontSize = 13.sp,
    fontWeight = FontWeight.Normal,
    lineHeight = 18.sp,
    textAlign = TextAlign.Start,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(
        alignment = LineHeightStyle.Alignment.Center,
        trim = LineHeightStyle.Trim.Both,
    ),
)

@Composable
private fun ToastIcon(type: String, iconColor: Color, glyphColor: Color) {
    Canvas(modifier = Modifier.size(24.dp)) {
        val s = size.minDimension / 24f
        when (type) {
            "info" -> drawWifiIcon(iconColor, s)
            else -> {
                val center = Offset(12f * s, 12f * s)
                drawCircle(color = iconColor, radius = 10f * s, center = center)
                drawCircle(
                    color = iconColor,
                    radius = 10f * s,
                    center = center,
                    style = Stroke(width = 1.5f * s),
                )
                val w = 1.5f * s
                when (type) {
                    "success" -> {
                        drawLine(
                            color = glyphColor,
                            start = Offset(8.5f * s, 12.5f * s),
                            end = Offset(10.5f * s, 14.5f * s),
                            strokeWidth = w,
                            cap = StrokeCap.Round,
                        )
                        drawLine(
                            color = glyphColor,
                            start = Offset(10.5f * s, 14.5f * s),
                            end = Offset(15.5f * s, 9.5f * s),
                            strokeWidth = w,
                            cap = StrokeCap.Round,
                        )
                    }
                    "error" -> {
                        drawLine(
                            color = glyphColor,
                            start = Offset(14.5f * s, 9.5f * s),
                            end = Offset(9.5f * s, 14.5f * s),
                            strokeWidth = w,
                            cap = StrokeCap.Round,
                        )
                        drawLine(
                            color = glyphColor,
                            start = Offset(9.5f * s, 9.5f * s),
                            end = Offset(14.5f * s, 14.5f * s),
                            strokeWidth = w,
                            cap = StrokeCap.Round,
                        )
                    }
                    else -> {
                        drawLine(
                            color = glyphColor,
                            start = Offset(12f * s, 17f * s),
                            end = Offset(12f * s, 11f * s),
                            strokeWidth = w,
                            cap = StrokeCap.Round,
                        )
                        drawCircle(
                            color = iconColor,
                            radius = 0.5f * s,
                            center = Offset(12f * s, 8f * s),
                            style = Fill,
                        )
                        drawCircle(
                            color = glyphColor,
                            radius = 0.5f * s,
                            center = Offset(12f * s, 8f * s),
                            style = Stroke(width = 1f * s),
                        )
                    }
                }
            }
        }
    }
}

private fun DrawScope.drawWifiIcon(color: Color, s: Float) {
    val path = Path().apply {
        moveTo(8.60791f * s, 15.5467f * s)
        cubicTo(9.65063f * s, 14.4213f * s, 11.0666f * s, 13.9257f * s, 12.438f * s, 14.0594f * s)
        lineTo(15.3364f * s, 16.9579f * s)
        cubicTo(14.9322f * s, 17.3308f * s, 14.3022f * s, 17.3068f * s, 13.9282f * s, 16.9032f * s)
        cubicTo(12.8538f * s, 15.7435f * s, 11.1462f * s, 15.7435f * s, 10.0718f * s, 16.9032f * s)
        cubicTo(9.69733f * s, 17.3072f * s, 9.06574f * s, 17.3313f * s, 8.66162f * s, 16.9569f * s)
        cubicTo(8.25755f * s, 16.5824f * s, 8.2335f * s, 15.9508f * s, 8.60791f * s, 15.5467f * s)
        close()
        moveTo(10.5337f * s, 12.1551f * s)
        cubicTo(9.39159f * s, 12.4416f * s, 8.30586f * s, 13.0659f * s, 7.41162f * s, 14.0311f * s)
        cubicTo(7.03719f * s, 14.4352f * s, 6.40562f * s, 14.4592f * s, 6.00147f * s, 14.0848f * s)
        cubicTo(5.59764f * s, 13.7104f * s, 5.57366f * s, 13.0797f * s, 5.94776f * s, 12.6756f * s)
        cubicTo(6.82913f * s, 11.7243f * s, 7.85866f * s, 11.0262f * s, 8.95654f * s, 10.578f * s)
        lineTo(10.5337f * s, 12.1551f * s)
        close()
        moveTo(11.7476f * s, 9.98325f * s)
        cubicTo(14.0238f * s, 9.91151f * s, 16.3217f * s, 10.8077f * s, 18.0522f * s, 12.6756f * s)
        cubicTo(18.4265f * s, 13.0797f * s, 18.4025f * s, 13.7104f * s, 17.9985f * s, 14.0848f * s)
        cubicTo(17.5944f * s, 14.4592f * s, 16.9628f * s, 14.4352f * s, 16.5884f * s, 14.0311f * s)
        cubicTo(15.8675f * s, 13.253f * s, 15.0225f * s, 12.6952f * s, 14.1235f * s, 12.3582f * s)
        lineTo(11.7476f * s, 9.98325f * s)
        close()
        moveTo(7.4458f * s, 9.06723f * s)
        cubicTo(6.47472f * s, 9.5887f * s, 5.56231f * s, 10.2849f * s, 4.75147f * s, 11.16f * s)
        cubicTo(4.37703f * s, 11.5642f * s, 3.74546f * s, 11.5882f * s, 3.34131f * s, 11.2137f * s)
        cubicTo(2.93746f * s, 10.8393f * s, 2.91343f * s, 10.2086f * s, 3.2876f * s, 9.80454f * s)
        cubicTo(4.10747f * s, 8.9196f * s, 5.01521f * s, 8.18517f * s, 5.98096f * s, 7.60239f * s)
        lineTo(7.4458f * s, 9.06723f * s)
        close()
        moveTo(8.29346f * s, 6.52817f * s)
        cubicTo(12.5347f * s, 5.09301f * s, 17.3591f * s, 6.18512f * s, 20.7124f * s, 9.80454f * s)
        cubicTo(21.0867f * s, 10.2086f * s, 21.0626f * s, 10.8393f * s, 20.6587f * s, 11.2137f * s)
        cubicTo(20.2545f * s, 11.5882f * s, 19.623f * s, 11.5642f * s, 19.2485f * s, 11.16f * s)
        cubicTo(16.7059f * s, 8.4158f * s, 13.1767f * s, 7.41285f * s, 9.91065f * s, 8.14633f * s)
        lineTo(8.29346f * s, 6.52817f * s)
        close()
    }
    drawPath(path, color = color)
    drawLine(
        color = color,
        start = Offset(4.23901f * s, 4.16736f * s),
        end = Offset(18.4817f * s, 18.4104f * s),
        strokeWidth = 1.3301f * s,
        cap = StrokeCap.Round,
    )
    drawCircle(
        color = color,
        radius = 1.27515f * s,
        center = Offset(12.041f * s, 18.8081f * s),
    )
}
