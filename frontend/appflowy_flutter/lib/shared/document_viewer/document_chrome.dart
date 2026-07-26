import 'dart:ui' as ui;

import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'document_typography.dart';
import 'document_viewer_theme.dart';

/// Everything the header needs to describe the open document.
@immutable
class DocumentIdentity {
  const DocumentIdentity({
    required this.title,
    required this.icon,
    this.typeLabel,
    this.modified,
    this.byteSize,
    this.breadcrumbs = const [],
  });

  final String title;
  final IconData icon;

  /// Short, human file type — "PDF", "Markdown", "Dart".
  final String? typeLabel;
  final DateTime? modified;
  final int? byteSize;
  final List<String> breadcrumbs;

  /// The single muted metadata line: type · size · modified.
  String get subtitle {
    final parts = <String>[
      if (typeLabel != null && typeLabel!.isNotEmpty) typeLabel!,
      if (byteSize != null) formatDocumentBytes(byteSize!),
      if (modified != null) formatDocumentTimestamp(modified!),
    ];
    return parts.join('  ·  ');
  }
}

/// Human byte sizes without trailing noise: `1.2 MB`, `840 KB`.
String formatDocumentBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 100 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}

/// Calm, reader-friendly timestamps rather than raw dates.
String formatDocumentTimestamp(DateTime moment, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final elapsed = reference.difference(moment);
  if (elapsed.inSeconds < 60) {
    return 'Just now';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes} min ago';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hr ago';
  }
  if (elapsed.inDays < 7) {
    return '${elapsed.inDays} d ago';
  }
  final format = moment.year == reference.year ? 'MMM d' : 'MMM d, yyyy';
  return DateFormat(format).format(moment);
}

/// The compact header shared by every document type.
///
/// Identity on the left, actions on the right, one hairline underneath.
/// No ribbons, no tab strips, no Material [AppBar].
class DocumentHeader extends StatelessWidget {
  const DocumentHeader({
    super.key,
    required this.identity,
    this.actions = const [],
    this.leading,
    this.dense = false,
  });

  final DocumentIdentity identity;
  final List<Widget> actions;
  final Widget? leading;

  /// Hides the metadata line when vertical space is scarce.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme);
    final subtitle = identity.subtitle;
    final showSubtitle = !dense && subtitle.isNotEmpty;

    return Container(
      height: dense
          ? DocumentViewerTheme.toolbarHeight + 8
          : DocumentViewerTheme.chromeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.chrome,
        border: Border(
          bottom: BorderSide(color: theme.hairline, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          _DocumentGlyph(icon: identity.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleLine(
                  title: identity.title,
                  breadcrumbs: dense ? const [] : identity.breadcrumbs,
                  titleStyle: typography.minorHeading.copyWith(
                    fontSize: 13.5,
                    height: 1.25,
                    color: theme.textPrimary,
                  ),
                  breadcrumbStyle: typography.caption.copyWith(
                    fontSize: 13,
                    height: 1.25,
                    color: theme.textMuted,
                  ),
                ),
                if (showSubtitle)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.caption.copyWith(
                      fontSize: 11,
                      height: 1.3,
                      color: theme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}

class _DocumentGlyph extends StatelessWidget {
  const _DocumentGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: theme.control,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: theme.hairline, width: 0.6),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 14, color: theme.icon),
    );
  }
}

/// Optional breadcrumbs and the document title on a single compact line.
class _TitleLine extends StatelessWidget {
  const _TitleLine({
    required this.title,
    required this.breadcrumbs,
    required this.titleStyle,
    required this.breadcrumbStyle,
  });

  final String title;
  final List<String> breadcrumbs;
  final TextStyle titleStyle;
  final TextStyle breadcrumbStyle;

  @override
  Widget build(BuildContext context) {
    if (breadcrumbs.isEmpty) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }
    final separator = TextSpan(
      text: '  /  ',
      style: breadcrumbStyle.copyWith(
        color: breadcrumbStyle.color?.withValues(alpha: 0.6),
      ),
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final segment in breadcrumbs) ...[
            TextSpan(text: segment, style: breadcrumbStyle),
            separator,
          ],
          TextSpan(text: title, style: titleStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A floating, blurred control cluster.
///
/// Apple Preview and Arc rather than a Material toolbar: almost invisible
/// border, soft layered shadow, and grouped controls.
class DocumentToolbar extends StatelessWidget {
  const DocumentToolbar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    this.blurSigma = 12,
    this.floating = true,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double blurSigma;

  /// Floating toolbars carry a shadow; inline toolbars sit flush in chrome.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final radius = BorderRadius.circular(DocumentViewerTheme.controlRadius + 2);
    final bar = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: floating ? theme.chrome : Colors.transparent,
        borderRadius: radius,
        border:
            floating ? Border.all(color: theme.chromeBorder, width: 0.6) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

    if (!floating) {
      return bar;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: theme.floatShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: bar,
        ),
      ),
    );
  }
}

/// Visually joins related controls inside a [DocumentToolbar].
class DocumentToolbarGroup extends StatelessWidget {
  const DocumentToolbarGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// A hairline separator between toolbar groups.
class DocumentToolbarSeparator extends StatelessWidget {
  const DocumentToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Container(
      width: 0.6,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: theme.divider,
    );
  }
}

/// Small, quiet metadata inside the toolbar — page counts, zoom levels.
class DocumentToolbarLabel extends StatelessWidget {
  const DocumentToolbarLabel({
    super.key,
    required this.label,
    this.onTap,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        style: typography.caption.copyWith(
          fontSize: 12,
          color: theme.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    if (onTap == null) {
      return content;
    }
    return _DocumentPressable(
      onPressed: onTap,
      tooltip: tooltip,
      child: content,
    );
  }
}

/// The premium icon button used across every viewer.
///
/// No splash, no ripple: a soft fill appears, the glyph lifts a single pixel,
/// and everything settles within the standard motion window.
class DocumentToolbarButton extends StatelessWidget {
  const DocumentToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = DocumentViewerTheme.controlSize,
    this.iconSize = DocumentViewerTheme.iconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return _DocumentPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      selected: selected,
      lift: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: onPressed == null
                ? theme.iconMuted
                : selected
                    ? theme.accent
                    : theme.icon,
          ),
        ),
      ),
    );
  }
}

/// Shared hover/press/focus behaviour for every document control.
class _DocumentPressable extends StatefulWidget {
  const _DocumentPressable({
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
    this.lift = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final bool lift;

  @override
  State<_DocumentPressable> createState() => _DocumentPressableState();
}

class _DocumentPressableState extends State<_DocumentPressable> {
  bool hovering = false;
  bool pressing = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(DocumentViewerTheme.controlRadius);

    final background = !enabled
        ? Colors.transparent
        : pressing
            ? theme.controlPressed
            : widget.selected
                ? theme.controlSelected
                : hovering || focused
                    ? theme.controlHover
                    : Colors.transparent;

    final lifted = widget.lift && hovering && enabled && !pressing;

    Widget control = AnimatedContainer(
      duration: AppFlowyMotion.fast,
      curve: AppFlowyMotion.standardCurve,
      transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: focused
            ? Border.all(color: theme.accent.withValues(alpha: 0.5), width: 0.8)
            : null,
      ),
      child: widget.child,
    );

    control = AnimatedOpacity(
      duration: AppFlowyMotion.fast,
      opacity: enabled ? 1 : 0.4,
      child: control,
    );

    control = Focus(
      canRequestFocus: enabled,
      onFocusChange: (value) => setState(() => focused = value),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() {
          hovering = false;
          pressing = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => pressing = true) : null,
          onTapUp: enabled ? (_) => setState(() => pressing = false) : null,
          onTapCancel: enabled ? () => setState(() => pressing = false) : null,
          onTap: widget.onPressed,
          child: control,
        ),
      ),
    );

    control = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: control,
    );

    if (widget.tooltip == null) {
      return control;
    }
    return Tooltip(
      message: widget.tooltip!,
      waitDuration: const Duration(milliseconds: 420),
      child: control,
    );
  }
}
