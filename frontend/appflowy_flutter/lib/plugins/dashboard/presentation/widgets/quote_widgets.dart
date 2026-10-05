import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_binding.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_common.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_entry_dialog.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/finance/finance_row_writer.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:appflowy/workspace/application/finance/quote_model.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

void registerQuoteWidgets() {
  DashboardWidgetRegistry.register(_spotlight);
  DashboardWidgetRegistry.register(_wall);
}

const _keyWhich = 'which';
const _keyRotate = 'rotate';

/// The face quotes are set in: a book face where the platform has one.
const quoteFontFamily = 'Georgia';
const quoteFontFallback = ['Cambria', 'Palatino Linotype', 'Times New Roman'];

/// How a quote of [length] is set: short lines large and italic, long
/// passages upright at a reading size with generous leading.
TextStyle quoteStyle(QuoteLength length, Color color, {double? size}) {
  final (base, height, italic) = switch (length) {
    QuoteLength.short => (30.0, 1.28, true),
    QuoteLength.medium => (23.0, 1.42, true),
    QuoteLength.long => (18.0, 1.6, false),
    QuoteLength.epic => (16.0, 1.65, false),
  };
  return TextStyle(
    fontFamily: quoteFontFamily,
    fontFamilyFallback: quoteFontFallback,
    fontSize: size ?? base,
    height: height,
    letterSpacing: -0.1,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: color,
  );
}

/// The largest size between [minimum] and [maximum] at which [text] fits
/// [box], or [minimum] when it does not fit even then.
double fitQuoteFontSize({
  required String text,
  required TextStyle style,
  required Size box,
  required TextScaler scaler,
  double minimum = 13,
  double maximum = 30,
}) {
  if (box.width <= 0 || box.height <= 0) {
    return minimum;
  }
  bool fits(double size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: box.width);
    final fits = painter.height <= box.height;
    painter.dispose();
    return fits;
  }

  if (fits(maximum)) {
    return maximum;
  }
  if (!fits(minimum)) {
    return minimum;
  }
  var low = minimum;
  var high = maximum;
  for (var step = 0; step < 10; step++) {
    final middle = (low + high) / 2;
    if (fits(middle)) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return low.floorToDouble();
}

/// Where a table keeps whether a quote is a favourite, by field id.
String? _favouriteColumn(DashboardWidgetContext data, ChartTable table) {
  final columns = FinanceColumns.resolve(
    table,
    QuoteRoles.all,
    settings: data.spec.settings,
  );
  return FinanceSheet(table).fieldId(columns[QuoteRoles.favourite]);
}

Widget _pickQuotes(DashboardWidgetContext data) => FinanceGhost(
      palette: data.palette,
      shape: FinanceGhostShape.quote,
      icon: Icons.format_quote_rounded,
      message: LocaleKeys.dashboard_money_pickQuotes.tr(),
      action:
          data.isTypable ? LocaleKeys.dashboard_money_chooseTable.tr() : null,
      onAction: () => unawaited(financePickTable(data)),
      color: data.tone.strong,
    );

List<DashboardConfigField> _quoteColumns(DashboardWidgetContext data) => [
      financeColumnsField(data, [
        (QuoteRoles.text, LocaleKeys.dashboard_money_quote.tr()),
        (QuoteRoles.author, LocaleKeys.dashboard_money_author.tr()),
        (QuoteRoles.source, LocaleKeys.dashboard_money_source.tr()),
        (QuoteRoles.themes, LocaleKeys.dashboard_money_theme.tr()),
        (QuoteRoles.favourite, LocaleKeys.dashboard_money_favourite.tr()),
      ]),
    ];

/// A round button that can carry any glyph, for the reading controls.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.palette,
    this.color,
    this.size = 32,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final DashboardPalette palette;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: FinanceHover(
          onTap: onTap,
          builder: (context, hovered) => AnimatedContainer(
            duration: DashboardMetrics.hover,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hovered
                  ? (palette.isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.75))
                  : (palette.isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.35)),
            ),
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: hovered ? 1.1 : 1,
              duration: DashboardMetrics.hover,
              child: Icon(
                icon,
                size: size * 0.5,
                color: color ?? palette.textSecondary,
              ),
            ),
          ),
        ),
      );
}

/// Opens [quote] to be read in full.
void showQuoteReading(
  BuildContext context, {
  required QuoteEntry quote,
  required DashboardPalette palette,
  required Color hue,
}) {
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: palette.isDark ? 0.55 : 0.3),
      builder: (dialogContext) => _QuoteReading(
        quote: quote,
        palette: palette,
        hue: hue,
      ),
    ),
  );
}

class _QuoteReading extends StatefulWidget {
  const _QuoteReading({
    required this.quote,
    required this.palette,
    required this.hue,
  });

  final QuoteEntry quote;
  final DashboardPalette palette;
  final Color hue;

  @override
  State<_QuoteReading> createState() => _QuoteReadingState();
}

class _QuoteReadingState extends State<_QuoteReading> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final quote = widget.quote;
    final colors = FinanceColors.of(palette);
    final body = quote.body;
    return Dialog(
      backgroundColor: palette.raised,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: -26,
              child: Text(
                '“',
                style: TextStyle(
                  fontFamily: quoteFontFamily,
                  fontFamilyFallback: quoteFontFallback,
                  fontSize: 200,
                  height: 1,
                  color: widget.hue.withValues(alpha: 0.12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 44, 40, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        body,
                        style: quoteStyle(
                          QuoteLength.of(body) == QuoteLength.short
                              ? QuoteLength.medium
                              : QuoteLength.long,
                          palette.textPrimary,
                          size: QuoteLength.of(body) == QuoteLength.short
                              ? 26
                              : 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      if (quote.author.isNotEmpty) ...[
                        FinanceAvatar(
                          label: quote.author,
                          colors: colors,
                          color: widget.hue,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (quote.author.isNotEmpty)
                              Text(
                                quote.author,
                                style: financeLabel(
                                  palette.textPrimary,
                                  size: 14,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            if (quote.source.isNotEmpty)
                              Text(
                                quote.source,
                                style: financeLabel(
                                  palette.textMuted,
                                  size: 12.5,
                                ).copyWith(fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),
                      _RoundButton(
                        icon: _copied
                            ? Icons.check_rounded
                            : Icons.content_copy_rounded,
                        tooltip: _copied
                            ? LocaleKeys.dashboard_money_copied.tr()
                            : LocaleKeys.dashboard_money_copyQuote.tr(),
                        palette: palette,
                        onTap: () async {
                          final attribution = [
                            if (quote.author.isNotEmpty) quote.author,
                            if (quote.source.isNotEmpty) quote.source,
                          ].join(', ');
                          await Clipboard.setData(
                            ClipboardData(
                              text: attribution.isEmpty
                                  ? '“$body”'
                                  : '“$body”\n— $attribution',
                            ),
                          );
                          if (mounted) {
                            setState(() => _copied = true);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _RoundButton(
                        icon: Icons.close_rounded,
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        palette: palette,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Remembers favourites somebody just toggled, until the table catches up.
mixin _Favourites<T extends StatefulWidget> on State<T> {
  final Map<String, bool> _pending = {};

  bool isFavourite(QuoteEntry quote) =>
      _pending[quote.rowId ?? ''] ?? quote.favourite;

  void reconcile(List<QuoteEntry> quotes) {
    for (final quote in quotes) {
      final wanted = _pending[quote.rowId ?? ''];
      if (wanted != null && wanted == quote.favourite) {
        _pending.remove(quote.rowId);
      }
    }
  }

  Future<void> toggleFavourite(
    DashboardWidgetContext data,
    ChartTable table,
    QuoteEntry quote,
  ) async {
    final rowId = quote.rowId;
    final column = _favouriteColumn(data, table);
    if (rowId == null || column == null || !data.isTypable) {
      return;
    }
    final next = !isFavourite(quote);
    setState(() => _pending[rowId] = next);
    final done = await FinanceRowWriter(data.spec.source.viewId)
        .write(rowId, column, next ? 'Yes' : 'No');
    if (!done && mounted) {
      setState(() => _pending.remove(rowId));
    }
  }
}

// ---------------------------------------------------------------- spotlight

final _spotlight = DashboardWidgetDefinition(
  type: 'quote_spotlight',
  label: () => LocaleKeys.dashboard_money_quoteSpotlight.tr(),
  description: () => LocaleKeys.dashboard_money_quoteSpotlightHint.tr(),
  icon: Icons.auto_stories_rounded,
  group: DashboardWidgetGroup.text,
  defaultColumnSpan: 8,
  defaultRowSpan: 7,
  minimumColumnSpan: 3,
  minimumRowSpan: 3,
  surface: DashboardSurface.gradient,
  identity: DashboardAccent.amber,
  showsTitleByDefault: false,
  padding: EdgeInsets.zero,
  defaultSettings: const {_keyWhich: 'daily', _keyRotate: 0},
  keywords: const [
    'quote of the day',
    'quotes',
    'inspiration',
    'wisdom',
    'daily',
    'commonplace',
  ],
  builder: (data) => _Spotlight(data: data),
  configure: (data) => [
    financeTableField(data),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_money_which.tr(),
      value: data.spec.setting(_keyWhich, fallback: 'daily'),
      choices: [
        DashboardChoice(
          value: 'daily',
          label: LocaleKeys.dashboard_money_whichDaily.tr(),
        ),
        DashboardChoice(
          value: 'favourites',
          label: LocaleKeys.dashboard_money_whichFavourites.tr(),
        ),
        DashboardChoice(
          value: 'all',
          label: LocaleKeys.dashboard_money_whichAll.tr(),
        ),
      ],
      onChanged: (value) => data.setSettings({_keyWhich: value}),
    ),
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_money_shuffle.tr(),
      value: data.spec.number(_keyRotate, fallback: 0),
      minimum: 0,
      maximum: 3600,
      step: 15,
      suffix: 's',
      onChanged: (value) => data.setSettings({_keyRotate: value.round()}),
    ),
    ..._quoteColumns(data),
  ],
);

class _Spotlight extends StatefulWidget {
  const _Spotlight({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> with _Favourites {
  final _random = math.Random();
  int _offset = 0;
  int? _shuffled;
  bool _forward = true;
  Timer? _rotation;
  int _rotationSeconds = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRotation();
  }

  @override
  void didUpdateWidget(_Spotlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRotation();
  }

  void _syncRotation() {
    final seconds = widget.data.spec.integer(_keyRotate, fallback: 0);
    final still = financeStill(widget.data, context);
    final wanted = still ? 0 : seconds;
    if (wanted == _rotationSeconds) {
      return;
    }
    _rotationSeconds = wanted;
    _rotation?.cancel();
    _rotation = wanted <= 0
        ? null
        : Timer.periodic(Duration(seconds: math.max(5, wanted)), (_) {
            if (mounted) {
              setState(() {
                _forward = true;
                _offset++;
              });
            }
          });
  }

  @override
  void dispose() {
    _rotation?.cancel();
    super.dispose();
  }

  void _step(int by) => setState(() {
        _forward = by > 0;
        _offset += by;
      });

  void _shuffle(int count) {
    if (count < 2) {
      return;
    }
    setState(() {
      _forward = true;
      _shuffled = _random.nextInt(count);
      _offset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      builder: (context, feed) {
        if (!feed.bound) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _pickQuotes(data),
          );
        }
        if (feed.loading) {
          return Center(
            child: FinanceShimmer(palette: palette, width: 220, still: still),
          );
        }
        final quotes = readQuotes(feed.table, settings: data.spec.settings);
        reconcile(quotes);
        final which = data.spec.setting(_keyWhich, fallback: 'daily');
        var pool =
            which == 'favourites' ? quotes.where(isFavourite).toList() : quotes;
        if (pool.isEmpty) {
          pool = quotes;
        }
        if (pool.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _pickQuotes(data),
          );
        }
        final count = pool.length;
        final base = _shuffled ??
            (which == 'all'
                ? 0
                : quoteOfTheDay(
                    count,
                    DateTime.now(),
                    salt: data.spec.id.hashCode & 0xffff,
                  ));
        final index = ((base + _offset) % count + count) % count;
        final quote = pool[index];
        final hue = data.tone.strong;
        final canFavourite = data.isTypable &&
            quote.rowId != null &&
            _favouriteColumn(data, feed.table) != null;
        final eyebrow = which == 'favourites'
            ? LocaleKeys.dashboard_money_favourites.tr()
            : LocaleKeys.dashboard_money_quoteSpotlight.tr();
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 210;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 10,
                  top: -30,
                  child: IgnorePointer(
                    child: Text(
                      '“',
                      style: TextStyle(
                        fontFamily: quoteFontFamily,
                        fontFamilyFallback: quoteFontFallback,
                        fontSize: math.min(200, constraints.maxHeight * 0.75),
                        height: 1,
                        color:
                            hue.withValues(alpha: palette.isDark ? 0.16 : 0.14),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 18 : 30,
                    compact ? 14 : 22,
                    compact ? 16 : 24,
                    compact ? 12 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FinanceEyebrow(
                              eyebrow,
                              color: data.tone.label,
                            ),
                          ),
                          if (!compact)
                            for (final theme in quote.themes.take(2))
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _ThemeChip(
                                  label: theme,
                                  color: colors.hueFor(theme),
                                  palette: palette,
                                ),
                              ),
                        ],
                      ),
                      SizedBox(height: compact ? 6 : 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: still
                              ? Duration.zero
                              : const Duration(milliseconds: 520),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: [
                              ...previous,
                              if (current != null) current,
                            ],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(0, _forward ? 0.06 : -0.06),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: _FittedQuote(
                            key: ValueKey(
                              '${quote.rowId}|$index|${quote.text.hashCode}',
                            ),
                            quote: quote,
                            color: data.tone.ink,
                            hue: hue,
                            palette: palette,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 12),
                      Row(
                        children: [
                          if (quote.author.isNotEmpty && !compact) ...[
                            FinanceAvatar(
                              label: quote.author,
                              colors: colors,
                              color: hue,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (quote.author.isNotEmpty)
                                  Text(
                                    quote.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: financeLabel(
                                      palette.textPrimary,
                                      size: 13,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                if (quote.source.isNotEmpty && !compact)
                                  Text(
                                    quote.source,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: financeLabel(
                                      palette.textMuted,
                                    ).copyWith(fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          ),
                          if (count > 1) ...[
                            _RoundButton(
                              icon: Icons.chevron_left_rounded,
                              tooltip:
                                  LocaleKeys.dashboard_money_previousQuote.tr(),
                              palette: palette,
                              onTap: () => _step(-1),
                            ),
                            const SizedBox(width: 4),
                            if (!compact) ...[
                              _RoundButton(
                                icon: Icons.shuffle_rounded,
                                tooltip:
                                    LocaleKeys.dashboard_money_shuffle.tr(),
                                palette: palette,
                                onTap: () => _shuffle(count),
                              ),
                              const SizedBox(width: 4),
                            ],
                            _RoundButton(
                              icon: Icons.chevron_right_rounded,
                              tooltip:
                                  LocaleKeys.dashboard_money_nextQuote.tr(),
                              palette: palette,
                              onTap: () => _step(1),
                            ),
                          ],
                          if (canFavourite) ...[
                            const SizedBox(width: 4),
                            _RoundButton(
                              icon: isFavourite(quote)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              tooltip: isFavourite(quote)
                                  ? LocaleKeys.dashboard_money_unfavourite.tr()
                                  : LocaleKeys.dashboard_money_favourite.tr(),
                              palette: palette,
                              color: isFavourite(quote)
                                  ? const Color(0xFFE5484D)
                                  : null,
                              onTap: () => unawaited(
                                toggleFavourite(data, feed.table, quote),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A quote set as large as its box allows. A passage too long even at a
/// reading size fades out at the bottom with a way to read it all.
class _FittedQuote extends StatelessWidget {
  const _FittedQuote({
    super.key,
    required this.quote,
    required this.color,
    required this.hue,
    required this.palette,
  });

  final QuoteEntry quote;
  final Color color;
  final Color hue;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) {
    final body = quote.body;
    final length = QuoteLength.of(body);
    final base = quoteStyle(length, color);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const moreHeight = 26.0;
        final box = constraints.biggest;
        final size = fitQuoteFontSize(
          text: body,
          style: base,
          box: box,
          scaler: scaler,
          minimum: 14,
          maximum: base.fontSize!,
        );
        final style = base.copyWith(fontSize: size);
        final painter = TextPainter(
          text: TextSpan(text: body, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: box.width);
        final overflows = painter.height > box.height;
        final lineHeight = painter.preferredLineHeight;
        painter.dispose();
        if (!overflows) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(body, style: style),
          );
        }
        final lines = math.max(
          1,
          ((box.height - moreHeight) / math.max(1, lineHeight)).floor(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, 0.72, 1],
                ).createShader(bounds),
                child: Text(
                  body,
                  style: style,
                  maxLines: lines,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
            SizedBox(
              height: moreHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FinanceHover(
                  onTap: () => showQuoteReading(
                    context,
                    quote: quote,
                    palette: palette,
                    hue: hue,
                  ),
                  builder: (context, hovered) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        LocaleKeys.dashboard_money_readMore.tr(),
                        style: financeLabel(
                          hue,
                          size: 12.5,
                          weight: FontWeight.w600,
                        ).copyWith(
                          decoration: hovered
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: hue,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: hue),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.color,
    required this.palette,
    this.selected = false,
    this.onTap,
    this.count,
    this.icon,
  });

  final String label;
  final Color color;
  final DashboardPalette palette;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;

  /// Drawn before the label; a glyph in the text would depend on the font
  /// having it.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink =
        Color.lerp(color, palette.textPrimary, palette.isDark ? 0.2 : 0.35)!;
    final text = Text(
      count == null ? label : '$label  $count',
      maxLines: 1,
      style: financeLabel(
        ink,
        size: 11,
        weight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
    );
    final chip = AnimatedContainer(
      duration: DashboardMetrics.hover,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: selected
              ? (palette.isDark ? 0.32 : 0.2)
              : (palette.isDark ? 0.16 : 0.1),
        ),
        borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
        border: Border.all(
          color: color.withValues(alpha: selected ? 0.6 : 0),
        ),
      ),
      child: icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 4),
                text,
              ],
            ),
    );
    final onTap = this.onTap;
    return onTap == null
        ? chip
        : FinanceHover(onTap: onTap, builder: (_, __) => chip);
  }
}

// --------------------------------------------------------------------- wall

final _wall = DashboardWidgetDefinition(
  type: 'quote_wall',
  label: () => LocaleKeys.dashboard_money_quoteWall.tr(),
  description: () => LocaleKeys.dashboard_money_quoteWallHint.tr(),
  icon: Icons.dashboard_rounded,
  group: DashboardWidgetGroup.text,
  defaultColumnSpan: 12,
  defaultRowSpan: 12,
  minimumColumnSpan: 4,
  minimumRowSpan: 5,
  identity: DashboardAccent.amber,
  surface: DashboardSurface.plain,
  showsTitleByDefault: false,
  keywords: const [
    'quotes',
    'quote wall',
    'collection',
    'masonry',
    'commonplace book',
    'highlights',
  ],
  builder: (data) => _Wall(data: data),
  configure: (data) => [
    financeTableField(data),
    ..._quoteColumns(data),
  ],
);

class _Wall extends StatefulWidget {
  const _Wall({required this.data});

  final DashboardWidgetContext data;

  @override
  State<_Wall> createState() => _WallState();
}

class _WallState extends State<_Wall> with _Favourites {
  final TextEditingController _search = TextEditingController();
  String? _theme;
  bool _favouritesOnly = false;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final palette = data.palette;
    final colors = FinanceColors.of(palette);
    final still = financeStill(data, context);
    return FinanceView(
      data: data,
      builder: (context, feed) {
        if (!feed.bound) {
          return _pickQuotes(data);
        }
        if (feed.loading) {
          return Center(
            child: FinanceShimmer(palette: palette, width: 220, still: still),
          );
        }
        final quotes = readQuotes(feed.table, settings: data.spec.settings);
        reconcile(quotes);
        final themes = <String, int>{};
        for (final quote in quotes) {
          for (final theme in quote.themes) {
            themes[theme] = (themes[theme] ?? 0) + 1;
          }
        }
        final needle = _search.text.trim().toLowerCase();
        final shown = [
          for (final quote in quotes)
            if ((_theme == null || quote.themes.contains(_theme)) &&
                (!_favouritesOnly || isFavourite(quote)) &&
                (needle.isEmpty ||
                    quote.text.toLowerCase().contains(needle) ||
                    quote.author.toLowerCase().contains(needle) ||
                    quote.source.toLowerCase().contains(needle)))
              quote,
        ];
        final canFavourite =
            data.isTypable && _favouriteColumn(data, feed.table) != null;
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = financeColumnsFor(
              constraints.maxWidth,
              250,
              maximum: 5,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      SizedBox(
                        width: math.min(220, constraints.maxWidth * 0.36),
                        child: _SearchField(
                          controller: _search,
                          palette: palette,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Center(
                                child: _ThemeChip(
                                  label:
                                      LocaleKeys.dashboard_money_allThemes.tr(),
                                  color: data.tone.strong,
                                  palette: palette,
                                  selected: _theme == null && !_favouritesOnly,
                                  count: quotes.length,
                                  onTap: () => setState(() {
                                    _theme = null;
                                    _favouritesOnly = false;
                                  }),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Center(
                                child: _ThemeChip(
                                  label: LocaleKeys.dashboard_money_favourites
                                      .tr(),
                                  icon: Icons.favorite_rounded,
                                  color: const Color(0xFFE5484D),
                                  palette: palette,
                                  selected: _favouritesOnly,
                                  onTap: () => setState(
                                    () => _favouritesOnly = !_favouritesOnly,
                                  ),
                                ),
                              ),
                            ),
                            for (final entry in themes.entries)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Center(
                                  child: _ThemeChip(
                                    label: entry.key,
                                    color: colors.hueFor(entry.key),
                                    palette: palette,
                                    selected: _theme == entry.key,
                                    count: entry.value,
                                    onTap: () => setState(
                                      () => _theme = _theme == entry.key
                                          ? null
                                          : entry.key,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (data.isTypable) ...[
                        const SizedBox(width: 8),
                        DashboardButton(
                          label: LocaleKeys.dashboard_money_addQuote.tr(),
                          palette: palette,
                          icon: Icons.add_rounded,
                          onPressed: () =>
                              _addQuote(data, feed.table, themes.keys),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(
                            LocaleKeys.dashboard_money_noQuotesMatch.tr(),
                            style: DashboardType.caption(palette),
                          ),
                        )
                      : MasonryGridView.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final quote = shown[index];
                            final key = quote.rowId ?? '${quote.text.hashCode}';
                            return FinanceEntrance(
                              key: ValueKey(key),
                              index: index,
                              still: still,
                              child: _QuoteCard(
                                quote: quote,
                                favourite: isFavourite(quote),
                                expanded: _expanded.contains(key),
                                colors: colors,
                                accent: data.tone.strong,
                                onExpand: () => setState(() {
                                  if (!_expanded.remove(key)) {
                                    _expanded.add(key);
                                  }
                                }),
                                onOpen: () => showQuoteReading(
                                  context,
                                  quote: quote,
                                  palette: palette,
                                  hue: quote.themes.isEmpty
                                      ? data.tone.strong
                                      : colors.hueFor(quote.themes.first),
                                ),
                                onFavourite: canFavourite && quote.rowId != null
                                    ? () => unawaited(
                                          toggleFavourite(
                                            data,
                                            feed.table,
                                            quote,
                                          ),
                                        )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

void _addQuote(
  DashboardWidgetContext data,
  ChartTable table,
  Iterable<String> themes,
) {
  unawaited(
    showFinanceEntryDialog(
      context: data.context,
      palette: data.palette,
      title: LocaleKeys.dashboard_money_addQuote.tr(),
      icon: Icons.format_quote_rounded,
      color: data.tone.strong,
      fields: [
        FinanceEntryField(
          key: QuoteRoles.text.key,
          label: LocaleKeys.dashboard_money_quote.tr(),
          kind: FinanceFieldKind.multiline,
          required: true,
        ),
        FinanceEntryField(
          key: QuoteRoles.author.key,
          label: LocaleKeys.dashboard_money_author.tr(),
        ),
        FinanceEntryField(
          key: QuoteRoles.source.key,
          label: LocaleKeys.dashboard_money_source.tr(),
        ),
        FinanceEntryField(
          key: QuoteRoles.themes.key,
          label: LocaleKeys.dashboard_money_theme.tr(),
          kind: FinanceFieldKind.choice,
          options: themes.toList(),
          wide: true,
        ),
      ],
      onSave: (values) => financeAddRow(
        data,
        table,
        QuoteRoles.all,
        {
          ...values,
          QuoteRoles.added.key: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      ),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.palette});

  final TextEditingController controller;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => TextEntryShortcuts(
        child: TextField(
          controller: controller,
          style: DashboardType.body(palette).copyWith(fontSize: 12.5),
          cursorColor: palette.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: LocaleKeys.dashboard_money_searchQuotes.tr(),
            hintStyle: DashboardType.body(
              palette,
              color: palette.textMuted,
            ).copyWith(fontSize: 12.5),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 16,
              color: palette.textMuted,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 30),
            filled: true,
            fillColor: palette.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : palette.sunken,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.favourite,
    required this.expanded,
    required this.colors,
    required this.accent,
    required this.onExpand,
    required this.onOpen,
    required this.onFavourite,
  });

  final QuoteEntry quote;
  final bool favourite;
  final bool expanded;
  final FinanceColors colors;
  final Color accent;
  final VoidCallback onExpand;
  final VoidCallback onOpen;
  final VoidCallback? onFavourite;

  @override
  Widget build(BuildContext context) {
    final palette = colors.palette;
    final body = quote.body;
    final length = QuoteLength.of(body);
    final hue =
        quote.themes.isEmpty ? accent : colors.hueFor(quote.themes.first);
    final style = quoteStyle(
      length,
      palette.textPrimary,
      size: switch (length) {
        QuoteLength.short => 19,
        QuoteLength.medium => 15.5,
        QuoteLength.long => 14,
        QuoteLength.epic => 13.5,
      },
    );
    const clampLines = 9;
    return FinanceHover(
      onTap: onOpen,
      builder: (context, hovered) => AnimatedContainer(
        duration: DashboardMetrics.settle,
        curve: DashboardMetrics.curve,
        transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: colors.solidWash(
            hue,
            palette.isPaper ? palette.surface : palette.raised,
            palette.isDark ? 0.08 : 0.07,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hue.withValues(alpha: hovered ? 0.4 : 0.16),
          ),
          boxShadow: hovered
              ? colors.glow(hue, lifted: true, strength: 0.8)
              : [
                  BoxShadow(
                    color: palette.shadowColor.withValues(
                      alpha: palette.isDark ? 0.2 : 0.05,
                    ),
                    blurRadius: 10,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“',
              style: TextStyle(
                fontFamily: quoteFontFamily,
                fontFamilyFallback: quoteFontFallback,
                fontSize: 44,
                height: 1,
                color: hue.withValues(alpha: 0.55),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(text: body, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: clampLines,
                )..layout(maxWidth: constraints.maxWidth);
                final long = painter.didExceedMaxLines;
                painter.dispose();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSize(
                      duration: DashboardMetrics.settle,
                      curve: DashboardMetrics.curve,
                      alignment: Alignment.topCenter,
                      child: Text(
                        body,
                        style: style,
                        maxLines: long && !expanded ? clampLines : null,
                        overflow: long && !expanded
                            ? TextOverflow.fade
                            : TextOverflow.visible,
                      ),
                    ),
                    if (long)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FinanceHover(
                          onTap: onExpand,
                          builder: (context, hovered) => Text(
                            expanded
                                ? LocaleKeys.dashboard_money_showLess.tr()
                                : LocaleKeys.dashboard_money_readMore.tr(),
                            style: financeLabel(
                              hue,
                              size: 12,
                              weight: FontWeight.w600,
                            ).copyWith(
                              decoration: hovered
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: hue,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (quote.author.isNotEmpty) ...[
                  FinanceAvatar(
                    label: quote.author,
                    colors: colors,
                    color: hue,
                    size: 26,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (quote.author.isNotEmpty)
                        Text(
                          quote.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: financeLabel(
                            palette.textPrimary,
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                      if (quote.source.isNotEmpty)
                        Text(
                          quote.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: financeLabel(
                            palette.textMuted,
                            size: 11,
                          ).copyWith(fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                if (onFavourite != null || favourite)
                  _RoundButton(
                    icon: favourite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    tooltip: favourite
                        ? LocaleKeys.dashboard_money_unfavourite.tr()
                        : LocaleKeys.dashboard_money_favourite.tr(),
                    palette: palette,
                    size: 28,
                    color: favourite ? const Color(0xFFE5484D) : null,
                    onTap: onFavourite,
                  ),
              ],
            ),
            if (quote.themes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final theme in quote.themes)
                    _ThemeChip(
                      label: theme,
                      color: colors.hueFor(theme),
                      palette: palette,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
