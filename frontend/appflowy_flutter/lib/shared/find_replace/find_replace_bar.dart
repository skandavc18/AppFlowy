import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'text_find.dart';

/// The colours the find bar paints itself with.
///
/// Resolved here rather than borrowed from a feature palette so the bar can be
/// dropped into a PDF, a code file or a preview without dragging that
/// surface's styling along with it.
@immutable
class FindBarPalette {
  const FindBarPalette({
    required this.surface,
    required this.field,
    required this.hover,
    required this.selected,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.danger,
    required this.shadow,
  });

  factory FindBarPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final scheme = theme.colorScheme;
    final usePaper =
        PaperTheme.isEnabled(context) && theme.brightness == Brightness.light;
    final surface = usePaper
        ? PaperTheme.popupBackground
        : premium?.floatingSurface ?? scheme.surfaceContainerHigh;
    return FindBarPalette(
      surface: surface,
      field: usePaper
          ? PaperTheme.controlBackground
          : premium?.mutedSurface ?? scheme.surfaceContainerHighest,
      hover: WorkspaceChrome.hoverColor(context),
      selected: usePaper
          ? PaperTheme.controlSelected
          : premium?.selected ??
              Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.16),
                surface,
              ),
      border: usePaper
          ? PaperTheme.strongBorder
          : premium?.border ?? scheme.outlineVariant.withValues(alpha: 0.5),
      textPrimary: usePaper
          ? PaperTheme.textPrimary
          : premium?.textPrimary ?? scheme.onSurface,
      textSecondary: usePaper
          ? PaperTheme.textSecondary
          : premium?.textSecondary ?? scheme.onSurfaceVariant,
      accent: usePaper ? PaperTheme.accent : premium?.accent ?? scheme.primary,
      danger: scheme.error,
      shadow: usePaper
          ? PaperTheme.shadow
          : premium?.shadow ?? Colors.black.withValues(alpha: 0.16),
    );
  }

  final Color surface;
  final Color field;
  final Color hover;
  final Color selected;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color danger;
  final Color shadow;
}

/// Fixed geometry, so every surface's find bar is the same size.
abstract final class FindBarMetrics {
  static const rowHeight = 32.0;
  static const maxWidth = 420.0;
  static const cardRadius = 12.0;
  static const fieldRadius = 7.0;
  static const controlSize = 26.0;
  static const controlRadius = 8.0;
  static const iconSize = 16.0;
  static const fieldWidth = 190.0;
  static const gap = 4.0;
}

/// A find, and optionally replace, bar in the shape people already know from
/// their code editor.
///
/// The widget owns none of the searching: a host hands it the counts and gets
/// told when to move, replace or change an option. That is what lets one bar
/// serve a document, a PDF, a source file and a rendered preview.
class FindReplaceBar extends StatelessWidget {
  const FindReplaceBar({
    super.key,
    required this.findController,
    required this.findFocusNode,
    required this.options,
    required this.onOptionsChanged,
    required this.matchCount,
    required this.currentMatch,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
    this.replaceController,
    this.replaceFocusNode,
    this.showReplace = false,
    this.onToggleReplace,
    this.onReplace,
    this.onReplaceAll,
    this.onSubmitted,
    this.queryInvalid = false,
    this.busy = false,
    this.hintText,
    this.supportsWholeWord = true,
    this.autofocus = true,
    this.onTapOutside,
    this.dismissOnTapOutside = true,
  });

  final TextEditingController findController;
  final FocusNode findFocusNode;
  final FindOptions options;
  final ValueChanged<FindOptions> onOptionsChanged;

  /// How many matches the host found, and which one it is showing (1 based).
  final int matchCount;
  final int currentMatch;

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  /// Supplying a replace controller is what makes the surface replaceable; a
  /// read-only preview simply leaves it out.
  final TextEditingController? replaceController;
  final FocusNode? replaceFocusNode;
  final bool showReplace;
  final VoidCallback? onToggleReplace;
  final VoidCallback? onReplace;
  final VoidCallback? onReplaceAll;
  final VoidCallback? onSubmitted;

  /// Set while the person is midway through typing a regular expression that
  /// does not compile yet.
  final bool queryInvalid;
  final bool busy;
  final String? hintText;
  final bool supportsWholeWord;
  final bool autofocus;

  /// Unlike the close button, outside dismissal must not restore old focus:
  /// the pointer is already activating another field, cell or page.
  final VoidCallback? onTapOutside;
  final bool dismissOnTapOutside;

  bool get _canReplace => replaceController != null;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return TapRegion(
      groupId: findController,
      onTapOutside: dismissOnTapOutside
          ? (_) {
              if (context.mounted &&
                  ModalRoute.of(context)?.isCurrent != false) {
                (onTapOutside ?? onClose)();
              }
            }
          : null,
      child: TextFieldTapRegion(
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  onClose();
                  return null;
                },
              ),
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : math.max(0.0, MediaQuery.sizeOf(context).width - 32);
                final width = math.min(FindBarMetrics.maxWidth, available);
                return _FindBarEntrance(
                  child: Container(
                    width: width,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius:
                          BorderRadius.circular(FindBarMetrics.cardRadius),
                      border: Border.all(color: palette.border, width: 0.6),
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadow,
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                          spreadRadius: -12,
                        ),
                        BoxShadow(
                          color: palette.shadow
                              .withValues(alpha: palette.shadow.a * 0.6),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFindRow(
                          context,
                          palette,
                          math.max(0, width - 13.2),
                        ),
                        _ReplaceRowReveal(
                          visible: showReplace && _canReplace,
                          child: _canReplace
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: FindBarMetrics.gap,
                                  ),
                                  child: _buildReplaceRow(context, palette),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFindRow(
    BuildContext context,
    FindBarPalette palette,
    double width,
  ) {
    final controlSize = _controlSize(context);
    final controlsWidth = math.min(
      width,
      MediaQuery.textScalerOf(context).scale(64) + controlSize * 3 + 8,
    );
    final inline = width >=
        controlsWidth +
            FindBarMetrics.fieldWidth +
            controlSize +
            FindBarMetrics.gap * 2;
    // One Wrap, including on wide panes: reflow never reparents the fields,
    // loses the draft/IME selection or recreates a focused EditableText.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: FindBarMetrics.gap,
      runSpacing: FindBarMetrics.gap,
      children: [
        SizedBox(
          key: const ValueKey('findQueryGroup'),
          width: inline ? width - controlsWidth - FindBarMetrics.gap : width,
          child: Row(
            children: [
              if (_canReplace && onToggleReplace != null)
                _FindBarButton(
                  buttonKey: const ValueKey('findToggleReplace'),
                  palette: palette,
                  icon: showReplace
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  tooltip: showReplace
                      ? LocaleKeys.findAndReplace_hideReplace.tr()
                      : LocaleKeys.findAndReplace_showReplace.tr(),
                  onPressed: onToggleReplace,
                )
              else
                SizedBox.square(
                  dimension: controlSize,
                  child: Center(
                    child: WorkspaceGlyph(
                      Icons.search_rounded,
                      size: FindBarMetrics.iconSize,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(width: FindBarMetrics.gap),
              Expanded(
                child: _buildField(
                  context,
                  palette,
                  controller: findController,
                  focusNode: findFocusNode,
                  hint: hintText ?? LocaleKeys.findAndReplace_find.tr(),
                  autofocus: autofocus,
                  invalid: queryInvalid,
                  onSubmitted: () => (onSubmitted ?? onNext)?.call(),
                  fieldKey: const ValueKey('findTextField'),
                  trailing: [
                    _FindBarToggle(
                      palette: palette,
                      label: 'Aa',
                      tooltip: LocaleKeys.findAndReplace_caseSensitive.tr(),
                      selected: options.caseSensitive,
                      onPressed: () => onOptionsChanged(
                        options.copyWith(caseSensitive: !options.caseSensitive),
                      ),
                    ),
                    if (supportsWholeWord)
                      _FindBarToggle(
                        palette: palette,
                        label: 'ab',
                        underlined: true,
                        tooltip: LocaleKeys.findAndReplace_wholeWord.tr(),
                        selected: options.wholeWord,
                        onPressed: () => onOptionsChanged(
                          options.copyWith(wholeWord: !options.wholeWord),
                        ),
                      ),
                    _FindBarToggle(
                      palette: palette,
                      label: '.*',
                      tooltip: LocaleKeys.findAndReplace_useRegex.tr(),
                      selected: options.useRegex,
                      onPressed: () => onOptionsChanged(
                        options.copyWith(useRegex: !options.useRegex),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          key: const ValueKey('findNavigationGroup'),
          width: controlsWidth,
          child: Row(
            children: [
              const SizedBox(width: FindBarMetrics.gap),
              Expanded(child: _buildCount(context, palette)),
              const SizedBox(width: FindBarMetrics.gap),
              _FindBarButton(
                buttonKey: const ValueKey('findPreviousMatch'),
                palette: palette,
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: LocaleKeys.findAndReplace_previousMatch.tr(),
                onPressed: onPrevious,
              ),
              _FindBarButton(
                buttonKey: const ValueKey('findNextMatch'),
                palette: palette,
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: LocaleKeys.findAndReplace_nextMatch.tr(),
                onPressed: onNext,
              ),
              _FindBarButton(
                buttonKey: const ValueKey('findClose'),
                palette: palette,
                icon: Icons.close_rounded,
                tooltip: LocaleKeys.findAndReplace_close.tr(),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReplaceRow(BuildContext context, FindBarPalette palette) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _controlSize(context) + FindBarMetrics.gap,
        ),
        Expanded(
          child: _buildField(
            context,
            palette,
            controller: replaceController!,
            focusNode: replaceFocusNode,
            hint: LocaleKeys.findAndReplace_replace.tr(),
            autofocus: false,
            invalid: false,
            onSubmitted: () => onReplace?.call(),
            fieldKey: const ValueKey('replaceTextField'),
            trailing: const [],
          ),
        ),
        const SizedBox(width: FindBarMetrics.gap),
        _FindBarButton(
          buttonKey: const ValueKey('findReplaceOne'),
          palette: palette,
          icon: Icons.find_replace_rounded,
          tooltip: LocaleKeys.findAndReplace_replace.tr(),
          onPressed: matchCount == 0 ? null : onReplace,
        ),
        _FindBarButton(
          buttonKey: const ValueKey('findReplaceAll'),
          palette: palette,
          icon: Icons.change_circle_rounded,
          tooltip: LocaleKeys.findAndReplace_replaceAll.tr(),
          onPressed: matchCount == 0 ? null : onReplaceAll,
        ),
      ],
    );
  }

  Widget _buildField(
    BuildContext context,
    FindBarPalette palette, {
    required TextEditingController controller,
    required FocusNode? focusNode,
    required String hint,
    required bool autofocus,
    required bool invalid,
    required VoidCallback onSubmitted,
    required Key fieldKey,
    required List<Widget> trailing,
  }) {
    return Container(
      height: math.max(
        FindBarMetrics.rowHeight,
        MediaQuery.textScalerOf(context).scale(13) + 12,
      ),
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(FindBarMetrics.fieldRadius),
        border: Border.all(
          color: invalid ? palette.danger : palette.border,
          width: invalid ? 1 : 0.6,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              // Keep native field focus on Enter without a delayed request
              // that could steal a later outside click or touch a disposed node.
              onEditingComplete: () {},
              onSubmitted: (_) => onSubmitted(),
              style: TextStyle(
                fontSize: 13,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                filled: false,
                hoverColor: Colors.transparent,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: palette.textSecondary.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          for (final control in trailing) control,
        ],
      ),
    );
  }

  Widget _buildCount(BuildContext context, FindBarPalette palette) {
    final label = queryInvalid
        ? LocaleKeys.findAndReplace_invalidRegex.tr()
        : findController.text.isEmpty
            ? ''
            : busy && matchCount == 0
                ? LocaleKeys.findAndReplace_searching.tr()
                : matchCount == 0
                    ? LocaleKeys.findAndReplace_noResult.tr()
                    : LocaleKeys.findAndReplace_matchOfTotal.tr(
                        args: ['$currentMatch', '$matchCount'],
                      );
    return Semantics(
      liveRegion: true,
      child: Container(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: queryInvalid ? palette.danger : palette.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// A size factor avoids RenderAnimatedSize's zero-duration self-layout bug.
/// Keep the field at one depth when motion preferences or disclosure change;
/// collapsed controls retain their draft but never take focus or pointer input.
class _ReplaceRowReveal extends StatelessWidget {
  const _ReplaceRowReveal({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: visible ? 1 : 0, end: visible ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context) ||
                MediaQuery.accessibleNavigationOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Offstage(
          offstage: !visible && value == 0,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: value,
              child: ExcludeFocus(
                excluding: !visible,
                child: ExcludeSemantics(
                  excluding: !visible,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: Opacity(opacity: value, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: child,
      );
}

double _controlSize(BuildContext context) => math.max(
      FindBarMetrics.controlSize,
      MediaQuery.textScalerOf(context).scale(11) + 8,
    );

class _FindBarButton extends StatelessWidget {
  const _FindBarButton({
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });

  final FindBarPalette palette;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final controlStyle = WorkspaceChrome.controlStyle(context);
    return SizedBox.square(
      dimension: _controlSize(context),
      child: IconButton(
        key: buttonKey,
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FindBarMetrics.controlRadius),
          ),
        ).copyWith(
          // Paint one wash on this surface, not a second Ink overlay over the
          // global IconButton background. Native sizing and glyphs stay intact.
          backgroundColor: controlStyle.backgroundColor,
          overlayColor: controlStyle.overlayColor,
          animationDuration: MediaQuery.disableAnimationsOf(context) ||
                  MediaQuery.accessibleNavigationOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
        ),
        icon: WorkspaceGlyph(
          icon,
          size: FindBarMetrics.iconSize,
          role: enabled
              ? WorkspaceGlyphRole.standard
              : WorkspaceGlyphRole.preserveInk,
          color: enabled
              ? palette.textSecondary
              : palette.textSecondary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// One entrance for the chrome, never a transition around the editor/viewer.
/// Rebuilding counts does not restart the tween or recreate native fields.
class _FindBarEntrance extends StatelessWidget {
  const _FindBarEntrance({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.94, end: 1),
        duration: MediaQuery.disableAnimationsOf(context) ||
                MediaQuery.accessibleNavigationOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -48),
            child: child,
          ),
        ),
        child: child,
      );
}

class _FindBarToggle extends StatelessWidget {
  const _FindBarToggle({
    required this.palette,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    this.underlined = false,
  });

  final FindBarPalette palette;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final bool underlined;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: selected,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox.square(
          dimension: _controlSize(context),
          child: Material(
            color: selected ? palette.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(FindBarMetrics.controlRadius),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(FindBarMetrics.controlRadius),
              hoverColor: palette.hover,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: selected ? palette.accent : palette.textSecondary,
                    decoration: underlined
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor:
                        selected ? palette.accent : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
