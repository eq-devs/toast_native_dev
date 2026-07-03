/// native_toast — shows toasts above Flutter widgets AND native WebViews
/// by delegating all rendering to Android WindowManager / iOS UIWindow.
library native_toast;

import 'package:flutter/services.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum ToastType { success, error, warning }

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

// ─── Public API ───────────────────────────────────────────────────────────────

/// Shows a native toast notification above all Flutter widgets and WebViews.
///
/// Example:
/// ```dart
/// showToast(type: ToastType.success, message: "Profile saved!");
///
/// showToast(
///   type: ToastType.warning,
///   message: "Session expiring soon",
///   options: NativeToastOptions(
///     position: ToastPosition.bottom,
///     length: NativeToastLength.long,
///     bgColor: Color(0xffCC8E12),
///     icon: NativeToastIcon.warning(),
///   ),
/// );
/// ```
Future<void> showToast({
  required ToastType type,
  required String message,
  NativeToastOptions options = const NativeToastOptions(),
}) async {
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
    'message': message,
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
    };

Color _defaultColorFor(ToastType type) => switch (type) {
      ToastType.success => const Color(0xff1B8918),
      ToastType.warning => const Color(0xffCC8E12),
      ToastType.error => const Color(0xffFF3B30),
    };
