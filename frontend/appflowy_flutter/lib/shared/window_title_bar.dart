import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/shared/workspace_design.dart';
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

  @override
  void initState() {
    super.initState();

    if (widget.showCaptionButtons &&
        (UniversalPlatform.isWindows || UniversalPlatform.isLinux)) {
      windowsButtonListener = WindowsButtonListener();
      windowManager.addListener(windowsButtonListener!);
      windowsButtonListener!.isMaximized.addListener(_isMaximizedChanged);
      windowManager
          .isMaximized()
          .then((v) => mounted ? setState(() => isMaximized = v) : null);
    } else {
      windowsButtonListener = null;
    }
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
              if (isMaximized)
                WindowCaptionButton.unmaximize(
                  brightness: brightness,
                  onPressed: () => windowManager.unmaximize(),
                )
              else
                WindowCaptionButton.maximize(
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
