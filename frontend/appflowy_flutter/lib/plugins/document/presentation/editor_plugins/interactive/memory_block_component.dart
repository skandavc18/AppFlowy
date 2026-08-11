import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class MemoryBlockKeys {
  const MemoryBlockKeys._();

  static const String type = 'interactive_memory';

  /// The question.
  static const String front = 'front';

  /// The answer.
  static const String back = 'back';
}

Node memoryNode({
  String front = '',
  String back = '',
  InteractiveAccent accent = InteractiveAccent.purple,
}) =>
    Node(
      type: MemoryBlockKeys.type,
      attributes: {
        MemoryBlockKeys.front: front,
        MemoryBlockKeys.back: back,
        InteractiveBlockKeys.accent: accent.name,
        InteractiveBlockKeys.size: InteractiveSize.medium.name,
      },
    );

class MemoryBlockComponentBuilder extends BlockComponentBuilder {
  MemoryBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MemoryBlockComponent(
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

class MemoryBlockComponent extends BlockComponentStatefulWidget {
  const MemoryBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MemoryBlockComponent> createState() => MemoryBlockComponentState();
}

class MemoryBlockComponentState extends State<MemoryBlockComponent>
    with
        BlockComponentConfigurable,
        InteractiveBlockMixin,
        TickerProviderStateMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const double _minimumFaceHeight = 84;

  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool get _showingBack => _flip.value > 0.5;

  String get _front => stringAttribute(MemoryBlockKeys.front);

  String get _back => stringAttribute(MemoryBlockKeys.back);

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void reveal() {
    if (_flip.status == AnimationStatus.forward ||
        _flip.status == AnimationStatus.completed) {
      unawaited(_flip.reverse());
    } else {
      unawaited(_flip.forward());
    }
  }

  /// Puts the card back to its question. Used by the menu and by `/memory`.
  void resetCard() => unawaited(_flip.reverse());

  List<AppMenuEntry> _menu() => interactiveMenuEntries(
        extra: [
          AppMenuItem(
            label: _showingBack
                ? LocaleKeys.interactive_memory_showQuestion.tr()
                : LocaleKeys.interactive_memory_showAnswer.tr(),
            icon: Icons.flip_camera_android_rounded,
            onSelected: reveal,
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_memory_reset.tr(),
            icon: Icons.restart_alt_rounded,
            onSelected: resetCard,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = accent.resolve(palette);

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_memory_name.tr(),
        menuBuilder: _menu,
        child: AnimatedBuilder(
          animation: _flip,
          builder: (context, _) {
            final turn = _flip.value * math.pi;
            final showingBack = _flip.value > 0.5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                // Just enough perspective to read as paper turning over;
                // any more and it reads as a spinning playing card.
                ..setEntry(3, 2, 0.0011)
                ..rotateY(turn),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..rotateY(showingBack ? math.pi : 0),
                child: _buildFace(palette, tone, showingBack),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFace(
    InteractivePalette palette,
    InteractiveTone tone,
    bool showingBack,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: showingBack ? tone.surface : palette.surface,
        borderRadius: BorderRadius.circular(InteractiveMetrics.blockRadius),
        border: Border.all(
          color: showingBack
              ? tone.strong.withValues(alpha: 0.32)
              : palette.border.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.32 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                showingBack
                    ? Icons.lightbulb_rounded
                    : Icons.help_outline_rounded,
                size: 13,
                color: tone.strong,
              ),
              const SizedBox(width: 7),
              InteractiveLabel(
                text: showingBack
                    ? LocaleKeys.interactive_memory_answer.tr()
                    : LocaleKeys.interactive_memory_question.tr(),
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minimumFaceHeight),
            child: InteractiveFocusGuard(
              child: InteractiveEditableText(
                // A key per face so the two texts never share a controller.
                key: ValueKey(showingBack),
                value: showingBack ? _back : _front,
                enabled: editable,
                maxLines: null,
                palette: palette,
                hint: showingBack
                    ? LocaleKeys.interactive_memory_backHint.tr()
                    : LocaleKeys.interactive_memory_frontHint.tr(),
                style: InteractiveType.body(palette)
                    .copyWith(fontSize: 14.5, height: 1.5),
                onChanged: (value) => writeAttributes({
                  showingBack ? MemoryBlockKeys.back : MemoryBlockKeys.front:
                      value,
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            child: InteractiveButton(
              label: showingBack
                  ? LocaleKeys.interactive_memory_showQuestion.tr()
                  : LocaleKeys.interactive_memory_showAnswer.tr(),
              icon: Icons.flip_camera_android_rounded,
              emphasis: showingBack
                  ? InteractiveEmphasis.subtle
                  : InteractiveEmphasis.ghost,
              palette: palette,
              onPressed: reveal,
            ),
          ),
        ],
      ),
    );
  }
}
