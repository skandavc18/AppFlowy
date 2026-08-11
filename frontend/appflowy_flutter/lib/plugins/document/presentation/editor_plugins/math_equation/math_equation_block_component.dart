import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'math_source_editor.dart';

class MathEquationBlockKeys {
  const MathEquationBlockKeys._();

  static const String type = 'math_equation';

  /// The LaTeX source. Everything the block needs lives here, so an equation
  /// survives a restart, a copy and a page duplication.
  static const String formula = 'formula';

  /// How wide the equation's box is, once somebody has sized it.
  static const String width = 'width';

  /// How tall the box is. Absent means it grows with its content.
  static const String height = 'height';
}

Node mathEquationNode({String formula = ''}) => Node(
      type: MathEquationBlockKeys.type,
      attributes: {MathEquationBlockKeys.formula: formula},
    );

class MathEquationBlockComponentBuilder extends BlockComponentBuilder {
  MathEquationBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MathEquationBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.children.isEmpty &&
      node.attributes[MathEquationBlockKeys.formula] is String;
}

class MathEquationBlockComponentWidget extends BlockComponentStatefulWidget {
  const MathEquationBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MathEquationBlockComponentWidget> createState() =>
      MathEquationBlockComponentWidgetState();
}

class MathEquationBlockComponentWidgetState
    extends State<MathEquationBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const Duration _expand = Duration(milliseconds: 260);

  /// Wide enough for the symbol strip to stay usable, and no wider.
  static const double _minimumWidth = 300;

  /// An equation is a short object; a page-wide box would be mostly margin.
  static const double _defaultWidth = 420;

  static const double _minimumHeight = 110;

  /// Enough for the field, the categories and the symbols to sit together.
  static const double _editingMinimumHeight = 420;

  bool _editing = false;
  bool _hovered = false;
  bool _focused = false;
  bool _menuOpen = false;

  /// What is being typed, before it is worth writing to the document.
  ///
  /// The preview follows this, so a keystroke re-typesets one equation rather
  /// than putting a transaction through the whole page.
  String? _draft;
  Timer? _commit;

  EditorState get _editorState => context.read<EditorState>();

  bool get _editable => _editorState.editable;

  String get formula =>
      node.attributes[MathEquationBlockKeys.formula] as String? ?? '';

  double get _width {
    final stored = node.attributes[MathEquationBlockKeys.width];
    return stored is num ? stored.toDouble() : _defaultWidth;
  }

  double? get _height {
    final stored = node.attributes[MathEquationBlockKeys.height];
    return stored is num ? stored.toDouble() : null;
  }

  /// The height to lay out at, which is not always the stored one: a box
  /// sized around an equation would clip the editor when it opens.
  double? get _layoutHeight {
    final stored = _height;
    if (stored == null || !_editing || !_editable) {
      return stored;
    }
    return math.max(stored, _editingMinimumHeight);
  }

  Future<void> _update(Map<String, Object?> attributes) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(transaction);
  }

  String get _shown => _draft ?? formula;

  bool get _chromeVisible => _hovered || _editing || _menuOpen || _focused;

  @override
  void dispose() {
    _commit?.cancel();
    super.dispose();
  }

  Future<void> _write(String value) {
    if (value == formula || !mounted) {
      return Future<void>.value();
    }
    final transaction = _editorState.transaction
      ..updateNode(node, {MathEquationBlockKeys.formula: value});
    return _editorState.apply(transaction);
  }

  void _onTyped(String value) {
    setState(() => _draft = value);
    _commit?.cancel();
    _commit = Timer(const Duration(milliseconds: 500), () {
      _commit = null;
      unawaited(_write(value));
    });
  }

  void _flush() {
    final draft = _draft;
    _commit?.cancel();
    _commit = null;
    if (draft != null) {
      unawaited(_write(draft));
    }
  }

  /// Opens the editor.
  ///
  /// Kept under this name because the slash menu calls it straight after
  /// inserting the block, so `/math` lands ready to type.
  void showEditingDialog() {
    if (!_editable || !mounted || _editing) {
      return;
    }
    setState(() {
      _editing = true;
      _draft = formula;
    });
  }

  void _closeEditor() {
    if (!_editing) {
      return;
    }
    _flush();
    setState(() {
      _editing = false;
      _draft = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    final latex = _shown;
    final hasFormula = latex.trim().isNotEmpty;
    final height = _layoutHeight;
    final stage = _stage(palette, latex, hasFormula);

    Widget child = AnimatedContainer(
      duration: VisualBlockMetrics.hover,
      curve: VisualBlockMetrics.curve,
      // Once the box has been given a height, anything that does not fit is
      // clipped by the corner rather than painted outside it.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surface(palette),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outline(palette)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Given a height the equation takes whatever the editor leaves, so
          // a taller box gives the mathematics more room rather than the
          // tool. Without one the column is unbounded and cannot flex at all.
          if (height == null) stage else Flexible(child: stage),
          AnimatedSize(
            duration: _expand,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _editing && _editable
                ? _editor(palette)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    child = Semantics(
      container: true,
      label: hasFormula
          ? '${LocaleKeys.diagrams_math_name.tr()}. $latex'
          : LocaleKeys.diagrams_math_name.tr(),
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              _editable &&
              !_editing) {
            showEditingDialog();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onSecondaryTapDown: (details) =>
                unawaited(_openMenu(context, details.globalPosition)),
            child: child,
          ),
        ),
      ),
    );

    // An equation is a small object on the page, not a banner: it takes the
    // width it was given rather than the width of the column.
    child = ResizableMedia(
      width: _width,
      minWidth: _minimumWidth,
      height: _layoutHeight,
      minHeight: _minimumHeight,
      maxHeight: VisualBlockMetrics.maximumEmbedHeight,
      alignment: blockEmbedAlignment(node),
      editable: _editable,
      onResize: (value) => unawaited(
        _update({MathEquationBlockKeys.width: value}),
      ),
      onResizeHeight: (value) => unawaited(
        _update({MathEquationBlockKeys.height: value}),
      ),
      child: child,
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (UniversalPlatform.isMobile) {
      child = MobileBlockActionButtons(
        node: node,
        editorState: _editorState,
        child: child,
      );
    }

    return child;
  }

  /// Almost nothing at rest; a breath of tint under the pointer.
  Color _surface(VisualBlockPalette palette) {
    if (_editing) {
      return palette.hover.withValues(alpha: palette.isDark ? 0.30 : 0.42);
    }
    if (_chromeVisible) {
      return palette.hover.withValues(alpha: palette.isDark ? 0.22 : 0.34);
    }
    return Colors.transparent;
  }

  Color _outline(VisualBlockPalette palette) {
    if (_editing || _focused) {
      return palette.accent.withValues(alpha: 0.26);
    }
    if (_chromeVisible) {
      return palette.border.withValues(alpha: 0.30);
    }
    return Colors.transparent;
  }

  /// The equation, with the block's identity and controls kept in the margin
  /// above it so they never push the mathematics around.
  Widget _stage(VisualBlockPalette palette, String latex, bool hasFormula) {
    final Widget content;
    if (!hasFormula) {
      content = _EmptyInvitation(
        palette: palette,
        onTap: _editable ? showEditingDialog : null,
      );
    } else {
      content = MouseRegion(
        cursor: _editable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: _editable ? showEditingDialog : null,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: MathEquationView(
              latex: latex,
              palette: palette,
              fontSize: 24,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Padding(
          // The top inset is the margin the chrome lives in, so revealing it
          // never moves the equation by a pixel.
          padding: const EdgeInsets.fromLTRB(0, 26, 0, 16),
          child: Align(child: content),
        ),
        Positioned(
          left: 12,
          top: 5,
          child: _identity(palette),
        ),
        Positioned(
          right: 6,
          top: 2,
          child: _actions(palette),
        ),
      ],
    );
  }

  Widget _identity(VisualBlockPalette palette) => AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: VisualBlockMetrics.reveal,
        curve: VisualBlockMetrics.curve,
        child: IgnorePointer(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.functions_rounded, size: 12, color: palette.textMuted),
              const SizedBox(width: 5),
              Text(
                LocaleKeys.diagrams_math_name.tr(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _actions(VisualBlockPalette palette) => AnimatedOpacity(
        opacity: _chromeVisible ? 1 : 0,
        duration: VisualBlockMetrics.reveal,
        curve: VisualBlockMetrics.curve,
        child: IgnorePointer(
          ignoring: !_chromeVisible,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_editable)
                VisualBlockButton(
                  icon: _editing
                      ? Icons.check_rounded
                      : Icons.edit_outlined,
                  tooltip: _editing
                      ? LocaleKeys.button_done.tr()
                      : LocaleKeys.diagrams_math_editEquation.tr(),
                  palette: palette,
                  size: 24,
                  onTap: _editing ? _closeEditor : showEditingDialog,
                ),
              VisualBlockButton(
                icon: Icons.open_in_full_rounded,
                tooltip: LocaleKeys.diagrams_common_fullscreen.tr(),
                palette: palette,
                size: 24,
                onTap: _openFullscreen,
              ),
              Builder(
                builder: (buttonContext) => VisualBlockButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip:
                      LocaleKeys.document_plugins_optionAction_more.tr(),
                  palette: palette,
                  size: 24,
                  selected: _menuOpen,
                  onTap: () {
                    final box =
                        buttonContext.findRenderObject() as RenderBox?;
                    final origin = box == null
                        ? Offset.zero
                        : box.localToGlobal(Offset(0, box.size.height + 4));
                    unawaited(_openMenu(buttonContext, origin));
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _editor(VisualBlockPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ColoredBox(
                color: palette.border.withValues(alpha: 0.22),
                child: const SizedBox(height: 1, width: double.infinity),
              ),
            ),
            MathSourceEditor(
              latex: formula,
              editorState: _editorState,
              onChanged: _onTyped,
              onClose: _closeEditor,
            ),
          ],
        ),
      );

  Future<void> _openMenu(BuildContext context, Offset position) async {
    setState(() => _menuOpen = true);
    await showAppMenu<Object?>(
      context: context,
      entries: _menuEntries(context),
      globalPosition: position,
    );
    if (mounted) {
      setState(() => _menuOpen = false);
    }
  }

  List<AppMenuEntry> _menuEntries(BuildContext menuContext) =>
      visualBlockMenuEntries(
        VisualBlockActions(
          editable: _editable,
          onEdit: showEditingDialog,
          editLabel: LocaleKeys.diagrams_math_editEquation.tr(),
          onFullscreen: _openFullscreen,
          onCopySource: () => unawaited(
            copyVisualBlockText(menuContext, _shown),
          ),
          copySourceLabel: LocaleKeys.diagrams_math_copyLatex.tr(),
          exports: [
            VisualBlockExport(
              label: LocaleKeys.diagrams_math_exportLatex.tr(),
              icon: Icons.description_outlined,
              run: () =>
                  exportVisualBlockText(menuContext, _shown, 'equation.tex'),
            ),
          ],
          onDuplicate: () =>
              unawaited(duplicateVisualBlock(_editorState, node)),
          onDelete: () => unawaited(deleteVisualBlock(_editorState, node)),
        ),
      );

  void _openFullscreen() {
    _flush();
    unawaited(
      showVisualBlockFullscreen<void>(
        context: context,
        icon: Icons.functions_rounded,
        title: LocaleKeys.diagrams_math_name.tr(),
        builder: (dialogContext) => MathWorkspace(
          latex: _shown,
          editable: _editable,
          editorState: _editorState,
          onChanged: (value) {
            if (mounted) {
              setState(() => _draft = value);
            }
            unawaited(_write(value));
          },
        ),
      ),
    );
  }
}

/// The quiet invitation shown while a block has no equation yet.
class _EmptyInvitation extends StatefulWidget {
  const _EmptyInvitation({required this.palette, this.onTap});

  final VisualBlockPalette palette;
  final VoidCallback? onTap;

  @override
  State<_EmptyInvitation> createState() => _EmptyInvitationState();
}

class _EmptyInvitationState extends State<_EmptyInvitation> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Math.tex(
                r'\sum',
                mathStyle: MathStyle.text,
                textStyle: TextStyle(
                  fontSize: 17,
                  color: _hovered ? palette.textSecondary : palette.textMuted,
                ),
                onErrorFallback: (_) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 10),
              Text(
                LocaleKeys.diagrams_math_placeholderTitle.tr(),
                style: TextStyle(
                  fontSize: 13.5,
                  color: _hovered ? palette.textSecondary : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders LaTeX, saying plainly when it cannot be read instead of throwing.
class MathEquationView extends StatelessWidget {
  const MathEquationView({
    super.key,
    required this.latex,
    required this.palette,
    this.fontSize = 20,
    this.mathStyle = MathStyle.display,
  });

  final String latex;
  final VisualBlockPalette palette;
  final double fontSize;
  final MathStyle mathStyle;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      latex,
      mathStyle: mathStyle,
      textStyle: TextStyle(fontSize: fontSize, color: palette.text),
      onErrorFallback: (error) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: _errorInk(palette),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              error.messageWithType,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: _errorInk(palette),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Restrained rather than alarming: an equation half-typed is not a fault.
  Color _errorInk(VisualBlockPalette palette) => Color.alphaBlend(
        (palette.isDark ? const Color(0xFFE58B8B) : const Color(0xFFB4544E))
            .withValues(alpha: 0.75),
        palette.textMuted,
      );
}

/// The fullscreen workspace: the equation at reading size, the source and the
/// symbols under it, and nothing else.
class MathWorkspace extends StatefulWidget {
  const MathWorkspace({
    super.key,
    required this.latex,
    required this.editable,
    required this.onChanged,
    this.editorState,
  });

  final String latex;
  final bool editable;
  final ValueChanged<String> onChanged;
  final EditorState? editorState;

  @override
  State<MathWorkspace> createState() => _MathWorkspaceState();
}

class _MathWorkspaceState extends State<MathWorkspace> {
  final UndoHistoryController _undo = UndoHistoryController();
  late String _latex = widget.latex;

  @override
  void dispose() {
    _undo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: palette.canvas,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: _latex.trim().isEmpty
                    ? Text(
                        LocaleKeys.diagrams_math_placeholderTitle.tr(),
                        style:
                            TextStyle(fontSize: 15, color: palette.textMuted),
                      )
                    : MathEquationView(
                        latex: _latex,
                        palette: palette,
                        fontSize: 42,
                      ),
              ),
            ),
          ),
        ),
        if (widget.editable)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(
                top: BorderSide(color: palette.border.withValues(alpha: 0.3)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MathSourceEditor(
                      latex: widget.latex,
                      editorState: widget.editorState,
                      undoController: _undo,
                      expanded: true,
                      onChanged: (value) {
                        setState(() => _latex = value);
                        widget.onChanged(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _toolbar(palette),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolbar(VisualBlockPalette palette) {
    return ValueListenableBuilder<UndoHistoryValue>(
      valueListenable: _undo,
      builder: (context, value, _) => Row(
        children: [
          VisualBlockButton(
            icon: Icons.undo_rounded,
            tooltip: LocaleKeys.toolbar_undo.tr(),
            palette: palette,
            onTap: value.canUndo ? _undo.undo : null,
          ),
          VisualBlockButton(
            icon: Icons.redo_rounded,
            tooltip: LocaleKeys.toolbar_redo.tr(),
            palette: palette,
            onTap: value.canRedo ? _undo.redo : null,
          ),
          const Spacer(),
          _TextAction(
            label: LocaleKeys.diagrams_math_copyLatex.tr(),
            palette: palette,
            onTap: () => unawaited(copyVisualBlockText(context, _latex)),
          ),
          const SizedBox(width: 8),
          _TextAction(
            label: LocaleKeys.button_done.tr(),
            palette: palette,
            primary: true,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// A word rather than a button: used where a control has to be readable
/// without drawing a box round itself.
class _TextAction extends StatefulWidget {
  const _TextAction({
    required this.label,
    required this.palette,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VisualBlockPalette palette;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final Color fill;
    if (widget.primary) {
      fill = palette.accent.withValues(alpha: _hovered ? 0.20 : 0.12);
    } else {
      fill = _hovered ? palette.hover.withValues(alpha: 0.8) : palette.hoverBase;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: VisualBlockMetrics.hover,
          curve: VisualBlockMetrics.curve,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(999),
          ),
          // Shrink-wrapped rather than aligned: an aligning container fills
          // its constraints and would eat the whole row.
          child: Center(
            widthFactor: 1,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: widget.primary ? palette.accent : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
