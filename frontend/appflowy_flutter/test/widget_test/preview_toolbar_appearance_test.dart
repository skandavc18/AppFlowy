import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_toolbar.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewport.dart';
import 'package:appflowy/shared/document_viewer/document_viewport_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _reference = ValueKey('preview-toolbar-reference');
const _samples = ['idle', 'hover'];
const _appearances = ['light', 'dark', 'paper'];

// One small idle/hover comparison per appearance. The main CLI owner generates
// and reviews these new baselines; this file does not replace either renderer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool fontFetching;
  final loadedFamilies = <String>{};
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final appearance in _appearances) {
      final text = _theme(appearance).textTheme;
      loadedFamilies.addAll([
        text.bodyMedium!.fontFamily!,
        text.bodySmall!.fontFamily!,
        text.titleMedium!.fontFamily!,
        text.headlineSmall!.fontFamily!,
        text.labelLarge!.fontFamily!,
      ]);
    }
    for (final family in loadedFamilies) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final appearance in _appearances) {
    testWidgets(
      '$appearance: real document and spreadsheet controls at idle and hover',
      (tester) async {
        tester.view.physicalSize = const Size(1160, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final editors = [for (final _ in _samples) _editor()];
        final documents = [
          for (final editor in editors) jsonEncode(editor.document.toJson()),
        ];
        final pointers = <int, Offset>{};
        try {
          await _mount(tester, appearance, editors);
          expect(find.byType(DocumentViewport), findsNWidgets(2));
          expect(find.byType(SpreadsheetBlockComponent), findsNWidgets(2));
          expect(find.byType(SpreadsheetGrid), findsNWidgets(2));
          expect(find.byType(PreviewToolbar), findsNWidgets(6));
          expect(find.text('Field notes.txt'), findsNWidgets(2));
          final viewports =
              tester.stateList(find.byType(DocumentViewport)).toList();
          final grids = tester.stateList(find.byType(SpreadsheetGrid)).toList();
          final geometry = {
            for (final sample in _samples)
              for (final kind in ['document', 'spreadsheet'])
                '$kind-$sample':
                    tester.getRect(find.byKey(ValueKey('$kind-$sample'))),
          };
          for (final sample in _samples) {
            _expectReveal(tester, sample, false);
          }

          // Separate real mouse devices hover separate preview scopes. Neither
          // keepVisible nor a synthetic hold forces the reference appearance.
          final targets = [
            find.byKey(const ValueKey('document-search-hover')),
            find
                .descendant(
                  of: find.byKey(const ValueKey('spreadsheet-hover')),
                  matching: find.byType(SpreadsheetToolbarButton),
                )
                .first,
          ];
          for (var index = 0; index < targets.length; index++) {
            final device = 80 + index;
            final position = tester.getCenter(targets[index]);
            pointers[device] = position;
            tester.binding.handlePointerEvent(
              PointerAddedEvent(
                device: device,
                kind: PointerDeviceKind.mouse,
                position: const Offset(8, 8),
              ),
            );
            tester.binding.handlePointerEvent(
              PointerHoverEvent(
                device: device,
                kind: PointerDeviceKind.mouse,
                position: position,
              ),
            );
          }
          await tester.pumpAndSettle();
          _expectReveal(tester, 'idle', false);
          _expectReveal(tester, 'hover', true);
          for (var index = 0; index < _samples.length; index++) {
            expect(
              tester.state(find.byType(DocumentViewport).at(index)),
              same(viewports[index]),
            );
            expect(
              tester.state(find.byType(SpreadsheetGrid).at(index)),
              same(grids[index]),
            );
            expect(
              jsonEncode(editors[index].document.toJson()),
              documents[index],
            );
          }
          for (final entry in geometry.entries) {
            expect(
              tester.getRect(find.byKey(ValueKey(entry.key))),
              entry.value,
            );
          }
          for (final sample in _samples) {
            final document =
                tester.element(find.byKey(ValueKey('document-$sample')));
            final spreadsheet =
                tester.element(find.byKey(ValueKey('spreadsheet-$sample')));
            final viewportStyle = DocumentViewportStyle.of(document);
            final sheetPalette = SpreadsheetPalette.of(spreadsheet);
            expect(viewportStyle.chrome, viewportStyle.canvas);
            expect(sheetPalette.chrome, sheetPalette.surface);
            for (final context in [document, spreadsheet]) {
              expect(PaperTheme.isEnabled(context), appearance == 'paper');
              expect(
                Theme.of(context).brightness,
                appearance == 'dark' ? Brightness.dark : Brightness.light,
              );
              expect(
                loadedFamilies,
                contains(Theme.of(context).textTheme.bodyMedium!.fontFamily),
              );
            }
            if (appearance == 'paper') {
              expect(viewportStyle.canvas, PaperTheme.editorPreviewBackground);
              expect(sheetPalette.surface, PaperTheme.editorBackground);
              expect(viewportStyle.controlHover, PaperTheme.hoverOverlay);
            }
          }
          for (final grid in tester
              .widgetList<SpreadsheetGrid>(find.byType(SpreadsheetGrid))) {
            expect(loadedFamilies, contains(grid.baseTextStyle!.fontFamily));
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_reference),
            matchesGoldenFile('goldens/preview_toolbar_$appearance.png'),
          );
        } finally {
          for (final pointer in pointers.entries) {
            tester.binding.handlePointerEvent(
              PointerRemovedEvent(
                device: pointer.key,
                kind: PointerDeviceKind.mouse,
                position: pointer.value,
              ),
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          for (final editor in editors) {
            editor.dispose();
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

void _expectReveal(WidgetTester tester, String sample, bool visible) {
  final bars = find.descendant(
    of: find.byKey(ValueKey('sample-$sample')),
    matching: find.byType(PreviewToolbar),
  );
  expect(bars, findsNWidgets(3));
  for (final element in bars.evaluate()) {
    final fade = find
        .descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(AnimatedOpacity),
        )
        .first;
    expect(tester.widget<AnimatedOpacity>(fade).opacity, visible ? 1 : 0);
    expect(
      tester.renderObject<RenderAnimatedOpacity>(fade).opacity.value,
      visible ? 1 : 0,
    );
  }
}

EditorState _editor() => EditorState(
      document: Document(
        root: pageNode(
          children: [
            spreadsheetNode(
              width: 520,
              height: 270,
              data: SpreadsheetData.fromRows(
                [
                  ['Workstream', 'Owner', 'Progress'],
                  ['Research', 'Ari', '40%'],
                  ['Prototype', 'Ren', '65%'],
                  ['Review', 'Lee', '90%'],
                  ['Release', 'Sam', 'Planned'],
                ],
              )
                ..setColumn(
                    0, const SheetColumn(title: 'Workstream', width: 180),)
                ..setColumn(1, const SheetColumn(title: 'Owner', width: 120))
                ..setColumn(
                    2, const SheetColumn(title: 'Progress', width: 140),),
            ),
          ],
        ),
      ),
    )..disableSealTimer = true;

Widget _referenceSheet(
  BuildContext context,
  String appearance,
  List<EditorState> editors,
) {
  final theme = Theme.of(context);
  return RepaintBoundary(
    key: _reference,
    child: Material(
      color: EditorSurfaceStyle.canvasBackgroundFor(
        theme.brightness,
        theme.scaffoldBackgroundColor,
        isPaper: PaperTheme.isEnabled(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Preview controls / ${appearance.toUpperCase()}',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Quiet at rest. Local controls on hover. Identity and content stay put.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < _samples.length; index++) ...[
                    if (index > 0) const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        key: ValueKey('sample-${_samples[index]}'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            index == 0 ? 'Idle' : 'Hover',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 240,
                            child: PreviewToolbarRegion(
                              child: _document(_samples[index], theme),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Spreadsheet', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Expanded(
                            child: AppFlowyEditor(
                              key: ValueKey('spreadsheet-${_samples[index]}'),
                              editorState: editors[index],
                              disableAutoScroll: true,
                              disableKeyboardService: true,
                              disableSelectionService: true,
                              editorStyle: EditorStyle.desktop(
                                padding: EdgeInsets.zero,
                                textStyleConfiguration: TextStyleConfiguration(
                                  text: theme.textTheme.bodyMedium!,
                                ),
                              ),
                              blockComponentBuilders: {
                                ...standardBlockComponentBuilderMap,
                                SpreadsheetBlockKeys.type:
                                    SpreadsheetBlockComponentBuilder(),
                              },
                              contextMenuItems: const [],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _document(String sample, ThemeData theme) => DocumentViewport(
      key: ValueKey('document-$sample'),
      identity: const DocumentIdentity(
        title: 'Field notes.txt',
        icon: Icons.description_outlined,
        subtitle: 'Plain text · Research brief',
      ),
      actions: [
        DocumentViewportButton(
          key: ValueKey('document-search-$sample'),
          icon: Icons.search_rounded,
          tooltip: 'Find in document',
          onPressed: () {},
        ),
        AppMenuIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Document options',
          entries: () => const [AppMenuItem(label: 'Document details')],
        ),
      ],
      floatingToolbar: DocumentFloatingToolbar(
        children: [
          DocumentViewportButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            onPressed: () {},
          ),
          const DocumentViewportLabel(label: '100%'),
          DocumentViewportButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom in',
            onPressed: () {},
          ),
          const DocumentViewportSeparator(),
          DocumentViewportFitButton(onPressed: () {}),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: SelectableText(
          'A calmer place to work\n\n'
          'Keep the document in view. Bring its tools forward only when '
          'they are useful, without moving the page beneath them.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      preferredFontFamily,
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  List<EditorState> editors,
) async {
  final theme = _theme(appearance);
  final defaults = AppFlowyDefaultTheme();
  await tester.pumpWidget(
    EasyLocalization(
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
          builder: (context, navigator) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: appearance == 'dark' ? defaults.dark() : defaults.light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: TooltipVisibility(visible: false, child: navigator!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  _referenceSheet(context, appearance, editors),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
