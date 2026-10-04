import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_support.dart' show initializeCalendarTests;
import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart'
    show settleVividIconPictures, vividIconTestTheme;

late _Translations _translations;

void main() {
  setUpAll(() async {
    await initializeCalendarTests();
    _translations = _Translations(
      await const TestBundleAssetLoader().load(
        'assets/translations',
        const Locale('en', 'US'),
      ),
    );
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance reminder pickers change style, not draft or state ink',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 800);
      addTearDown(tester.view.reset);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final storage = _NoConnectionsStorage();
      Future<AppReminder?>? result;
      getIt.pushNewScope();
      getIt.registerSingleton<KeyValueStorage>(storage);
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showReminderComposer(
                    context,
                    initialText: 'Review manuscript',
                    initialWhen: DateTime(2026, 10, 1, 9),
                  );
                },
                child: const Text('Open reminder'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Open reminder'));
        await settleVividIconPictures(tester);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        expect(result, isNotNull);
        expect(ProviderConnections.instance.isLoaded, isTrue);
        expect(ProviderConnections.instance.all, isEmpty);
        final context = tester.element(dialog);
        final palette = calendarPaletteOf(context);
        expect(PaperTheme.isEnabled(context), appearance == 'paper');
        expect(
          Theme.of(context).brightness,
          appearance == 'dark' ? Brightness.dark : Brightness.light,
        );
        expect(DefaultIconStyleScope.of(context), same(styles));
        final repeat = find.byType(PopupMenuButton<CalendarRecurrenceKind>);
        final priority = find.byType(PopupMenuButton<ReminderPriority>);
        final dateGlyph = _glyph(dialog, 'calendar-blank');
        final timeGlyph = _glyph(dialog, 'clock');
        final dateButton = find
            .ancestor(
              of: dateGlyph,
              matching: find.byType(GestureDetector),
            )
            .first;
        final timeButton = find
            .ancestor(
              of: timeGlyph,
              matching: find.byType(GestureDetector),
            )
            .first;
        final controls = [repeat, priority, dateButton, timeButton];
        final input =
            find.descendant(of: dialog, matching: find.byType(TextField));
        await tester.enterText(input, 'Keep this draft tomorrow at 9am');
        final editableFinder = find.descendant(
          of: dialog,
          matching: find.byType(EditableText),
        );
        final editable = tester.widget<EditableText>(editableFinder);
        const selection = TextSelection(baseOffset: 2, extentOffset: 9);
        editable.controller.selection = selection;
        await tester.pump();
        // Parsing the draft may resize its summary. Measure only after that
        // intentional layout change, before changing the icon preference.
        final elements = controls.map(tester.element).toList();
        final rectangles = controls.map(tester.getRect).toList();
        for (final rectangle in rectangles) {
          expect(rectangle.height, 38);
        }
        final inputState = tester.state(editableFinder);
        final dialogElement = tester.element(dialog);
        final dialogBounds = tester.getRect(dialog);

        for (final style in [
          DefaultIconStyle.monochrome,
          DefaultIconStyle.vivid,
          DefaultIconStyle.monochrome,
        ]) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(
            tester,
            dialog,
            'calendar-blank',
            style,
            size: 14,
            ink: palette.textMuted,
          );
          _expectGlyph(
            tester,
            dialog,
            'clock',
            style,
            size: 14,
            ink: palette.textMuted,
          );
          _expectGlyph(
            tester,
            repeat,
            'repeat',
            style,
            size: 14,
            ink: palette.textMuted,
          );
          _expectGlyph(
            tester,
            repeat,
            'caret-down',
            style,
            size: 15,
            ink: palette.textMuted,
          );
          _expectGlyph(
            tester,
            priority,
            'flag',
            style,
            size: 14,
            ink: palette.textMuted,
            preserveInk: true,
          );
          _expectGlyph(
            tester,
            priority,
            'caret-down',
            style,
            size: 15,
            ink: palette.textMuted,
          );
          _expectGlyph(
            tester,
            dialog,
            'volume',
            style,
            size: 15,
            ink: palette.textMuted,
            preserveInk: true,
          );
          for (var i = 0; i < controls.length; i++) {
            expect(tester.element(controls[i]), same(elements[i]));
            expect(tester.getRect(controls[i]), rectangles[i]);
          }
          expect(tester.element(dialog), same(dialogElement));
          expect(tester.getRect(dialog), dialogBounds);
          expect(tester.state(editableFinder), same(inputState));
          expect(editable.controller.text, 'Keep this draft tomorrow at 9am');
          expect(editable.controller.selection, selection);
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
          expect(storage.writes, isEmpty);
        }

        // These use the real native picker/switch callbacks, not their fields.
        await tester.tap(repeat);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            PopupMenuItem<CalendarRecurrenceKind>,
            LocaleKeys.reminders_repeats_daily.tr(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: repeat,
            matching: find.text(LocaleKeys.reminders_repeats_daily.tr()),
          ),
          findsOneWidget,
        );
        await tester.tap(priority);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            PopupMenuItem<ReminderPriority>,
            LocaleKeys.reminders_priorities_high.tr(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: priority,
            matching: find.text(LocaleKeys.reminders_priorities_high.tr()),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byType(Switch));
        styles.value = DefaultIconStyle.vivid;
        await settleVividIconPictures(tester);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
        _expectGlyph(
          tester,
          dialog,
          'volume-off',
          DefaultIconStyle.vivid,
          size: 15,
          ink: palette.textMuted,
          preserveInk: true,
        );
        _expectGlyph(
          tester,
          priority,
          'flag',
          DefaultIconStyle.vivid,
          size: 14,
          ink: palette.textMuted,
          preserveInk: true,
        );

        // Both open AppFlowy's own date picker, anchored under the button.
        // Dismissing it outside the popup leaves the composer untouched.
        final popup = find.byKey(const ValueKey('date_picker_popup'));
        for (final (button, includesTime) in [
          (dateButton, false),
          (timeButton, true),
        ]) {
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(popup, findsOneWidget);
          expect(find.byType(DatePickerDialog), findsNothing);
          expect(find.byType(TimePickerDialog), findsNothing);
          final popupRect = tester.getRect(popup);
          expect(popupRect.top, tester.getRect(button).bottom + 6);
          expect(popupRect.left, tester.getRect(button).left);
          expect(
            (tester.widget<Container>(popup).decoration! as ShapeDecoration)
                .color,
            Theme.of(tester.element(popup)).cardColor,
          );
          expect(
            find.descendant(
              of: popup,
              matching: find.byKey(const ValueKey('date_time_text_field_time')),
            ),
            includesTime ? findsOneWidget : findsNothing,
          );
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          expect(popup, findsNothing);
          expect(dialog, findsOneWidget);
        }
        expect(editable.controller.text, 'Keep this draft tomorrow at 9am');
        expect(tester.state(editableFinder), same(inputState));
        await tester.tap(find.text(LocaleKeys.reminders_cancel.tr()));
        await tester.pumpAndSettle();
        expect(await result!, isNull);
        expect(dialog, findsNothing);
        expect(storage.reads, everyElement(ProviderConnections.storageKey));
        expect(storage.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await getIt.popScope();
        styles.dispose();
      }
    });
  }
}

Widget _app(
  String appearance,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child,
) =>
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: _translations,
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: vividIconTestTheme(appearance),
          themeAnimationDuration: Duration.zero,
          home: DefaultIconStyleScope(
            styles: styles,
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );

Finder _glyph(Finder parent, String name) => find.descendant(
      of: parent,
      matching: find.byWidgetPredicate(
        (widget) => widget is WorkspaceGlyph && widget.name == name,
      ),
    );

void _expectGlyph(
  WidgetTester tester,
  Finder parent,
  String name,
  DefaultIconStyle style, {
  required double size,
  required Color ink,
  bool preserveInk = false,
}) {
  final finder = _glyph(parent, name);
  expect(finder, findsOneWidget);
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  expect(glyph.role == WorkspaceGlyphRole.preserveInk, preserveInk);
  expect(glyph.size, size);
  expect(tester.getSize(finder), Size.square(size));
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: finder, matching: find.byType(SvgPicture)),
  );
  final vivid = style == DefaultIconStyle.vivid && !preserveInk;
  final source = vivid
      ? vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!
      : defaultIconSvg(name)!;
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      source,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
  expect(
    picture.colorFilter,
    vivid ? null : ColorFilter.mode(ink, BlendMode.srcIn),
  );
  expect(picture.excludeFromSemantics, isTrue);
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(english);
}

/// The dialog may inspect connected-account metadata, but must not initialize
/// reminders, reach credential storage, or persist anything in this fixture.
class _NoConnectionsStorage extends Fake implements KeyValueStorage {
  final reads = <String>[];
  final writes = <String>[];

  @override
  Future<String?> get(String key) async {
    reads.add(key);
    if (key != ProviderConnections.storageKey) {
      throw StateError('Unexpected storage read: $key');
    }
    return '[]';
  }

  @override
  Future<void> set(String key, String value) async {
    writes.add(key);
    throw StateError('The reminder glyph fixture must not save data');
  }
}
