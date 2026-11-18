## 0.1.2

* Restored the horizontal layout from 0.1.0: 14pt side margin and 520pt max width. The 60pt minimum height from 0.1.1 stays.

## 0.1.1

* Toast size now follows the design: at least 60pt tall with centred content, at most 370pt wide (was 520pt), with a 10pt minimum side margin (was 14pt).

## 0.1.0

**Breaking / behaviour changes**

* Default colors changed for contrast: success `#0E7A3E`, error `#D11A2A`, info `#2B2B2F`; warning keeps `#F8B632` but now uses dark text. Icons stay white on every type.
* The warning icon is now an exclamation mark and the info icon a real "i". The WiFi glyph moved to the new `NativeToastIcon.offline`.
* Default duration is 4 seconds (6 seconds for errors) instead of 2.
* `NativeToastIcon.color`, `NativeToastOptions.position` and `NativeToastOptions.length` are now nullable. An icon without a color is white.
* Title is limited to 2 lines and subtitle to 3. Toasts are at most 520pt wide.
* Android: the newest bottom toast is now closest to the bottom edge, matching iOS and the README.

**Added**

* `showToast` returns the toast id; new `dismissToast(id)` and `dismissAllToasts()`.
* `NativeToastOptions.key` (update a visible toast in place), `textColor`, and `showCloseButton` (on by default for `never` toasts).
* `setToastDefaults` / `NativeToastDefaults` for app-wide position, duration, colors and text color.
* Icon entrance animation with its own motion per type: success draws the check and bounces, error bursts the cross out and shakes, warning drops the "!" in and wobbles, info pops its dot and pulses, offline strikes the slash through. On by default; turn it off with `NativeToastOptions.animateIcon` or `NativeToastDefaults.animateIcon`.
* Screen-reader announcements and a "Dismiss" accessibility action; Dynamic Type on iOS; Reduce Motion on iOS.
* Bottom toasts stay above the keyboard; left and right safe-area insets are respected.

**Motion and gestures**

* Unified timing on both platforms: 300 ms enter, 200 ms exit, neighbours reflow at the same moment.
* Exit follows `dismissDirection`. Swipe exits and spring-backs continue from the finger's velocity.
* A fast flick dismisses before the threshold; releasing while moving back cancels.
* Wrong-direction drags rubber-band; the toast fades as it nears the threshold with a haptic tick; it shrinks slightly while held.
* After any touch the toast stays at least 1.5 seconds.

**Fixed**

* Android: the padded edge of a toast ignored touches and let taps through.
* Android: dismissal was decided from raw finger travel instead of the visible position, and a second drag after a cancelled one no longer starts from the first drag's distance.
* Android: bottom toasts could be drawn under the navigation bar on windows that are not edge-to-edge.
* Android: the plugin no longer overwrites or clears lifecycle owners provided by the host activity, and its own owner follows the activity lifecycle.
* iOS: visible toasts re-lay out on rotation and size changes; a toast can be grabbed again while it springs back.

**Performance**

* Android: the Compose overlay is created on the first toast instead of at activity start, and is hidden while empty.
* iOS: toasts set an explicit `shadowPath`.

## 0.0.11

* Match JP Notification: `success` / `error` / `warning` / `info` colors and the four type icons.
* Replace required `message` with optional `title` and `subtitle`. Null or blank lines are not drawn; both missing is a no-op.
* Add Android JUnit, iOS XCTest, and example integration tests for the native MethodChannel contract.
* **Breaking:** `showToast(message:)` is now `title` / `subtitle`. Default type colors are `#18A957`, `#FB2C36`, `#F8B632`, `#969696`.

## 0.0.9

* iOS: reuse a single overlay `UIWindow` for all toasts instead of allocating one per toast.
* Android: remove a toast from the stack exactly when its exit animation completes, instead of after a fixed delay.
* Use monotonic clocks (`SystemClock.elapsedRealtime` / `systemUptime`) for pause/resume timers so wall-clock changes can't corrupt remaining duration.
* Drop the `length` argument from the MethodChannel payload; `durationMs` is now the single source of truth on both platforms.
* Remove the `androidx.compose.material3` dependency from the Android build.
* **Breaking:** `NativeToastLength.name` has been removed (it was unused internally).

## 0.0.8

* Update native toast spacing to use 14dp/pt content padding and icon gap.
* Position top and bottom Android toasts relative to system bars before applying edge padding.
* Match iOS top and bottom edge spacing to the updated 14pt toast layout.

## 0.0.7

* Start-align Android toast message text after the icon.
* Tighten Android toast text line metrics so messages remain vertically centered.

## 0.0.6

* Center Android native toast message text within the toast content area.

## 0.0.5

* Fix Android Compose `Offset` import so the example app builds successfully.
* Add Dart MethodChannel contract tests for toast options, durations, colors, icons, and dismiss directions.
* Expand the example app into a manual test lab for stress, full-size, stacking, timer, color, and gesture risk cases.

## 0.0.4

* Correct README and package description wording around Flutter overlays and native platform views.

## 0.0.3

* Sync README with the current API, MethodChannel name, and platform implementation.
* Exclude local build output and machine-specific files from the pub.dev package archive.

## 0.0.2

* Rewrite README with accurate API documentation and clearer structure (no code changes).

## 0.0.1

* Initial release.
* Native toast notifications that render above Flutter widgets **and** native WebViews (Hybrid Composition).
* Android: Jetpack Compose overlay on the Activity's `DecorView`.
* iOS: per-toast `UIWindow` at `.alert + 1`.
* Features: success / error / warning types, top / bottom positions, custom colors and icons, durations (`short` / `medium` / `long` / `ages` / `never` / custom ms), drag-to-dismiss, hold-to-pause, mirrored enter/exit animations.
