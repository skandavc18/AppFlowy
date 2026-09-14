import 'package:appflowy/plugins/document/presentation/editor_plugins/file/csv_preview.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mounts a small subset of 6000 cells and reaches the last row',
      (tester) async {
    await tester.pumpWidget(
      _host(
        CsvPreview(text: _csv(1000), separator: ','),
        size: const Size(320, 180),
      ),
    );

    final list = _list(tester);
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect((list.childrenDelegate as SliverChildBuilderDelegate).childCount, 1000);
    expect(list.shrinkWrap, isFalse);
    expect(list.itemExtent, isNull);
    expect(_cell('0000:0'), findsOneWidget);
    expect(_cell('0999:0'), findsNothing);
    expect(_mountedCells(tester).length, inInclusiveRange(6, 299));
    expect(find.byType(IntrinsicWidth), findsNothing);
    for (final table in tester.widgetList<Table>(find.byType(Table))) {
      expect(table.children, hasLength(1));
      expect(table.columnWidths, hasLength(6));
      expect(table.columnWidths!.values, everyElement(isA<FixedColumnWidth>()));
    }

    // The inner list is wider than the visible horizontal viewport; its
    // geometric center can fall on the vertical scrollbar. Drag the visible
    // preview body instead, so every gesture actually scrolls the row list.
    await tester.dragUntilVisible(
      _cell('0999:0'),
      find.byType(CsvPreview),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    expect(_cell('0999:0').hitTestable(), findsOneWidget);
    expect(_cell('0000:0'), findsNothing);
    expect(_mountedCells(tester).length, lessThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps headers aligned and long values fully selectable',
      (tester) async {
    final longValue = '${List.filled(18, 'readable words').join(' ')} THE_END';
    await tester.pumpWidget(
      _host(
        CsvPreview(
          text: 'First,Second\n$longValue,Tail\nShort,Last',
          separator: ',',
        ),
        size: const Size(600, 420),
      ),
    );

    expect(_columnWidths(tester).first, 280);
    expect(
      tester.getTopLeft(_cell('First')).dx,
      tester.getTopLeft(_cell(longValue)).dx,
    );
    expect(
      tester.getTopLeft(_cell('Second')).dx,
      tester.getTopLeft(_cell('Tail')).dx,
    );
    expect(
      tester.getTopLeft(_cell('Tail')).dy,
      tester.getTopLeft(_cell(longValue)).dy,
    );
    expect(
      tester.getSize(_cell(longValue)).height,
      greaterThan(tester.getSize(_cell('First')).height),
    );
    expect(tester.widget<SelectableText>(_cell(longValue)).maxLines, isNull);

    final editableFinder = find.descendant(
      of: _cell(longValue),
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(editableFinder);
    final state = tester.state<EditableTextState>(editableFinder);
    final render = state.renderEditable;
    final lastCaret = render.getLocalRectForCaret(
      TextPosition(offset: longValue.length),
    );
    expect(render.text!.toPlainText(), longValue);
    expect(lastCaret.top, greaterThan(0));
    expect(lastCaret.top, lessThan(render.size.height));
    expect(editable.readOnly, isTrue);
    state.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(
      editable.controller.selection.textInside(editable.controller.text),
      longValue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('samples exactly the first 32 rows without dropping later columns',
      (tester) async {
    const sampled = 'measured sample';
    final lateValue = List.filled(30, 'long').join(' ');
    final lines = List.generate(33, (row) {
      if (row == 31) {
        return '$sampled,y';
      }
      return row == 32 ? 'x,$lateValue,extra' : 'x,y';
    });
    await tester.pumpWidget(
      _host(CsvPreview(text: lines.join('\n'), separator: ',')),
    );

    final widths = _columnWidths(tester);
    expect(widths, hasLength(3));
    expect(widths.first, greaterThan(96));
    expect(widths.first, lessThanOrEqualTo(280));
    expect(widths.skip(1), [96.0, 96.0]);
    expect(_cell(lateValue), findsNothing);
    final controller = _list(tester).controller!;
    await tester.scrollUntilVisible(
      _cell(lateValue),
      600,
      scrollable: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.controller == controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(_cell(lateValue), findsOneWidget);
    expect(_cell('extra'), findsOneWidget);
    expect(_columnWidths(tester), widths);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short tables start at the same inset with single shared borders',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const CsvPreview(text: 'a,b\nc,d', separator: ','),
        size: const Size(720, 240),
      ),
    );

    expect(_columnWidths(tester), [96.0, 96.0]);
    expect(
      tester.getTopLeft(_cell('a')).dx,
      tester.getTopLeft(find.byType(CsvPreview)).dx + 20,
    );
    expect(tester.getTopLeft(_cell('a')).dx, tester.getTopLeft(_cell('c')).dx);
    final tables = tester.widgetList<Table>(find.byType(Table)).toList();
    expect(tables, hasLength(2));
    expect(tester.getSize(find.byType(Table).first).width, 192);
    expect(tables.first.border!.top.width, 1);
    expect(tables.last.border!.top, BorderSide.none);
    for (final table in tables) {
      expect(table.defaultVerticalAlignment, TableCellVerticalAlignment.top);
      expect(table.border!.bottom.width, 1);
      expect(table.border!.left.width, 1);
      expect(table.border!.right.width, 1);
      expect(table.border!.verticalInside.width, 1);
      expect(table.border!.horizontalInside, BorderSide.none);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves the empty message and does not trim a blank row',
      (tester) async {
    await tester.pumpWidget(
      _host(const CsvPreview(text: '', separator: ',')),
    );
    expect(find.text('This table is empty.'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);

    await tester.pumpWidget(
      _host(const CsvPreview(text: '\n', separator: ',')),
    );
    expect(find.text('This table is empty.'), findsNothing);
    expect(_mountedCells(tester), ['']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splits tabs and CRLF while preserving trailing empty cells',
      (tester) async {
    await tester.pumpWidget(
      _host(const CsvPreview(text: 'A\tB\r\n1\t2\r\n3\t\r\n', separator: '\t')),
    );
    expect(_mountedCells(tester), ['A', 'B', '1', '2', '3', '']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains simple delimiter splitting rather than interpreting quotes',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const CsvPreview(
          text: 'first,second\n"one,two", last ',
          separator: ',',
        ),
      ),
    );
    expect(_mountedCells(tester), ['first', 'second', '', '"one', 'two"', ' last ']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caps rows at 1000 including the header and ignores later columns',
      (tester) async {
    final ignored = List.generate(20, (column) => 'ignored $column').join(',');
    await tester.pumpWidget(
      _host(CsvPreview(text: '${_csv(1000)}\n$ignored', separator: ',')),
    );
    final delegate = _list(tester).childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 1000);
    expect(delegate.build(tester.element(find.byType(ListView)), 1000), isNull);
    expect(_columnWidths(tester), hasLength(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshes row counts, column counts and widths when inputs change',
      (tester) async {
    Future<void> show(String text, String separator) => tester.pumpWidget(
          _host(CsvPreview(text: text, separator: separator)),
        );
    await show('a,b\nc,d', ',');
    final state = tester.state(find.byType(CsvPreview));
    expect(_columnWidths(tester), [96.0, 96.0]);

    const text = 'Long enough to widen the column|B|C\n1|2|3\n4|5|6';
    await show(text, ',');
    expect(_columnWidths(tester), [280.0]);
    expect(
      (_list(tester).childrenDelegate as SliverChildBuilderDelegate).childCount,
      3,
    );
    expect(_cell('a'), findsNothing);

    await show(text, '|');
    expect(_columnWidths(tester), [280.0, 96.0, 96.0]);
    expect(_cell('B'), findsOneWidget);
    expect(_cell('6'), findsOneWidget);

    await show('x|y|z', '|');
    expect(_columnWidths(tester), [96.0, 96.0, 96.0]);
    expect(_mountedCells(tester), ['x', 'y', 'z']);
    expect(tester.state(find.byType(CsvPreview)), same(state));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolls each axis independently with exactly two scrollbars',
      (tester) async {
    await tester.pumpWidget(
      _host(CsvPreview(text: _csv(100), separator: ','), size: const Size(300, 180)),
    );
    final vertical = _list(tester).controller!;
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    final previewScrollbars = find.byWidgetPredicate(
      (widget) => widget is Scrollbar &&
          (widget.controller == vertical || widget.controller == horizontal),
    );
    expect(previewScrollbars, findsNWidgets(2));
    expect(
      tester.widgetList<Scrollbar>(previewScrollbars).map((bar) => bar.controller),
      unorderedEquals([vertical, horizontal]),
    );
    expect(vertical.position.maxScrollExtent, greaterThan(0));
    expect(horizontal.position.maxScrollExtent, greaterThan(0));

    await _trackpad(tester, const Offset(-150, 0));
    await tester.pumpAndSettle();
    final horizontalOffset = horizontal.offset;
    expect(horizontalOffset, greaterThan(0));
    expect(vertical.offset, 0);

    await _trackpad(tester, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(vertical.offset, greaterThan(0));
    expect(horizontal.offset, horizontalOffset);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(vertical.hasClients, isFalse);
    expect(horizontal.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits the real document viewport and inherits its scroll physics',
      (tester) async {
    await tester.pumpWidget(
      _host(
        AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(),
          child: const DocumentViewport(
            framed: false,
            identity: DocumentIdentity(title: 'Table.csv', icon: Icons.table_chart),
            child: DocumentScrollScope(
              enabled: false,
              child: CsvPreview(text: 'a,b\nc,d', separator: ','),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(ListView)).height,
      240 - DocumentViewportStyle.contentTopInset,
    );
    expect(_list(tester).physics, isNull);
    expect(_list(tester).controller!.position.physics, isA<DocumentScrollPhysics>());
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(horizontal.physics, isNull);
    expect(horizontal.controller!.position.physics, isA<DocumentScrollPhysics>());
    expect(find.byType(Scrollbar), findsNWidgets(2));
    // SelectableText creates its own zero-range scrolling wrappers. The
    // preview axes themselves must not get a second automatic scrollbar.
    expect(
      find.ancestor(of: find.byType(ListView), matching: find.byType(DocumentScrollbar)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to a finite 400px viewport under unbounded height',
      (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [CsvPreview(text: _csv(1000), separator: ',')],
        ),
        size: const Size(320, 500),
      ),
    );
    expect(tester.getSize(find.byType(ListView)).height, 400);
    expect(_mountedCells(tester).length, lessThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remeasures for inherited fonts, nonlinear scaling and direction',
      (tester) async {
    const preview = CsvPreview(text: 'abcdefghij,B\nc,d', separator: ',');
    const configurations = [
      (TextStyle(fontSize: 14), TextScaler.noScaling, TextDirection.ltr),
      (TextStyle(fontSize: 18), TextScaler.noScaling, TextDirection.ltr),
      (
        TextStyle(fontSize: 14, letterSpacing: 1),
        _NonlinearTextScaler(),
        TextDirection.rtl,
      ),
    ];
    State<CsvPreview>? originalState;
    double? previousWidth;
    for (final (style, scaler, direction) in configurations) {
      await tester.pumpWidget(
        _host(preview, style: style, scaler: scaler, direction: direction),
      );
      originalState ??= tester.state<State<CsvPreview>>(find.byType(CsvPreview));
      final context = tester.element(_cell('abcdefghij'));
      final width = _columnWidths(tester).first;
      expect(width, closeTo(_measureWidth(context, 'abcdefghij'), 0.01));
      expect(width, isNot(previousWidth));
      expect(tester.state(find.byType(CsvPreview)), same(originalState));
      expect(
        tester.renderObject<RenderTable>(find.byType(Table).first).textDirection,
        direction,
      );
      previousWidth = width;
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('updates inherited ink and dividers in light, dark and paper modes',
      (tester) async {
    final light = ThemeData.light();
    final paper = light.copyWith(
      scaffoldBackgroundColor: PaperTheme.editorPreviewBackground,
      dividerColor: PaperTheme.strongBorder,
      textTheme: light.textTheme.apply(bodyColor: PaperTheme.textPrimary),
      extensions: [const PaperThemeExtension(enabled: true)],
    );
    const preview = CsvPreview(text: 'First,Second\nValue,Other', separator: ',');
    State<CsvPreview>? originalState;
    for (final theme in [light, ThemeData.dark(), paper]) {
      await tester.pumpWidget(_host(preview, theme: theme));
      await tester.pumpAndSettle();
      originalState ??= tester.state<State<CsvPreview>>(find.byType(CsvPreview));
      final context = tester.element(_cell('First'));
      final editable = tester.widget<EditableText>(
        find.descendant(of: _cell('First'), matching: find.byType(EditableText)),
      );
      expect(tester.state(find.byType(CsvPreview)), same(originalState));
      expect(editable.style.color, theme.textTheme.bodyMedium!.color);
      expect(PaperTheme.isEnabled(context), identical(theme, paper));
      for (final table in tester.widgetList<Table>(find.byType(Table))) {
        expect(table.border!.bottom.color, theme.dividerColor);
        expect(table.border!.verticalInside.color, theme.dividerColor);
        expect(table.children.single.decoration, isNull);
      }
      // The ancestor paints the surface; the preview must not cover it.
      expect(
        find.descendant(of: find.byType(CsvPreview), matching: find.byType(ColoredBox)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

String _csv(int rows) => List.generate(
      rows,
      (row) => List.generate(6, (column) => '${row.toString().padLeft(4, '0')}:$column')
          .join(','),
    ).join('\n');

Future<void> _trackpad(WidgetTester tester, Offset delta) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  final point = tester.getCenter(find.byType(CsvPreview));
  await gesture.panZoomStart(point);
  for (var step = 1; step <= 5; step++) {
    await gesture.panZoomUpdate(
      point,
      pan: delta * (step / 5),
      timeStamp: Duration(milliseconds: step * 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.panZoomUpdate(
    point,
    pan: delta,
    timeStamp: const Duration(milliseconds: 300),
  );
  await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 301));
}

Finder _cell(String text) => find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == text,
    );

ListView _list(WidgetTester tester) => tester.widget<ListView>(find.byType(ListView));

List<String?> _mountedCells(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((cell) => cell.data)
    .toList();

List<double> _columnWidths(WidgetTester tester) => tester
    .widget<Table>(find.byType(Table).first)
    .columnWidths!
    .values
    .map((column) => (column as FixedColumnWidth).value)
    .toList();

double _measureWidth(BuildContext context, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: DefaultTextStyle.of(context).style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  );
  try {
    painter.layout();
    return (painter.width + 16).clamp(96.0, 280.0).toDouble();
  } finally {
    painter.dispose();
  }
}

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 18 ? 1.5 : 1.2);

  @override
  double get textScaleFactor => 1;
}

Widget _host(
  Widget child, {
  Size size = const Size(480, 240),
  ThemeData? theme,
  TextStyle style = const TextStyle(fontSize: 14, height: 1.2),
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
}) =>
    MaterialApp(
      theme: theme ?? ThemeData(platform: TargetPlatform.windows),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!.merge(style),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );