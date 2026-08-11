import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'visual_block_style.dart';

/// Opens a visual block at window size.
///
/// One route for the four block types, so the way a diagram, a mind map, an
/// equation and a drawing grow out of the page is identical: the same soft
/// scrim, the same grow-and-fade transition, Escape and F11 to leave.
Future<T?> showVisualBlockFullscreen<T>({
  required BuildContext context,
  required IconData icon,
  required String title,
  required Widget Function(BuildContext context) builder,
  List<Widget> Function(BuildContext context)? actions,
  String? subtitle,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.44),
    transitionDuration: VisualBlockMetrics.reveal,
    pageBuilder: (dialogContext, animation, _) => _VisualBlockFullscreen(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actions: actions,
      builder: builder,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _VisualBlockFullscreen extends StatelessWidget {
  const _VisualBlockFullscreen({
    required this.icon,
    required this.title,
    required this.builder,
    this.subtitle,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget Function(BuildContext context) builder;
  final List<Widget> Function(BuildContext context)? actions;

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(Navigator.of(context).maybePop()),
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            unawaited(Navigator.of(context).maybePop()),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: palette.isDark ? 0.5 : 0.22),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      icon: icon,
                      title: title,
                      subtitle: subtitle,
                      palette: palette,
                      actions: actions,
                    ),
                    Expanded(child: Builder(builder: builder)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.palette,
    this.subtitle,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VisualBlockPalette palette;
  final List<Widget> Function(BuildContext context)? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
      color: palette.surface,
      child: Row(
        children: [
          Icon(icon, size: 17, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            ...actions!(context),
            const SizedBox(width: 6),
          ],
          VisualBlockButton(
            icon: Icons.close_rounded,
            tooltip: LocaleKeys.button_close.tr(),
            palette: palette,
            onTap: () => unawaited(Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }
}
