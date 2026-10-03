import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_markup.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/palette_ai.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A conversation with the assistant, held inside the palette.
///
/// The palette's own search box is where questions are typed; this shows the
/// conversation, the pages it is drawing on, and what can be done with an
/// answer once it has arrived.
class PaletteAIPanel extends StatefulWidget {
  const PaletteAIPanel({
    super.key,
    required this.conversation,
    required this.sources,
    required this.modelLabel,
    required this.onAsk,
    required this.onRemoveSource,
    required this.onOpenSource,
    required this.onSetUp,
    required this.onPickModel,
    required this.onNewConversation,
    required this.onSaveAsPage,
    this.onInsert,
    this.insertTargetName = '',
    this.onContinueInChat,
    this.hasCurrentPage = false,
  });

  final PaletteAIConversation conversation;

  /// The pages the next question will be asked with.
  final List<PaletteAISource> sources;
  final String modelLabel;
  final ValueChanged<String> onAsk;
  final ValueChanged<PaletteAISource> onRemoveSource;
  final ValueChanged<String> onOpenSource;
  final VoidCallback onSetUp;
  final VoidCallback onPickModel;

  /// Forgets the conversation so the next question starts afresh.
  final VoidCallback onNewConversation;
  final Future<void> Function(PaletteAITurn turn) onSaveAsPage;

  /// Adds an answer to the page open behind the palette. Null when no page
  /// that can be written to is open.
  final Future<void> Function(String markdown)? onInsert;
  final String insertTargetName;

  /// Hands the conversation to a chat page. Null when the model answering
  /// cannot carry it on there.
  final VoidCallback? onContinueInChat;

  /// Whether a page is open behind the palette, for the suggestions offered
  /// before anything is asked.
  final bool hasCurrentPage;

  @override
  State<PaletteAIPanel> createState() => _PaletteAIPanelState();
}

class _PaletteAIPanelState extends State<PaletteAIPanel> {
  final _scroll = ScrollController();
  int _seenTurns = 0;

  @override
  void initState() {
    super.initState();
    widget.conversation.addListener(_changed);
    _seenTurns = widget.conversation.turns.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  @override
  void didUpdateWidget(PaletteAIPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation != widget.conversation) {
      oldWidget.conversation.removeListener(_changed);
      widget.conversation.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.conversation.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Follow the answer down as it arrives, unless somebody scrolled up to
    // read something earlier; a new question always comes into view.
    final turns = widget.conversation.turns.length;
    final asked = turns > _seenTurns;
    _seenTurns = turns;
    final follow = asked ||
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.position.pixels < 64;
    setState(() {});
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  void _toBottom() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final turns = conversation.turns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          modelLabel: widget.modelLabel,
          busy: conversation.isBusy,
          canClear: turns.isNotEmpty,
          onPickModel: widget.onPickModel,
          onStop: () => unawaited(conversation.stop()),
          onClear: widget.onNewConversation,
        ),
        if (widget.sources.isNotEmpty)
          _SourceRow(
            sources: widget.sources,
            onRemove: widget.onRemoveSource,
            onOpen: widget.onOpenSource,
          ),
        Expanded(
          child: turns.isEmpty
              ? _EmptyConversation(
                  hasCurrentPage: widget.hasCurrentPage,
                  onAsk: widget.onAsk,
                )
              : FlowyScrollbar(
                  controller: _scroll,
                  thumbVisibility: false,
                  child: ListView.builder(
                    key: const ValueKey('command-palette-ai-conversation'),
                    controller: _scroll,
                    padding: const EdgeInsets.only(right: 8, bottom: 16),
                    itemCount: turns.length,
                    itemBuilder: (context, index) {
                      final turn = turns[index];
                      final last = index == turns.length - 1;
                      return _TurnView(
                        key: ValueKey('command-palette-ai-turn-${turn.id}'),
                        turn: turn,
                        isLast: last,
                        onRetry: () => unawaited(conversation.retry()),
                        onSetUp: widget.onSetUp,
                        onOpenSource: widget.onOpenSource,
                        onInsert: widget.onInsert,
                        insertTargetName: widget.insertTargetName,
                        onSaveAsPage: widget.onSaveAsPage,
                        onContinueInChat: last ? widget.onContinueInChat : null,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.modelLabel,
    required this.busy,
    required this.canClear,
    required this.onPickModel,
    required this.onStop,
    required this.onClear,
  });

  final String modelLabel;
  final bool busy;
  final bool canClear;
  final VoidCallback onPickModel;
  final VoidCallback onStop;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.s),
      child: Row(
        children: [
          // Takes what the trailing buttons leave, so a long model name
          // shortens instead of pushing them out of a narrow palette.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ExcludeFocus(
                child: TextButton.icon(
                  key: const ValueKey('command-palette-ai-model'),
                  onPressed: onPickModel,
                  style: WorkspaceChrome.controlStyle(context).copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  icon: WorkspaceGlyph(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: palette.accent,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            modelLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyle.caption.enhanced(
                              color: theme.textColorScheme.secondary,
                            ),
                          ),
                        ),
                      ),
                      WorkspaceGlyph(
                        Icons.arrow_drop_down_rounded,
                        size: 16,
                        color: palette.secondaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            _HeaderButton(
              key: const ValueKey('command-palette-ai-stop'),
              icon: Icons.stop_rounded,
              label: LocaleKeys.commandPalette_ai_stop.tr(),
              onTap: onStop,
            ),
          if (canClear)
            _HeaderButton(
              key: const ValueKey('command-palette-ai-new'),
              icon: Icons.add_rounded,
              label: LocaleKeys.commandPalette_ai_newConversation.tr(),
              onTap: onClear,
            ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return ExcludeFocus(
      child: TextButton.icon(
        onPressed: onTap,
        style: WorkspaceChrome.controlStyle(context).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
        icon: WorkspaceGlyph(icon, size: 15, color: palette.secondaryText),
        label: Text(
          label,
          style: theme.textStyle.caption
              .standard(color: theme.textColorScheme.secondary),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.sources,
    required this.onRemove,
    required this.onOpen,
  });

  final List<PaletteAISource> sources;
  final ValueChanged<PaletteAISource> onRemove;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: theme.spacing.m),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            LocaleKeys.commandPalette_ai_using.tr(),
            style: theme.textStyle.caption
                .standard(color: theme.textColorScheme.tertiary),
          ),
          for (final source in sources)
            PaletteAISourceChip(
              key: ValueKey('command-palette-ai-source-${source.id}'),
              source: source,
              onTap: () => onOpen(source.id),
              onRemove: () => onRemove(source),
            ),
        ],
      ),
    );
  }
}

/// A page the assistant reads from, as a small chip.
class PaletteAISourceChip extends StatelessWidget {
  const PaletteAISourceChip({
    super.key,
    required this.source,
    required this.onTap,
    this.onRemove,
  });

  final PaletteAISource source;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    final title = source.title.trim().isEmpty
        ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
        : source.title;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.secondarySurface,
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
            hoverColor: WorkspaceChrome.hoverColor(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WorkspaceGlyph(
                    source.isCurrentPage
                        ? Icons.article_rounded
                        : Icons.description_outlined,
                    size: 13,
                    color: palette.secondaryText,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      source.isCurrentPage
                          ? LocaleKeys.commandPalette_ai_currentPage
                              .tr(args: [title])
                          : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyle.caption
                          .standard(color: theme.textColorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onRemove != null)
            ExcludeFocus(
              child: InkWell(
                onTap: onRemove,
                borderRadius:
                    BorderRadius.circular(WorkspaceTokens.controlRadius),
                hoverColor: WorkspaceChrome.hoverColor(context),
                child: Tooltip(
                  message: LocaleKeys.commandPalette_ai_removeSource.tr(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 6, 4),
                    child: WorkspaceGlyph(
                      Icons.close_rounded,
                      size: 12,
                      color: palette.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.hasCurrentPage,
    required this.onAsk,
  });

  final bool hasCurrentPage;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    final suggestions = [
      if (hasCurrentPage) ...[
        (
          Icons.short_text_rounded,
          LocaleKeys.commandPalette_ai_suggestionSummarize.tr(),
        ),
        (
          Icons.checklist_rounded,
          LocaleKeys.commandPalette_ai_suggestionActionItems.tr(),
        ),
        (
          Icons.school_rounded,
          LocaleKeys.commandPalette_ai_suggestionExplain.tr(),
        ),
      ] else ...[
        (
          Icons.lightbulb_outline_rounded,
          LocaleKeys.commandPalette_ai_suggestionBrainstorm.tr(),
        ),
        (
          Icons.event_note_rounded,
          LocaleKeys.commandPalette_ai_suggestionPlan.tr(),
        ),
      ],
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WorkspaceTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: WorkspaceGlyph(
                  Icons.auto_awesome_rounded,
                  size: 22,
                  color: palette.accent,
                ),
              ),
            ),
            const VSpace(WorkspaceTokens.space4),
            Text(
              LocaleKeys.commandPalette_ai_emptyTitle.tr(),
              textAlign: TextAlign.center,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.cardTitle,
              ),
            ),
            const VSpace(WorkspaceTokens.space2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                LocaleKeys.commandPalette_ai_emptyHint.tr(),
                textAlign: TextAlign.center,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ),
              ),
            ),
            const VSpace(WorkspaceTokens.space4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (icon, text) in suggestions)
                  ActionChip(
                    avatar: WorkspaceGlyph(
                      icon,
                      size: 15,
                      color: palette.accent,
                    ),
                    label: Text(
                      text,
                      style: theme.textStyle.caption
                          .standard(color: theme.textColorScheme.primary),
                    ),
                    backgroundColor: palette.secondarySurface,
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(WorkspaceTokens.controlRadius),
                    ),
                    onPressed: () => onAsk(text),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({
    super.key,
    required this.turn,
    required this.isLast,
    required this.onRetry,
    required this.onSetUp,
    required this.onOpenSource,
    required this.onSaveAsPage,
    required this.insertTargetName,
    this.onInsert,
    this.onContinueInChat,
  });

  final PaletteAITurn turn;
  final bool isLast;
  final VoidCallback onRetry;
  final VoidCallback onSetUp;
  final ValueChanged<String> onOpenSource;
  final Future<void> Function(PaletteAITurn turn) onSaveAsPage;
  final Future<void> Function(String markdown)? onInsert;
  final String insertTargetName;
  final VoidCallback? onContinueInChat;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    final failure = turn.failure;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.secondarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  turn.question,
                  style: theme.textStyle.body
                      .standard(color: theme.textColorScheme.primary),
                ),
              ),
            ),
          ),
          const VSpace(10),
          Row(
            children: [
              WorkspaceGlyph(
                Icons.auto_awesome_rounded,
                size: 14,
                color: palette.accent,
              ),
              const HSpace(6),
              Flexible(
                child: Text(
                  turn.engineLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle.caption
                      .standard(color: theme.textColorScheme.tertiary),
                ),
              ),
              if (turn.status == PaletteAITurnStatus.stopped) ...[
                const HSpace(6),
                Text(
                  '· ${LocaleKeys.commandPalette_ai_stopped.tr()}',
                  style: theme.textStyle.caption
                      .standard(color: theme.textColorScheme.tertiary),
                ),
              ],
            ],
          ),
          const VSpace(6),
          if (turn.hasAnswer)
            Semantics(
              liveRegion: turn.isActive,
              child: NotebookMarkup(
                key: const ValueKey('command-palette-ai-answer'),
                source: turn.answer,
                palette: CodeBlockPalette.resolve(context),
              ),
            )
          else if (turn.isActive)
            const _Thinking(),
          for (final note in turn.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note,
                style: theme.textStyle.caption
                    .standard(color: theme.textColorScheme.tertiary)
                    .copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          if (failure != null)
            _FailureView(
              failure: failure,
              onRetry: onRetry,
              onSetUp: onSetUp,
            ),
          if (turn.sources.isNotEmpty && !turn.isActive) ...[
            const VSpace(8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final source in turn.sources)
                  PaletteAISourceChip(
                    source: source,
                    onTap: () => onOpenSource(source.id),
                  ),
              ],
            ),
          ],
          if (!turn.isActive && turn.hasAnswer) ...[
            const VSpace(8),
            _AnswerActions(
              turn: turn,
              onInsert: onInsert,
              insertTargetName: insertTargetName,
              onSaveAsPage: onSaveAsPage,
              onRetry: isLast ? onRetry : null,
              onContinueInChat: onContinueInChat,
            ),
          ],
        ],
      ),
    );
  }
}

class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// How lit [dot] is now: each one swells in turn, then rests.
  double _pulse(int dot) {
    final phase = (_controller.value * 3 - dot) % 3;
    if (phase >= 1) return 0;
    return (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return Semantics(
      liveRegion: true,
      label: LocaleKeys.commandPalette_ai_thinking.tr(),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var dot = 0; dot < 3; dot++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent
                          .withValues(alpha: 0.25 + 0.6 * _pulse(dot)),
                    ),
                  ),
              ],
            ),
          ),
          const HSpace(6),
          Text(
            LocaleKeys.commandPalette_ai_thinking.tr(),
            style: theme.textStyle.caption
                .standard(color: theme.textColorScheme.tertiary),
          ),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.failure,
    required this.onRetry,
    required this.onSetUp,
  });

  final PaletteAIFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return Container(
      key: const ValueKey('command-palette-ai-failure'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.destructive.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        border: Border.all(color: palette.destructive.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WorkspaceGlyph(
                Icons.error_outline_rounded,
                size: 16,
                color: palette.destructive,
                role: WorkspaceGlyphRole.preserveInk,
              ),
              const HSpace(8),
              Expanded(
                child: SelectableText(
                  failure.message,
                  style: theme.textStyle.caption
                      .standard(color: theme.textColorScheme.primary),
                ),
              ),
            ],
          ),
          const VSpace(8),
          Wrap(
            spacing: 6,
            children: [
              _ActionButton(
                icon: Icons.refresh_rounded,
                label: LocaleKeys.commandPalette_ai_retry.tr(),
                onTap: onRetry,
              ),
              if (failure.needsSetup)
                _ActionButton(
                  key: const ValueKey('command-palette-ai-setup'),
                  icon: Icons.settings_rounded,
                  label: LocaleKeys.commandPalette_ai_setup.tr(),
                  onTap: onSetUp,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerActions extends StatefulWidget {
  const _AnswerActions({
    required this.turn,
    required this.onSaveAsPage,
    required this.insertTargetName,
    this.onInsert,
    this.onRetry,
    this.onContinueInChat,
  });

  final PaletteAITurn turn;
  final Future<void> Function(PaletteAITurn turn) onSaveAsPage;
  final Future<void> Function(String markdown)? onInsert;
  final String insertTargetName;
  final VoidCallback? onRetry;
  final VoidCallback? onContinueInChat;

  @override
  State<_AnswerActions> createState() => _AnswerActionsState();
}

class _AnswerActionsState extends State<_AnswerActions> {
  bool _copied = false;
  bool _working = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.turn.answer.trim()));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _busy(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insert = widget.onInsert;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _ActionButton(
          key: const ValueKey('command-palette-ai-copy'),
          icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
          label: _copied
              ? LocaleKeys.commandPalette_ai_copied.tr()
              : LocaleKeys.commandPalette_ai_copy.tr(),
          onTap: _copy,
        ),
        if (insert != null)
          _ActionButton(
            key: const ValueKey('command-palette-ai-insert'),
            icon: Icons.playlist_add_rounded,
            label: LocaleKeys.commandPalette_ai_insert.tr(),
            tooltip: widget.insertTargetName,
            onTap: _working
                ? null
                : () => _busy(() => insert(widget.turn.answer.trim())),
          ),
        _ActionButton(
          key: const ValueKey('command-palette-ai-save'),
          icon: Icons.note_add_rounded,
          label: LocaleKeys.commandPalette_ai_savePage.tr(),
          onTap: _working
              ? null
              : () => _busy(() => widget.onSaveAsPage(widget.turn)),
        ),
        if (widget.onRetry != null)
          _ActionButton(
            key: const ValueKey('command-palette-ai-retry'),
            icon: Icons.refresh_rounded,
            label: LocaleKeys.commandPalette_ai_retry.tr(),
            onTap: widget.onRetry,
          ),
        if (widget.onContinueInChat != null)
          _ActionButton(
            key: const ValueKey('command-palette-ai-continue'),
            icon: Icons.forum_rounded,
            label: LocaleKeys.commandPalette_ai_continueInChat.tr(),
            onTap: widget.onContinueInChat,
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip = '',
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    final button = TextButton.icon(
      onPressed: onTap,
      style: WorkspaceChrome.controlStyle(context).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      icon: WorkspaceGlyph(icon, size: 14, color: palette.secondaryText),
      label: Text(
        label,
        style: theme.textStyle.caption
            .standard(color: theme.textColorScheme.secondary),
      ),
    );
    return tooltip.isEmpty ? button : Tooltip(message: tooltip, child: button);
  }
}
