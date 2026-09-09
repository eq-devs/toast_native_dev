import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:toast_native_dev/toast_native_dev.dart';
import 'package:toast_native_dev_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
  }

  testWidgets('native showToast completes for each type', (tester) async {
    await pumpApp(tester);

    await expectLater(
      showToast(type: ToastType.success, title: 'Saved'),
      completes,
    );
    await expectLater(
      showToast(
        type: ToastType.error,
        title: 'Something went wrong',
        subtitle: 'Try again',
      ),
      completes,
    );
    await expectLater(
      showToast(type: ToastType.warning, subtitle: 'Save your work'),
      completes,
    );
    await expectLater(
      showToast(
        type: ToastType.info,
        title: 'No connection',
        options: const NativeToastOptions(position: ToastPosition.bottom),
      ),
      completes,
    );
  });

  testWidgets('empty toast is a Dart no-op', (tester) async {
    await pumpApp(tester);
    await expectLater(showToast(type: ToastType.success), completes);
  });

  testWidgets('custom native options complete without a platform error',
      (tester) async {
    await pumpApp(tester);
    await expectLater(
      showToast(
        type: ToastType.error,
        title: 'Offline',
        options: const NativeToastOptions(
          position: ToastPosition.bottom,
          length: NativeToastLength.ms(1500),
          bgColor: Color(0xaa112233),
          icon: NativeToastIcon.none,
          dismissDirection: NativeToastDismissDirection.up,
        ),
      ),
      completes,
    );
  });
}
