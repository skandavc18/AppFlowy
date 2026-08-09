import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The look the connections pages share.
///
/// Both the account list and one account's own page are lists of the same
/// thing — a card with a glyph, a name, a line saying what it is for, and one
/// control — so the card lives here and neither page draws its own.
abstract final class ConnectionsMetrics {
  static const double cardRadius = 12;
  static const double glyphSize = 36;
  static const double glyphRadius = 10;
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(14, 12, 12, 12);
  static const Duration hover = Duration(milliseconds: 140);
}

/// What an account is reached for, in words rather than product names.
///
/// "Google Drive" says whose it is; this says what turning it on does, which
/// is the question somebody is actually answering.
String providerServicePurpose(ProviderService service) => switch (service) {
      ProviderService.googleDrive ||
      ProviderService.oneDrive ||
      ProviderService.box =>
        LocaleKeys.providers_settings_purpose_files.tr(),
      ProviderService.googlePhotos ||
      ProviderService.immich =>
        LocaleKeys.providers_settings_purpose_photos.tr(),
      ProviderService.googleCalendar =>
        LocaleKeys.providers_settings_purpose_calendar.tr(),
      ProviderService.gmail ||
      ProviderService.outlookMail =>
        LocaleKeys.providers_settings_purpose_mail.tr(),
      ProviderService.github ||
      ProviderService.gitlab =>
        LocaleKeys.providers_settings_purpose_code.tr(),
      ProviderService.local => '',
    };

/// The rounded accent tile every row leads with.
class ConnectionGlyph extends StatelessWidget {
  const ConnectionGlyph({
    super.key,
    required this.icon,
    required this.accent,
    this.muted = false,
    this.size = ConnectionsMetrics.glyphSize,
  });

  final IconData icon;
  final Color accent;
  final bool muted;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: muted ? 0.08 : 0.14),
          borderRadius: BorderRadius.circular(ConnectionsMetrics.glyphRadius),
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: muted ? accent.withValues(alpha: 0.7) : accent,
        ),
      );
}

/// One row of the connections pages.
///
/// Tappable when it leads somewhere, inert when it only carries a control, but
/// always the same shape so the page reads as one list.
class ConnectionCard extends StatefulWidget {
  const ConnectionCard({
    super.key,
    required this.palette,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.footer,
  });

  final FolderExplorerPalette palette;
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    // Hover has to fade within one hue: a tween that starts at transparent
    // black passes through grey on a light surface.
    final resting = palette.surface;
    final surface = hovered && widget.onTap != null
        ? Color.alphaBlend(palette.hover, resting)
        : resting;

    final card = AnimatedContainer(
      duration: ConnectionsMetrics.hover,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(ConnectionsMetrics.cardRadius),
        border: Border.all(
          color: palette.border.withValues(alpha: hovered ? 0.6 : 0.4),
        ),
      ),
      padding: ConnectionsMetrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              widget.leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontVariations: const [FontVariation.weight(580)],
                      ),
                    ),
                    if (widget.subtitle case final String subtitle
                        when subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 10),
                widget.trailing!,
              ],
            ],
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: 10),
            widget.footer!,
          ],
        ],
      ),
    );

    if (widget.onTap == null) {
      return card;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}

/// The dashed-feeling "one more of these" row.
///
/// Deliberately a full-width button rather than a link in a caption: adding a
/// second account of the same service is a normal thing to do, not a corner
/// case to be hidden.
class ConnectionAddButton extends StatefulWidget {
  const ConnectionAddButton({
    super.key,
    required this.palette,
    required this.label,
    required this.accent,
    required this.onPressed,
    this.icon = Icons.add_rounded,
  });

  final FolderExplorerPalette palette;
  final String label;
  final Color accent;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  State<ConnectionAddButton> createState() => _ConnectionAddButtonState();
}

class _ConnectionAddButtonState extends State<ConnectionAddButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: ConnectionsMetrics.hover,
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: hovered ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(ConnectionsMetrics.cardRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    fontVariations: const [FontVariation.weight(600)],
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

/// A quiet button for the actions beside a row.
class ConnectionTextButton extends StatelessWidget {
  const ConnectionTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? tone;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: tone,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      );
}
