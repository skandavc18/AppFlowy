import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class StickyNoteBlockKeys {
  const StickyNoteBlockKeys._();

  static const String type = 'sticky_note';

  /// The note's heading. Empty means the note is body only.
  static const String title = 'title';

  /// The note itself.
  static const String text = 'text';

  /// How tall the body is once somebody has sized it. Absent grows with the
  /// text.
  static const String height = 'height';
}

Node stickyNoteNode({
  String title = '',
  String text = '',
  InteractiveAccent accent = InteractiveAccent.yellow,
  InteractiveSize size = InteractiveSize.compact,
}) =>
    Node(
      type: StickyNoteBlockKeys.type,
      attributes: {
        StickyNoteBlockKeys.title: title,
        StickyNoteBlockKeys.text: text,
        InteractiveBlockKeys.accent: accent.name,
        InteractiveBlockKeys.size: size.name,
      },
    );

class StickyNoteBlockComponentBuilder extends BlockComponentBuilder {
  StickyNoteBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return StickyNoteBlockComponent(
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
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class StickyNoteBlockComponent extends BlockComponentStatefulWidget {
  const StickyNoteBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<StickyNoteBlockComponent> createState() =>
      StickyNoteBlockComponentState();
}

class StickyNoteBlockComponentState extends State<StickyNoteBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  /// A note is never shorter than this, so an empty one still reads as a card
  /// rather than as a line of text.
  static const double _minimumBodyHeight = 76;

  final FocusNode _bodyFocus = FocusNode(debugLabel: 'sticky note body');

  bool _focused = false;

  String get _title => stringAttribute(StickyNoteBlockKeys.title);

  String get _text => stringAttribute(StickyNoteBlockKeys.text);

  double? get _height {
    final stored = node.attributes[StickyNoteBlockKeys.height];
    return stored is num ? stored.toDouble() : null;
  }

  @override
  void dispose() {
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Puts the caret in the note. `/sticky` calls it so a new note lands ready
  /// to be written in.
  void focusBody() => _bodyFocus.requestFocus();

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = accent.resolve(palette);

    final Widget child = InteractiveBlockShell(
      node: node,
      size: blockSize,
      semanticsLabel: LocaleKeys.interactive_stickyNote_name.tr(),
      menuBuilder: () => interactiveMenuEntries(
        extra: [
          AppMenuItem(
            label: LocaleKeys.interactive_stickyNote_focus.tr(),
            icon: Icons.edit_rounded,
            enabled: editable,
            onSelected: focusBody,
          ),
        ],
      ),
      child: _buildNote(palette, tone),
    );

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: child,
    );
  }

  Widget _buildNote(InteractivePalette palette, InteractiveTone tone) {
    final body = InteractiveFocusGuard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: tone.strong),
              const SizedBox(width: 8),
              Expanded(
                child: InteractiveEditableText(
                  value: _title,
                  enabled: editable,
                  hint: LocaleKeys.interactive_stickyNote_titleHint.tr(),
                  style: InteractiveType.strong(palette, size: 13.5),
                  onChanged: (value) =>
                      writeAttributes({StickyNoteBlockKeys.title: value}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: _height ?? _minimumBodyHeight,
              maxHeight: _height ?? double.infinity,
            ),
            child: InteractiveEditableText(
              value: _text,
              focusNode: _bodyFocus,
              enabled: editable,
              maxLines: null,
              hint: LocaleKeys.interactive_stickyNote_bodyHint.tr(),
              style: InteractiveType.body(palette).copyWith(height: 1.5),
              onFocusChanged: (value) => setState(() => _focused = value),
              onChanged: (value) =>
                  writeAttributes({StickyNoteBlockKeys.text: value}),
            ),
          ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: InteractiveMetrics.hover,
      curve: InteractiveMetrics.curve,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(InteractiveMetrics.blockRadius),
        border: Border.all(
          color: _focused
              ? tone.strong.withValues(alpha: 0.45)
              : tone.border.withValues(alpha: 0.8),
          width: _focused ? 1.4 : 1,
        ),
        // Two very soft shadows: a wide ambient one and a tight contact one,
        // so the note sits a little above the page without a drop shadow.
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(alpha: palette.isDark ? 0.32 : 0.055),
            blurRadius: 22,
            offset: const Offset(0, 9),
            spreadRadius: -12,
          ),
          BoxShadow(
            color:
                Colors.black.withValues(alpha: palette.isDark ? 0.20 : 0.035),
            blurRadius: 5,
            offset: const Offset(0, 2),
            spreadRadius: -3,
          ),
        ],
      ),
      child: body,
    );
  }
}
