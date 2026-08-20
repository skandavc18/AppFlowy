import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/dart/built_in/stock_chart.dart';
import 'package:appflowy/extensions/dart/built_in/stock_extension.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The dashboard card for a share price.
///
/// Bigger than the document block on purpose: a dashboard has room for the
/// chart, the period picker and a scrubbable line, which is what makes a price
/// worth looking at rather than merely reading.
const stockWidgetType = 'ext.stock.quote';

const _keySymbol = 'symbol';
const _keyRange = 'range';
const _keyShowChart = 'showChart';
const _keyShowPicker = 'showPicker';
const _keyFilled = 'filled';

DashboardWidgetDefinition stockDashboardWidget() => DashboardWidgetDefinition(
      type: stockWidgetType,
      extensionId: 'stock',
      label: () => 'Share price',
      description: () => 'A price, its move and a chart you can scrub',
      icon: Icons.trending_up_rounded,
      group: DashboardWidgetGroup.data,
      defaultColumnSpan: 6,
      defaultRowSpan: 6,
      minimumColumnSpan: 3,
      minimumRowSpan: 4,
      showsTitleByDefault: false,
      keywords: const ['stock', 'share', 'ticker', 'price', 'quote', 'market'],
      defaultSettings: const {
        _keySymbol: 'AAPL',
        _keyRange: 'month1',
        _keyShowChart: true,
        _keyShowPicker: true,
        _keyFilled: true,
      },
      builder: (context) => _StockCard(context: context),
      configure: (context) => [
        DashboardConfigText(
          label: 'Ticker',
          value: context.spec.setting(_keySymbol, fallback: 'AAPL'),
          placeholder: 'AAPL',
          hint:
              'RELIANCE.NS, TCS.NS, ^NSEI, BTC-USD — any symbol the service knows',
          onChanged: (value) => context.setSettings({
            _keySymbol: StockFeed.normalise(value),
          }),
        ),
        DashboardConfigButton(
          label: 'Search for a ticker…',
          icon: Icons.search_rounded,
          onPressed: () => _pickSymbol(context),
        ),
        DashboardConfigChoice(
          label: 'Period',
          value: context.spec.setting(_keyRange, fallback: 'month1'),
          choices: [
            for (final range in StockRange.values)
              DashboardChoice(
                value: range.name,
                label: range.label,
                description: range.caption,
              ),
          ],
          onChanged: (value) => context.setSettings({_keyRange: value}),
        ),
        DashboardConfigToggle(
          label: 'Show the chart',
          value: context.spec.flag(_keyShowChart, fallback: true),
          onChanged: (value) => context.setSettings({_keyShowChart: value}),
        ),
        DashboardConfigToggle(
          label: 'Fill under the line',
          value: context.spec.flag(_keyFilled, fallback: true),
          onChanged: (value) => context.setSettings({_keyFilled: value}),
        ),
        DashboardConfigToggle(
          label: 'Show the period picker',
          hint: 'Lets anyone reading the dashboard change the period',
          value: context.spec.flag(_keyShowPicker, fallback: true),
          onChanged: (value) => context.setSettings({_keyShowPicker: value}),
        ),
      ],
    );

/// Opens the same search the document block uses, and writes the choice back.
Future<void> _pickSymbol(DashboardWidgetContext context) async {
  final chosen = await showDialog<String>(
    context: context.context,
    builder: (_) => const _SymbolSearchDialog(),
  );
  if (chosen != null && chosen.isNotEmpty) {
    context.setSettings({_keySymbol: StockFeed.normalise(chosen)});
  }
}

class _SymbolSearchDialog extends StatefulWidget {
  const _SymbolSearchDialog();

  @override
  State<_SymbolSearchDialog> createState() => _SymbolSearchDialogState();
}

class _SymbolSearchDialogState extends State<_SymbolSearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Find a ticker'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: StockSymbolField(
              controller: _controller,
              autofocus: true,
              onSubmitted: _submit,
              onChosen: (_) => _submit(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Use')),
        ],
      );
}

class _StockCard extends StatefulWidget {
  const _StockCard({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<_StockCard> {
  /// Which point the pointer is over, or null when it is away.
  int? _scrubbed;

  String get _symbol =>
      widget.context.spec.setting(_keySymbol, fallback: 'AAPL');

  StockRange get _range => StockRange.named(
        widget.context.spec.setting(_keyRange, fallback: 'month1'),
      );

  @override
  void initState() {
    super.initState();
    _ensureFresh();
  }

  @override
  void didUpdateWidget(_StockCard old) {
    super.didUpdateWidget(old);
    _ensureFresh();
  }

  void _ensureFresh() {
    final feed = StockFeed.active;
    if (feed == null || _symbol.isEmpty) {
      return;
    }
    unawaited(feed.watch(_symbol, _range));
    unawaited(feed.refresh(_symbol, _range));
  }

  void _chooseRange(StockRange range) {
    // A reader changing the period is a real edit to the dashboard, so it goes
    // through the controller and is remembered.
    widget.context.setSettings({_keyRange: range.name});
    final feed = StockFeed.active;
    if (feed != null) {
      unawaited(feed.watch(_symbol, range));
      unawaited(feed.refresh(_symbol, range));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: ExtensionDataStore.instance.revision,
        builder: (context, _, __) => _build(context),
      );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = widget.context.tone;
    final spec = widget.context.spec;
    final symbol = _symbol;
    final range = _range;

    if (symbol.isEmpty) {
      return _message(context, 'Choose a ticker in the panel on the right.');
    }

    final entry = ExtensionDataStore.instance
        .entryFor(StockFeed.qualifiedQuoteKey(symbol, range));
    final stored = entry?.value;
    final quote = stored is Map
        ? StockQuote.fromJson(Map<String, Object?>.from(stored))
        : null;

    if (quote != null && quote.error.isNotEmpty) {
      return _message(context, quote.error, isError: true);
    }
    if (quote == null || quote.price == null) {
      return _message(context, 'Fetching $symbol…', spinner: true);
    }

    final showChart = spec.flag(_keyShowChart, fallback: true);
    final showPicker = spec.flag(_keyShowPicker, fallback: true);
    final filled = spec.flag(_keyFilled, fallback: true);

    final moved = quote.changeOver(range) ?? 0;
    final rising = moved >= 0;
    final accent = stockAccent(rising);
    final percent = quote.changePercentOver(range);

    final scrubbed = _scrubbed;
    final showing = scrubbed != null && scrubbed < quote.series.length
        ? quote.series[scrubbed]
        : quote.price!;
    final scrubbedAt = scrubbed == null ? null : quote.timeAt(scrubbed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                quote.symbol.isEmpty ? symbol : quote.symbol,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tone.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry != null)
              Text(
                _stampFor(entry.writtenAt, range),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tone.inkSoft,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              showing.toStringAsFixed(2),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: tone.ink,
                fontWeight: FontWeight.w600,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
            if (quote.currency.isNotEmpty) ...[
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  quote.currency,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: tone.inkSoft),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(
              rising
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              size: 20,
              color: accent,
            ),
            Flexible(
              child: Text(
                '${moved.abs().toStringAsFixed(2)}'
                '${percent == null ? '' : ' (${percent.abs().toStringAsFixed(2)}%)'}'
                ' · ${scrubbedAt == null ? range.caption : _scrubLabel(scrubbedAt, range)}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scrubbedAt == null ? accent : tone.inkSoft,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        if (showChart) ...[
          const SizedBox(height: 10),
          Expanded(
            child: quote.series.length < 2
                ? const SizedBox.shrink()
                : StockChart(
                    values: quote.series,
                    color: accent,
                    filled: filled,
                    baseline: quote.baselineFor(range),
                    scrubbed: _scrubbed,
                    onScrub: (index) {
                      if (index != _scrubbed) {
                        setState(() => _scrubbed = index);
                      }
                    },
                  ),
          ),
        ] else
          const Spacer(),
        if (showPicker) ...[
          const SizedBox(height: 8),
          StockRangePicker(
            selected: range,
            accent: accent,
            muted: tone.inkSoft,
            enabled: widget.context.isEditable || widget.context.isPresenting,
            onSelected: _chooseRange,
          ),
        ],
      ],
    );
  }

  Widget _message(
    BuildContext context,
    String text, {
    bool isError = false,
    bool spinner = false,
  }) {
    final theme = Theme.of(context);
    final tone = widget.context.tone;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          else
            Icon(
              isError ? Icons.cloud_off_rounded : Icons.trending_up_rounded,
              size: 16,
              color: isError ? theme.colorScheme.error : tone.inkSoft,
            ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isError ? theme.colorScheme.error : tone.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Intraday shows a clock; anything longer shows a date, because "14:32" on a
  /// five-year chart tells you nothing.
  static String _stampFor(DateTime at, StockRange range) =>
      range == StockRange.day1 || range == StockRange.day5
          ? DateFormat.Hm().format(at)
          : DateFormat.MMMd().format(at);

  static String _scrubLabel(DateTime at, StockRange range) =>
      range == StockRange.day1 || range == StockRange.day5
          ? DateFormat.MMMd().add_Hm().format(at)
          : DateFormat.yMMMd().format(at);
}
