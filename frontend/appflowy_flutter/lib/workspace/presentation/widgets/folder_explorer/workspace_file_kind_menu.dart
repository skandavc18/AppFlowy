import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The one shape every "add a file" menu wears.
///
/// The sidebar submenu, the explorer toolbar, the gallery header and every
/// context menu render [WorkspaceFileKindMenu], so a file type is named with
/// the same glyph, the same tile and the same row wherever it is offered.
abstract final class WorkspaceFileKindMenuStyle {
  static const width = 268.0;
  static const cornerRadius = 18.0;
  static const rowHeight = 40.0;
  static const rowRadius = 10.0;
  static const rowInset = 6.0;
  static const iconTileSize = 26.0;
  static const iconTileRadius = 9.0;
  static const iconSize = 16.0;
  static const labelSize = 13.5;
  static const headingSize = 10.5;
  static const verticalPadding = 8.0;

  /// Constraints for a popover hosting the menu, so the popover neither
  /// squeezes nor stretches the card.
  static const popoverConstraints = BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: 640,
  );
}

/// Shows the creatable and uploadable file types anchored at [globalPosition].
///
/// Used by the explorer toolbar, its context menu, the gallery header and the
/// sidebar root button so every surface offers the same set as the `/` slash
/// menu, in the same clothes.
Future<WorkspaceFileMenuAction?> showWorkspaceFileKindMenu({
  required BuildContext context,
  required Offset globalPosition,
}) {
  final navigator = Navigator.of(context);
  return navigator.push(
    _WorkspaceFileKindMenuRoute(
      position: globalPosition,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// The list of creatable and uploadable file types.
class WorkspaceFileKindMenu extends StatelessWidget {
  const WorkspaceFileKindMenu({super.key, required this.onSelected});

  final ValueChanged<WorkspaceFileMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final children = <Widget>[];
    WorkspaceFileSource? section;
    for (final action in workspaceFileMenuActions) {
      if (action.source != section) {
        if (section != null) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 5),
              child: Container(height: 1, color: palette.border),
            ),
          );
        }
        section = action.source;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 5),
            child: Text(
              action.source.heading.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: WorkspaceFileKindMenuStyle.headingSize,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: palette.textMuted,
              ),
            ),
          ),
        );
      }
      children.add(
        _WorkspaceFileKindRow(
          action: action,
          palette: palette,
          onSelected: onSelected,
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: WorkspaceFileKindMenuStyle.width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.floatingSurface,
            borderRadius: BorderRadius.circular(
              WorkspaceFileKindMenuStyle.cornerRadius,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 28,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              WorkspaceFileKindMenuStyle.cornerRadius,
            ),
            child: ConstrainedBox(
              // The list is long enough to run past a short window, so it
              // scrolls instead of overflowing.
              constraints: BoxConstraints(
                maxHeight: math.max(
                  240,
                  MediaQuery.sizeOf(context).height * 0.62,
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  vertical: WorkspaceFileKindMenuStyle.verticalPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceFileKindRow extends StatefulWidget {
  const _WorkspaceFileKindRow({
    required this.action,
    required this.palette,
    required this.onSelected,
  });

  final WorkspaceFileMenuAction action;
  final FolderExplorerPalette palette;
  final ValueChanged<WorkspaceFileMenuAction> onSelected;

  @override
  State<_WorkspaceFileKindRow> createState() => _WorkspaceFileKindRowState();
}

class _WorkspaceFileKindRowState extends State<_WorkspaceFileKindRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelected(widget.action),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WorkspaceFileKindMenuStyle.rowInset,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            height: WorkspaceFileKindMenuStyle.rowHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: WorkspaceFileKindMenuStyle.rowInset,
            ),
            decoration: BoxDecoration(
              color: hovered ? palette.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(
                WorkspaceFileKindMenuStyle.rowRadius,
              ),
            ),
            child: Row(
              children: [
                WorkspaceFileKindGlyph(
                  icon: widget.action.icon,
                  palette: palette,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: WorkspaceFileKindMenuStyle.labelSize,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The nested "Add file" entry, which reveals every supported file type.
///
/// Shared by the sidebar `+` button, the folder header and the sidebar
/// background menu so a submenu is never a second design.
class WorkspaceFileAddAction extends PopoverActionCell {
  WorkspaceFileAddAction({required this.onCreate});

  final void Function(WorkspaceFileMenuAction action) onCreate;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        workspaceAddFileIcon,
        color: iconColor,
        size: 17,
      );

  @override
  Widget? rightIcon(Color iconColor) => Icon(
        Icons.chevron_right_rounded,
        color: iconColor,
        size: 16,
      );

  @override
  String get name => LocaleKeys.workspaceFolderExplorer_addFile.tr();

  @override
  bool get openOnHover => true;

  /// The menu draws its own card, so the popover must not stack another one
  /// behind it.
  @override
  Decoration? get popoverDecoration => const BoxDecoration();

  @override
  EdgeInsets? get popoverMargin => EdgeInsets.zero;

  @override
  BoxConstraints? get popoverConstraints =>
      WorkspaceFileKindMenuStyle.popoverConstraints;

  @override
  PopoverActionCellBuilder get builder =>
      (context, parentController, controller) => WorkspaceFileKindMenu(
            onSelected: (action) {
              controller.close();
              parentController.close();
              onCreate(action);
            },
          );
}

/// The accent tile a file type's glyph sits in.
class WorkspaceFileKindGlyph extends StatelessWidget {
  const WorkspaceFileKindGlyph({
    super.key,
    required this.icon,
    this.palette,
  });

  final IconData icon;
  final FolderExplorerPalette? palette;

  @override
  Widget build(BuildContext context) {
    final palette = this.palette ?? FolderExplorerPalette.of(context);
    return Container(
      width: WorkspaceFileKindMenuStyle.iconTileSize,
      height: WorkspaceFileKindMenuStyle.iconTileSize,
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
          WorkspaceFileKindMenuStyle.iconTileRadius,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: WorkspaceFileKindMenuStyle.iconSize,
        color: palette.accent,
      ),
    );
  }
}

class _WorkspaceFileKindMenuRoute extends PopupRoute<WorkspaceFileMenuAction> {
  _WorkspaceFileKindMenuRoute({
    required this.position,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Offset position;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Builder(
      builder: (context) => CustomSingleChildLayout(
        delegate: _WorkspaceFileKindMenuLayout(
          position: position,
          windowPadding: MediaQuery.paddingOf(context),
        ),
        child: capturedThemes.wrap(
          WorkspaceFileKindMenu(
            onSelected: (action) => Navigator.of(context).pop(action),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

class _WorkspaceFileKindMenuLayout extends SingleChildLayoutDelegate {
  const _WorkspaceFileKindMenuLayout({
    required this.position,
    required this.windowPadding,
  });

  final Offset position;
  final EdgeInsets windowPadding;

  static const _screenInset = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).deflate(
      windowPadding + const EdgeInsets.all(_screenInset),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = windowPadding.left + _screenInset;
    final minY = windowPadding.top + _screenInset;
    final maxX =
        size.width - windowPadding.right - _screenInset - childSize.width;
    final maxY =
        size.height - windowPadding.bottom - _screenInset - childSize.height;
    return Offset(
      math.min(position.dx, math.max(minX, maxX)),
      math.min(position.dy, math.max(minY, maxY)),
    );
  }

  @override
  bool shouldRelayout(_WorkspaceFileKindMenuLayout oldDelegate) =>
      position != oldDelegate.position ||
      windowPadding != oldDelegate.windowPadding;
}
