# toast_native_dev

Native toast notifications that render **above Flutter widgets *and* native WebViews**, by delegating rendering to the platform's own overlay layer.

[![pub package](https://img.shields.io/pub/v/toast_native_dev.svg)](https://pub.dev/packages/toast_native_dev)

## Why this exists

Flutter's standard overlay mechanisms (`OverlayEntry`, `ScaffoldMessenger`, `Overlay.of(...)`) are hidden behind Hybrid Composition WebViews — toasts disappear *under* a `webview_flutter` `WebView`. This plugin sidesteps the problem by rendering on a native layer the WebView can't cover:

| Platform | Native overlay |
|---|---|
| Android | `ComposeView` attached to the Activity's `DecorView` (z = 100) |
| iOS | Per-toast `UIWindow` at `windowLevel = .alert + 1` |

## Install

```yaml
dependencies:
  toast_native_dev: ^0.0.1
```

```dart
import 'package:toast_native_dev/toast_native_dev.dart';
```

## Quick start

```dart
showToast(
  type: ToastType.success,
  message: 'Profile saved',
);
```

That's it. Defaults: top position, 2-second duration, white icon matching the type, swipe-up to dismiss.

## Customizing

All optional configuration goes through `NativeToastOptions`:

```dart
showToast(
  type: ToastType.warning,
  message: 'Session expiring in 30 seconds',
  options: NativeToastOptions(
    position: ToastPosition.bottom,
    length: NativeToastLength.long,
    bgColor: Color(0xFFCC8E12),
    icon: NativeToastIcon.warning(color: Colors.white),
    dismissDirection: NativeToastDismissDirection.down,
  ),
);
```

## API

### `showToast({type, message, options})`

| Parameter | Type | Required | Default |
|---|---|---|---|
| `type` | `ToastType` | ✅ | — |
| `message` | `String` | ✅ | — |
| `options` | `NativeToastOptions` |   | `const NativeToastOptions()` |

Returns `Future<void>` that completes when the platform call returns (does **not** wait for the toast to dismiss).

### `ToastType`

`success` · `error` · `warning` — picks the default background color and icon.

| Type | Default color |
|---|---|
| `success` | `#1B8918` (green) |
| `warning` | `#CC8E12` (amber) |
| `error` | `#FF3B30` (red) |

### `NativeToastOptions`

| Field | Type | Default | Notes |
|---|---|---|---|
| `position` | `ToastPosition` | `top` | `top` or `bottom` |
| `length` | `NativeToastLength` | `short` | See lengths below |
| `bgColor` | `Color?` | type-based | Overrides the type default |
| `icon` | `NativeToastIcon?` | type-based | Pass `NativeToastIcon.none` to hide |
| `dismissDirection` | `NativeToastDismissDirection?` | matches `position` | `up` for top toasts, `down` for bottom |

### `NativeToastLength`

| Constant | Duration |
|---|---|
| `NativeToastLength.short` | 2 s |
| `NativeToastLength.medium` | 4 s |
| `NativeToastLength.long` | 6 s |
| `NativeToastLength.ages` | 10 s |
| `NativeToastLength.never` | never auto-dismisses |
| `NativeToastLength.ms(int)` | custom milliseconds |

```dart
options: NativeToastOptions(length: NativeToastLength.ms(2500))
```

### `NativeToastIcon`

| Constructor | Renders |
|---|---|
| `NativeToastIcon.success({color})` | white check in a circle |
| `NativeToastIcon.warning({color})` | exclamation mark in a circle |
| `NativeToastIcon.error({color})` | white X in a circle |
| `NativeToastIcon.none` | no icon |

Icons are vector-drawn on a 20-pt canvas — no asset files, no rasterization.

## User gestures

Both behaviors are enabled by default, no configuration needed.

| Gesture | Behavior |
|---|---|
| **Drag toward the dismiss edge** | Toast moves with the finger. Past 56 dp → dismissed. Under threshold → springs back. |
| **Drag the other way** | Clamped — toast won't move (resists wrong-direction swipes). |
| **Touch and hold** | Auto-dismiss timer pauses. Lift finger → timer resumes from where it stopped. |

## Animation

- 450 ms total, fade + slide composed in lockstep
- Enter: `FastOutSlowInEasing` (decelerates as it arrives)
- Exit: `easeInCubic` (accelerates as it leaves)
- Drag-then-dismiss: slide is additive (starts from current drag position) so the motion is always continuous
- Stacking is animated: when a new toast appears or one is dismissed, neighbors smoothly slide to make/fill room

## Platform support

| Platform | Min version |
|---|---|
| Android | API 21 (Lollipop), Compose 1.7 / Kotlin 2.2 |
| iOS | 13.0 |

## Architecture in 3 lines

- **Dart** (`lib/toast_native_dev.dart`) — public API; converts args and fires `MethodChannel('toast_native_dev/channel').invokeMethod('showToast', …)`.
- **Android** (`android/.../NativeToastPlugin.kt`) — keeps one `ComposeView` on the DecorView with a `mutableStateListOf<ToastData>`; `ToastOverlay.kt` is the Compose UI.
- **iOS** (`ios/Classes/NativeToastPlugin.swift`) — one `UIWindow` per toast at `.alert + 1`, with `PassthroughView`/`PassthroughWindow` so touches outside the toast fall through to the app.

## License

MIT — see [LICENSE](LICENSE).
