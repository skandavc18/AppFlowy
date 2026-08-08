import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// How long ago, in words, without a dependency.
String providerRelativeTime(DateTime? when) {
  if (when == null) {
    return LocaleKeys.providers_never.tr();
  }
  final elapsed = DateTime.now().difference(when);
  if (elapsed.inSeconds < 45) {
    return LocaleKeys.providers_justNow.tr();
  }
  if (elapsed.inMinutes < 60) {
    return LocaleKeys.providers_minutesAgo.tr(args: ['${elapsed.inMinutes}']);
  }
  if (elapsed.inHours < 24) {
    return LocaleKeys.providers_hoursAgo.tr(args: ['${elapsed.inHours}']);
  }
  if (elapsed.inDays < 30) {
    return LocaleKeys.providers_daysAgo.tr(args: ['${elapsed.inDays}']);
  }
  return DateFormat.yMMMd().format(when);
}

/// The line the interface shows for one state.
///
/// Every provider failure passes through here, which is the rule that keeps a
/// stranger's error body off the screen: the state decides the words, never
/// the service.
({String title, String body, IconData icon}) providerStateCopy(
  ProviderStatus status,
  ProviderServiceInfo info,
) {
  return switch (status) {
    ProviderStatus.offline => (
        title: LocaleKeys.providers_state_offlineTitle.tr(),
        body: LocaleKeys.providers_state_offlineBody.tr(args: [info.label]),
        icon: Icons.cloud_off_rounded,
      ),
    ProviderStatus.authExpired => (
        title: LocaleKeys.providers_state_expiredTitle.tr(),
        body: LocaleKeys.providers_state_expiredBody.tr(args: [info.label]),
        icon: Icons.lock_clock_rounded,
      ),
    ProviderStatus.permissionDenied => (
        title: LocaleKeys.providers_state_deniedTitle.tr(),
        body: LocaleKeys.providers_state_deniedBody.tr(args: [info.label]),
        icon: Icons.no_encryption_gmailerrorred_rounded,
      ),
    ProviderStatus.notFound => (
        title: LocaleKeys.providers_state_missingTitle.tr(),
        body: LocaleKeys.providers_state_missingBody.tr(args: [info.label]),
        icon: Icons.search_off_rounded,
      ),
    ProviderStatus.rateLimited => (
        title: LocaleKeys.providers_state_rateLimitedTitle.tr(),
        body: LocaleKeys.providers_state_rateLimitedBody.tr(args: [info.label]),
        icon: Icons.hourglass_top_rounded,
      ),
    _ => (
        title: LocaleKeys.providers_state_errorTitle.tr(),
        body: LocaleKeys.providers_state_errorBody.tr(args: [info.label]),
        icon: Icons.error_outline_rounded,
      ),
  };
}

/// The subtle "where this came from" mark.
///
/// Deliberately quiet: a glyph in the service's hue and the service's name at
/// the size of a caption. The collection's own name stays the loudest thing on
/// the screen, because that is what the person named it.
class ProviderBadge extends StatelessWidget {
  const ProviderBadge({
    super.key,
    required this.source,
    required this.palette,
    this.detail = '',
    this.compact = false,
    this.onTap,
  });

  final CollectionSource source;
  final CollectionPalette palette;

  /// The album, repository or folder the collection is bound to.
  final String detail;

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (source.isLocal) {
      return const SizedBox.shrink();
    }

    final info = source.info;
    final label = detail.trim().isEmpty ? info.label : detail.trim();
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(info.icon, size: compact ? 11 : 13, color: info.accent),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: compact ? 10.5 : 11.5,
              height: 1.1,
              letterSpacing: 0.05,
              fontVariations: const [FontVariation.weight(560)],
            ),
          ),
        ),
      ],
    );

    if (onTap == null) {
      return badge;
    }
    return _Tappable(
      onTap: onTap!,
      palette: palette,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: badge,
      ),
    );
  }
}

/// The strip that says when the collection last agreed with its service, and
/// offers to ask again.
class ProviderSyncStrip extends StatelessWidget {
  const ProviderSyncStrip({
    super.key,
    required this.palette,
    required this.status,
    required this.lastSyncedAt,
    required this.onSync,
    this.canSync = true,
  });

  final CollectionPalette palette;
  final ProviderStatus status;
  final DateTime? lastSyncedAt;
  final VoidCallback onSync;
  final bool canSync;

  @override
  Widget build(BuildContext context) {
    final busy = status.isBusy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: palette.accent,
            ),
          )
        else
          Icon(
            status.isFailure
                ? Icons.cloud_off_rounded
                : Icons.cloud_done_rounded,
            size: 13,
            color:
                status.isFailure ? _warningColor(context) : palette.textMuted,
          ),
        const SizedBox(width: 6),
        Text(
          busy
              ? LocaleKeys.providers_syncing.tr()
              : LocaleKeys.providers_lastSynced
                  .tr(args: [providerRelativeTime(lastSyncedAt)]),
          style: TextStyle(color: palette.textMuted, fontSize: 11.5),
        ),
        if (canSync && !busy) ...[
          const SizedBox(width: 8),
          _Tappable(
            onTap: onSync,
            palette: palette,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync_rounded, size: 12, color: palette.accent),
                  const SizedBox(width: 4),
                  Text(
                    LocaleKeys.providers_sync.tr(),
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: 11.5,
                      fontVariations: const [FontVariation.weight(580)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A whole-panel state, for when there is nothing underneath to show.
class ProviderStateView extends StatelessWidget {
  const ProviderStateView({
    super.key,
    required this.status,
    required this.info,
    required this.palette,
    this.onRetry,
    this.onReconnect,
    this.retryAfter,
  });

  final ProviderStatus status;
  final ProviderServiceInfo info;
  final CollectionPalette palette;
  final VoidCallback? onRetry;
  final VoidCallback? onReconnect;
  final Duration? retryAfter;

  @override
  Widget build(BuildContext context) {
    if (status == ProviderStatus.loading) {
      return _Centred(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              LocaleKeys.providers_loading.tr(args: [info.label]),
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final copy = providerStateCopy(status, info);
    final wait = retryAfter;
    return _Centred(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: info.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(copy.icon, size: 22, color: info.accent),
            ),
            const SizedBox(height: 16),
            Text(
              copy.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontVariations: const [FontVariation.weight(620)],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              wait == null
                  ? copy.body
                  : LocaleKeys.providers_state_rateLimitedWait
                      .tr(args: ['${wait.inSeconds}']),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status.needsReconnect && onReconnect != null)
                  _ActionButton(
                    label: LocaleKeys.providers_reconnect.tr(),
                    palette: palette,
                    primary: true,
                    onPressed: onReconnect!,
                  ),
                if (status.isRetryable && onRetry != null) ...[
                  if (status.needsReconnect && onReconnect != null)
                    const SizedBox(width: 8),
                  _ActionButton(
                    label: LocaleKeys.providers_tryAgain.tr(),
                    palette: palette,
                    onPressed: onRetry!,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin bar over content that is already on screen, for a refresh that
/// failed. Nothing is taken away — the collection stays readable.
class ProviderStaleBanner extends StatelessWidget {
  const ProviderStaleBanner({
    super.key,
    required this.status,
    required this.info,
    required this.palette,
    this.onRetry,
    this.onReconnect,
  });

  final ProviderStatus status;
  final ProviderServiceInfo info;
  final CollectionPalette palette;
  final VoidCallback? onRetry;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final copy = providerStateCopy(status, info);
    final accent = _warningColor(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 10),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(copy.icon, size: 15, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              copy.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
            ),
          ),
          if (status.needsReconnect && onReconnect != null)
            _ActionButton(
              label: LocaleKeys.providers_reconnect.tr(),
              palette: palette,
              dense: true,
              onPressed: onReconnect!,
            )
          else if (onRetry != null)
            _ActionButton(
              label: LocaleKeys.providers_tryAgain.tr(),
              palette: palette,
              dense: true,
              onPressed: onRetry!,
            ),
        ],
      ),
    );
  }
}

/// The amber a warning uses, blended so it reads in paper, light and dark
/// without ever being a saturated slab.
Color _warningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE0A33A)
        : const Color(0xFFB4761B);

class _Centred extends StatelessWidget {
  const _Centred({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(32), child: child),
      );
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.palette,
    required this.onPressed,
    this.primary = false,
    this.dense = false,
  });

  final String label;
  final CollectionPalette palette;
  final VoidCallback onPressed;
  final bool primary;
  final bool dense;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final background = widget.primary
        ? palette.accent.withValues(alpha: hovered ? 0.20 : 0.13)
        : Color.alphaBlend(
            palette.hover.withValues(alpha: hovered ? 1 : 0),
            palette.surface,
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 10 : 14,
            vertical: widget.dense ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.primary ? palette.accent : palette.textSecondary,
              fontSize: widget.dense ? 11.5 : 12.5,
              fontVariations: const [FontVariation.weight(580)],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tappable extends StatefulWidget {
  const _Tappable({
    required this.child,
    required this.onTap,
    required this.palette,
  });

  final Widget child;
  final VoidCallback onTap;
  final CollectionPalette palette;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              // Fading from the real colour at zero alpha, never from
              // transparent black, so the hover does not flash grey.
              color: widget.palette.hover.withValues(alpha: hovered ? 1 : 0),
              borderRadius: BorderRadius.circular(7),
            ),
            child: widget.child,
          ),
        ),
      );
}
