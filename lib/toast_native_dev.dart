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

  const NativeToastIcon.success({Color color = const Color(0xffffffff)})
      : this._('success', color);

  const NativeToastIcon.warning({Color color = const Color(0xffffffff)})
      : this._('warning', color);

  const NativeToastIcon.error({Color color = const Color(0xffffffff)})
      : this._('error', color);

  const NativeToastIcon.info({Color color = const Color(0xffffffff)})
      : this._('info', color);

  static const none = NativeToastIcon._('none', Color(0x00000000));

  final String name;
  final Color color;
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
    this.position = ToastPosition.top,
    this.length = NativeToastLength.short,
    this.bgColor,
    this.icon,
    this.dismissDirection,
  });

  final ToastPosition position;
  final NativeToastLength length;
  final Color? bgColor;
  final NativeToastIcon? icon;
  final NativeToastDismissDirection? dismissDirection;
}

// ─── MethodChannel ────────────────────────────────────────────────────────────

const _channel = MethodChannel('toast_native_dev/channel');

String _visibleText(String? value) {
  if (value == null) return '';
  return value.trim();
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Shows a native toast above Flutter widgets and WebViews.
///
/// [title] and [subtitle] are optional. A null or blank value is not drawn.
/// If both are missing, this is a no-op.
///
/// Icon and background follow [type] unless [NativeToastOptions] overrides them.
Future<void> showToast({
  required ToastType type,
  String? title,
  String? subtitle,
  NativeToastOptions options = const NativeToastOptions(),
}) async {
  final resolvedTitle = _visibleText(title);
  final resolvedSubtitle = _visibleText(subtitle);
  if (resolvedTitle.isEmpty && resolvedSubtitle.isEmpty) {
    return;
  }

  final resolvedPosition = options.position;
  final resolvedLength = options.length;
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
  final resolvedColor = options.bgColor ?? _defaultColorFor(type);
  final resolvedIcon = options.icon ?? _defaultIconFor(type);

  await _channel.invokeMethod('showToast', {
    'type': type.name,
    'title': resolvedTitle,
    'subtitle': resolvedSubtitle,
    'position': resolvedPosition.name,
    'durationMs': resolvedLength.durationMs,
    'color': resolvedColor.toARGB32(),
    'icon': resolvedIcon.name,
    'iconColor': resolvedIcon.color.toARGB32(),
    'dismissDirection': resolvedDismiss.name,
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

NativeToastIcon _defaultIconFor(ToastType type) => switch (type) {
      ToastType.success => const NativeToastIcon.success(),
      ToastType.warning => const NativeToastIcon.warning(),
      ToastType.error => const NativeToastIcon.error(),
      ToastType.info => const NativeToastIcon.info(),
    };

Color _defaultColorFor(ToastType type) => switch (type) {
      ToastType.success => const Color(0xff18A957),
      ToastType.warning => const Color(0xffF8B632),
      ToastType.error => const Color(0xffFB2C36),
      ToastType.info => const Color(0xff969696),
    };
