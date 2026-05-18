# toast_native_dev

Native toast notifications for Flutter that render above Flutter widgets and native WebViews.

The plugin does not use Flutter `OverlayEntry`, `ScaffoldMessenger`, or `Overlay.of(...)` for rendering. Toasts are drawn by the native platform layer so they can stay visible above Hybrid Composition WebViews.

[![pub package](https://img.shields.io/pub/v/toast_native_dev.svg)](https://pub.dev/packages/toast_native_dev)

## Why

Flutter overlays can be covered by native views such as `webview_flutter` WebViews. This package avoids that by rendering toasts outside Flutter's widget overlay stack:

| Platform | Native rendering layer |
|---|---|
| Android | A `ComposeView` attached to the Activity `DecorView` |
| iOS | One passthrough `UIWindow` per toast on the active `UIWindowScene` |

Touches outside the toast pass through to the Flutter app, so the page remains usable while a toast is visible.

## Install

```yaml
dependencies:
  toast_native_dev: ^0.0.2
```

```dart
import 'package:toast_native_dev/toast_native_dev.dart';
```

## Quick Start

```dart
await showToast(
  type: ToastType.success,
  message: 'Profile saved',
);
```

Default behavior:

| Option | Default |
|---|---|
| Position | `ToastPosition.top` |
| Duration | `NativeToastLength.short` - 2 seconds |
| Background | Based on `ToastType` |
| Icon | Based on `ToastType` |
| Dismiss direction | `up` for top, `down` for bottom |

## Custom Toast

```dart
await showToast(
  type: ToastType.warning,
  message: 'Session expiring soon',
  options: const NativeToastOptions(
    position: ToastPosition.bottom,
    length: NativeToastLength.long,
    bgColor: Color(0xffCC8E12),
    icon: NativeToastIcon.warning(color: Color(0xffffffff)),
    dismissDirection: NativeToastDismissDirection.down,
  ),
);
```

## API

### `showToast`

```dart
Future<void> showToast({
  required ToastType type,
  required String message,
  NativeToastOptions options = const NativeToastOptions(),
})
```

The returned `Future<void>` completes after the native platform receives the request. It does not wait until the toast disappears.

### `ToastType`

| Value | Default color | Default icon |
|---|---:|---|
| `ToastType.success` | `0xff1B8918` | Check mark in circle |
| `ToastType.warning` | `0xffCC8E12` | Info mark in circle |
| `ToastType.error` | `0xffFF3B30` | X mark in circle |

### `NativeToastOptions`

| Field | Type | Default | Description |
|---|---|---|---|
| `position` | `ToastPosition` | `ToastPosition.top` | Shows the toast at the top or bottom. |
| `length` | `NativeToastLength` | `NativeToastLength.short` | Auto-dismiss duration. |
| `bgColor` | `Color?` | Type color | Overrides the default background color. |
| `icon` | `NativeToastIcon?` | Type icon | Overrides or hides the icon. |
| `dismissDirection` | `NativeToastDismissDirection?` | Based on position | Drag direction that dismisses the toast. |

### `ToastPosition`

| Value | Behavior |
|---|---|
| `ToastPosition.top` | Toasts stack downward from the top edge. |
| `ToastPosition.bottom` | Toasts stack upward from the bottom edge. The newest bottom toast stays closest to the bottom. |

### `NativeToastLength`

| Value | Duration |
|---|---:|
| `NativeToastLength.short` | 2 seconds |
| `NativeToastLength.medium` | 4 seconds |
| `NativeToastLength.long` | 6 seconds |
| `NativeToastLength.ages` | 10 seconds |
| `NativeToastLength.never` | No auto-dismiss |
| `NativeToastLength.ms(int)` | Custom duration in milliseconds |

Custom durations must be positive. `NativeToastLength.never` is the only non-positive supported duration.

```dart
await showToast(
  type: ToastType.success,
  message: 'Saved',
  options: const NativeToastOptions(
    length: NativeToastLength.ms(1500),
  ),
);
```

### `NativeToastIcon`

| Value | Behavior |
|---|---|
| `NativeToastIcon.success({color})` | Check mark in circle. |
| `NativeToastIcon.warning({color})` | Info mark in circle. |
| `NativeToastIcon.error({color})` | X mark in circle. |
| `NativeToastIcon.none` | Hides the icon. |

Icons are drawn natively; no image assets are required.

## Gestures

| Gesture | Behavior |
|---|---|
| Drag in `dismissDirection` | Moves the toast with the finger. If dragged past the threshold, the toast dismisses. |
| Drag opposite direction | Movement is clamped, so the toast resists the wrong direction. |
| Touch and hold | Pauses the auto-dismiss timer. |
| Release after hold | Resumes the remaining auto-dismiss duration. |

## Stacking

Multiple toasts can be visible at the same time.

- Top toasts stack downward.
- Bottom toasts stack upward.
- Removing a toast rebuilds the stack offsets.
- Background taps pass through to Flutter on iOS.

## Platform Support

| Platform | Minimum |
|---|---|
| Android | API 21 |
| iOS | 13.0 |

## Implementation Notes

### Dart

Public API lives in `lib/toast_native_dev.dart`.

The MethodChannel is:

```dart
const MethodChannel('toast_native_dev/channel');
```

`showToast` sends these arguments to native code:

| Argument | Type |
|---|---|
| `type` | `success`, `warning`, or `error` |
| `message` | `String` |
| `position` | `top` or `bottom` |
| `length` | Named length |
| `durationMs` | Duration in milliseconds |
| `color` | ARGB integer |
| `icon` | `success`, `warning`, `error`, or `none` |
| `iconColor` | ARGB integer |
| `dismissDirection` | `up` or `down` |

### Android

Android code lives in:

```text
android/src/main/kotlin/dev/eqdevs/toast_native_dev/
```

The plugin attaches a single `ComposeView` to the Activity `DecorView` and renders all active toasts from a `mutableStateListOf<ToastData>`.

### iOS

iOS code lives in:

```text
ios/Classes/NativeToastPlugin.swift
```

Each toast gets its own passthrough `UIWindow` attached to the active `UIWindowScene`. The window is above Flutter and native WebViews, while touches outside the toast pass through to the app.

## Development

Analyze:

```sh
flutter analyze
```

Format:

```sh
dart format .
```

Run the example app:

```sh
cd example
flutter run
```

Build the iOS simulator example:

```sh
cd example
flutter build ios --simulator
```

## License

MIT - see [LICENSE](LICENSE).
