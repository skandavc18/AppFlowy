import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

class WindowsButtonListener extends WindowListener {
  WindowsButtonListener();

  final ValueNotifier<bool> isMaximized = ValueNotifier(false);
  final ValueNotifier<bool> isFullScreen = ValueNotifier(false);
  bool _disposed = false;

  /// Reads the window's current state. The events only report changes, so a
  /// title bar made while the window is maximized or full screen needs this.
  void readWindowState() {
    windowManager.isMaximized().then((v) => _set(isMaximized, v));
    windowManager.isFullScreen().then((v) => _set(isFullScreen, v));
  }

  void _set(ValueNotifier<bool> notifier, bool value) {
    if (!_disposed) notifier.value = value;
  }

  @override
  void onWindowMaximize() => isMaximized.value = true;

  @override
  void onWindowUnmaximize() => isMaximized.value = false;

  @override
  void onWindowEnterFullScreen() => isFullScreen.value = true;

  @override
  void onWindowLeaveFullScreen() => isFullScreen.value = false;

  void dispose() {
    _disposed = true;
    isMaximized.dispose();
    isFullScreen.dispose();
  }
}

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({
    super.key,
    this.leftChildren = const [],
    this.backgroundColor,
    this.title,
    this.showCaptionButtons = true,
    this.height = WorkspaceTokens.headerHeight,
  });

  final List<Widget> leftChildren;
  final Color? backgroundColor;
  final Widget? title;
  final bool showCaptionButtons;
  final double height;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> {
  late final WindowsButtonListener? windowsButtonListener;
  bool isMaximized = false;
  bool isFullScreen = false;

  @override
  void initState() {
    super.initState();

    if (widget.showCaptionButtons &&
        (UniversalPlatform.isWindows || UniversalPlatform.isLinux)) {
      final listener = windowsButtonListener = WindowsButtonListener();
      windowManager.addListener(listener);
      listener.isMaximized.addListener(_windowStateChanged);
      listener.isFullScreen.addListener(_windowStateChanged);
      listener.readWindowState();
    } else {
      windowsButtonListener = null;
    }
  }

  void _windowStateChanged() {
    final listener = windowsButtonListener!;
    if (mounted) {
      setState(() {
        isMaximized = listener.isMaximized.value;
        isFullScreen = listener.isFullScreen.value;
      });
    }
  }

  // Some Linux desktops (macOS-like shells) answer the maximize button by
  // going full screen. Restoring has to leave full screen then: unmaximizing
  // would only change the size kept behind it.
  void _restore() {
    if (isFullScreen) {
      windowManager.setFullScreen(false);
    } else {
      windowManager.unmaximize();
    }
  }

  @override
  void dispose() {
    final listener = windowsButtonListener;
    if (listener != null) {
      windowManager.removeListener(listener);
      listener.isMaximized.removeListener(_windowStateChanged);
      listener.isFullScreen.removeListener(_windowStateChanged);
      listener.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return ColoredBox(
      color: widget.backgroundColor ?? WorkspacePalette.of(context).chrome,
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            const SizedBox(width: WorkspaceTokens.space2),
            ...widget.leftChildren,
            if (widget.title != null) ...[
              Expanded(child: widget.title!),
              // A sibling, never an ancestor of interactive chrome. This
              // blank drag/double-click target survives a crowded header.
              const SizedBox(
                width: WorkspaceTokens.space6,
                child: WindowDragTarget(),
              ),
            ] else
              const Expanded(child: WindowDragTarget()),
            if (widget.showCaptionButtons) ...[
              WindowCaptionButton.minimize(
                brightness: brightness,
                onPressed: () => windowManager.minimize(),
              ),
              if (isMaximized || isFullScreen)
                WindowCaptionButton.unmaximize(
                  key: const ValueKey('window-caption-restore'),
                  brightness: brightness,
                  onPressed: _restore,
                )
              else
                WindowCaptionButton.maximize(
                  key: const ValueKey('window-caption-maximize'),
                  brightness: brightness,
                  onPressed: () => windowManager.maximize(),
                ),
              WindowCaptionButton.close(
                brightness: brightness,
                onPressed: () => windowManager.close(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A deliberately empty native drag/double-click target. Not accepting a child
/// makes it impossible to accidentally put interactive chrome inside it.
class WindowDragTarget extends StatelessWidget {
  const WindowDragTarget({super.key});

  @override
  Widget build(BuildContext context) {
    const space = SizedBox.expand();
    return ExcludeSemantics(
      child: UniversalPlatform.isWindows || UniversalPlatform.isLinux
          ? DragToMoveArea(child: space)
          : const MoveWindowDetector(child: space),
    );
  }
}
