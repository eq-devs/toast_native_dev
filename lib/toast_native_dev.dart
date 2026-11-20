/// native_toast — shows toasts above Flutter widgets AND native WebViews
/// by delegating all rendering to Android WindowManager / iOS UIWindow.
library native_toast;

import 'package:flutter/services.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum ToastType { success, error, warning, info }

enum ToastPosition { top, bottom }

enum NativeToastDismissDirection { up, down }

class NativeToastIcon {
  const NativeToastIcon._(this.name, this.color);

  /// Check mark in a circle.
  const NativeToastIcon.success({Color? color}) : this._('success', color);

  /// Exclamation mark in a circle.
  const NativeToastIcon.warning({Color? color}) : this._('warning', color);

  /// Cross in a circle.
  const NativeToastIcon.error({Color? color}) : this._('error', color);

  /// Letter "i" in a circle.
  const NativeToastIcon.info({Color? color}) : this._('info', color);

  /// Crossed-out WiFi symbol, for connectivity messages.
  const NativeToastIcon.offline({Color? color}) : this._('offline', color);

  static const none = NativeToastIcon._('none', Color(0x00000000));

  final String name;

  /// Icon color. When null the icon is white, the same on every toast type.
  final Color? color;
}

class NativeToastLength {
  const NativeToastLength._(this.durationMs);

  const NativeToastLength.ms(int durationMs) : this._(durationMs);

  static const short = NativeToastLength._(2000);
  static const medium = NativeToastLength._(4000);
  static const long = NativeToastLength._(6000);
  static const ages = NativeToastLength._(10000);
  static const never = NativeToastLength._(-1);

  final int durationMs;
}

// ─── Options ─────────────────────────────────────────────────────────────────

class NativeToastOptions {
  const NativeToastOptions({
    this.position,
    this.length,
    this.bgColor,
    this.textColor,
    this.icon,
    this.dismissDirection,
    this.key,
    this.showCloseButton,
    this.animateIcon,
  });

  /// Screen edge. Falls back to [NativeToastDefaults.position].
  final ToastPosition? position;

  /// Auto-dismiss duration. Falls back to [NativeToastDefaults.length], then
  /// to 6 seconds for errors and 4 seconds for every other type.
  final NativeToastLength? length;

  /// Background color. Falls back to [NativeToastDefaults.colors], then to the
  /// built-in color for the toast type.
  final Color? bgColor;

  /// Title and subtitle color. When null, the text is white on the built-in
  /// type colors; on a custom background, white or near-black is picked,
  /// whichever contrasts more with it.
  final Color? textColor;

  final NativeToastIcon? icon;
  final NativeToastDismissDirection? dismissDirection;

  /// Identifies the toast. Showing another toast with the same key updates the
  /// one already on screen instead of adding a new one. The key is also the id
  /// returned by [showToast].
  final String? key;

  /// Shows a close button. Defaults to true only for
  /// [NativeToastLength.never] toasts.
  final bool? showCloseButton;

  /// Plays the icon's entrance animation (a springy pop while the glyph draws
  /// itself). Falls back to [NativeToastDefaults.animateIcon], which is true.
  final bool? animateIcon;
}

/// App-wide defaults applied by [showToast] when an option is not set.
class NativeToastDefaults {
  const NativeToastDefaults({
    this.position = ToastPosition.top,
    this.length,
    this.colors = const {},
    this.textColor,
    this.animateIcon = true,
  });

  final ToastPosition position;

  /// When null: 6 seconds for errors, 4 seconds for every other type.
  final NativeToastLength? length;

  /// Background color overrides per type.
  final Map<ToastType, Color> colors;

  /// When null, text is white on the built-in type colors and picked for best
  /// contrast on a custom background.
  final Color? textColor;

  /// Whether icons play their entrance animation.
  final bool animateIcon;
}

NativeToastDefaults _defaults = const NativeToastDefaults();

/// Replaces the app-wide defaults used by [showToast].
void setToastDefaults(NativeToastDefaults defaults) {
  _defaults = defaults;
}

// ─── MethodChannel ────────────────────────────────────────────────────────────

const _channel = MethodChannel('toast_native_dev/channel');

int _nextId = 0;

String _visibleText(String? value) {
  if (value == null) return '';
  return value.trim();
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Shows a native toast above Flutter widgets and WebViews.
///
/// [title] and [subtitle] are optional. A null or blank value is not drawn.
/// If both are missing, this is a no-op and returns null.
///
/// Icon, background and text color follow [type] unless [NativeToastOptions]
/// or [setToastDefaults] override them.
///
/// Returns the toast id, which can be passed to [dismissToast].
Future<String?> showToast({
  required ToastType type,
  String? title,
  String? subtitle,
  NativeToastOptions options = const NativeToastOptions(),
}) async {
  final resolvedTitle = _visibleText(title);
  final resolvedSubtitle = _visibleText(subtitle);
  if (resolvedTitle.isEmpty && resolvedSubtitle.isEmpty) {
    return null;
  }

  final resolvedPosition = options.position ?? _defaults.position;
  final resolvedLength =
      options.length ?? _defaults.length ?? _defaultLengthFor(type);
  if (resolvedLength.durationMs <= 0 && resolvedLength.durationMs != -1) {
    throw ArgumentError.value(
      resolvedLength.durationMs,
      'options.length',
      'Custom duration must be a positive integer in milliseconds.',
    );
  }
  final resolvedDismiss = options.dismissDirection ??
      (resolvedPosition == ToastPosition.top
          ? NativeToastDismissDirection.up
          : NativeToastDismissDirection.down);
  final customColor = options.bgColor ?? _defaults.colors[type];
  final resolvedColor = customColor ?? _defaultColorFor(type);
  // The design uses white text on every built-in color; only a custom
  // background gets its text color picked by contrast.
  final resolvedTextColor = options.textColor ??
      _defaults.textColor ??
      (customColor == null ? _lightText : _readableTextOn(customColor));
  final resolvedIcon = options.icon ?? _defaultIconFor(type);
  final resolvedIconColor = resolvedIcon.color ?? _lightText;
  final id = options.key ?? 'toast_${++_nextId}';

  await _channel.invokeMethod('showToast', {
    'id': id,
    'type': type.name,
    'title': resolvedTitle,
    'subtitle': resolvedSubtitle,
    'position': resolvedPosition.name,
    'durationMs': resolvedLength.durationMs,
    'color': resolvedColor.toARGB32(),
    'textColor': resolvedTextColor.toARGB32(),
    'icon': resolvedIcon.name,
    'iconColor': resolvedIconColor.toARGB32(),
    'dismissDirection': resolvedDismiss.name,
    'closeButton': options.showCloseButton ?? (resolvedLength.durationMs == -1),
    'iconAnimation': options.animateIcon ?? _defaults.animateIcon,
  });
  return id;
}

/// Dismisses the toast with the given [id] (the value returned by
/// [showToast], or its [NativeToastOptions.key]). Does nothing if that toast
/// is already gone.
Future<void> dismissToast(String id) async {
  await _channel.invokeMethod('dismissToast', {'id': id});
}

/// Dismisses every visible toast.
Future<void> dismissAllToasts() async {
  await _channel.invokeMethod('dismissAll');
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _lightText = Color(0xffffffff);
const _darkText = Color(0xff1a1a1a);

/// White or near-black, whichever has the higher WCAG contrast ratio on [bg].
Color _readableTextOn(Color bg) {
  final luminance = bg.computeLuminance();
  final whiteContrast = 1.05 / (luminance + 0.05);
  final darkContrast =
      (luminance + 0.05) / (_darkText.computeLuminance() + 0.05);
  return whiteContrast >= darkContrast ? _lightText : _darkText;
}

NativeToastLength _defaultLengthFor(ToastType type) =>
    type == ToastType.error ? NativeToastLength.long : NativeToastLength.medium;

NativeToastIcon _defaultIconFor(ToastType type) => switch (type) {
      ToastType.success => const NativeToastIcon.success(),
      ToastType.warning => const NativeToastIcon.warning(),
      ToastType.error => const NativeToastIcon.error(),
      ToastType.info => const NativeToastIcon.info(),
    };

// The design-system palette; every one is paired with white text.
Color _defaultColorFor(ToastType type) => switch (type) {
      ToastType.success => const Color(0xff18A957),
      ToastType.warning => const Color(0xffF8B632),
      ToastType.error => const Color(0xffFB2C36),
      ToastType.info => const Color(0xff969696),
    };
