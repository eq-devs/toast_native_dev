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
