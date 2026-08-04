import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The card shown when a marker is hovered or chosen.
///
/// It carries everything the pin already knows, so it appears the moment the
/// pointer arrives rather than after a round trip: a cover, the row's icon and
/// name, a few properties, its tags and when it was last touched.
class AppLocationPopup extends StatelessWidget {
  const AppLocationPopup({
    super.key,
    required this.pin,
    required this.palette,
    this.onOpen,
    this.onEnter,
    this.onExit,
    this.footnote = '',
  });

  final AppMapPin pin;
  final MapPalette palette;
  final VoidCallback? onOpen;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;

  /// A line under the card, used for the marker's coordinates.
  final String footnote;

  @override
  Widget build(BuildContext context) {
    final cover = pin.coverUrl;
    return MouseRegion(
      onEnter: (_) => onEnter?.call(),
      onExit: (_) => onExit?.call(),
      cursor: onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          width: MapMetrics.popupWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MapMetrics.popupRadius),
            boxShadow: palette.popupShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MapMetrics.popupRadius),
            child: BackdropFilter(
              // The blur is what makes the card sit above the map rather than
              // on it; the surface stays a shade short of opaque to show it.
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.floating
                      .withValues(alpha: palette.isDark ? 0.92 : 0.94),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(MapMetrics.popupRadius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cover != null && cover.isNotEmpty)
                      _Cover(url: cover, palette: palette),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        cover == null || cover.isEmpty ? 13 : 11,
                        14,
                        13,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Title(pin: pin, palette: palette),
                          if (pin.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              pin.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                          if (pin.status.isNotEmpty || pin.tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _Chips(pin: pin, palette: palette),
                          ],
                          if (pin.properties.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _Properties(pin: pin, palette: palette),
                          ],
                          if (pin.lastModified != null || footnote.isNotEmpty)
                            _Footer(
                              palette: palette,
                              lastModified: pin.lastModified,
                              footnote: footnote,
                            ),
                        ],
                      ),
                    ),
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

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.palette});

  final String url;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final isRemote = url.startsWith('http://') || url.startsWith('https://');
    return SizedBox(
      height: MapMetrics.popupCover,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: palette.hover),
          if (isRemote)
            Image.network(url, fit: BoxFit.cover, errorBuilder: _broken)
          else
            Image.file(File(url), fit: BoxFit.cover, errorBuilder: _broken),
          // A scrim keeps the title legible whatever the picture is.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  palette.floating.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _broken(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) =>
      const SizedBox.shrink();
}

class _Title extends StatelessWidget {
  const _Title({required this.pin, required this.palette});

  final AppMapPin pin;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final icon = pin.icon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null && icon.isNotEmpty) ...[
          Text(icon, style: const TextStyle(fontSize: 16, height: 1.25)),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            pin.title.trim().isEmpty ? '—' : pin.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.25,
              letterSpacing: -0.15,
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
              fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.pin, required this.palette});

  final AppMapPin pin;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (pin.status.isNotEmpty)
        _Chip(
          label: pin.status,
          color: pin.color ?? palette.swatchFor(pin.status),
          palette: palette,
          filled: true,
        ),
      for (final tag in pin.tags.take(4))
        _Chip(label: tag, color: palette.swatchFor(tag), palette: palette),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.palette,
    this.filled = false,
  });

  final String label;
  final Color color;
  final MapPalette palette;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filled) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: palette.isDark
                  ? Color.lerp(color, Colors.white, 0.45)
                  : Color.lerp(color, Colors.black, 0.3),
              fontWeight: FontWeight.w600,
              fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Properties extends StatelessWidget {
  const _Properties({required this.pin, required this.palette});

  final AppMapPin pin;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final entries = pin.properties.entries.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.palette,
    required this.lastModified,
    required this.footnote,
  });

  final MapPalette palette;
  final DateTime? lastModified;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (lastModified != null)
        DateFormat.yMMMd().add_jm().format(lastModified!),
      if (footnote.isNotEmpty) footnote,
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        parts.join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.2,
          color: palette.textMuted.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
