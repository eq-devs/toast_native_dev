# toast_native_dev

Native toast notifications for Flutter that render above Flutter widgets and platform views.

The plugin does not use Flutter `OverlayEntry`, `ScaffoldMessenger`, or `Overlay.of(...)` for rendering. Toasts are drawn by the native platform layer so they can stay visible above native views that may cover Flutter-rendered overlays.

[![pub package](https://img.shields.io/pub/v/toast_native_dev.svg)](https://pub.dev/packages/toast_native_dev)

## Why

Flutter toasts and overlays work normally above Flutter widgets. The problem starts when a screen contains native platform views: those views can sit outside or above Flutter's overlay stack, depending on the platform and composition mode. This package avoids that layer ordering issue by rendering toasts through native overlay surfaces:

| Platform | Native rendering layer |
|---|---|
| Android | A `ComposeView` attached to the Activity `DecorView` |
| iOS | One shared passthrough `UIWindow` on the active `UIWindowScene` |

Touches outside the toast pass through to the Flutter app, so the page remains usable while a toast is visible.

## Install

```yaml
dependencies:
  toast_native_dev: ^0.1.4
```

```dart
import 'package:toast_native_dev/toast_native_dev.dart';
```

## Quick Start

```dart
await showToast(
  type: ToastType.success,
  title: 'Profile saved',
);
```

Default behavior:

| Option | Default |
|---|---|
| Position | `ToastPosition.top` |
| Duration | 4 seconds; 6 seconds for `ToastType.error` |
| Background | Based on `ToastType` |
| Text color | White on the built-in colors; on a custom background, white or near-black, whichever contrasts more |
| Icon | Based on `ToastType`, white on every type |
| Icon animation | On: each icon type plays its own entrance motion |
| Dismiss direction | `up` for top, `down` for bottom |
| Close button | Shown only for `NativeToastLength.never` |

## Custom Toast

```dart
await showToast(
  type: ToastType.warning,
  title: 'Session expiring soon',
  subtitle: 'Save your work',
  options: const NativeToastOptions(
    position: ToastPosition.bottom,
    length: NativeToastLength.long,
  ),
);
```

## API

### `showToast`

```dart
Future<String?> showToast({
  required ToastType type,
  String? title,
  String? subtitle,
  NativeToastOptions options = const NativeToastOptions(),
})
```

`title` and `subtitle` are optional. A null or blank value is not drawn. The title is limited to 2 lines and the subtitle to 3. If both are missing, `showToast` does nothing and returns `null`.

The future completes after the native platform receives the request; it does not wait until the toast disappears. It returns the toast id, which is the `key` option when one is set.

### `dismissToast` and `dismissAllToasts`

```dart
final id = await showToast(
  type: ToastType.info,
  title: 'Uploading',
  options: const NativeToastOptions(length: NativeToastLength.never),
);
await dismissToast(id!);

await dismissAllToasts();
```

### `setToastDefaults`

Sets app-wide defaults once, so individual calls do not repeat them.

```dart
setToastDefaults(const NativeToastDefaults(
  position: ToastPosition.bottom,
  length: NativeToastLength.long,
  colors: {ToastType.success: Color(0xff0B5FFF)},
));
```

### `ToastType`

| Value | Default color | Default icon |
|---|---:|---|
| `ToastType.success` | `0xff18A957` | Check circle |
| `ToastType.error` | `0xffFB2C36` | Close circle |
| `ToastType.warning` | `0xffF8B632` | Exclamation circle |
| `ToastType.info` | `0xff969696` | Info circle |

These are the design-system colors, all with white text. White on the yellow and gray backgrounds is below 4.5:1 contrast; pass `textColor` (or set it in `setToastDefaults`) if you need it higher.

### `NativeToastOptions`

| Field | Type | Default | Description |
|---|---|---|---|
| `position` | `ToastPosition?` | `ToastPosition.top` | Shows the toast at the top or bottom. |
| `length` | `NativeToastLength?` | 4 s, 6 s for errors | Auto-dismiss duration. |
| `bgColor` | `Color?` | Type color | Overrides the default background color. |
| `textColor` | `Color?` | White (best contrast on a custom `bgColor`) | Title and subtitle color. |
| `icon` | `NativeToastIcon?` | Type icon | Overrides or hides the icon. |
| `dismissDirection` | `NativeToastDismissDirection?` | Based on position | Drag direction that dismisses the toast. Timed exits slide the same way. |
| `key` | `String?` | None | Showing a toast with a key that is already visible updates that toast instead of adding another. |
| `showCloseButton` | `bool?` | `true` for `never` | Shows a close button. |
| `animateIcon` | `bool?` | `true` | Plays the icon's entrance animation. Turn it off per toast here, or for the whole app with `setToastDefaults(const NativeToastDefaults(animateIcon: false))`. |

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
  title: 'Saved',
  options: const NativeToastOptions(
    length: NativeToastLength.ms(1500),
  ),
);
```

### `NativeToastIcon`

| Value | Behavior |
|---|---|
| `NativeToastIcon.success({color})` | Check circle. |
| `NativeToastIcon.error({color})` | Close circle. |
| `NativeToastIcon.warning({color})` | Exclamation circle. |
| `NativeToastIcon.info({color})` | Info circle. |
| `NativeToastIcon.offline({color})` | WiFi disconnect. |
| `NativeToastIcon.none` | Hides the icon. |

Icons are drawn natively; no image assets are required. When `color` is omitted the icon is white on every toast type.

When a toast appears its icon badge pops in with a light spring, then plays a motion that fits its meaning:

| Icon | Motion |
|---|---|
| Success | The check is drawn like a pen stroke, then the badge bounces. |
| Error | The cross bursts out from its centre, then the badge shakes side to side. |
| Warning | The "!" drops in and its dot pops, then the badge wobbles. |
| Info | The dot pops, the stem grows down from it, then one soft pulse. |
| Offline | The slash strikes through the WiFi symbol. |

The whole motion takes one second and is identical on Android and iOS. Set `animateIcon: false` to show the icon immediately. It is skipped when Reduce Motion is on (iOS) or system animations are off (Android).

## Gestures

| Gesture | Behavior |
|---|---|
| Drag in `dismissDirection` | Moves the toast with the finger and fades it as it nears the 56pt threshold, with a haptic tick on crossing. |
| Release past the threshold | Dismisses, continuing at the finger's speed. |
| Fast flick toward the edge | Dismisses even before the threshold. |
| Release while moving back | Cancels: the toast springs back, even from past the threshold. |
| Drag opposite direction | The toast follows with rubber-band resistance. |
| Touch and hold | Pauses the auto-dismiss timer; the toast shrinks slightly. |
| Release | Resumes the timer with at least 1.5 seconds left. |
| Tap the close button | Dismisses (when shown). |

## Stacking

- Any number of toasts can be visible at once; each one shows immediately.
- Top toasts stack downward; bottom toasts stack upward with the newest closest to the edge.
- Neighbours slide into place at the same moment a toast enters or leaves.
- Toasts are at most 520pt wide and centered, at least 60pt tall, respect all safe-area insets, and bottom toasts stay above the keyboard.
- Taps outside a toast pass through to the app.

## Accessibility

- Toasts are announced by VoiceOver and TalkBack when they appear and expose a "Dismiss" action.
- Android applies the system "Time to take action" setting to the duration; iOS keeps timed toasts for at least 6 seconds while VoiceOver is running.
- Text scales with Dynamic Type on iOS and the font scale on Android.
- With Reduce Motion (iOS) toasts fade instead of sliding; Android follows the system animation scale.

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
| `id` | `String`, unique per toast or the caller's `key` |
| `type` | `success`, `warning`, `error`, or `info` |
| `title` | `String` (empty when omitted) |
| `subtitle` | `String` (empty when omitted) |
| `position` | `top` or `bottom` |
| `durationMs` | Duration in milliseconds (`-1` = never auto-dismiss) |
| `color` | ARGB integer |
| `textColor` | ARGB integer |
| `icon` | `success`, `warning`, `error`, `info`, `offline`, or `none` |
| `iconColor` | ARGB integer |
| `dismissDirection` | `up` or `down` |
| `closeButton` | `bool` |
| `iconAnimation` | `bool` |

Two more methods exist: `dismissToast` with an `id` argument, and `dismissAll` with no arguments.

### Android

Android code lives in:

```text
android/src/main/kotlin/dev/eqdevs/toast_native_dev/
```

The plugin attaches a single `ComposeView` to the Activity `DecorView` when the first toast is shown, hides it while no toast is visible, and renders all active toasts from a `mutableStateListOf<ToastData>`.

### iOS

iOS code lives in:

```text
ios/Classes/NativeToastPlugin.swift
```

One shared passthrough `UIWindow` is attached to the active `UIWindowScene`. The window is above Flutter and native platform views, while touches outside the toast pass through to the app.

## Development

Analyze:

```sh
flutter analyze
```

Format:

```sh
dart format .
```

Unit tests (Dart + Android JUnit):

```sh
flutter test
cd example/android && ./gradlew :toast_native_dev:testDebugUnitTest
```

Native integration tests (needs a device or simulator):

```sh
cd example
flutter test integration_test/native_toast_test.dart
```

iOS XCTest (from `example/ios`, after `pod install`):

```sh
xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RunnerTests
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
