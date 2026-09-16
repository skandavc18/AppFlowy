import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

class WindowsButtonListener extends WindowListener {
  WindowsButtonListener();

  final ValueNotifier<bool> isMaximized = ValueNotifier(false);

  @override
  void onWindowMaximize() => isMaximized.value = true;

  @override
  void onWindowUnmaximize() => isMaximized.value = false;

  void dispose() => isMaximized.dispose();
}

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({
    super.key,
    this.leftChildren = const [],
    this.backgroundColor,
    this.title,
  });

  final List<Widget> leftChildren;
  final Color? backgroundColor;
  final Widget? title;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> {
  late final WindowsButtonListener? windowsButtonListener;
  bool isMaximized = false;

  @override
  void initState() {
    super.initState();

    if (UniversalPlatform.isWindows || UniversalPlatform.isLinux) {
      windowsButtonListener = WindowsButtonListener();
      windowManager.addListener(windowsButtonListener!);
      windowsButtonListener!.isMaximized.addListener(_isMaximizedChanged);
    } else {
      windowsButtonListener = null;
    }

    windowManager
        .isMaximized()
        .then((v) => mounted ? setState(() => isMaximized = v) : null);
  }

  void _isMaximizedChanged() {
    if (mounted) {
      setState(() => isMaximized = windowsButtonListener!.isMaximized.value);
    }
  }

  @override
  void dispose() {
    if (windowsButtonListener != null) {
      windowManager.removeListener(windowsButtonListener!);
      windowsButtonListener!.isMaximized.removeListener(_isMaximizedChanged);
      windowsButtonListener?.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final row = Row(
      children: [
        const HSpace(4),
        ...widget.leftChildren,
        if (widget.title != null) ...[
          Expanded(child: widget.title!),
          // Always leave a native drag/double-click target, even when tabs
          // fill the strip. Tab gestures must never drag the window.
          DragToMoveArea(child: const SizedBox(width: 36, height: 40)),
        ] else
          const Spacer(),
        WindowCaptionButton.minimize(
          brightness: brightness,
          onPressed: () => windowManager.minimize(),
        ),
        if (isMaximized) ...[
          WindowCaptionButton.unmaximize(
            brightness: brightness,
            onPressed: () => windowManager.unmaximize(),
          ),
        ] else ...[
          WindowCaptionButton.maximize(
            brightness: brightness,
            onPressed: () => windowManager.maximize(),
          ),
        ],
        WindowCaptionButton.close(
          brightness: brightness,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: widget.backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: widget.title == null ? DragToMoveArea(child: row) : row,
    );
  }
}
