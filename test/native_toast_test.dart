import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toast_native_dev/toast_native_dev.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('toast_native_dev/channel');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('showToast sends the expected default channel payload', () async {
    await showToast(type: ToastType.success, message: 'Saved');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'showToast');
    expect(calls.single.arguments, {
      'type': 'success',
      'message': 'Saved',
      'position': 'top',
      'length': 'short',
      'durationMs': 2000,
      'color': 0xff1b8918,
      'icon': 'success',
      'iconColor': 0xffffffff,
      'dismissDirection': 'up',
    });
  });

  test('bottom position defaults dismiss direction to down', () async {
    await showToast(
      type: ToastType.warning,
      message: 'Expiring',
      options: const NativeToastOptions(position: ToastPosition.bottom),
    );

    expect(calls.single.arguments, containsPair('position', 'bottom'));
    expect(calls.single.arguments, containsPair('dismissDirection', 'down'));
  });

  test('custom options are forwarded to native platforms', () async {
    await showToast(
      type: ToastType.error,
      message: 'Offline',
      options: const NativeToastOptions(
        position: ToastPosition.bottom,
        length: NativeToastLength.ms(1500),
        bgColor: Color(0xaa112233),
        icon: NativeToastIcon.none,
        dismissDirection: NativeToastDismissDirection.up,
      ),
    );

    expect(calls.single.arguments, {
      'type': 'error',
      'message': 'Offline',
      'position': 'bottom',
      'length': 'custom',
      'durationMs': 1500,
      'color': 0xaa112233,
      'icon': 'none',
      'iconColor': 0x00000000,
      'dismissDirection': 'up',
    });
  });

  test('never duration is forwarded as -1', () async {
    await showToast(
      type: ToastType.warning,
      message: 'Pinned',
      options: const NativeToastOptions(length: NativeToastLength.never),
    );

    expect(calls.single.arguments, containsPair('length', 'never'));
    expect(calls.single.arguments, containsPair('durationMs', -1));
  });

  test('invalid custom duration fails before calling native code', () async {
    expect(
      () => showToast(
        type: ToastType.success,
        message: 'Invalid',
        options: const NativeToastOptions(length: NativeToastLength.ms(0)),
      ),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });
}
