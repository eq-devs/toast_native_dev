# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What This Is

`toast_native_dev` is a Flutter plugin that renders toast notifications **above Flutter widgets AND native WebViews** by delegating all rendering to native platform layers — Android `WindowManager` and iOS `UIWindow`. Flutter's `OverlayEntry`/`ScaffoldMessenger` are intentionally not used because they are hidden behind Hybrid Composition WebViews.

## Commands

Run the example app (required for visual testing — there are no automated tests):
```sh
cd example && flutter run
```

Lint and format:
```sh
flutter analyze
dart format .
```

## Architecture

The plugin has three layers:

**Dart (`lib/native_toast.dart`)** — public API only. Converts enum arguments to strings and fires a `MethodChannel` call to `com.yourapp/native_toast`. `NativeToastConfig` is an optional wrapper widget that sets global defaults via a static `_ToastDefaults` class; it does no rendering.

**Android (`android/src/main/kotlin/.../NativeToastPlugin.kt`)** — implements `FlutterPlugin` + `ActivityAware`. Gets the `WindowManager` from `ActivityPluginBinding`. Each toast is added as a native `View` via `WindowManager.addView()` using `TYPE_APPLICATION_OVERLAY` (falls back to `TYPE_APPLICATION` if overlay permission is denied). Toast stacking is managed in `activeToasts: MutableList<ToastEntry>`; after every add/remove, `rebuildOffsets()` calls `WindowManager.updateViewLayout()` to reposition all active toasts.

**iOS (`ios/Classes/NativeToastPlugin.swift`)** — each toast gets its own `UIWindow` at `windowLevel = .alert + 1`, with a `PassthroughViewController`/`PassthroughView` as the root so touches pass through the window background to the app. The `PassthroughView.hitTest` returns `nil` for self, forwarding all unhandled touches. Stacking and offset rebuild follow the same pattern as Android.

### MethodChannel contract

Channel name: `com.yourapp/native_toast`  
Method: `showToast`  
Arguments: `type` (success/error/warning), `message`, `position` (top/bottom), `length` (short/medium/long/ages/never), `isClosable` (bool), `dismissDirection` (up/down)

### Key invariants

- All UI work must happen on the main thread — Android dispatches via `Handler(Looper.getMainLooper())`, iOS via `DispatchQueue.main.async`.
- `ToastLength.never` sends duration `-1`; both platforms check `> 0` before scheduling auto-dismiss.
- On iOS, `ToastEntry` uses `struct` (value type) — the `dismissWorkItem` field requires writing back to `activeToasts[idx]` after mutation.
- The Android close-button tap is detected by hit-testing `getChildAt(2)` in the touch listener — fragile to view hierarchy changes in `buildToastView`.
