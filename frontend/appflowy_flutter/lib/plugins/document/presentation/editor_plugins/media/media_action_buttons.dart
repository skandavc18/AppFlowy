import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const _feedbackDuration = Duration(milliseconds: 1600);
const _transitionDuration = Duration(milliseconds: 140);

enum _MediaAction { copy, share }

/// Compact, native copy/share controls for either floating or inline chrome.
///
/// Only explicit activation touches [actions]. Feedback is local to this
/// source and never contains a file path, signed URL, header or backend error.
class MediaActionButtons extends StatefulWidget {
  const MediaActionButtons({
    super.key,
    required this.source,
    this.actions = const MediaActionService(),
    this.decorated = true,
    this.buttonSize = 28,
    this.onDarkSurface = false,
  }) : assert(buttonSize > 0 && buttonSize < double.infinity);

  final MediaActionSource source;
  final MediaActionService actions;
  final bool decorated;
  final double buttonSize;

  /// Contrasting ink and feedback for a host-owned dark overlay.
  final bool onDarkSurface;

  @override
  State<MediaActionButtons> createState() => _MediaActionButtonsState();
}

class _MediaActionButtonsState extends State<MediaActionButtons> {
  final _copyFocus = FocusNode(debugLabel: 'Media copy');
  final _shareFocus = FocusNode(debugLabel: 'Media share');
  final _busyFocus = FocusNode(debugLabel: 'Media action in progress');
  Timer? _feedbackTimer;
  _MediaAction? _pending;
  _MediaAction? _failed;
  bool _copied = false;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant MediaActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.actions != widget.actions) {
      _revision++;
      _clearFeedback();
      // Do not release the lock here: the previous operation can still write
      // to the clipboard or open a sheet. Serialize even across source changes.
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _copyFocus.dispose();
    _shareFocus.dispose();
    _busyFocus.dispose();
    super.dispose();
  }

  void _clearFeedback() {
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    _copied = false;
    _failed = null;
  }

  Future<void> _perform(
    _MediaAction action, {
    required MediaActionSource source,
    required MediaActionService actions,
    required int revision,
    required BuildContext buttonContext,
  }) async {
    // Also guard callbacks retained before a rebuild or before disabling the
    // controls; merely setting onPressed to null would not guard those calls.
    if (!mounted || _pending != null || revision != _revision) {
      return;
    }
    final origin =
        action == _MediaAction.share ? _shareOrigin(buttonContext) : null;
    final focus = action == _MediaAction.copy ? _copyFocus : _shareFocus;
    final restoreFocus = focus.hasFocus;
    if (restoreFocus) {
      // Native disabled buttons cannot retain focus. A non-traversable anchor
      // keeps the reveal open until they are enabled again.
      _busyFocus.requestFocus();
    }
    final operationRevision = ++_revision;
    setState(() {
      _clearFeedback();
      _pending = action;
    });

    var succeeded = false;
    try {
      if (action == _MediaAction.copy) {
        await actions.copy(source);
      } else {
        // Capture the anchor before any await, including service-side file IO.
        await actions.share(source, sharePositionOrigin: origin);
      }
      succeeded = true;
    } catch (_) {
      // Intentionally do not stringify or log errors: they can contain source
      // credentials. The controls expose only localized, friendly feedback.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pending = null;
      if (_revision == operationRevision) {
        _failed = succeeded ? null : action;
        // Opening/dismissing a share sheet does not prove delivery.
        _copied = succeeded && action == _MediaAction.copy;
      }
    });
    if (restoreFocus && _revision == operationRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _revision == operationRevision &&
            _pending == null &&
            _busyFocus.hasPrimaryFocus) {
          // Wait for onPressed to be re-enabled, and never steal focus from a
          // user who has moved to another control while the service was busy.
          focus.requestFocus();
        }
      });
    }
    if (_revision == operationRevision && _copied) {
      _feedbackTimer = Timer(_feedbackDuration, () {
        if (mounted && _revision == operationRevision) {
          setState(() {
            _feedbackTimer = null;
            _copied = false;
          });
        }
      });
    }
  }

  Rect? _shareOrigin(BuildContext buttonContext) {
    if (!buttonContext.mounted) {
      return null;
    }
    final box = buttonContext.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty ||
        !box.size.isFinite) {
      return null;
    }
    // All four corners also handle a scaled/rotated media host, not just an
    // untranslated local Size attached to a global top-left point.
    final origin = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    ).expandToInclude(
      Rect.fromPoints(
        box.localToGlobal(Offset(box.size.width, 0)),
        box.localToGlobal(Offset(0, box.size.height)),
      ),
    );
    return origin.isFinite && !origin.isEmpty ? origin : null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = _MediaActionPalette.of(
      context,
      onDarkSurface: widget.onDarkSurface,
    );
    final duration = _animationDuration(context);
    final padding = widget.decorated ? 4.0 : 0.0;
    final width = widget.buttonSize * 2 + 4 + padding * 2;
    final height = widget.buttonSize + padding * 2;

    // Explicit dimensions, rather than LayoutBuilder/AnimatedSize, also work
    // in intrinsic-height file rows. Only exceptionally tight hosts scale down.
    return Focus(
      focusNode: _busyFocus,
      skipTraversal: true,
      includeSemantics: false,
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  key: const ValueKey('media-action-surface'),
                  decoration: BoxDecoration(
                    color: widget.decorated ? palette.surface : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: widget.decorated
                        ? EditorSurfaceStyle.embedShadow(context)
                        : null,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final action in _MediaAction.values) ...[
                            if (action == _MediaAction.share)
                              const SizedBox(width: 4),
                            Builder(
                              builder: (buttonContext) => _buildButton(
                                buttonContext,
                                action,
                                palette,
                                duration,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // The badge has no layout or hit-test footprint. It stays small
                // but can accommodate translated/scaled text above a narrow bar.
                Positioned(
                  bottom: height + 4,
                  right: 0,
                  width: 144,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      // The button's live region announces the same feedback.
                      child: AnimatedSwitcher(
                        key: ValueKey(('feedback', _revision)),
                        duration: duration,
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _copied
                            ? Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      LocaleKeys.form_copied.tr(),
                                      key: const ValueKey('media-copied'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: 10,
                                            height: 1.2,
                                            color: palette.ink,
                                          ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
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

  Widget _buildButton(
    BuildContext buttonContext,
    _MediaAction action,
    _MediaActionPalette palette,
    Duration duration,
  ) {
    final source = widget.source;
    final actions = widget.actions;
    final revision = _revision;
    final copied = action == _MediaAction.copy && _copied;
    final failed = action == _failed;
    final pending = action == _pending;
    final tooltip = copied
        ? LocaleKeys.form_copied.tr()
        : failed
            ? action == _MediaAction.copy
                ? LocaleKeys.message_copy_fail.tr()
                : LocaleKeys.mediaActions_shareFailed.tr()
            : action == _MediaAction.copy
                ? LocaleKeys.editor_copy.tr()
                : LocaleKeys.button_share.tr();

    return SizedBox.square(
      dimension: widget.buttonSize,
      child: TooltipTheme(
        // Supply the accessible name below, rather than repeating hover help.
        data:
            TooltipTheme.of(buttonContext).copyWith(excludeFromSemantics: true),
        child: IconButton(
          key: ValueKey('media-${action.name}'),
          tooltip: tooltip,
          focusNode: action == _MediaAction.copy ? _copyFocus : _shareFocus,
          onPressed: _pending != null
              ? null
              : () => unawaited(
                    _perform(
                      action,
                      source: source,
                      actions: actions,
                      revision: revision,
                      buttonContext: buttonContext,
                    ),
                  ),
          style: _buttonStyle(palette, duration),
          // Inside the native button's boundary, the label and live feedback
          // share its enabled/focus state and tap action, not an empty parent.
          icon: Semantics(
            label: tooltip,
            liveRegion: copied || failed,
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 16,
              child: AnimatedSwitcher(
                // Rebinding a source drops outgoing feedback immediately while
                // retaining the actual button and its keyboard focus state.
                key: ValueKey((revision, action)),
                duration: duration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: pending
                    ? SizedBox.square(
                        key: ValueKey('media-${action.name}-progress'),
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: palette.ink.withValues(alpha: 0.65),
                          value: duration == Duration.zero ? 0.65 : null,
                        ),
                      )
                    : Icon(
                        copied
                            ? Icons.check_rounded
                            : failed
                                ? Icons.error_outline_rounded
                                : action == _MediaAction.copy
                                    ? Icons.copy_rounded
                                    : Icons.ios_share_rounded,
                        key: ValueKey((action, copied, failed)),
                        size: 16,
                        color: failed
                            ? palette.error
                            : copied
                                ? palette.accent
                                : null,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle(
    _MediaActionPalette palette,
    Duration duration,
  ) =>
      IconButton.styleFrom(
        foregroundColor: palette.ink,
        disabledForegroundColor: palette.ink.withValues(alpha: 0.4),
        minimumSize: Size.square(widget.buttonSize),
        maximumSize: Size.square(widget.buttonSize),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashFactory: NoSplash.splashFactory,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.onDarkSurface ? 4 : 8),
        ),
      ).copyWith(
        animationDuration: duration,
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.ink.withValues(alpha: 0.4)
              : palette.ink,
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          final alpha = states.contains(WidgetState.disabled)
              ? 0.0
              : states.contains(WidgetState.pressed)
                  ? 0.12
                  : states.contains(WidgetState.hovered)
                      ? widget.onDarkSurface
                          ? 0.1
                          : 0.07
                      : 0.0;
          return palette.accent.withValues(alpha: alpha);
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? palette.focusRing
                : palette.focusRing.withValues(alpha: 0),
          ),
        ),
      );
}

/// Hides pointer/semantics immediately, but keeps descendants in the Tab order.
///
/// Focus and assistive navigation reveal the child even if [visible] is false.
/// Nothing is clipped, so a child's copy-feedback badge can paint above it.
class MediaActionReveal extends StatefulWidget {
  const MediaActionReveal({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  State<MediaActionReveal> createState() => _MediaActionRevealState();
}

class _MediaActionRevealState extends State<MediaActionReveal> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final show = widget.visible ||
        _focused ||
        (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false);
    final duration = _animationDuration(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (mounted && _focused != focused) {
          setState(() => _focused = focused);
        }
      },
      child: IgnorePointer(
        ignoring: !show,
        child: ExcludeSemantics(
          excluding: !show,
          child: AnimatedOpacity(
            key: const ValueKey('media-action-reveal'),
            opacity: show ? 1 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, 0.06),
              duration: duration,
              curve: Curves.easeOutCubic,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shares hover/focus visibility between a media body and its overlaid chrome.
/// Touch platforms and assistive navigation do not require a hover gesture.
class MediaHoverRegion extends StatefulWidget {
  const MediaHoverRegion({super.key, required this.builder});

  final Widget Function(BuildContext context, bool visible) builder;

  @override
  State<MediaHoverRegion> createState() => _MediaHoverRegionState();
}

class _MediaHoverRegionState extends State<MediaHoverRegion> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final visible = _hovered ||
        _focused ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false);
    return MouseRegion(
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (_) {
        if (mounted && !_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (mounted && _hovered) {
          setState(() => _hovered = false);
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: (focused) {
          if (mounted && _focused != focused) {
            setState(() => _focused = focused);
          }
        },
        child: widget.builder(context, visible),
      ),
    );
  }
}

Duration _animationDuration(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  return (media?.disableAnimations ?? false) ||
          (media?.accessibleNavigation ?? false)
      ? Duration.zero
      : _transitionDuration;
}

class _MediaActionPalette {
  const _MediaActionPalette({
    required this.surface,
    required this.ink,
    required this.accent,
    required this.focusRing,
    required this.error,
  });

  factory _MediaActionPalette.of(
    BuildContext context, {
    bool onDarkSurface = false,
  }) {
    if (onDarkSurface) {
      return _MediaActionPalette(
        surface: Colors.black.withValues(alpha: 0.6),
        ink: Colors.white,
        accent: Colors.white,
        focusRing: Colors.white,
        error: Colors.white,
      );
    }
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final paper =
        theme.brightness == Brightness.light && PaperTheme.isEnabled(context);
    return _MediaActionPalette(
      surface: paper
          ? PaperTheme.popupBackground
          : premium?.floatingSurface ?? theme.cardColor,
      ink: paper
          ? PaperTheme.textSecondary
          : premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      accent: paper
          ? PaperTheme.accent
          : premium?.accent ?? theme.colorScheme.primary,
      focusRing:
          paper ? PaperTheme.focusRing : premium?.focusRing ?? theme.focusColor,
      error: theme.colorScheme.error,
    );
  }

  final Color surface;
  final Color ink;
  final Color accent;
  final Color focusRing;
  final Color error;
}
