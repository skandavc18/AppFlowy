import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_support.dart';

Finder _dateText(String label) => find.descendant(
      of: find.byType(CalendarMonthView),
      matching: find.text(label),
    );

Finder _badge(Finder text) =>
    find.ancestor(of: text, matching: find.byType(DecoratedBox)).first;

Finder _dayTarget(Finder text) => find
    .ancestor(of: text, matching: find.byType(DragTarget<CalendarEvent>))
    .first;

void _expectBadge(
  WidgetTester tester,
  Finder text, {
  required String label,
  required bool named,
  required bool rtl,
}) {
  final badge = _badge(text);
  final decoration =
      tester.widget<DecoratedBox>(badge).decoration as BoxDecoration;
  expect(decoration.shape, named ? BoxShape.rectangle : BoxShape.circle);
  expect(
    decoration.borderRadius,
    named ? BorderRadius.circular(CalendarMetrics.pillRadius) : null,
  );
  final badgeBox = tester.renderObject<RenderBox>(badge);
  final badgeRect = MatrixUtils.transformRect(
    badgeBox.getTransformTo(null),
    Offset.zero & badgeBox.size,
  );
  final cellRect = tester.getRect(_dayTarget(text));
  expect(badgeRect.size.isFinite, isTrue);
  expect(badgeRect.isEmpty, isFalse);
  expect(cellRect.inflate(0.01).contains(badgeRect.topLeft), isTrue);
  expect(cellRect.inflate(0.01).contains(badgeRect.bottomRight), isTrue);
  if (!named) {
    expect(badgeRect.width, closeTo(badgeRect.height, 0.01));
  }
  if (rtl) {
    expect(badgeRect.right, closeTo(cellRect.right - 8, 0.01));
  } else {
    expect(badgeRect.left, closeTo(cellRect.left + 8, 0.01));
  }

  // Check the actual painted bounds, including any narrow-cell scale-down,
  // rather than comparing the paragraph's untransformed layout size.
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final paintedText = MatrixUtils.transformRect(
    paragraph.getTransformTo(null),
    Offset.zero & paragraph.size,
  );
  expect(badgeRect.inflate(0.01).contains(paintedText.topLeft), isTrue);
  expect(badgeRect.inflate(0.01).contains(paintedText.bottomRight), isTrue);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(tester.getSemantics(text).label, label);
  expect(
    Directionality.of(tester.element(text)),
    rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
  );
}

void main() {
  setUpAll(initializeCalendarTests);

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final scale in [1.0, 2.0]) {
      for (final rtl in [false, true]) {
        testWidgets(
          'reused month badges page frame-by-frame: $appearance ${scale}x rtl=$rtl',
          (tester) async {
            final workspace = CalendarWorkspace(
              providers: [CalendarFixtureProvider()],
            );
            final shell = GlobalKey<CalendarShellState>();
            final semantics = tester.ensureSemantics();
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            Widget calendar() => CalendarShell(
                  key: shell,
                  workspace: workspace,
                  initialDate: DateTime(2026, 8, 14),
                  quiet: true,
                  delegate: CalendarViewDelegate(
                    colorOf: workspace.colorFor,
                    canEdit: false,
                  ),
                );
            try {
              await mountCalendarTest(
                tester,
                calendar(),
                appearance: appearance,
                size: const Size(700, 560),
                textScale: scale,
                rtl: rtl,
                reducedMotion: false,
                accessibleNavigation: false,
              );
              await mouse.addPointer(location: Offset.zero);
              await mouse.moveTo(tester.getCenter(find.byType(CalendarShell)));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 240));
              expect(tester.takeException(), isNull);

              final august = DateTime(2026, 8);
              final september = DateTime(2026, 9);
              final augustFirst = DateFormat.MMMd().format(august);
              final septemberFirst = DateFormat.MMMd().format(september);
              // In August's Monday-first grid, July 28 and August 1 occupy
              // the slots that September reuses for September 1 and 5.
              final numberElement = tester.element(_dateText('28').first);
              final firstDayElement = tester.element(_dateText(augustFirst));
              final dayState = tester.state(_dayTarget(_dateText('28').first));
              final monthState = tester.state(find.byType(CalendarMonthView));
              final titleStyle = tester
                  .widget<Text>(find.text(DateFormat.yMMMM().format(august)))
                  .style;

              Future<void> pageMonth({required bool forward}) async {
                await tester.tap(
                  find.byTooltip(
                    forward
                        ? LocaleKeys.calendarView_next.tr()
                        : LocaleKeys.calendarView_previous.tr(),
                  ),
                );
                for (var frame = 0; frame <= 30; frame++) {
                  await tester.pump(
                    frame == 0
                        ? Duration.zero
                        : const Duration(milliseconds: 8),
                  );
                  expect(
                    tester.takeException(),
                    isNull,
                    reason: 'forward=$forward, frame=$frame',
                  );
                  final number = _dateText(
                    forward ? septemberFirst : '28',
                  ).first;
                  final first = _dateText(forward ? '5' : augustFirst);
                  expect(tester.element(number), same(numberElement));
                  expect(tester.element(first), same(firstDayElement));
                  expect(tester.state(_dayTarget(number)), same(dayState));
                  expect(
                    tester.state(find.byType(CalendarMonthView)),
                    same(monthState),
                  );
                  _expectBadge(
                    tester,
                    number,
                    label: forward ? septemberFirst : '28',
                    named: forward,
                    rtl: rtl,
                  );
                  _expectBadge(
                    tester,
                    first,
                    label: forward ? '5' : augustFirst,
                    named: !forward,
                    rtl: rtl,
                  );
                }
                final month = forward ? september : august;
                final title = find.text(DateFormat.yMMMM().format(month));
                expect(title, findsOneWidget);
                expect(tester.widget<Text>(title).style, titleStyle);
                expect(
                  tester
                      .widget<CalendarMonthView>(
                        find.byType(CalendarMonthView),
                      )
                      .month,
                  month,
                );
              }

              await pageMonth(forward: true);
              final circleSize = tester.getSize(_badge(_dateText('5')));
              expect(circleSize.width, closeTo(22 * scale, 0.01));
              expect(circleSize.height, closeTo(circleSize.width, 0.01));
              expect(
                tester.getSize(_badge(_dateText(septemberFirst))).width,
                greaterThan(circleSize.width),
              );
              await pageMonth(forward: false);

              // Narrowing must not solve the transition by replacing the
              // badge, clipping scaled text, or dropping the month name from
              // its semantics.
              await tester.pumpWidget(
                calendarTestApp(
                  calendar(),
                  appearance: appearance,
                  size: const Size(240, 300),
                  textScale: scale,
                  rtl: rtl,
                  reducedMotion: false,
                  accessibleNavigation: false,
                ),
              );
              expect(tester.takeException(), isNull);
              expect(
                tester.element(_dateText(augustFirst)),
                same(firstDayElement),
              );
              _expectBadge(
                tester,
                _dateText(augustFirst),
                label: augustFirst,
                named: true,
                rtl: rtl,
              );
              _expectBadge(
                tester,
                _dateText('28').first,
                label: '28',
                named: false,
                rtl: rtl,
              );
            } finally {
              await mouse.removePointer();
              await tester.pumpWidget(const SizedBox());
              semantics.dispose();
              workspace.dispose();
            }
          },
        );
      }
    }

    testWidgets(
      '$appearance: reused today badge still fades its fill in and out',
      (tester) async {
        final today = DateTime.now();
        final currentMonth = DateTime(today.year, today.month);
        final dayIndex = monthGridDays(currentMonth).indexWhere(
          (day) => isSameDay(day, today),
        );
        // Keep the same grid slot mounted even when today occupies week six.
        // At least two months away also excludes today from spillover dates.
        final otherMonth = List<DateTime>.generate(
          12,
          (index) => DateTime(today.year, today.month - index - 2),
        ).firstWhere((month) => monthGridDays(month).length > dayIndex);
        final month = ValueNotifier(otherMonth);
        try {
          await mountCalendarTest(
            tester,
            ValueListenableBuilder<DateTime>(
              valueListenable: month,
              builder: (_, value, __) => CalendarMonthView(
                month: value,
                events: const [],
                delegate: CalendarViewDelegate(
                  colorOf: (_) => Colors.green,
                  canEdit: false,
                ),
              ),
            ),
            appearance: appearance,
            size: const Size(700, 560),
            reducedMotion: false,
            accessibleNavigation: false,
          );
          final text = find.descendant(
            of: find.byType(DragTarget<CalendarEvent>).at(dayIndex),
            matching: find.byType(Text),
          );
          final element = tester.element(text);
          final palette = calendarPaletteOf(element);
          Color fill() => (tester.widget<DecoratedBox>(_badge(text)).decoration
                  as BoxDecoration)
              .color!;

          expect(fill().a, 0);
          month.value = currentMonth;
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.element(text), same(element));
          expect(fill().a, 0);
          await tester.pump(const Duration(milliseconds: 90));
          expect(fill().a, greaterThan(0));
          expect(fill().a, lessThan(1));
          await tester.pump(const Duration(milliseconds: 91));
          expect(fill(), palette.todayBadge);

          month.value = otherMonth;
          await tester.pump();
          expect(tester.element(text), same(element));
          expect(fill(), palette.todayBadge);
          await tester.pump(const Duration(milliseconds: 90));
          expect(fill().a, greaterThan(0));
          expect(fill().a, lessThan(1));
          await tester.pump(const Duration(milliseconds: 91));
          expect(fill().a, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          month.dispose();
        }
      },
    );
  }
}
