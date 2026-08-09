import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_palette.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The shape of the suggestion surface.
///
/// It is a floating sheet, not a menu: rounded, softly shadowed, quiet
/// typography and enough air that a correction reads at a glance.
abstract final class SpellPopupMetrics {
  static const double width = 268;
  static const double radius = 14;
  static const double rowHeight = 30;
  static const double rowRadius = 8;
  static const double cardPadding = 6;
  static const double gap = 8;
  static const Duration open = Duration(milliseconds: 150);
  static const Duration close = Duration(milliseconds: 110);
  static const Curve curve = Curves.easeOutCubic;
  static const double maximumHeight = 320;
}

/// Where the flagged words are on the screen, so the sheet can sit beside
/// them rather than on top of them.
Rect? spellIssueRect(Node node, SpellCheckResult issue) {
  final selectable = node.selectable;
  if (selectable == null) {
    return null;
  }
  final rects = selectable.getRectsInSelection(
    Selection(
      start: Position(path: node.path, offset: issue.start),
      end: Position(path: node.path, offset: issue.end),
    ),
    shiftWithBaseOffset: true,
  );
  if (rects.isEmpty) {
    return null;
  }
  var bounds = selectable.transformRectToGlobal(
    rects.first,
    shiftWithBaseOffset: true,
  );
  for (final rect in rects.skip(1)) {
    bounds = bounds.expandToInclude(
      selectable.transformRectToGlobal(rect, shiftWithBaseOffset: true),
    );
  }
  return bounds;
}

/// Whether a sheet is already open, so a second click does not stack one on
/// top of another.
bool get isSpellSuggestionOpen => _entry != null;

OverlayEntry? _entry;

void dismissSpellSuggestions() {
  if (_entry == null) {
    return;
  }
  _entry?.remove();
  _entry = null;
  keepEditorFocusNotifier.decrease();
}

/// Opens the suggestions for [actions], anchored to [anchor] in global
/// coordinates.
void showSpellSuggestions(
  BuildContext context, {
  required SpellCheckActions actions,
  required Rect anchor,
}) {
  dismissSpellSuggestions();
  final overlay = Overlay.of(context, rootOverlay: true);
  // The sheet takes the keyboard for its arrow keys; the page must keep the
  // selection the correction is about.
  keepEditorFocusNotifier.increase();
  final entry = OverlayEntry(
    builder: (_) => _SpellSuggestionLayer(actions: actions, anchor: anchor),
  );
  _entry = entry;
  overlay.insert(entry);
}

class _SpellSuggestionLayer extends StatelessWidget {
  const _SpellSuggestionLayer({required this.actions, required this.anchor});

  final SpellCheckActions actions;
  final Rect anchor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        // Anywhere else is a way out, and the click still reaches the page
        // underneath so the caret goes where it was aimed.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (_) => dismissSpellSuggestions(),
            onSecondaryTapDown: (_) => dismissSpellSuggestions(),
          ),
        ),
        CustomSingleChildLayout(
          delegate: _SpellPopupLayout(anchor: anchor, insets: media.padding),
          child: SpellSuggestionCard(
            actions: actions,
            onDismiss: dismissSpellSuggestions,
          ),
        ),
      ],
    );
  }
}

/// Keeps the sheet on the screen and off the words it is about.
class _SpellPopupLayout extends SingleChildLayoutDelegate {
  const _SpellPopupLayout({required this.anchor, required this.insets});

  final Rect anchor;
  final EdgeInsets insets;

  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          SpellPopupMetrics.width,
          constraints.maxHeight - insets.vertical - _margin * 2,
        ),
      ).tighten(width: SpellPopupMetrics.width);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + SpellPopupMetrics.gap;
    final above = anchor.top - SpellPopupMetrics.gap - childSize.height;
    final fitsBelow = below + childSize.height <= size.height - _margin;
    final top = fitsBelow
        ? below
        : (above >= _margin ? above : size.height - _margin - childSize.height);
    final left = anchor.left.clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(_SpellPopupLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.insets != insets;
}

/// The sheet itself.
class SpellSuggestionCard extends StatefulWidget {
  const SpellSuggestionCard({
    super.key,
    required this.actions,
    required this.onDismiss,
  });

  final SpellCheckActions actions;
  final VoidCallback onDismiss;

  @override
  State<SpellSuggestionCard> createState() => _SpellSuggestionCardState();
}

class _SpellSuggestionCardState extends State<SpellSuggestionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: SpellPopupMetrics.open,
    reverseDuration: SpellPopupMetrics.close,
  )..forward();

  late final List<Suggestion> _suggestions = widget.actions.suggestions();
  late final List<_SpellRow> _rows = _buildRows();

  final FocusNode _focusNode = FocusNode(debugLabel: 'spell suggestions');
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _reveal.dispose();
    super.dispose();
  }

  List<_SpellRow> _buildRows() {
    final actions = widget.actions;
    return [
      for (final suggestion in _suggestions)
        _SpellRow(
          label: suggestion.replacement,
          isSuggestion: true,
          onSelected: () => actions.replaceWith(suggestion.replacement),
        ),
      _SpellRow(
        label: LocaleKeys.document_spellCheck_ignore.tr(),
        icon: Icons.block_rounded,
        onSelected: actions.ignoreOnce,
      ),
      if (!actions.isIgnoredEverywhere)
        _SpellRow(
          label: LocaleKeys.document_spellCheck_ignoreAll.tr(),
          icon: Icons.done_all_rounded,
          onSelected: actions.ignoreEverywhere,
        ),
      if (!actions.isIgnoredOnThisPage)
        _SpellRow(
          label: LocaleKeys.document_spellCheck_ignoreOnPage.tr(),
          icon: Icons.article_outlined,
          onSelected: () => actions.ignoreOnThisPage(),
        ),
      if (actions.canAddToDictionary)
        _SpellRow(
          label: LocaleKeys.document_spellCheck_addToDictionary.tr(),
          icon: Icons.library_add_rounded,
          onSelected: () => actions.addToDictionary(),
        ),
    ];
  }

  void _move(int delta) {
    if (_rows.isEmpty) {
      return;
    }
    final next = (_highlighted + delta + _rows.length) % _rows.length;
    setState(() => _highlighted = next);
  }

  void _activate(int index) {
    if (index < 0 || index >= _rows.length) {
      return;
    }
    widget.onDismiss();
    _rows[index].onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = SpellCheckPalette.of(context);
    final issue = widget.actions.issue;

    return FocusScope(
      // The page keeps its caret; this sheet only wants the arrow keys.
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _reveal,
            curve: SpellPopupMetrics.curve,
          ),
          child: ScaleTransition(
            alignment: Alignment.topLeft,
            scale: Tween<double>(begin: 0.97, end: 1).animate(
              CurvedAnimation(
                parent: _reveal,
                curve: SpellPopupMetrics.curve,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: SpellPopupMetrics.width,
                decoration: BoxDecoration(
                  color: premium.floatingSurface,
                  borderRadius:
                      BorderRadius.circular(SpellPopupMetrics.radius),
                  border: Border.all(
                    color: premium.border.withValues(alpha: 0.5),
                    width: 0.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: premium.shadow.withValues(alpha: 0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                      spreadRadius: -8,
                    ),
                    BoxShadow(
                      color: premium.shadow.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: SpellPopupMetrics.maximumHeight,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(
                      SpellPopupMetrics.cardPadding,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildBody(premium, palette, issue),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    PremiumThemeExtension premium,
    SpellCheckPalette palette,
    SpellCheckResult issue,
  ) {
    final children = <Widget>[
      _Heading(
        label: issue.kind.isSpelling
            ? LocaleKeys.document_spellCheck_spelling.tr()
            : LocaleKeys.document_spellCheck_grammar_title.tr(),
        color: palette.colorFor(issue.kind),
        premium: premium,
      ),
      _Flagged(text: issue.text, premium: premium),
      if (issue.message != null && !issue.kind.isSpelling)
        _Explanation(message: issue.message!.tr(), premium: premium),
    ];

    if (_suggestions.isEmpty) {
      children.add(
        _Explanation(
          message: LocaleKeys.document_spellCheck_noSuggestions.tr(),
          premium: premium,
        ),
      );
    }

    var index = 0;
    var separated = false;
    for (final row in _rows) {
      if (!row.isSuggestion && !separated) {
        separated = true;
        children.add(_Rule(premium: premium));
      }
      final position = index;
      children.add(
        _Row(
          row: row,
          premium: premium,
          accent: palette.colorFor(issue.kind),
          isBest: row.isSuggestion && position == 0,
          isHighlighted: position == _highlighted,
          onHover: () => setState(() => _highlighted = position),
          onPressed: () => _activate(position),
        ),
      );
      index++;
    }
    return children;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _activate(_highlighted);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _SpellRow {
  const _SpellRow({
    required this.label,
    required this.onSelected,
    this.icon,
    this.isSuggestion = false,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
  final bool isSuggestion;
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.label,
    required this.color,
    required this.premium,
  });

  final String label;
  final Color color;
  final PremiumThemeExtension premium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
              color: premium.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Flagged extends StatelessWidget {
  const _Flagged({required this.text, required this.premium});

  final String text;
  final PremiumThemeExtension premium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14.5,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: premium.textPrimary,
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.message, required this.premium});

  final String message;
  final PremiumThemeExtension premium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: premium.textSecondary,
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.premium});

  final PremiumThemeExtension premium;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Container(
        height: 0.7,
        color: premium.border.withValues(alpha: 0.55),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.premium,
    required this.accent,
    required this.isBest,
    required this.isHighlighted,
    required this.onHover,
    required this.onPressed,
  });

  final _SpellRow row;
  final PremiumThemeExtension premium;
  final Color accent;
  final bool isBest;
  final bool isHighlighted;
  final VoidCallback onHover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = row.isSuggestion ? premium.textPrimary : premium.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: SpellPopupMetrics.curve,
          height: SpellPopupMetrics.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // Fading from a fully transparent copy of the wash keeps the tween
            // in one hue; `Colors.transparent` would pass through grey.
            color: isHighlighted
                ? premium.hover
                : premium.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(SpellPopupMetrics.rowRadius),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: row.isSuggestion
                    ? (isBest
                        ? Icon(Icons.check_rounded, size: 14, color: accent)
                        : null)
                    : Icon(row.icon, size: 15, color: premium.textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.1,
                    fontWeight: isBest ? FontWeight.w600 : FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
