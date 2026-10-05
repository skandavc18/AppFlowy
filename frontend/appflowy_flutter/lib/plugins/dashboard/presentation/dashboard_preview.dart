import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_variables_bar.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The widest a previewed dashboard is laid out at before it is scaled down.
///
/// Wide enough for the twelve-column arrangement a dashboard is normally seen
/// in. A narrow pane lays it out narrower — as a narrower window would — so
/// its words stay legible rather than shrinking to nothing.
const double dashboardPreviewLayoutWidth = 1240;

/// The narrowest a previewed dashboard is laid out at.
const double dashboardPreviewMinimumLayoutWidth = 960;

/// A dashboard as it really looks, drawn small and read only.
///
/// The real sections and cards are built against a controller with an empty
/// view id, which never writes, so a preview cannot change the dashboard it
/// shows. Nothing inside takes the pointer or the keyboard: a preview is looked
/// at, not used. The content scrolls when it is taller than the space given.
class DashboardLivePreview extends StatefulWidget {
  const DashboardLivePreview({
    super.key,
    required this.document,
    this.layoutWidth,
    this.view,
    this.userProfile,
  });

  final DashboardDocument document;

  /// The width to lay the board out at; by default it follows the pane.
  final double? layoutWidth;

  /// The dashboard's page. When given, its cover, icon and title are drawn
  /// above the board exactly as the page draws them, at the same scale.
  final ViewPB? view;
  final UserProfilePB? userProfile;

  @override
  State<DashboardLivePreview> createState() => _DashboardLivePreviewState();
}

class _DashboardLivePreviewState extends State<DashboardLivePreview> {
  late DashboardController _controller = _controllerFor(widget.document);
  final DashboardSectionRegistry _sections = DashboardSectionRegistry();

  static DashboardController _controllerFor(DashboardDocument document) =>
      DashboardController(
        viewId: '',
        document: document,
        mode: DashboardMode.presentation,
      );

  @override
  void didUpdateWidget(covariant DashboardLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      final previous = _controller;
      _controller = _controllerFor(widget.document);
      // The cards still listen to the old controller until this frame has
      // rebuilt them against the new one.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final document = widget.document;
    final view = widget.view;
    final empty = document.widgetCount == 0;
    Widget emptyNote() => BoardPreviewEmptyNote(
          key: const ValueKey('dashboard-preview-empty'),
          icon: Icons.dashboard_rounded,
          message: LocaleKeys.viewLibrary_emptyDashboard.tr(),
        );
    if (empty && view == null) return emptyNote();

    Widget backdrop(Widget child) => switch (document.settings.background) {
          DashboardBackground.canvas => child,
          DashboardBackground.tinted => ColoredBox(
              color:
                  palette.sunken.withValues(alpha: palette.isDark ? 0.5 : 0.7),
              child: child,
            ),
          DashboardBackground.grid => DashboardGridBackdrop(
              palette: palette,
              step: document.settings.density.rowHeight +
                  document.settings.density.gap,
              child: child,
            ),
        };

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }
        final layoutWidth = widget.layoutWidth ??
            (constraints.maxWidth * 1.6)
                .clamp(
                  dashboardPreviewMinimumLayoutWidth,
                  dashboardPreviewLayoutWidth,
                )
                .toDouble();
        // The page's own reading inset at the width it is laid out at, so the
        // cover, the title and the board line up as they do on the page.
        final inset = view == null
            ? WorkspaceTokens.space6
            : WorkspaceTokens.pageInset(layoutWidth);
        final maxWidth = document.settings.maxWidth;
        final page = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (view != null)
              _DashboardPreviewHeader(
                view: view,
                document: document,
                palette: palette,
                inset: inset,
                userProfile: widget.userProfile,
              )
            else
              const SizedBox(height: 20),
            if (!empty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth > 0 ? maxWidth : double.infinity,
                    ),
                    child: DashboardBoard(
                      registry: _sections,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (document.settings.showControlBar)
                            DashboardVariablesBar(
                              controller: _controller,
                              palette: palette,
                            ),
                          for (final section in document.sections)
                            DashboardSectionView(
                              key: ValueKey(section.id),
                              controller: _controller,
                              section: section,
                              palette: palette,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 28),
          ],
        );
        final scaled = FittedBox(
          key: const ValueKey('dashboard-preview-board'),
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: layoutWidth,
            child: backdrop(
              // A preview is looked at: no field, grip or button inside
              // it may take the pointer or the keyboard.
              ExcludeFocus(
                child: IgnorePointer(
                  child: MediaQuery.withNoTextScaling(child: page),
                ),
              ),
            ),
          ),
        );
        final scroll = SingleChildScrollView(
          key: const ValueKey('dashboard-preview-scroll'),
          primary: false,
          child: empty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    scaled,
                    // Said at reading size, not as small as the page.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: WorkspaceTokens.space4,
                      ),
                      child: emptyNote(),
                    ),
                  ],
                )
              : scaled,
        );
        if (view == null) return scroll;
        // The page's ground runs on below a short dashboard, as it does on
        // the page itself.
        return ColoredBox(
          color: switch (document.settings.background) {
            DashboardBackground.tinted => Color.alphaBlend(
                palette.sunken.withValues(alpha: palette.isDark ? 0.5 : 0.7),
                palette.canvas,
              ),
            _ => palette.canvas,
          },
          child: scroll,
        );
      },
    );
  }
}

/// The top of a dashboard page — cover, icon, title and subtitle — built
/// with the same header the page itself uses.
class _DashboardPreviewHeader extends StatelessWidget {
  const _DashboardPreviewHeader({
    required this.view,
    required this.document,
    required this.palette,
    required this.inset,
    this.userProfile,
  });

  final ViewPB view;
  final DashboardDocument document;
  final DashboardPalette palette;
  final double inset;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    final cover = view.cover;
    final icon = view.icon.toEmojiIconData();
    final glyph = icon.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: icon,
            emojiSize: WorkspaceTokens.pageIconSize,
            opticalRole: IconOpticalRole.header,
          )
        : WorkspaceGlyph.named(
            'layout',
            size: WorkspaceTokens.pageIconSize,
            color: palette.accent,
          );
    final iconSize = IconSize.decode(view.extra) ??
        (icon.isNotEmpty
            ? IconOpticalSize.resolve(
                role: IconOpticalRole.header,
                baseSize: WorkspaceTokens.pageIconSize,
              ).slotSize
            : WorkspaceTokens.pageIconSize);
    final maxWidth = document.settings.maxWidth;
    return WorkspacePageHeader(
      key: const ValueKey('dashboard-preview-header'),
      maxWidth: maxWidth > 0 ? maxWidth + inset * 2 : double.infinity,
      contentInset: inset,
      coverHeight:
          PageCoverHeight.decode(view.extra) ?? WorkspaceTokens.coverHeight,
      cover: cover != null && !cover.isNone
          ? ViewCoverImage(
              cover: cover,
              userProfile: userProfile,
              width: double.infinity,
            )
          : null,
      identity: WorkspacePageIdentity(
        icon: PageIconArtwork(size: iconSize, child: glyph),
        title: Text(
          view.name.isEmpty ? LocaleKeys.dashboard_untitled.tr() : view.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: WorkspaceTypography.style(
            context,
            WorkspaceTextRole.pageTitle,
          ),
        ),
        description: document.subtitle.isEmpty
            ? null
            : Text(
                document.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.body,
                  color: palette.textSecondary,
                ),
              ),
      ),
    );
  }
}

/// A dashboard's arrangement, drawn as a small picture of its cards.
///
/// Cheap enough for a wall of gallery cards: it reads nothing and builds no
/// widget from the dashboard itself — only where each card sits, what it is,
/// and the words it opens with.
class DashboardMiniature extends StatelessWidget {
  const DashboardMiniature({super.key, required this.document});

  final DashboardDocument document;

  static const double _referenceWidth = 1200;
  static const double _narrowestWidth = 560;
  static const double _sectionHeading = 34;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    if (document.widgetCount == 0) {
      return BoardPreviewEmptyNote(
        key: const ValueKey('dashboard-miniature-empty'),
        icon: Icons.dashboard_rounded,
        message: LocaleKeys.viewLibrary_emptyDashboard.tr(),
        compact: true,
      );
    }

    // Where every visible widget sits, in grid units. Heights do not depend
    // on the width a grid is laid out at, so the board's height is known
    // before the width is chosen.
    final density = document.settings.density;
    final step = density.rowHeight + density.gap;
    final sections = <({
      String? heading,
      List<DashboardWidgetSpec> widgets,
      List<DashboardSlot> slots,
    })>[];
    var height = 0.0;
    for (final section in document.sections) {
      final visible = [
        for (final widget in section.widgets)
          if (!widget.hidden) widget,
      ];
      if (visible.isEmpty && !section.hasHeading) {
        continue;
      }
      final slots = resolveDashboardLayout(
        [
          for (final widget in visible)
            DashboardSlot(id: widget.id, placement: widget.placement),
        ],
        columns: DashboardPlacement.referenceColumns,
        compact: section.layout != DashboardSectionLayout.free,
      );
      sections.add(
        (
          heading: section.hasHeading ? section.title : null,
          widgets: visible,
          slots: slots,
        ),
      );
      if (section.hasHeading) height += _sectionHeading;
      height += dashboardLayoutHeight(slots) * step + density.gap;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 12.0;
        final width = math.max(0.0, constraints.maxWidth - padding * 2);
        if (width <= 0) return const SizedBox.shrink();
        // Laid out at the width that gives the board the shape of the card,
        // a short dashboard fills its card instead of sitting in a strip.
        final room = constraints.hasBoundedHeight
            ? constraints.maxHeight - padding * 2
            : 0.0;
        final reference = room > 0 && height > 0
            ? (height * width / room)
                .clamp(_narrowestWidth, _referenceWidth)
                .toDouble()
            : _referenceWidth;
        final metrics = dashboardGridMetrics(
          width: reference,
          columns: DashboardPlacement.referenceColumns,
          gap: density.gap,
          rowHeight: density.rowHeight,
        );
        final scale = width / reference;
        final cards = <({Rect rect, DashboardWidgetSpec spec})>[];
        final headings = <({double top, String title})>[];
        var top = 0.0;
        for (final section in sections) {
          final heading = section.heading;
          if (heading != null) {
            headings.add((top: top, title: heading));
            top += _sectionHeading;
          }
          for (var index = 0; index < section.widgets.length; index++) {
            final placement = section.slots[index].placement;
            cards.add(
              (
                rect: Rect.fromLTWH(
                  padding + metrics.leftOf(placement.column) * scale,
                  padding + (top + metrics.topOf(placement.row)) * scale,
                  math.max(2, metrics.widthOf(placement.columnSpan) * scale),
                  math.max(2, metrics.heightOf(placement.rowSpan) * scale),
                ),
                spec: section.widgets[index],
              ),
            );
          }
          top += dashboardLayoutHeight(section.slots) * step + density.gap;
        }
        // Positioned children never size a stack; this one does.
        final extent = SizedBox(
          width: constraints.maxWidth,
          height: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : padding * 2 + top * scale,
        );
        return ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.84, 1],
            ).createShader(bounds),
            child: Stack(
              key: const ValueKey('dashboard-miniature'),
              children: [
                extent,
                for (final heading in headings)
                  Positioned(
                    left: padding,
                    top: padding + heading.top * scale,
                    right: padding,
                    child: Text(
                      heading.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.sectionLabel(palette).copyWith(
                        fontSize: math.max(6.5, 12 * scale * 1.6),
                      ),
                    ),
                  ),
                for (final card in cards)
                  Positioned.fromRect(
                    rect: card.rect,
                    child: _MiniatureCard(
                      spec: card.spec,
                      palette: palette,
                      scale: scale,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniatureCard extends StatelessWidget {
  const _MiniatureCard({
    required this.spec,
    required this.palette,
    required this.scale,
  });

  final DashboardWidgetSpec spec;
  final DashboardPalette palette;
  final double scale;

  static const _textTypes = {
    'heading',
    'text',
    'quote',
    'callout',
    'sticky_note',
  };

  @override
  Widget build(BuildContext context) {
    final definition = DashboardWidgetRegistry.definitionFor(spec.type);
    // The miniature wears what the widget wears on the board: a sheet, a
    // wash of colour, a gradient, or nothing at all.
    final appearance = dashboardAppearanceOf(spec, palette);
    final tone = appearance.tone;
    final words =
        _textTypes.contains(spec.type) ? spec.setting('text').trim() : '';
    final label = spec.title.trim().isNotEmpty
        ? spec.title.trim()
        : definition?.label() ?? spec.type;
    final radius = math.max(2.0, DashboardMetrics.cardRadius * scale * 1.4);
    if (spec.type == 'heading') {
      // A heading is words on the board, not a card: draw the words.
      return LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            words.isNotEmpty ? words : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardType.title(palette, size: 20).copyWith(
              color: tone.ink,
              fontSize: (constraints.maxHeight * 0.62).clamp(6.0, 20.0),
              height: 1.1,
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final roomy = height >= 22 && width >= 34;
        final glyph = math.min(16.0, math.max(8.0, height * 0.32));
        final surface = appearance.surface;
        final gradient = !appearance.media &&
                surface == DashboardSurface.gradient &&
                tone.gradient.length > 1
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tone.gradient,
              )
            : null;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: appearance.media
                ? tone.surface.withValues(alpha: 0.45)
                : surface == DashboardSurface.plain || gradient != null
                    ? null
                    : tone.surface,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: surface == DashboardSurface.floating || appearance.media
                ? Border.all(color: tone.border, width: 0.6)
                : null,
          ),
          child: !roomy
              ? const SizedBox.expand()
              : Padding(
                  padding: EdgeInsets.all(math.min(6, height * 0.12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          WorkspaceGlyph(
                            definition?.icon ?? Icons.widgets_rounded,
                            size: glyph,
                            color: palette.strongFor(appearance.accent),
                          ),
                          SizedBox(width: math.max(2, glyph * 0.3)),
                          Expanded(
                            child: Text(
                              words.isNotEmpty && spec.type == 'heading'
                                  ? words
                                  : label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashboardType.cardTitle(
                                palette,
                                color: tone.inkSoft,
                              ).copyWith(fontSize: math.max(6.5, glyph * 0.72)),
                            ),
                          ),
                        ],
                      ),
                      if (words.isNotEmpty &&
                          spec.type != 'heading' &&
                          height >= 40) ...[
                        SizedBox(height: math.max(2, glyph * 0.25)),
                        Expanded(
                          child: Text(
                            words,
                            overflow: TextOverflow.fade,
                            style: DashboardType.body(
                              palette,
                              color: tone.ink,
                            ).copyWith(
                              fontSize: math.max(6, glyph * 0.62),
                              height: 1.25,
                            ),
                          ),
                        ),
                      ] else if (_sketchOf(spec.type) case final sketch?
                          when height >= 34) ...[
                        SizedBox(height: math.max(2, glyph * 0.35)),
                        Expanded(
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _SketchPainter(
                              sketch: sketch,
                              color: palette.strongFor(appearance.accent),
                              faint: tone.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// A shape that says what a card draws, small enough for a miniature.
enum _Sketch { line, donut, bars, rows, tiles, payoff, ring, mirror, figure }

_Sketch? _sketchOf(String type) => switch (type) {
      'trend' || 'portfolio' || 'net_worth' || 'chart' => _Sketch.line,
      'allocation' => _Sketch.donut,
      'heatmap' ||
      'pnl_calendar' ||
      'calendar' ||
      'balance_sheet' =>
        _Sketch.tiles,
      'holdings' ||
      'watchlist' ||
      'list' ||
      'database' ||
      'reminders' =>
        _Sketch.rows,
      'options_book' || 'options_payoff' => _Sketch.payoff,
      'pnl_stats' || 'loans' || 'progress' => _Sketch.ring,
      'option_chain' => _Sketch.mirror,
      'options_summary' || 'metric' || 'counter' => _Sketch.figure,
      'quote_wall' || 'quote_spotlight' => _Sketch.bars,
      _ => null,
    };

class _SketchPainter extends CustomPainter {
  const _SketchPainter({
    required this.sketch,
    required this.color,
    required this.faint,
  });

  final _Sketch sketch;
  final Color color;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 6) {
      return;
    }
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, h * 0.04)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final soft = Paint()..color = color.withValues(alpha: 0.18);
    final muted = Paint()..color = faint.withValues(alpha: 0.22);
    switch (sketch) {
      case _Sketch.line:
        const shape = [0.72, 0.6, 0.66, 0.44, 0.5, 0.3, 0.36, 0.14];
        final points = [
          for (var i = 0; i < shape.length; i++)
            Offset(w * i / (shape.length - 1), h * shape[i]),
        ];
        final line = Path()..addPolygon(points, false);
        canvas
          ..drawPath(
            Path.from(line)
              ..lineTo(w, h)
              ..lineTo(0, h)
              ..close(),
            soft,
          )
          ..drawPath(line, stroke);
      case _Sketch.donut:
        final radius = math.min(w, h) * 0.42;
        final centre = Offset(w / 2, h / 2);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.42
          ..strokeCap = StrokeCap.butt;
        var start = -math.pi / 2;
        for (final (share, alpha) in const [
          (0.46, 1.0),
          (0.24, 0.7),
          (0.18, 0.45),
          (0.12, 0.25),
        ]) {
          final sweep = share * math.pi * 2;
          canvas.drawArc(
            Rect.fromCircle(center: centre, radius: radius),
            start + 0.06,
            sweep - 0.12,
            false,
            ring..color = color.withValues(alpha: alpha),
          );
          start += sweep;
        }
      case _Sketch.bars:
      case _Sketch.rows:
        final count = math.max(2, math.min(5, (h / 9).floor()));
        final gap = h / count;
        for (var i = 0; i < count; i++) {
          final top = i * gap + gap * 0.25;
          final barHeight = gap * (sketch == _Sketch.rows ? 0.34 : 0.4);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, top, w, barHeight),
              Radius.circular(barHeight / 2),
            ),
            muted,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, top, w * (0.86 - i * 0.14), barHeight),
              Radius.circular(barHeight / 2),
            ),
            soft..color = color.withValues(alpha: 0.32),
          );
        }
      case _Sketch.tiles:
        const columns = 7;
        final rows = math.max(2, math.min(4, (h / (w / columns)).floor()));
        final cell = math.min(w / columns, h / rows);
        for (var row = 0; row < rows; row++) {
          for (var column = 0; column < columns; column++) {
            final strength = ((row * 3 + column * 5) % 7) / 7;
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  column * cell + cell * 0.1,
                  row * cell + cell * 0.1,
                  cell * 0.8,
                  cell * 0.8,
                ),
                Radius.circular(cell * 0.2),
              ),
              Paint()..color = color.withValues(alpha: 0.12 + strength * 0.5),
            );
          }
        }
      case _Sketch.payoff:
        final zero = h * 0.62;
        final shape = Path()
          ..moveTo(0, h * 0.95)
          ..lineTo(w * 0.3, h * 0.95)
          ..lineTo(w * 0.42, h * 0.2)
          ..lineTo(w * 0.58, h * 0.2)
          ..lineTo(w * 0.7, h * 0.95)
          ..lineTo(w, h * 0.95);
        canvas
          ..drawLine(Offset(0, zero), Offset(w, zero), muted..strokeWidth = 1)
          ..drawPath(
            Path.from(shape)
              ..lineTo(w, zero)
              ..lineTo(0, zero)
              ..close(),
            soft,
          )
          ..drawPath(shape, stroke);
      case _Sketch.ring:
        final radius = math.min(w, h) * 0.4;
        final centre = Offset(math.min(w / 2, radius * 1.4), h / 2);
        final width = radius * 0.32;
        canvas
          ..drawCircle(
            centre,
            radius,
            Paint()
              ..color = faint.withValues(alpha: 0.18)
              ..style = PaintingStyle.stroke
              ..strokeWidth = width,
          )
          ..drawArc(
            Rect.fromCircle(center: centre, radius: radius),
            -math.pi / 2,
            math.pi * 1.3,
            false,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round,
          );
        if (w > radius * 4) {
          final left = centre.dx + radius * 1.8;
          for (var i = 0; i < 3; i++) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(left, h * (0.22 + i * 0.22), w - left, h * 0.08),
                Radius.circular(h * 0.04),
              ),
              muted,
            );
          }
        }
      case _Sketch.mirror:
        final count = math.max(3, math.min(7, (h / 6).floor()));
        final gap = h / count;
        for (var i = 0; i < count; i++) {
          final depth = 1 - (i - count / 2).abs() / count;
          final barHeight = gap * 0.5;
          final top = i * gap + gap * 0.25;
          canvas
            ..drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTRB(
                  w / 2 - w * 0.46 * depth,
                  top,
                  w / 2 - 1,
                  top + barHeight,
                ),
                Radius.circular(barHeight / 2),
              ),
              Paint()..color = color.withValues(alpha: 0.55),
            )
            ..drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTRB(
                  w / 2 + 1,
                  top,
                  w / 2 + w * 0.42 * (1.1 - depth),
                  top + barHeight,
                ),
                Radius.circular(barHeight / 2),
              ),
              Paint()..color = faint.withValues(alpha: 0.4),
            );
        }
      case _Sketch.figure:
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, h * 0.12, w * 0.55, h * 0.3),
              Radius.circular(h * 0.08),
            ),
            Paint()..color = color.withValues(alpha: 0.7),
          )
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, h * 0.58, w * 0.32, h * 0.14),
              Radius.circular(h * 0.07),
            ),
            muted,
          );
    }
  }

  @override
  bool shouldRepaint(_SketchPainter oldDelegate) =>
      oldDelegate.sketch != sketch ||
      oldDelegate.color != color ||
      oldDelegate.faint != faint;
}

/// What a board preview says when there is nothing on the board yet.
class BoardPreviewEmptyNote extends StatelessWidget {
  const BoardPreviewEmptyNote({
    super.key,
    required this.icon,
    required this.message,
    this.compact = false,
  });

  final IconData icon;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(WorkspaceTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceGlyph(
                icon,
                size: compact ? 40 : 30,
                color: palette.mutedText,
              ),
              const SizedBox(height: WorkspaceTokens.space2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
