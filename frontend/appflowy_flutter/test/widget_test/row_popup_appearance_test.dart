import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/desktop_field_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/database/widgets/row/row_banner.dart';
import 'package:appflowy/plugins/database/widgets/row/row_comments.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail_scroll_surface.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _popup = ValueKey('popup-reference');
const _title = ValueKey('row-banner-title');
const _properties = ValueKey('popup-properties');
const _comments = ValueKey('row-comments-heading');
const _actions = ValueKey('popup-actions');
const _notes = ValueKey('popup-notes');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  for (final mode in _modes) {
    testWidgets('$mode: coverless popup has page hierarchy and breathing room',
        (tester) async {
      final fixture = _Fixture();
      try {
        await tester.pumpWidget(_app(fixture, mode: mode));
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byKey(_popup));
        final title = tester.getRect(find.byKey(_title));
        final heading = tester.getRect(
          find.byKey(const ValueKey('row-properties-heading')),
        );
        final properties = tester.getRect(find.byKey(_properties));
        final comments = tester.getRect(find.byKey(_comments));
        final notes = tester.getRect(find.byKey(_notes));
        expect(title.top - bounds.top, 128);
        expect(title.left - bounds.left, 72);
        expect(title.right, bounds.right - 72);
        expect(heading.top - title.bottom, closeTo(24, 0.01));
        expect(comments.top - properties.bottom, closeTo(32, 0.01));
        expect(comments.left, title.left);
        expect(heading.left, title.left);
        expect(notes.left, title.left);
        expect(
          notes.top -
              tester
                  .getBottomLeft(
                    find.byKey(const ValueKey('row-comment-composer')),
                  )
                  .dy,
          closeTo(36, 0.01),
        );
        final field = tester.widget<TextField>(find.byKey(_title));
        expect(field.style!.fontSize, 40);
        expect(field.style!.fontWeight, FontWeight.w700);
        expect(
          field.style!.fontVariations,
          contains(const FontVariation('wght', 700)),
        );
        expect(field.autofocus, isFalse);
        expect(fixture.focus.hasFocus, isFalse);
        expect(find.byType(Divider), findsNothing);
        expect(find.byType(RowCover), findsNothing);
        expect(find.text('Add Cover').hitTestable(), findsOneWidget);
        expect(fixture.title.text, 'A clearer place to think');
        expect(rowCommentNodeOf(fixture.editor.document), isNull);
        if (mode == 'paper') {
          expect(
            tester
                .widget<Material>(find.byKey(const ValueKey('popup-surface')))
                .color,
            isNot(Colors.white),
          );
          expect(
            PaperTheme.isEnabled(tester.element(find.byKey(_title))),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets('$mode: title and comment drafts survive popup scrolling',
        (tester) async {
      final fixture = _Fixture();
      try {
        await tester.pumpWidget(_app(fixture, mode: mode, height: 540));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_title), 'An edited page title');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(fixture.focus.hasFocus, isFalse);
        await tester
            .ensureVisible(find.byKey(const ValueKey('row-comment-input')));
        await tester.enterText(
          find.byKey(const ValueKey('row-comment-input')),
          'Keep this unsent comment',
        );
        await tester.pumpAndSettle();
        final comment = tester
            .widget<TextField>(
              find.byKey(const ValueKey('row-comment-input')),
            )
            .controller!;
        fixture.scroll.jumpTo(fixture.scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(find.byKey(_popup)).dy;
        expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 12);
        await tester.tap(find.byKey(_actions));
        await tester.pumpAndSettle();
        expect(fixture.actions, 1);
        fixture.scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(fixture.title.text, 'An edited page title');
        expect(comment.text, 'Keep this unsent comment');
        expect(rowCommentsOf(fixture.editor.document), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets(
        '$mode: covered and icon headers retain their intended geometry',
        (tester) async {
      final fixture = _Fixture();
      try {
        for (final covered in [false, true]) {
          for (final icon in ['', '📘']) {
            final row = RowMetaPB(
              id: 'synthetic-row',
              icon: icon,
              cover: covered ? defaultRowCover('synthetic-row') : RowCoverPB(),
            );
            await tester.pumpWidget(_app(fixture, mode: mode, row: row));
            await tester.pumpAndSettle();
            final header = tester.getRect(find.byType(RowBannerHeader));
            final expected = covered
                ? 290.0
                : icon.isEmpty
                    ? 112.0
                    : 188.0;
            expect(header.height, expected);
            expect(
              tester.getTopLeft(find.byKey(_title)).dy - header.bottom,
              16,
            );
            if (icon.isNotEmpty) {
              final iconBounds = tester.getRect(find.byType(RowIcon));
              expect(iconBounds.top, greaterThanOrEqualTo(header.top));
              expect(iconBounds.bottom, lessThanOrEqualTo(header.bottom));
            }
            expect(
              find.byType(RowCover),
              covered ? findsOneWidget : findsNothing,
            );
            expect(rowCoverHeightFor(row), covered ? 250 : 0);
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets('$mode popup visual reference', (tester) async {
      tester.view.physicalSize = const Size(820, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = _Fixture();
      try {
        await tester.pumpWidget(_app(fixture, mode: mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(_popup),
          matchesGoldenFile('goldens/row_popup_$mode.png'),
        );
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'narrow popup title wraps without pushing actions or losing draft',
      (tester) async {
    final fixture = _Fixture();
    fixture.title.text = 'A longer title that needs space to wrap';
    try {
      await tester.pumpWidget(
        _app(fixture, mode: 'paper', width: 440, height: 600, textScale: 1.4),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_title)).height, greaterThan(60));
      expect(fixture.title.text, 'A longer title that needs space to wrap');
      expect(find.text('Add Cover').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

class _Fixture {
  final title = TextEditingController(text: 'A clearer place to think');
  final focus = FocusNode();
  final scroll = ScrollController();
  final editor = EditorState.blank()..disableSealTimer = true;
  int actions = 0;
  int titleSubmits = 0;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    title.dispose();
    focus.dispose();
    scroll.dispose();
    editor.dispose();
    await tester.pump();
  }
}

Widget _popupBody(
  _Fixture fixture,
  BuildContext context,
  RowMetaPB row,
  double width,
) {
  final inset = (width * 0.1).clamp(28.0, rowDetailContentInset);
  final theme = Theme.of(context);
  return Material(
    key: const ValueKey('popup-surface'),
    color: theme.cardColor,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: RowDetailScrollSurface(
      coverHeight: rowCoverHeightFor(row),
      actions: IconButton(
        key: _actions,
        tooltip: 'Open as page',
        onPressed: () => fixture.actions++,
        icon: const Icon(Icons.open_in_full_rounded, size: 16),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(28),
          padding: const EdgeInsets.all(6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: SingleChildScrollView(
        controller: fixture.scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RowDetailHeader(
              contentInset: inset,
              banner: Column(
                children: [
                  RowBannerHeader(
                    rowMeta: row,
                    spacious: true,
                    contentInset: inset,
                    onIconChanged: (_) {},
                    onCoverChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: RowBannerTitleField(
                      controller: fixture.title,
                      focusNode: fixture.focus,
                      spacious: true,
                      onEditingComplete: () => fixture.titleSubmits++,
                    ),
                  ),
                ],
              ),
              properties: Padding(
                key: _properties,
                padding: const EdgeInsets.only(left: 24),
                child: Column(
                  children: [
                    _property(
                      context,
                      'Created',
                      FieldType.CreatedTime,
                      const Text('September 18, 2026'),
                    ),
                    _property(
                      context,
                      'Tags',
                      FieldType.MultiSelect,
                      Text(
                        'Empty',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ),
                    _property(
                      context,
                      'Progress',
                      FieldType.RichText,
                      PropertyValueControl(
                        style: const PropertyStyle(
                          kind: PropertyStyleKind.progress,
                        ),
                        value: '54.183636',
                        onChanged: (_) {},
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('New property'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.hintColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 36),
              child: RowCommentSection(
                editorState: fixture.editor,
                userProfile: UserProfilePB(id: Int64(7), name: 'Ada'),
                padding: EdgeInsets.zero,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Text(
                'Room for the details',
                key: _notes,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Text(
                'A calm space for your notes, ideas, and the conversations around them.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontSize: 15, height: 1.6),
              ),
            ),
            const SizedBox(height: 600),
          ],
        ),
      ),
    ),
  );
}

Widget _property(
  BuildContext context,
  String name,
  FieldType type,
  Widget value,
) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            height: 32,
            child: FieldCellButton(
              field: FieldPB(id: name, name: name, fieldType: type),
              onTap: () {},
              fontSize: 13.5,
              textColor: Theme.of(context).hintColor,
              margin: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: value),
        ],
      ),
    );

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Widget _app(
  _Fixture fixture, {
  String mode = 'light',
  double width = 720,
  double height = 760,
  double textScale = 1,
  RowMetaPB? row,
}) {
  final theme = _theme(mode);
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => AppFlowyTheme(
          data: appTheme,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: RepaintBoundary(
                key: _popup,
                child: Builder(
                  builder: (context) => _popupBody(
                    fixture,
                    context,
                    row ?? RowMetaPB(id: 'synthetic-row', cover: RowCoverPB()),
                    width,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
