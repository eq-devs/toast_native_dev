package dev.eqdevs.toast_native_dev

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.dismiss
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.sin
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

// Motion spec — kept in sync with the iOS renderer.
private const val EnterMs = 300
private const val ExitMs = 200
private const val ExitFadeMs = 140          // fade finishes in the first 70% of the exit
private const val ReflowMs = 300
private const val PressDownMs = 120
private const val PressUpMs = 180
private const val RubberBand = 0.18f        // wrong-direction drag follows 18% of the finger
private const val ArmedAlpha = 0.6f         // opacity once the drag reaches the threshold
private const val PressedScale = 0.98f
private const val SettleDamping = 0.85f

private val EnterEasing = CubicBezierEasing(0.2f, 0f, 0f, 1f)
private val ExitEasing = CubicBezierEasing(0.3f, 0f, 1f, 1f)

private val ToastGap = 8.dp
private val ToastEdgeMargin = 14.dp
private val ToastMaxWidth = 520.dp
private val ToastDismissThreshold = 56.dp
private val ToastFlickVelocity = 800.dp     // per second, toward the dismiss edge
private val ToastReverseVelocity = 100.dp   // per second, back toward rest
private val ToastFlingDistance = 96.dp

private const val TitleMaxLines = 2
private const val SubtitleMaxLines = 3

data class ToastData(
    val id: String,
    val type: String,
    val title: String,
    val subtitle: String,
    val position: String,
    val dismissDirection: String,
    val color: Long?,
    val textColor: Long?,
    val icon: String,
    val iconColor: Long?,
    val closeButton: Boolean,
    val animateIcon: Boolean = true,
    val visible: Boolean = true,
    // Bumped when a toast is replaced in place (same key shown again).
    val epoch: Int = 0,
)

@Composable
fun ToastOverlay(
    toasts: List<ToastData>,
    onDismiss: (id: String) -> Unit,
    onRemoved: (id: String) -> Unit,
    onHold: (id: String) -> Unit,
    onRelease: (id: String) -> Unit,
) {
    // Split once per list change instead of on every recomposition.
    val topToasts by remember(toasts) {
        derivedStateOf { toasts.filter { it.position == "top" } }
    }
    // List order is kept: a Column lays its last child lowest, so the newest
    // bottom toast ends up closest to the bottom edge.
    val bottomToasts by remember(toasts) {
        derivedStateOf { toasts.filter { it.position != "top" } }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .windowInsetsPadding(
                    WindowInsets.safeDrawing.only(
                        WindowInsetsSides.Top + WindowInsetsSides.Horizontal
                    )
                )
                .padding(top = ToastEdgeMargin, start = ToastEdgeMargin, end = ToastEdgeMargin)
                .widthIn(max = ToastMaxWidth)
                .fillMaxWidth(),
        ) {
            topToasts.forEach { toast ->
                key(toast.id) {
                    ToastSlot(toast, atTop = true, onDismiss, onRemoved, onHold, onRelease)
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                // safeDrawing includes the keyboard, so bottom toasts stay above it.
                .windowInsetsPadding(
                    WindowInsets.safeDrawing.only(
                        WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal
                    )
                )
                .padding(bottom = ToastEdgeMargin, start = ToastEdgeMargin, end = ToastEdgeMargin)
                .widthIn(max = ToastMaxWidth)
                .fillMaxWidth(),
        ) {
            bottomToasts.forEach { toast ->
                key(toast.id) {
                    ToastSlot(toast, atTop = false, onDismiss, onRemoved, onHold, onRelease)
                }
            }
        }
    }
}

@Composable
private fun ToastSlot(
    toast: ToastData,
    atTop: Boolean,
    onDismiss: (id: String) -> Unit,
    onRemoved: (id: String) -> Unit,
    onHold: (id: String) -> Unit,
    onRelease: (id: String) -> Unit,
) {
    // initialState = false so the first transition plays as an enter animation.
    val visibilityState = remember { MutableTransitionState(initialState = false) }
    visibilityState.targetState = toast.visible

    // Remove the toast from the backing list exactly when the exit animation
    // finishes (idle while settled hidden) — no fixed-delay guess.
    LaunchedEffect(visibilityState.isIdle, visibilityState.currentState) {
        if (visibilityState.isIdle && !visibilityState.currentState) {
            onRemoved(toast.id)
        }
    }

    // Enter comes from the toast's own edge; exit follows the dismiss direction.
    val enterSign = if (atTop) -1 else 1
    val exitSign = if (toast.dismissDirection == "up") -1 else 1
    // The slot grows/shrinks from its stack edge so neighbours reflow in the
    // same moment the toast enters or leaves. clip = false keeps the shadow.
    val edge = if (atTop) Alignment.Top else Alignment.Bottom

    AnimatedVisibility(
        visibleState = visibilityState,
        enter = fadeIn(tween(EnterMs, easing = EnterEasing)) +
            slideInVertically(tween(EnterMs, easing = EnterEasing)) { enterSign * it } +
            expandVertically(tween(ReflowMs, easing = EnterEasing), expandFrom = edge, clip = false),
        exit = fadeOut(tween(ExitFadeMs, easing = LinearEasing)) +
            slideOutVertically(tween(ExitMs, easing = ExitEasing)) { exitSign * it } +
            shrinkVertically(tween(ReflowMs, easing = EnterEasing), shrinkTowards = edge, clip = false),
    ) {
        // The gap lives inside the animated slot so it collapses with it.
        Box(
            modifier = Modifier.padding(
                top = if (atTop) 0.dp else ToastGap,
                bottom = if (atTop) ToastGap else 0.dp,
            )
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

// Non-snapshot gesture bookkeeping; none of it needs to trigger recomposition.
private class DragSession {
    var armed = false     // past the dismiss threshold
    var settle: Job? = null
}

@Composable
private fun ToastItem(
    toast: ToastData,
    onDismiss: () -> Unit,
    onHold: () -> Unit,
    onRelease: () -> Unit,
) {
    val bgColor = Color(toast.color ?: defaultBackground(toast.type))
    val textColor = Color(toast.textColor ?: defaultText(toast.type))
    // Icons are white on every type unless the caller picks a color.
    val iconColor = Color(toast.iconColor ?: 0xFFFFFFFF)
    // +1 when the toast dismisses downward, -1 upward.
    val sign = if (toast.dismissDirection == "up") -1f else 1f

    val density = LocalDensity.current
    val thresholdPx = with(density) { ToastDismissThreshold.toPx() }
    val flickPx = with(density) { ToastFlickVelocity.toPx() }
    val reversePx = with(density) { ToastReverseVelocity.toPx() }
    val flingPx = with(density) { ToastFlingDistance.toPx() }

    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val session = remember { DragSession() }

    // Live translation. Read only inside graphicsLayer, so dragging updates the
    // layer without recomposing or relaying out.
    var dragOffset by remember { mutableFloatStateOf(0f) }
    var pressed by remember { mutableStateOf(false) }
    val pressScale = animateFloatAsState(
        targetValue = if (pressed) PressedScale else 1f,
        animationSpec = tween(if (pressed) PressDownMs else PressUpMs),
        label = "toastPress",
    )

    // A replaced toast starts from rest again.
    LaunchedEffect(toast.epoch) {
        if (toast.epoch > 0) {
            session.settle?.cancel()
            session.armed = false
            dragOffset = 0f
        }
    }

    val dragState = rememberDraggableState { delta ->
        // A drag always continues from where the toast is right now. Finger
        // travel is derived from the visible offset on every event instead of
        // being stored, so nothing from an earlier drag can leak into this one,
        // and no ordering between this callback and onDragStarted is assumed.
        session.settle?.cancel()
        session.settle = null
        val travel = (if (dragOffset * sign >= 0f) dragOffset else dragOffset / RubberBand) + delta
        // Free movement toward the dismiss edge, rubber-band the other way.
        dragOffset = if (travel * sign >= 0f) travel else travel * RubberBand
        val nowArmed = dragOffset * sign > thresholdPx
        if (nowArmed && !session.armed) {
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        }
        session.armed = nowArmed
    }

    val titleStyle = remember(textColor) { toastTitleStyle.copy(color = textColor) }
    val subtitleStyle = remember(textColor) { toastSubtitleStyle.copy(color = textColor) }

    // Toast content metrics are kept in sync with the iOS renderer.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer {
                translationY = dragOffset
                // Fade toward ArmedAlpha as the drag nears the threshold, so the
                // user can see whether letting go will dismiss.
                val progress = (dragOffset * sign / thresholdPx).coerceIn(0f, 1f)
                alpha = 1f - (1f - ArmedAlpha) * progress
                scaleX = pressScale.value
                scaleY = pressScale.value
            }
            .shadow(
                elevation = 2.dp,
                shape = RoundedCornerShape(16.dp),
                ambientColor = Color(0x1A000000),
                spotColor = Color(0x1A000000),
            )
            .background(bgColor, RoundedCornerShape(16.dp))
            // Gestures sit before the padding so the whole toast, including its
            // padded edge, is touchable and never lets taps fall through.
            // Hold: fires on finger-down, pauses the auto-dismiss timer.
            .pointerInput(toast.id) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    pressed = true
                    onHold()
                    try {
                        // Wait until every pointer is lifted before resuming.
                        do {
                            val event = awaitPointerEvent()
                        } while (event.changes.any { it.pressed })
                    } finally {
                        pressed = false
                        onRelease()
                    }
                }
            }
            .draggable(
                state = dragState,
                orientation = Orientation.Vertical,
                enabled = toast.visible,
                onDragStarted = {
                    // Grab the toast wherever it is, even mid spring-back.
                    session.settle?.cancel()
                    session.settle = null
                },
                onDragStopped = { velocity ->
                    val toward = dragOffset * sign
                    val towardVelocity = velocity * sign
                    // Release direction wins over distance: a flick toward the
                    // edge dismisses, moving back toward rest cancels.
                    val dismiss = when {
                        towardVelocity > flickPx && toward > 0f -> true
                        towardVelocity < -reversePx -> false
                        else -> toward > thresholdPx
                    }
                    session.armed = false
                    session.settle?.cancel()
                    if (dismiss) {
                        // Starts the exit transition; this animation carries the
                        // finger's velocity on top of it so there is no stall.
                        onDismiss()
                        session.settle = scope.launch {
                            animate(
                                initialValue = dragOffset,
                                targetValue = dragOffset + sign * flingPx,
                                initialVelocity = velocity,
                                animationSpec = spring(
                                    dampingRatio = Spring.DampingRatioNoBouncy,
                                    stiffness = Spring.StiffnessMediumLow,
                                ),
                            ) { value, _ -> dragOffset = value }
                        }
                    } else {
                        session.settle = scope.launch {
                            animate(
                                initialValue = dragOffset,
                                targetValue = 0f,
                                initialVelocity = velocity,
                                animationSpec = spring(
                                    dampingRatio = SettleDamping,
                                    stiffness = Spring.StiffnessMediumLow,
                                ),
                            ) { value, _ -> dragOffset = value }
                        }
                    }
                },
            )
            // One node for screen readers: announced when it appears, with a
            // dismiss action so it never depends on the swipe gesture.
            .semantics(mergeDescendants = true) {
                liveRegion = LiveRegionMode.Polite
                dismiss { onDismiss(); true }
            }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (toast.icon != "none") {
            // Keyed on epoch so a replaced toast replays its icon entrance.
            key(toast.epoch) {
                ToastIcon(
                    type = toast.icon,
                    iconColor = iconColor,
                    glyphColor = bgColor,
                    animate = toast.animateIcon,
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            if (toast.title.isNotEmpty()) {
                BasicText(
                    text = toast.title,
                    style = titleStyle,
                    maxLines = TitleMaxLines,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (toast.subtitle.isNotEmpty()) {
                BasicText(
                    text = toast.subtitle,
                    style = subtitleStyle,
                    maxLines = SubtitleMaxLines,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (toast.closeButton) {
            Spacer(modifier = Modifier.width(12.dp))
            CloseButton(color = textColor, onClick = onDismiss)
        }
    }
}

private fun defaultBackground(type: String): Long = when (type) {
    "success" -> 0xFF0E7A3E
    "error" -> 0xFFD11A2A
    "info" -> 0xFF2B2B2F
    else -> 0xFFF8B632
}

// The yellow warning background needs dark text to stay readable.
private fun defaultText(type: String): Long = when (type) {
    "success", "error", "info" -> 0xFFFFFFFF
    else -> 0xFF1A1A1A
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
private fun CloseButton(color: Color, onClick: () -> Unit) {
    // Drawn at 24dp to match the icon, but the touch target is 40dp.
    Box(modifier = Modifier.size(24.dp), contentAlignment = Alignment.Center) {
        Canvas(
            modifier = Modifier
                .requiredSize(40.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = onClick,
                )
                .semantics { contentDescription = "Dismiss" }
                .padding(8.dp)
        ) {
            scale(size.minDimension / 24f, pivot = Offset.Zero) {
                drawLine(color, Offset(7.5f, 7.5f), Offset(16.5f, 16.5f), 1.75f, StrokeCap.Round)
                drawLine(color, Offset(16.5f, 7.5f), Offset(7.5f, 16.5f), 1.75f, StrokeCap.Round)
            }
        }
    }
}

// ─── Icons ────────────────────────────────────────────────────────────────────
// All icons are drawn in a 24-unit box and scaled to the canvas.

// ─── Icon motion ──────────────────────────────────────────────────────────────
// Every icon shares one entrance (a springy pop of the badge), then plays a
// motion that fits its meaning:
//   success — the check draws left to right, then the badge bounces
//   error   — the cross bursts out from its centre, then the badge shakes
//   warning — the "!" drops in and its dot pops, then the badge wobbles
//   info    — the dot pops, the stem grows down, then one soft pulse
//   offline — the slash strikes through the WiFi symbol
// Everything is a pure function of elapsed milliseconds, so the iOS renderer
// uses exactly the same numbers.

private const val IconMotionMs = 1000f

private fun seg(ms: Float, start: Float, end: Float): Float =
    ((ms - start) / (end - start)).coerceIn(0f, 1f)

private fun easeOutCubic(x: Float): Float {
    val inv = 1f - x
    return 1f - inv * inv * inv
}

// Overshoots past 1 before settling, like a light spring.
private fun easeOutBack(x: Float): Float {
    val c1 = 1.70158f
    val c3 = c1 + 1f
    val d = x - 1f
    return 1f + c3 * d * d * d + c1 * d * d
}

// 0 → 1 → 0.
private fun bump(x: Float): Float = sin(PI.toFloat() * x)

// A wave that fades to rest: used for the shake and the wobble.
private fun decayingWave(x: Float, cycles: Float): Float =
    (1f - x) * sin(x * cycles * 2f * PI.toFloat())

private fun iconKind(type: String): String = when (type) {
    "success", "error", "warning", "offline" -> type
    else -> "info"
}

private fun iconAlpha(ms: Float): Float = seg(ms, 80f, 200f)

private fun iconScale(kind: String, ms: Float): Float {
    val pop = 0.5f + 0.5f * easeOutBack(seg(ms, 80f, 380f))
    val accent = when (kind) {
        "success" -> 1f + 0.18f * bump(seg(ms, 430f, 730f))
        "info" -> 1f + 0.10f * bump(seg(ms, 520f, 820f))
        else -> 1f
    }
    return pop * accent
}

// Horizontal shake in 24-unit icon space.
private fun iconShake(kind: String, ms: Float): Float =
    if (kind == "error") 3f * decayingWave(seg(ms, 380f, 780f), 3f) else 0f

// Wobble in degrees.
private fun iconTilt(kind: String, ms: Float): Float =
    if (kind == "warning") 14f * decayingWave(seg(ms, 430f, 930f), 2.5f) else 0f

@Composable
private fun ToastIcon(type: String, iconColor: Color, glyphColor: Color, animate: Boolean) {
    val kind = iconKind(type)
    // One linear clock drives the whole motion. With system animations off it
    // jumps straight to the end, which is the finished icon.
    val clock = remember { Animatable(if (animate) 0f else IconMotionMs) }
    LaunchedEffect(Unit) {
        if (animate) {
            clock.animateTo(IconMotionMs, tween(IconMotionMs.toInt(), easing = LinearEasing))
        }
    }

    Canvas(
        modifier = Modifier
            .size(24.dp)
            .graphicsLayer {
                val ms = clock.value
                val scale = iconScale(kind, ms)
                scaleX = scale
                scaleY = scale
                alpha = iconAlpha(ms)
                translationX = iconShake(kind, ms).dp.toPx()
                rotationZ = iconTilt(kind, ms)
            }
    ) {
        val ms = clock.value
        scale(size.minDimension / 24f, pivot = Offset.Zero) {
            if (kind == "offline") {
                drawOfflineIcon(iconColor, ms)
            } else {
                drawCircle(color = iconColor, radius = 10.75f, center = Offset(12f, 12f))
                when (kind) {
                    "success" -> drawCheckGlyph(glyphColor, ms)
                    "error" -> drawCrossGlyph(glyphColor, ms)
                    "warning" -> drawExclamationGlyph(glyphColor, ms)
                    else -> drawInfoGlyph(glyphColor, ms)
                }
            }
        }
    }
}

private const val GlyphStroke = 1.5f

// Draws the part of the segment a→b covered by `fraction` (clamped to 0..1).
private fun DrawScope.drawPartialLine(
    color: Color, a: Offset, b: Offset, fraction: Float, width: Float = GlyphStroke,
) {
    if (fraction <= 0f) return
    drawLine(color, a, lerp(a, b, fraction.coerceAtMost(1f)), width, StrokeCap.Round)
}

// The check is written like a pen stroke: short leg, then the long one.
private fun DrawScope.drawCheckGlyph(color: Color, ms: Float) {
    val progress = easeOutCubic(seg(ms, 200f, 480f))
    drawPartialLine(color, Offset(8.5f, 12.5f), Offset(10.5f, 14.5f), seg(progress, 0f, 0.29f))
    drawPartialLine(color, Offset(10.5f, 14.5f), Offset(15.5f, 9.5f), seg(progress, 0.29f, 1f))
}

// All four arms of the cross burst out from the centre at once.
private fun DrawScope.drawCrossGlyph(color: Color, ms: Float) {
    val progress = easeOutCubic(seg(ms, 200f, 400f))
    val center = Offset(12f, 12f)
    drawPartialLine(color, center, Offset(14.5f, 9.5f), progress)
    drawPartialLine(color, center, Offset(9.5f, 14.5f), progress)
    drawPartialLine(color, center, Offset(9.5f, 9.5f), progress)
    drawPartialLine(color, center, Offset(14.5f, 14.5f), progress)
}

// "!" — the stem drops in from above and settles, then the dot pops below it.
private fun DrawScope.drawExclamationGlyph(color: Color, ms: Float) {
    val drop = -6f * (1f - easeOutBack(seg(ms, 200f, 450f)))
    val stemAlpha = seg(ms, 200f, 300f)
    if (stemAlpha > 0f) {
        drawLine(
            color.copy(alpha = color.alpha * stemAlpha),
            Offset(12f, 7.5f + drop), Offset(12f, 13f + drop), GlyphStroke, StrokeCap.Round,
        )
    }
    val dot = easeOutBack(seg(ms, 400f, 560f)).coerceAtLeast(0f)
    drawCircle(color, radius = dot, center = Offset(12f, 16.25f))
}

// "i" — the dot pops first, then the stem grows down from it.
private fun DrawScope.drawInfoGlyph(color: Color, ms: Float) {
    val dot = easeOutBack(seg(ms, 200f, 360f)).coerceAtLeast(0f)
    drawCircle(color, radius = dot, center = Offset(12f, 7.75f))
    drawPartialLine(
        color, Offset(12f, 11f), Offset(12f, 16.5f), easeOutCubic(seg(ms, 300f, 520f)),
    )
}

// The slash strikes through as the symbol pops in.
private fun DrawScope.drawOfflineIcon(color: Color, ms: Float) {
    drawPath(OfflinePath, color = color)
    drawPartialLine(
        color, Offset(4.23901f, 4.16736f), Offset(18.4817f, 18.4104f),
        easeOutCubic(seg(ms, 200f, 580f)), 1.3301f,
    )
    drawCircle(color = color, radius = 1.27515f, center = Offset(12.041f, 18.8081f))
}

// Built once and reused by every draw.
private val OfflinePath: Path by lazy(LazyThreadSafetyMode.NONE) {
    Path().apply {
        moveTo(8.60791f, 15.5467f)
        cubicTo(9.65063f, 14.4213f, 11.0666f, 13.9257f, 12.438f, 14.0594f)
        lineTo(15.3364f, 16.9579f)
        cubicTo(14.9322f, 17.3308f, 14.3022f, 17.3068f, 13.9282f, 16.9032f)
        cubicTo(12.8538f, 15.7435f, 11.1462f, 15.7435f, 10.0718f, 16.9032f)
        cubicTo(9.69733f, 17.3072f, 9.06574f, 17.3313f, 8.66162f, 16.9569f)
        cubicTo(8.25755f, 16.5824f, 8.2335f, 15.9508f, 8.60791f, 15.5467f)
        close()
        moveTo(10.5337f, 12.1551f)
        cubicTo(9.39159f, 12.4416f, 8.30586f, 13.0659f, 7.41162f, 14.0311f)
        cubicTo(7.03719f, 14.4352f, 6.40562f, 14.4592f, 6.00147f, 14.0848f)
        cubicTo(5.59764f, 13.7104f, 5.57366f, 13.0797f, 5.94776f, 12.6756f)
        cubicTo(6.82913f, 11.7243f, 7.85866f, 11.0262f, 8.95654f, 10.578f)
        lineTo(10.5337f, 12.1551f)
        close()
        moveTo(11.7476f, 9.98325f)
        cubicTo(14.0238f, 9.91151f, 16.3217f, 10.8077f, 18.0522f, 12.6756f)
        cubicTo(18.4265f, 13.0797f, 18.4025f, 13.7104f, 17.9985f, 14.0848f)
        cubicTo(17.5944f, 14.4592f, 16.9628f, 14.4352f, 16.5884f, 14.0311f)
        cubicTo(15.8675f, 13.253f, 15.0225f, 12.6952f, 14.1235f, 12.3582f)
        lineTo(11.7476f, 9.98325f)
        close()
        moveTo(7.4458f, 9.06723f)
        cubicTo(6.47472f, 9.5887f, 5.56231f, 10.2849f, 4.75147f, 11.16f)
        cubicTo(4.37703f, 11.5642f, 3.74546f, 11.5882f, 3.34131f, 11.2137f)
        cubicTo(2.93746f, 10.8393f, 2.91343f, 10.2086f, 3.2876f, 9.80454f)
        cubicTo(4.10747f, 8.9196f, 5.01521f, 8.18517f, 5.98096f, 7.60239f)
        lineTo(7.4458f, 9.06723f)
        close()
        moveTo(8.29346f, 6.52817f)
        cubicTo(12.5347f, 5.09301f, 17.3591f, 6.18512f, 20.7124f, 9.80454f)
        cubicTo(21.0867f, 10.2086f, 21.0626f, 10.8393f, 20.6587f, 11.2137f)
        cubicTo(20.2545f, 11.5882f, 19.623f, 11.5642f, 19.2485f, 11.16f)
        cubicTo(16.7059f, 8.4158f, 13.1767f, 7.41285f, 9.91065f, 8.14633f)
        lineTo(8.29346f, 6.52817f)
        close()
    }
}
