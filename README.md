# toast_native_dev

Native toast notifications that render **above Flutter widgets and native WebViews** by delegating to platform overlays — Android `DecorView` + Jetpack Compose, iOS `UIWindow` at `.alert + 1`.

Standard Flutter overlay mechanisms (`OverlayEntry`, `ScaffoldMessenger`) are hidden behind Hybrid Composition WebViews. This plugin works around that by rendering on a native layer above the Flutter view.

## Install

```yaml
dependencies:
  toast_native_dev: ^0.0.1
```

## Usage

```dart
import 'package:toast_native_dev/toast_native_dev.dart';

showNativeToast(
  type: NativeToastType.success,
  message: 'Saved successfully',
  position: NativeToastPosition.top,
  length: NativeToastLength.short,
);
```

### Configure global defaults

Wrap your app in `NativeToastConfig` to set defaults for every toast:

```dart
NativeToastConfig(
  defaultPosition: NativeToastPosition.top,
  defaultLength: NativeToastLength.medium,
  child: MaterialApp(home: HomePage()),
)
```

### Parameters

| Parameter | Type | Default |
|---|---|---|
| `type` | `NativeToastType` — `success` / `error` / `warning` | `success` |
| `message` | `String` | required |
| `position` | `NativeToastPosition` — `top` / `bottom` | `top` |
| `length` | `NativeToastLength` — `short` (2s) / `medium` (4s) / `long` (6s) / `ages` (10s) / `never` | `short` |
| `durationMs` | `int?` — custom override in milliseconds | — |
| `bgColor` | `Color?` — custom background | type default |
| `icon` | `NativeToastIcon?` — `success` / `error` / `warning` / `none` | matches type |
| `iconColor` | `Color?` | white |
| `dismissDirection` | `NativeToastDismissDirection?` — `up` / `down` | matches position |

## Behavior

- **Drag to dismiss** — swipe toward the toast's dismiss edge past the threshold to dismiss; under threshold springs back.
- **Hold to pause** — touch and hold the toast to pause its auto-dismiss timer; release to resume.
- **Mirrored animations** — enter uses `FastOutSlowInEasing`, exit uses `easeInCubic` (true reverse curve), both 450 ms.
- **Stacked toasts** — multiple toasts stack vertically with smooth repositioning when added/dismissed.

## Platform support

| Platform | Min version |
|---|---|
| Android | API 21 (Lollipop) |
| iOS | 13.0 |

## License

MIT — see [LICENSE](LICENSE).
