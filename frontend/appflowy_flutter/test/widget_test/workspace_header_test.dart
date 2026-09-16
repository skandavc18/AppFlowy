import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/cover_title.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/document_width_action.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    for (final width in [320.0, 600.0, 1100.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('$appearance header fits $width at text scale $scale',
            (tester) async {
          tester.view.physicalSize = const Size(1400, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _app(
              appearance,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: SizedBox(width: width, child: _header(context)),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final header = tester.getRect(find.byType(WorkspaceHeaderLayout));
          final title = tester.getRect(
            find.text('A library of research, ideas and things to revisit'),
          );
          final field = tester.getRect(find.byType(TextField));
          final button = tester.getRect(find.widgetWithText(TextButton, 'Add'));
          for (final rect in [title, field, button]) {
            expect(rect.left, greaterThanOrEqualTo(header.left));
            expect(rect.right, lessThanOrEqualTo(header.right + 0.5));
            expect(rect.bottom, lessThanOrEqualTo(header.bottom + 0.5));
          }
          expect(
            find.widgetWithText(TextButton, 'Add').hitTestable(),
            findsOneWidget,
          );
        });
      }
    }

    testWidgets('$appearance page and collection titles share the chosen face',
        (tester) async {
      late TextStyle document;
      late TextStyle collection;
      late PremiumThemeExtension palette;
      await tester.pumpWidget(
        _app(
          appearance,
          Builder(
            builder: (context) {
              document = coverTitleTextStyle(context);
              collection = WorkspaceChrome.title(context, compact: true);
              palette = PremiumThemeExtension.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(document.fontFamily, collection.fontFamily);
      expect(document.color, palette.textPrimary);
      expect(collection.color, palette.textPrimary);
      expect(document.fontSize, greaterThan(collection.fontSize!));
      expect(document.fontVariations, [const FontVariation.weight(700)]);
      expect(collection.fontVariations, [const FontVariation.weight(650)]);
    });

    for (final width in [320.0, 720.0]) {
      testWidgets('$appearance collection views stay reachable at $width',
          (tester) async {
        var selected = 'view-0';
        final views = [
          for (var i = 0; i < 7; i++)
            CollectionViewDefinition(
              id: 'view-$i',
              labelKey: 'View $i',
              icon: Icons.view_agenda_rounded,
              builder: (_, __) => const SizedBox(),
            ),
        ];
        await tester.pumpWidget(
          _app(
            appearance,
            Center(
              child: SizedBox(
                width: width,
                child: StatefulBuilder(
                  builder: (context, setState) => CollectionViewSwitcher(
                    palette: CollectionPalette.of(context, CollectionKind.book),
                    views: views,
                    activeViewId: selected,
                    onChanged: (id) => setState(() => selected = id),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final menu = find.byKey(const ValueKey('collection-view-menu'));
        expect(menu.hitTestable(), findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuRow), findsNWidgets(7));
        await tester.tap(find.widgetWithText(AppMenuRow, 'View 6'));
        await tester.pumpAndSettle();
        expect(selected, 'view-6');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$appearance width picker preserves custom values until chosen',
        (tester) async {
      var width = 1111.0;
      var changes = 0;
      await tester.pumpWidget(
        _app(
          appearance,
          Center(
            child: SizedBox(
              width: 225,
              child: StatefulBuilder(
                builder: (context, setState) => DocumentWidthPicker(
                  width: width,
                  onChanged: (value) => setState(() {
                    width = value;
                    changes++;
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(width, 1111);
      expect(changes, 0);
      expect(find.text(LocaleKeys.workspaceChrome_customWidth), findsOneWidget);
      expect(find.text(LocaleKeys.workspaceChrome_widthScope), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('document-width-reading')));
      await tester.pumpAndSettle();
      expect(width, DocumentWidthPreset.reading.width);
      expect(changes, 1);
      expect(find.text(LocaleKeys.workspaceChrome_customWidth), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resizing the header preserves the focused search field',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var width = 1100.0;
    late StateSetter resize;
    final focus = FocusNode();
    final controller = TextEditingController();
    await tester.pumpWidget(
      _app(
        'paper',
        StatefulBuilder(
          builder: (context, setState) {
            resize = setState;
            return Center(
              child: SizedBox(
                width: width,
                child: _header(context, focus: focus, controller: controller),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Retain this query');
    final field = tester.state(find.byType(EditableText));
    resize(() => width = 320);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(field));
    expect(focus.hasFocus, isTrue);
    expect(controller.text, 'Retain this query');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    controller.dispose();
  });

  testWidgets('width presets and header controls honour reduced motion',
      (tester) async {
    var invoked = false;
    await tester.pumpWidget(
      _app(
        'light',
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      style: WorkspaceChrome.controlStyle(context),
                      onPressed: () => invoked = true,
                      child: const Text('Add'),
                    ),
                    SizedBox(
                      width: 225,
                      child: DocumentWidthPicker(
                        width: 960,
                        onChanged: (_) {},
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
    for (final button
        in tester.widgetList<TextButton>(find.byType(TextButton))) {
      expect(button.style!.animationDuration, Duration.zero);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(invoked, isTrue);
  });
}

Widget _header(
  BuildContext context, {
  FocusNode? focus,
  TextEditingController? controller,
}) =>
    WorkspaceHeaderLayout(
      identity: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'A library of research, ideas and things to revisit',
            style: WorkspaceChrome.title(context, compact: true),
          ),
          const SizedBox(height: 6),
          const Text('Book collection · 14 objects'),
        ],
      ),
      actions: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 220,
            child: TextField(focusNode: focus, controller: controller),
          ),
          TextButton(
            style: WorkspaceChrome.controlStyle(context),
            onPressed: () {},
            child: const Text('Add'),
          ),
        ],
      ),
    );

Widget _app(String appearance, Widget child) => MaterialApp(
      theme: DesktopAppearance().getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(body: child),
    );
