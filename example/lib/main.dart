import 'dart:async';

import 'package:flutter/material.dart';
import 'package:toast_native_dev/toast_native_dev.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Toast Native Demo',
      home: ToastTestLab(),
    );
  }
}

class ToastTestLab extends StatefulWidget {
  const ToastTestLab({super.key});

  @override
  State<ToastTestLab> createState() => _ToastTestLabState();
}

class _ToastTestLabState extends State<ToastTestLab> {
  bool _isRunningStress = false;
  int _sentCount = 0;

  Future<void> _runBurst({
    required int count,
    required Duration gap,
    required ToastPosition position,
  }) async {
    if (_isRunningStress) return;
    setState(() {
      _isRunningStress = true;
      _sentCount = 0;
    });

    for (var i = 0; i < count && mounted; i++) {
      await showToast(
        type: ToastType.values[i % ToastType.values.length],
        message: 'Burst ${i + 1}/$count',
        options: NativeToastOptions(
          position: position,
          length: const NativeToastLength.ms(900),
          icon: i.isEven ? null : NativeToastIcon.none,
        ),
      );
      setState(() => _sentCount = i + 1);
      await Future<void>.delayed(gap);
    }

    if (mounted) {
      setState(() => _isRunningStress = false);
    }
  }

  Future<void> _runMixedStack() async {
    for (var i = 0; i < 8; i++) {
      await showToast(
        type: ToastType.values[i % ToastType.values.length],
        message:
            i.isEven ? 'Top stack item ${i + 1}' : 'Bottom stack item ${i + 1}',
        options: NativeToastOptions(
          position: i.isEven ? ToastPosition.top : ToastPosition.bottom,
          length: NativeToastLength.long,
          dismissDirection: i.isEven
              ? NativeToastDismissDirection.up
              : NativeToastDismissDirection.down,
        ),
      );
    }
  }

  Future<void> _runFullSizeCases() async {
    await showToast(
      type: ToastType.success,
      message:
          'Full width multiline toast: Profile saved across a long title, wrapped message, narrow phone width, landscape tablet width, and split-screen windows.',
      options: const NativeToastOptions(length: NativeToastLength.long),
    );
    await showToast(
      type: ToastType.warning,
      message: '中文长文案测试：用于检查不同屏幕宽度、字体回退、换行、图标对齐和安全区边距。',
      options: const NativeToastOptions(
        position: ToastPosition.bottom,
        length: NativeToastLength.long,
      ),
    );
    await showToast(
      type: ToastType.error,
      message:
          'SuperLongTokenWithoutSpaces_abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789',
      options: const NativeToastOptions(
        length: NativeToastLength.long,
        icon: NativeToastIcon.none,
      ),
    );
  }

  Future<void> _runRiskCases() async {
    await showToast(
      type: ToastType.warning,
      message:
          'Never toast: swipe to dismiss, verify it does not block touches.',
      options: const NativeToastOptions(length: NativeToastLength.never),
    );
    await showToast(
      type: ToastType.success,
      message:
          'Transparent custom color should not crash native color parsing.',
      options: const NativeToastOptions(
        bgColor: Color(0xAA111111),
        icon: NativeToastIcon.success(color: Color(0xFFFFD166)),
      ),
    );
    await showToast(
      type: ToastType.error,
      message: 'Bottom toast with upward dismiss direction.',
      options: const NativeToastOptions(
        position: ToastPosition.bottom,
        dismissDirection: NativeToastDismissDirection.up,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Native Toast Test Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DeviceInfo(media: media, sentCount: _sentCount),
          const SizedBox(height: 16),
          _Section(
            title: 'Basic',
            children: [
              _ActionButton(
                label: 'Success Toast',
                onPressed: () => showToast(
                  type: ToastType.success,
                  message:
                      'Profile saved!Profile                                                                 ',
                  options: const NativeToastOptions(
                    length: NativeToastLength.medium,
                  ),
                ),
              ),
              _ActionButton(
                label: 'Error Toast',
                onPressed: () => showToast(
                  type: ToastType.error,
                  message: 'Something went wrong.',
                ),
              ),
              _ActionButton(
                label: 'Warning Bottom',
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
              ),
              _ActionButton(
                label: 'Custom 1500ms',
                onPressed: () => showToast(
                  type: ToastType.success,
                  message: 'Custom 1500ms toast',
                  options: const NativeToastOptions(
                    length: NativeToastLength.ms(1500),
                  ),
                ),
              ),
            ],
          ),
          _Section(
            title: 'Stress',
            children: [
              _ActionButton(
                label: _isRunningStress ? 'Running...' : 'Burst 50 Top',
                onPressed: _isRunningStress
                    ? null
                    : () => _runBurst(
                          count: 50,
                          gap: const Duration(milliseconds: 35),
                          position: ToastPosition.top,
                        ),
              ),
              _ActionButton(
                label: _isRunningStress ? 'Running...' : 'Burst 50 Bottom',
                onPressed: _isRunningStress
                    ? null
                    : () => _runBurst(
                          count: 50,
                          gap: const Duration(milliseconds: 35),
                          position: ToastPosition.bottom,
                        ),
              ),
              _ActionButton(
                label: 'Mixed Stack 8',
                onPressed: _runMixedStack,
              ),
            ],
          ),
          _Section(
            title: 'Full Size',
            children: [
              _ActionButton(
                label: 'Long Text Matrix',
                onPressed: _runFullSizeCases,
              ),
            ],
          ),
          _Section(
            title: 'Risk Cases',
            children: [
              _ActionButton(
                label: 'Timers, Colors, Directions',
                onPressed: _runRiskCases,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceInfo extends StatelessWidget {
  const _DeviceInfo({required this.media, required this.sentCount});

  final MediaQueryData media;
  final int sentCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Size ${media.size.width.toStringAsFixed(0)} x ${media.size.height.toStringAsFixed(0)}  '
          'DPR ${media.devicePixelRatio.toStringAsFixed(2)}  '
          'Sent $sentCount',
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
