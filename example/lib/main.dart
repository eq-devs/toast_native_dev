import 'package:flutter/material.dart';
import 'package:toast_native_dev/native_toast.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toast Native Demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Toast Demo')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            
            children: [
              ElevatedButton(
                onPressed: () => showToast(
                  type: ToastType.success,
                  message:
                      'Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!Profile saved!',
                  options: const NativeToastOptions(
                      length: NativeToastLength.medium),
                ),
                child: const Text('Success Toast'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => showToast(
                  type: ToastType.error,
                  message: 'Something went wrong.',
                ),
                child: const Text('Error Toast'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => showToast(
                  type: ToastType.warning,
                  message: 'Session expiring soon',
                  options: const NativeToastOptions(
                    position: ToastPosition.bottom,
                    length: NativeToastLength.long,
                    bgColor: Color(0xffCC8E12),
                    icon: NativeToastIcon.warning(color: Color(0xffffffff)),
                    dismissDirection: NativeToastDismissDirection.down,
                  ),
                ),
                child: const Text('Warning (bottom)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  // Stack test — all 3 appear simultaneously
                  showToast(type: ToastType.success, message: 'First toast');
                  showToast(type: ToastType.warning, message: 'Second toast');
                  showToast(type: ToastType.error, message: 'Third toast');
                },
                child: const Text('Stack 3 Toasts'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => showToast(
                  type: ToastType.success,
                  message: 'Custom 1500ms toast',
                  options: const NativeToastOptions(
                    length: NativeToastLength.ms(1500),
                  ),
                ),
                child: const Text('Custom Duration Toast'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
