import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toast_native_dev/toast_native_dev.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('toast_native_dev/channel');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    setToastDefaults(const NativeToastDefaults());
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
    final id = await showToast(type: ToastType.success, title: 'Saved');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'showToast');
    expect(id, isNotNull);
    expect(calls.single.arguments, {
      'id': id,
      'type': 'success',
      'title': 'Saved',
      'subtitle': '',
      'position': 'top',
      'durationMs': 4000,
      'color': 0xff0e7a3e,
      'textColor': 0xffffffff,
      'icon': 'success',
      'iconColor': 0xffffffff,
      'dismissDirection': 'up',
      'closeButton': false,
      'iconAnimation': true,
    });
  });

  test('null title and subtitle is a no-op', () async {
    expect(await showToast(type: ToastType.success), isNull);
    expect(
      await showToast(type: ToastType.error, title: '  ', subtitle: ''),
      isNull,
    );
    expect(calls, isEmpty);
  });

  test('subtitle only is forwarded without a title', () async {
    await showToast(type: ToastType.warning, subtitle: 'Save your work');
    expect(calls.single.arguments, containsPair('title', ''));
    expect(calls.single.arguments, containsPair('subtitle', 'Save your work'));
    expect(calls.single.arguments, containsPair('icon', 'warning'));
    expect(calls.single.arguments, containsPair('color', 0xfff8b632));
  });

  test('warning uses dark text but keeps the white icon of every other type',
      () async {
    await showToast(type: ToastType.warning, title: 'Careful');
    expect(calls.single.arguments, containsPair('textColor', 0xff1a1a1a));
    expect(calls.single.arguments, containsPair('iconColor', 0xffffffff));
  });

  test('icon animation can be turned off globally', () async {
    setToastDefaults(const NativeToastDefaults(animateIcon: false));
    await showToast(type: ToastType.success, title: 'Saved');
    expect(calls.single.arguments, containsPair('iconAnimation', false));
  });

  test('info type uses the dark neutral color and the info icon', () async {
    await showToast(type: ToastType.info, title: 'Heads up');
    expect(calls.single.arguments, containsPair('type', 'info'));
    expect(calls.single.arguments, containsPair('color', 0xff2b2b2f));
    expect(calls.single.arguments, containsPair('textColor', 0xffffffff));
    expect(calls.single.arguments, containsPair('icon', 'info'));
  });

  test('offline icon is forwarded by name', () async {
    await showToast(
      type: ToastType.info,
      title: 'Интернет үзіліп қалды',
      options: const NativeToastOptions(icon: NativeToastIcon.offline()),
    );
    expect(calls.single.arguments, containsPair('icon', 'offline'));
  });

  test('errors stay longer than other types by default', () async {
    await showToast(type: ToastType.error, title: 'Failed');
    expect(calls.single.arguments, containsPair('durationMs', 6000));
  });

  test('bottom position defaults dismiss direction to down', () async {
    await showToast(
      type: ToastType.warning,
      title: 'Expiring',
      options: const NativeToastOptions(position: ToastPosition.bottom),
    );

    expect(calls.single.arguments, containsPair('position', 'bottom'));
    expect(calls.single.arguments, containsPair('dismissDirection', 'down'));
  });

  test('custom options are forwarded to native platforms', () async {
    final id = await showToast(
      type: ToastType.error,
      title: 'Offline',
      options: const NativeToastOptions(
        position: ToastPosition.bottom,
        length: NativeToastLength.ms(1500),
        bgColor: Color(0xaa112233),
        textColor: Color(0xffabcdef),
        icon: NativeToastIcon.none,
        dismissDirection: NativeToastDismissDirection.up,
        key: 'network',
        showCloseButton: true,
        animateIcon: false,
      ),
    );

    expect(id, 'network');
    expect(calls.single.arguments, {
      'id': 'network',
      'type': 'error',
      'title': 'Offline',
      'subtitle': '',
      'position': 'bottom',
      'durationMs': 1500,
      'color': 0xaa112233,
      'textColor': 0xffabcdef,
      'icon': 'none',
      'iconColor': 0x00000000,
      'dismissDirection': 'up',
      'closeButton': true,
      'iconAnimation': false,
    });
  });

  test('text color follows the background when not set', () async {
    await showToast(
      type: ToastType.success,
      title: 'Light',
      options: const NativeToastOptions(bgColor: Color(0xffffffff)),
    );
    await showToast(
      type: ToastType.success,
      title: 'Dark',
      options: const NativeToastOptions(bgColor: Color(0xff000000)),
    );
    expect(calls[0].arguments, containsPair('textColor', 0xff1a1a1a));
    expect(calls[1].arguments, containsPair('textColor', 0xffffffff));
  });

  test('explicit icon color wins over the text color', () async {
    await showToast(
      type: ToastType.success,
      title: 'Saved',
      options: const NativeToastOptions(
        icon: NativeToastIcon.success(color: Color(0xffffd166)),
      ),
    );
    expect(calls.single.arguments, containsPair('iconColor', 0xffffd166));
  });

  test('never duration is forwarded as -1 with a close button', () async {
    await showToast(
      type: ToastType.warning,
      title: 'Pinned',
      options: const NativeToastOptions(length: NativeToastLength.never),
    );

    expect(calls.single.arguments, containsPair('durationMs', -1));
    expect(calls.single.arguments, containsPair('closeButton', true));
  });

  test('invalid custom duration fails before calling native code', () async {
    expect(
      () => showToast(
        type: ToastType.success,
        title: 'Invalid',
        options: const NativeToastOptions(length: NativeToastLength.ms(0)),
      ),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('each toast gets its own id unless a key is given', () async {
    final first = await showToast(type: ToastType.success, title: 'One');
    final second = await showToast(type: ToastType.success, title: 'Two');
    expect(first, isNot(second));
  });

  test('global defaults apply when an option is not set', () async {
    setToastDefaults(const NativeToastDefaults(
      position: ToastPosition.bottom,
      length: NativeToastLength.ages,
      colors: {ToastType.success: Color(0xff000000)},
      textColor: Color(0xff00ff00),
    ));

    await showToast(type: ToastType.success, title: 'Saved');
    expect(calls.single.arguments, containsPair('position', 'bottom'));
    expect(calls.single.arguments, containsPair('dismissDirection', 'down'));
    expect(calls.single.arguments, containsPair('durationMs', 10000));
    expect(calls.single.arguments, containsPair('color', 0xff000000));
    expect(calls.single.arguments, containsPair('textColor', 0xff00ff00));

    calls.clear();
    await showToast(
      type: ToastType.success,
      title: 'Saved',
      options: const NativeToastOptions(position: ToastPosition.top),
    );
    expect(calls.single.arguments, containsPair('position', 'top'));
  });

  test('dismissToast and dismissAllToasts call the native side', () async {
    await dismissToast('network');
    await dismissAllToasts();

    expect(calls[0].method, 'dismissToast');
    expect(calls[0].arguments, {'id': 'network'});
    expect(calls[1].method, 'dismissAll');
    expect(calls[1].arguments, isNull);
  });
}
