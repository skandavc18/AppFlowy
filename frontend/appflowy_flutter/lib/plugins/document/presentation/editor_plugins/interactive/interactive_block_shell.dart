import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'interactive_style.dart';

/// Attribute names every interactive block shares.
///
/// Keeping them in one place is what lets the shell offer size, colour,
/// duplicate and delete without each block restating them.
abstract final class InteractiveBlockKeys {
  /// `compact` | `medium` | `wide`.
  static const String size = 'block_size';

  /// One of [InteractiveAccent].
  static const String accent = 'accent';

  /// The caption printed above the control.
  static const String label = 'label';
}

/// Everything an interactive block's state needs to be one of the family.
///
/// It supplies the editor plumbing (reading and writing attributes without a
/// transaction per keystroke), the shared size and colour choices, and the
/// rows those choices contribute to the one context menu.
mixin InteractiveBlockMixin<T extends StatefulWidget> on State<T> {
  Node get node;

  EditorState get editorState => context.read<EditorState>();

  bool get editable => editorState.editable;

  /// A write that is in flight, so a rebuild carrying the previous attributes
  /// does not put the old value back.
  bool _writing = false;

  bool get isWriting => _writing;

  Object? attribute(String key) => node.attributes[key];

  String stringAttribute(String key, {String fallback = ''}) {
    final value = node.attributes[key];
    return value is String ? value : fallback;
  }

  double doubleAttribute(String key, {required double fallback}) {
    final value = node.attributes[key];
    return value is num ? value.toDouble() : fallback;
  }

  bool boolAttribute(String key, {bool fallback = false}) {
    final value = node.attributes[key];
    return value is bool ? value : fallback;
  }

  InteractiveSize get blockSize =>
      InteractiveSize.fromValue(node.attributes[InteractiveBlockKeys.size]);

  InteractiveAccent get accent =>
      InteractiveAccent.fromValue(node.attributes[InteractiveBlockKeys.accent]);

  String get blockLabel => stringAttribute(InteractiveBlockKeys.label);

  /// Merge [attributes] into the node.
  ///
  /// Passing a null value removes the key, which is how `composeAttributes`
  /// already behaves.
  Future<void> writeAttributes(Map<String, Object?> attributes) async {
    if (!mounted || !editable) {
      return;
    }
    _writing = true;
    try {
      final transaction = editorState.transaction
        ..updateNode(node, {...node.attributes, ...attributes});
      await editorState.apply(transaction);
    } finally {
      _writing = false;
    }
  }

  Future<void> duplicateBlock() async {
    final transaction = editorState.transaction
      ..insertNode(node.path.next, node.deepCopy());
    await editorState.apply(transaction);
  }

  Future<void> deleteBlock() async {
    final transaction = editorState.transaction..deleteNode(node);
    await editorState.apply(transaction);
  }

  /// The size and colour submenus, plus duplicate and delete.
  ///
  /// [extra] rows are the ones only this block has; they come first so the
  /// block's own actions are not buried under the shared ones.
  List<AppMenuEntry> interactiveMenuEntries({
    List<AppMenuEntry> extra = const <AppMenuEntry>[],
    bool showSize = true,
    bool showAccent = true,
    List<InteractiveAccent> accents = InteractiveAccent.values,
  }) {
    final entries = <AppMenuEntry>[
      ...extra,
      if (extra.isNotEmpty) const AppMenuSeparator(),
      if (showSize)
        AppMenuItem(
          label: LocaleKeys.interactive_menu_size.tr(),
          icon: Icons.straighten_rounded,
          submenu: [
            for (final size in InteractiveSize.values)
              AppMenuItem(
                label: interactiveSizeLabel(size),
                icon: switch (size) {
                  InteractiveSize.compact => Icons.crop_square_rounded,
                  InteractiveSize.medium => Icons.crop_7_5_rounded,
                  InteractiveSize.wide => Icons.crop_16_9_rounded,
                },
                selected: size == blockSize,
                enabled: editable,
                onSelected: () => unawaited(
                  writeAttributes({InteractiveBlockKeys.size: size.name}),
                ),
              ),
          ],
        ),
      if (showAccent)
        AppMenuItem(
          label: LocaleKeys.interactive_menu_colour.tr(),
          icon: Icons.palette_rounded,
          submenu: [
            for (final value in accents)
              AppMenuItem(
                label: interactiveAccentLabel(value),
                iconWidget: InteractiveAccentDot(accent: value),
                selected: value == accent,
                enabled: editable,
                onSelected: () => unawaited(
                  writeAttributes({InteractiveBlockKeys.accent: value.name}),
                ),
              ),
          ],
        ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.button_duplicate.tr(),
        icon: Icons.control_point_duplicate_rounded,
        enabled: editable,
        onSelected: () => unawaited(duplicateBlock()),
      ),
      AppMenuItem(
        label: LocaleKeys.button_delete.tr(),
        icon: Icons.delete_outline_rounded,
        destructive: true,
        enabled: editable,
        onSelected: () => unawaited(deleteBlock()),
      ),
    ];
    return normalizeAppMenuEntries(entries);
  }
}

String interactiveSizeLabel(InteractiveSize size) => switch (size) {
      InteractiveSize.compact => LocaleKeys.interactive_size_compact.tr(),
      InteractiveSize.medium => LocaleKeys.interactive_size_medium.tr(),
      InteractiveSize.wide => LocaleKeys.interactive_size_wide.tr(),
    };

String interactiveAccentLabel(InteractiveAccent accent) => switch (accent) {
      InteractiveAccent.paper => LocaleKeys.interactive_accent_paper.tr(),
      InteractiveAccent.neutral => LocaleKeys.interactive_accent_neutral.tr(),
      InteractiveAccent.yellow => LocaleKeys.interactive_accent_yellow.tr(),
      InteractiveAccent.blue => LocaleKeys.interactive_accent_blue.tr(),
      InteractiveAccent.green => LocaleKeys.interactive_accent_green.tr(),
      InteractiveAccent.pink => LocaleKeys.interactive_accent_pink.tr(),
      InteractiveAccent.purple => LocaleKeys.interactive_accent_purple.tr(),
      InteractiveAccent.orange => LocaleKeys.interactive_accent_orange.tr(),
      InteractiveAccent.red => LocaleKeys.interactive_accent_red.tr(),
    };

String interactiveControlSizeLabel(InteractiveControlSize size) =>
    switch (size) {
      InteractiveControlSize.small => LocaleKeys.interactive_size_small.tr(),
      InteractiveControlSize.medium => LocaleKeys.interactive_size_medium.tr(),
      InteractiveControlSize.large => LocaleKeys.interactive_size_large.tr(),
    };

String interactiveShapeLabel(InteractiveShape shape) => switch (shape) {
      InteractiveShape.rounded => LocaleKeys.interactive_shape_rounded.tr(),
      InteractiveShape.pill => LocaleKeys.interactive_shape_pill.tr(),
      InteractiveShape.square => LocaleKeys.interactive_shape_square.tr(),
    };

/// The swatch a colour row shows instead of an icon.
class InteractiveAccentDot extends StatelessWidget {
  const InteractiveAccentDot({super.key, required this.accent});

  final InteractiveAccent accent;

  @override
  Widget build(BuildContext context) {
    final tone = accent.resolve(interactivePaletteOf(context));
    return Center(
      widthFactor: 1,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: tone.surface,
          shape: BoxShape.circle,
          border: Border.all(color: tone.strong.withValues(alpha: 0.7), width: 1.4),
        ),
      ),
    );
  }
}

/// Where the hover-revealed controls sit.
enum InteractiveControlsPlacement {
  /// Over the block's own top-right corner. Right for a block whose corner is
  /// empty — a note, a progress bar, a card.
  inside,

  /// Just outside the right edge, for a block that already has a control
  /// there. A counter's `+` would otherwise be half covered.
  outside,
}

/// The frame every interactive block is laid out in.
///
/// It contributes no chrome of its own: the block paints its own surface, and
/// the shell only decides how wide it sits, reveals the controls under the
/// pointer and carries the one context menu. Revealing the controls never
/// moves the content — they float above the top-right corner.
class InteractiveBlockShell extends StatefulWidget {
  const InteractiveBlockShell({
    super.key,
    required this.node,
    required this.child,
    required this.menuBuilder,
    this.size = InteractiveSize.medium,
    this.controls = const <Widget>[],
    this.semanticsLabel,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.controlsOffset = const Offset(-4, 4),
    this.placement = InteractiveControlsPlacement.inside,
  });

  final Node node;
  final Widget child;

  /// The rows of the shared three-dot menu.
  final List<AppMenuEntry> Function() menuBuilder;

  final InteractiveSize size;

  /// Small controls shown before the three-dot button; they fade in with the
  /// pointer rather than living on the page.
  final List<Widget> controls;

  final String? semanticsLabel;
  final EdgeInsets padding;
  final Offset controlsOffset;
  final InteractiveControlsPlacement placement;

  @override
  State<InteractiveBlockShell> createState() => _InteractiveBlockShellState();
}

class _InteractiveBlockShellState extends State<InteractiveBlockShell> {
  /// How far outside the block the cluster floats when it cannot sit on top
  /// of it: its own width plus a little air.
  static const double _clusterGutter = 38;

  bool _hovered = false;
  bool _menuOpen = false;

  bool get _controlsVisible => _hovered || _menuOpen;

  Future<void> _openMenu(Offset position) async {
    setState(() => _menuOpen = true);
    await showAppMenu<Object?>(
      context: context,
      entries: widget.menuBuilder(),
      globalPosition: position,
    );
    if (mounted) {
      setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final width = widget.size.maxWidth;
    final outside = widget.placement == InteractiveControlsPlacement.outside;

    Widget body = Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          top: outside ? 0 : widget.controlsOffset.dy,
          bottom: outside ? 0 : null,
          right: outside ? -_clusterGutter : widget.controlsOffset.dx,
          child: Align(
            alignment: Alignment.topRight,
            child: AnimatedOpacity(
              duration: InteractiveMetrics.reveal,
              curve: InteractiveMetrics.curve,
              opacity: _controlsVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _ControlCluster(
                  palette: palette,
                  children: [
                    ...widget.controls,
                    Builder(
                      builder: (context) => InteractiveIconButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: LocaleKeys
                            .document_plugins_optionAction_more
                            .tr(),
                        palette: palette,
                        selected: _menuOpen,
                        onPressed: () {
                          final box =
                              context.findRenderObject() as RenderBox?;
                          final origin = box == null
                              ? Offset.zero
                              : box.localToGlobal(
                                  Offset(0, box.size.height + 4),
                                );
                          unawaited(_openMenu(origin));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (width.isFinite) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: body,
      );
    }

    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: blockEmbedAlignment(widget.node),
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onSecondaryTapDown: (details) =>
                unawaited(_openMenu(details.globalPosition)),
            child: Semantics(
              container: true,
              label: widget.semanticsLabel,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlCluster extends StatelessWidget {
  const _ControlCluster({required this.palette, required this.children});

  final InteractivePalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.raised.withValues(alpha: palette.isDark ? 0.92 : 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.34 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Keeps the editor's own key handling away from an embedded field.
///
/// appflowy_editor's keyboard service is an ancestor of anything a block
/// renders, so without this Backspace inside a text field deletes the whole
/// block instead of a character.
class InteractiveFocusGuard extends StatelessWidget {
  const InteractiveFocusGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          context.read<EditorState>().selection = null;
        }
      },
      child: child,
    );
  }
}

/// The block-level chrome every interactive block ends its build with: the
/// configured padding, the `+`/`::` handles and, on a phone, the action bar.
Widget decorateInteractiveBlock({
  required BlockComponentStatefulWidget widget,
  required EditorState editorState,
  required EdgeInsets padding,
  required Widget child,
}) {
  Widget result = Padding(padding: padding, child: child);

  if (widget.showActions && widget.actionBuilder != null) {
    result = BlockComponentActionWrapper(
      node: widget.node,
      actionBuilder: widget.actionBuilder!,
      actionTrailingBuilder: widget.actionTrailingBuilder,
      child: result,
    );
  }

  if (UniversalPlatform.isMobile) {
    result = MobileBlockActionButtons(
      node: widget.node,
      editorState: editorState,
      child: result,
    );
  }

  return result;
}
