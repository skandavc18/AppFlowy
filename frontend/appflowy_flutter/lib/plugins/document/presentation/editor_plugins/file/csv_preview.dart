import 'dart:convert';

import 'package:flutter/material.dart';

/// A read-only delimited preview that mounts only visible rows and their cache.
class CsvPreview extends StatefulWidget {
  const CsvPreview({super.key, required this.text, required this.separator});

  final String text;
  final String separator;

  @override
  State<CsvPreview> createState() => _CsvPreviewState();
}

class _CsvPreviewState extends State<CsvPreview> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  late List<List<String>> _rows;
  int _columnCount = 0;
  List<double>? _widths;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant CsvPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.separator != widget.separator) {
      _parse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widths = null;
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _parse() {
    _rows = const LineSplitter()
        .convert(widget.text)
        .take(1000)
        .map((line) => line.split(widget.separator))
        .toList(growable: false);
    _columnCount =
        _rows.fold(0, (count, row) => row.length > count ? row.length : count);
    _widths = null;
  }

  List<double> _measureWidths() {
    final widths = List<double>.filled(_columnCount, 96);
    final inherited = DefaultTextStyle.of(context).style;
    final style = MediaQuery.boldTextOf(context)
        ? inherited.merge(const TextStyle(fontWeight: FontWeight.bold))
        : inherited;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    try {
      // Bound shaping work, not the data: later columns still get a width.
      for (final row in _rows.take(32)) {
        for (var column = 0; column < row.length; column++) {
          painter.text = TextSpan(text: row[column], style: style);
          painter.layout();
          final width = (painter.width + 16).clamp(96.0, 280.0).toDouble();
          if (width > widths[column]) {
            widths[column] = width;
          }
        }
      }
      return widths;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return const Center(child: Text('This table is empty.'));
    }
    final widths = _widths ??= _measureWidths();
    final columnWidths = {
      for (var i = 0; i < widths.length; i++) i: FixedColumnWidth(widths[i]),
    };
    final width = widths.fold(24.0, (sum, width) => sum + width);
    final side = BorderSide(color: Theme.of(context).dividerColor);
    final rows = ListView.builder(
      controller: _vertical,
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      itemBuilder: (context, row) => Table(
        columnWidths: columnWidths,
        border: TableBorder(
          // The previous row owns the shared horizontal line.
          top: row == 0 ? side : BorderSide.none,
          bottom: side,
          left: side,
          right: side,
          verticalInside: side,
        ),
        children: [
          TableRow(
            children: [
              for (var column = 0; column < _columnCount; column++)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    column < _rows[row].length ? _rows[row][column] : '',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.hasBoundedHeight ? constraints.maxHeight : 400.0;
        return SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : width,
          height: height,
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _vertical,
              notificationPredicate: (notification) =>
                  notification.depth == 1 &&
                  notification.metrics.axis == Axis.vertical,
              child: Scrollbar(
                controller: _horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, height: height, child: rows),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
