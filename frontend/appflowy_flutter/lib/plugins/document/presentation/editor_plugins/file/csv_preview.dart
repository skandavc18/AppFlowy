import 'dart:convert';

import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter/material.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'csv_find.dart';

/// A read-only delimited preview that mounts only visible rows and their cache.
class CsvPreview extends StatefulWidget {
  const CsvPreview({super.key, required this.text, required this.separator});

  final String text;
  final String separator;

  @override
  State<CsvPreview> createState() => _CsvPreviewState();
}

class _CsvPreviewState extends State<CsvPreview> {
  final _vertical = LocalFileFindScrollController(suggestedRowHeight: 36);
  final _horizontal = ScrollController();
  late final _find = LocalFileFindController(
    canRead: () => _canRead,
    search: (query, options) => _canRead
        ? searchSurfaceEntries(csvFindEntries(_rows), query, options)
        : const [],
  );
  StandaloneFileScope? _host;
  bool _findOpen = false;
  int _binding = 0;
  late List<List<String>> _rows;
  int _columnCount = 0;
  List<double>? _widths;

  bool get _canRead =>
      mounted && (_host == null || (_host!.available && _host!.canRead()));

  @override
  void initState() {
    super.initState();
    _parse();
    _find.addListener(_findChanged);
  }

  @override
  void didUpdateWidget(covariant CsvPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.separator != widget.separator) {
      _binding++;
      _parse();
      _find.refresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host = StandaloneFileScope.maybeOf(context);
    _widths = null;
    if (!_canRead) _find.close();
  }

  void _findChanged() {
    // Only opening/closing changes padding. Queries repaint the permanently
    // mounted targets without rebuilding the table or its selection fields.
    if (mounted && _findOpen != _find.isOpen) {
      setState(() => _findOpen = _find.isOpen);
    }
  }

  Future<void> _reveal(SurfaceFindMatch hit) async {
    final id = hit.id;
    if (id is! CsvFindCell) return;
    final binding = _binding;
    bool current() =>
        _canRead &&
        binding == _binding &&
        _find.isOpen &&
        identical(_find.current, hit) &&
        TickerMode.of(context) &&
        ModalRoute.of(context)?.isCurrent != false;
    if (!current()) return;
    await _vertical.reveal(id.row, isCurrent: current);
    // SurfaceFindHost then reveals the actual word, including the horizontal
    // viewport and the native SelectableText geometry of this exact cell.
  }

  @override
  void dispose() {
    _binding++;
    _find.removeListener(_findChanged);
    _find.dispose();
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
    final widths = _widths ??= _measureWidths();
    final columnWidths = {
      for (var i = 0; i < widths.length; i++) i: FixedColumnWidth(widths[i]),
    };
    final width = widths.fold(24.0, (sum, width) => sum + width);
    final side = BorderSide(color: Theme.of(context).dividerColor);
    final rows = ListView.builder(
      controller: _vertical,
      padding: EdgeInsets.fromLTRB(12, _findOpen ? 76 : 12, 12, 12),
      itemCount: _rows.length,
      itemBuilder: (context, row) => AutoScrollTag(
        key: ValueKey(('csv-row', row)),
        controller: _vertical,
        index: row,
        child: Table(
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
                    child: SurfaceFindTarget(
                      id: (row: row, column: column),
                      includeEditable: true,
                      child: SelectableText(
                        column < _rows[row].length ? _rows[row][column] : '',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.hasBoundedHeight ? constraints.maxHeight : 400.0;
        return SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : width,
          height: height,
          child: ContextualFindRegion(
            debugLabel: 'CSV preview access',
            isActive: () => _canRead,
            findInEditable: true,
            onFind: _find.open,
            child: SurfaceFindHost(
              controller: _find,
              debugLabel: 'CSV preview',
              findInEditable: true,
              onReveal: _reveal,
              child: !_canRead
                  ? const SizedBox.shrink()
                  : _rows.isEmpty
                      ? const Center(child: Text('This table is empty.'))
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
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
                                child: SizedBox(
                                  width: width,
                                  height: height,
                                  child: rows,
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        );
      },
    );
  }
}
