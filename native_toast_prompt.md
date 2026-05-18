# Claude Code Prompt — Native Toast (Flutter + Android + iOS)

## 🎯 Goal
Build a Flutter plugin/module called `native_toast` that shows toast notifications
**above both Flutter widgets and native WebViews** using native platform overlays.
The toast must work in a hybrid Flutter app that uses native Android/iOS WebViews
(Hybrid Composition / PlatformView).

---

## 📦 Project Structure to Create

```
native_toast/
├── lib/
│   └── native_toast.dart          # Dart public API
├── android/
│   └── src/main/kotlin/
│       └── NativeToastPlugin.kt   # Android WindowManager implementation
├── ios/
│   └── Classes/
│       └── NativeToastPlugin.swift # iOS UIWindow implementation
└── pubspec.yaml
```

---

## ✅ Requirements

### 1. Single Public Function (Dart)

```dart
showToast({
  required ToastType type,      // success | error | warning
  required String message,
  ToastPosition position,       // top | bottom  (default: top)
  ToastLength length,           // short | medium | long | ages | never  (default: short)
  bool isClosable,              // show close (✕) button  (default: false)
  String? dismissDirection,     // 'up' | 'down'  (default: matches position)
});
```

### 2. Toast Types

| Type | Background Color | Icon |
|---|---|---|
| `ToastType.success` | `#2E7D32` (dark green) | ✅ checkmark circle |
| `ToastType.error` | `#C62828` (dark red) | ❌ error circle |
| `ToastType.warning` | `#E65100` (dark orange) | ⚠️ warning triangle |

### 3. Global Wrapper Widget (optional but recommended)

```dart
NativeToastConfig(
  position: ToastPosition.top,
  length: ToastLength.medium,
  child: MaterialApp(...),
)
```
Sets global defaults so `showToast()` works context-free anywhere in the app.

---

## 🎨 UI/UX — Match `toast_dev` package behavior

### Visual Design
- Rounded corners: `radius = 14`
- Padding: `horizontal: 16, vertical: 12`
- Icon on left, message text on right, optional ✕ on far right
- White icon + white text
- Subtle drop shadow: `elevation = 8`
- Max width: `screen width - 32px`
- Font: system font, weight medium, size 14

### Animations (native side)
- **Enter**: slide in from top (if `position: top`) or bottom (if `position: bottom`) + fade in
- **Exit**: slide out in dismiss direction + fade out
- **Duration**: `400ms` with ease-in-out curve
- **Stack behavior**: if multiple toasts, stack vertically with `8px` gap — do NOT overlap

### Gestures
- **Swipe to dismiss**: swipe up (top toast) or down (bottom toast) to dismiss
- **Tap close button**: if `isClosable: true`, show ✕ and dismiss on tap
- Dismissed toast triggers exit animation before removal

### Duration (ToastLength)
| Value | Duration |
|---|---|
| `short` | 2 seconds |
| `medium` | 4 seconds |
| `long` | 6 seconds |
| `ages` | 10 seconds |
| `never` | stays until manually dismissed |

---

## 🤖 Android Implementation — `NativeToastPlugin.kt`

Use `WindowManager` to add a native overlay view **above everything** including WebView.

Key requirements:
- Use `WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY`  
  or `TYPE_APPLICATION` if overlay permission not available
- Set `FLAG_NOT_FOCUSABLE` so it doesn't steal keyboard focus
- Gravity: `Gravity.TOP or Gravity.CENTER_HORIZONTAL` (or BOTTOM)
- Add margin from top/bottom: `64dp`
- Handle stack: maintain a list of active toasts, offset each by height + 8dp
- Implement swipe gesture with `GestureDetector` for dismiss
- Animate with `ObjectAnimator` (translationY + alpha)
- Auto-dismiss after duration using `Handler.postDelayed`
- Thread-safe: all UI operations on main thread via `runOnUiThread`
- Handle `MethodChannel` call: `showToast` with args `type`, `message`, `position`, `length`, `isClosable`

---

## 🍎 iOS Implementation — `NativeToastPlugin.swift`

Use a new `UIWindow` with high `windowLevel` to show above everything.

Key requirements:
- Create `UIWindow` with `windowLevel = UIWindow.Level.alert + 1`
- Make it `isUserInteractionEnabled = true` only for the toast view
- Use `UILabel` + `UIImageView` for icon inside a `UIView` container
- Corner radius, shadow via `CALayer`
- Stack: maintain array of active toast views, offset by height + 8
- Swipe gesture: `UIPanGestureRecognizer` for dismiss
- Animate with `UIView.animate` (transform + alpha)
- Auto-dismiss with `DispatchQueue.main.asyncAfter`
- Handle `FlutterMethodChannel` call: `showToast`
- Cleanup: remove `UIWindow` reference when no toasts remain

---

## 🔌 MethodChannel Contract

**Channel name**: `com.yourapp/native_toast`

**Flutter → Native call**:
```json
method: "showToast"
arguments: {
  "type": "success",        // "success" | "error" | "warning"
  "message": "Saved!",
  "position": "top",        // "top" | "bottom"
  "length": "short",        // "short" | "medium" | "long" | "ages" | "never"
  "isClosable": false,
  "dismissDirection": "up"  // "up" | "down"
}
```

---

## 📋 Dart Enums

```dart
enum ToastType { success, error, warning }
enum ToastPosition { top, bottom }
enum ToastLength { short, medium, long, ages, never }
```

---

## 🧪 Example Usage

```dart
// Simple
showToast(type: ToastType.success, message: "Profile saved!");
showToast(type: ToastType.error, message: "Something went wrong.");
showToast(type: ToastType.warning, message: "Check your connection.");

// With options
showToast(
  type: ToastType.warning,
  message: "Session expiring soon",
  position: ToastPosition.bottom,
  length: ToastLength.long,
  isClosable: true,
);
```

---

## ⚠️ Important Notes

1. **Do NOT use Flutter OverlayEntry or ScaffoldMessenger** — these are hidden behind WebView
2. **All UI must be drawn natively** (Android View / iOS UIView) via MethodChannel
3. Flutter's role is **only to call** the MethodChannel — nothing else
4. Ensure toast appears **above Hybrid Composition WebView** on both platforms
5. Test stacking: call `showToast` 3 times quickly — all 3 should stack without overlapping
6. On Android, handle the case where `TYPE_APPLICATION_OVERLAY` requires permission — fallback to `TYPE_APPLICATION`

---

## 🏁 Deliverables

- [ ] `lib/native_toast.dart` — clean public API
- [ ] `android/.../NativeToastPlugin.kt` — full WindowManager implementation  
- [ ] `ios/.../NativeToastPlugin.swift` — full UIWindow implementation
- [ ] `pubspec.yaml` — plugin setup
- [ ] Brief usage example in comments
