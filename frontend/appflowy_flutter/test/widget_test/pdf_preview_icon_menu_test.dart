import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'file_controls_test_support.dart';
import 'test_asset_bundle.dart';

const _previewIcon = ValueKey('file-preview-identity-icon');
const _iconButton = ValueKey('file-icon-picker-button');
const _frame = ValueKey('resizable_media');
const _pdfBytes = '%PDF synthetic icon-placement fixture';

// Actual editor, file block, PDF chrome, overflow and icon picker. Only the
// native decoder is unavailable: menu placement/identity must also work while
// a PDF cannot decode, without duplicating a native rasterizer test harness.
// Intentionally UNRUN in the restricted implementation session.
void main() {
  fileControlTestSetup();
  late Directory directory;
  late File pdf;
  late File text;
  late PdfDocumentFactory originalFactory;
  late _UnavailablePdfFactory factory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pdf-icon-menu-');
    pdf = await File('${directory.path}/report.pdf').writeAsString(_pdfBytes);
    text = await File('${directory.path}/notes.txt').writeAsString('Keep me.');
  });

  setUp(() {
    originalFactory = PdfDocumentFactory.instance;
    factory = _UnavailablePdfFactory();
    PdfDocumentFactory.instance = factory;
  });

  tearDown(() => PdfDocumentFactory.instance = originalFactory);
  tearDownAll(() => directory.delete(recursive: true));

  for (final mode in fileControlAppearances) {
    _test('$mode: PDF icon lives only in More, saves and survives chip mode',
        (tester) async {
      final fixture = _Fixture(pdf, 'report.pdf');
      try {
        await _mount(tester, fixture, mode: mode);
        expect(find.byKey(_previewIcon), findsNothing);
        expect(find.byType(FileBlockIconButton), findsNothing);
        expect(
          find.byKey(const ValueKey('file-preview-media-actions')),
          findsOneWidget,
        );
        final previewState = tester.state(find.byType(FilePreview));
        final materializer = tester.state(find.byType(MaterializedFileBuilder));
        final pdfState = tester.state(find.byType(PdfPreview));
        final viewerState = tester.state(find.byType(PdfViewer));
        final bounds = tester.getRect(find.byKey(_frame));
        final future = _previewFuture(tester);
        final before = Map<String, dynamic>.from(fixture.node.attributes);
        final neighbor = fixture.editor.document.root.children[1];
        final draft = neighbor.delta!.toPlainText();

        await _openPdfMenu(tester);
        final menu = tester.widget<FileBlockMenu>(find.byType(FileBlockMenu));
        expect(menu.onChangeIcon, isNull, reason: 'No dead host-side callback');
        expect(find.byType(FileBlockIconButton), findsOneWidget);
        expect(find.byKey(_previewIcon), findsNothing);
        expect(
          find.text(LocaleKeys.document_plugins_cover_changeIcon.tr()),
          findsOneWidget,
        );
        final owner = tester.widget<FileBlockIconButton>(
          find.byType(FileBlockIconButton),
        );
        final binding = owner.binding;
        expect(owner.showLabel, isTrue);
        expect(_glyph(tester).icon.emoji, '📄');
        final anchor = tester.getRect(find.byKey(_iconButton));
        expect(anchor.isFinite, isTrue);
        expect(anchor.isEmpty, isFalse);
        expect(anchor.left, greaterThanOrEqualTo(0));
        expect(anchor.right, lessThanOrEqualTo(1200));
        if (mode == 'paper') {
          expect(
            PaperTheme.isEnabled(tester.element(find.byKey(_iconButton))),
            isTrue,
          );
          final hover = tester
              .widget<TextButton>(find.byKey(_iconButton))
              .style!
              .overlayColor!
              .resolve({WidgetState.hovered})!;
          expect(hover.r, greaterThan(hover.b));
          expect(hover, isNot(Colors.white));
        }

        await clickFileControl(tester, find.byKey(_iconButton));
        final picker = tester.widget<FlowyIconEmojiPicker>(
          find.byType(FlowyIconEmojiPicker),
        );
        expect(picker.tabs, kAllIconPickerTabs);
        const expectedTabs = [
          PickerTabType.emoji,
          PickerTabType.defaultIcons,
          PickerTabType.icon,
          PickerTabType.custom,
        ];
        expect(picker.effectiveTabs, expectedTabs);
        expect(
          tester.widget<PickerTab>(find.byType(PickerTab)).tabs,
          expectedTabs,
        );
        expect(keepEditorFocusNotifier.value, fixture.focusHolds + 1);
        picker.onSelectedEmoji!(EmojiIconData.emoji('📚').toSelectedResult());
        await settleFileControls(tester);
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        expect(
          find.byType(FileBlockMenu),
          findsOneWidget,
          reason: 'More stays open so the child picker has a live anchor',
        );
        expect(find.byType(FileBlockIconButton), findsOneWidget);
        expect(_glyph(tester).icon.emoji, '📚');
        expect(keepEditorFocusNotifier.value, fixture.focusHolds);
        expect(
          Map<String, dynamic>.from(fixture.node.attributes)
            ..remove(FileBlockKeys.icon),
          before..remove(FileBlockKeys.icon),
        );
        expect(neighbor.delta!.toPlainText(), draft);
        expect(tester.state(find.byType(FilePreview)), same(previewState));
        expect(
          tester.state(find.byType(MaterializedFileBuilder)),
          same(materializer),
        );
        expect(tester.state(find.byType(PdfPreview)), same(pdfState));
        expect(tester.state(find.byType(PdfViewer)), same(viewerState));
        expect(_previewFuture(tester), same(future));
        expect(tester.getRect(find.byKey(_frame)), bounds);
        expect(factory.opened, [pdf.path]);
        expect(await tester.runAsync(pdf.readAsString), _pdfBytes);

        menu.onClose!();
        await settleFileControls(tester);
        expect(find.byType(FileBlockIconButton), findsNothing);
        await _openPdfMenu(tester);
        expect(
          tester
              .widget<FileBlockIconButton>(find.byType(FileBlockIconButton))
              .binding,
          same(binding),
        );
        expect(_glyph(tester).icon.emoji, '📚');
        await tester.ensureVisible(find.text('Show as file'));
        await clickFileControl(tester, find.text('Show as file'));
        expect(find.byKey(const ValueKey('file-block-chip')), findsOneWidget);
        expect(find.byType(FileBlockMenu), findsNothing);
        expect(find.byType(FileBlockIconButton), findsOneWidget);
        expect(_glyph(tester).icon.emoji, '📚');
        expect(
          tester
              .widget<FileBlockIconButton>(find.byType(FileBlockIconButton))
              .showLabel,
          isFalse,
        );
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  _test(
      'other file previews retain the original bottom-left icon and menu action',
      (tester) async {
    final fixture = _Fixture(text, 'notes.txt');
    try {
      await _mount(tester, fixture, mode: 'paper');
      expect(find.byKey(_previewIcon), findsOneWidget);
      expect(find.byType(FileBlockIconButton), findsOneWidget);
      expect(tester.widget<Positioned>(find.byKey(_previewIcon)).left, 48);
      expect(tester.widget<Positioned>(find.byKey(_previewIcon)).bottom, 20);
      expect(
        tester
            .widget<FileBlockIconButton>(find.byType(FileBlockIconButton))
            .showLabel,
        isFalse,
      );
      await clickFileControl(tester, find.byTooltip('More actions'));
      expect(
        tester.widget<FileBlockMenu>(find.byType(FileBlockMenu)).onChangeIcon,
        isNotNull,
      );
      await clickFileControl(
        tester,
        find.text(LocaleKeys.document_plugins_cover_changeIcon.tr()),
      );
      final picker = tester.widget<FlowyIconEmojiPicker>(
        find.byType(FlowyIconEmojiPicker),
      );
      picker.onSelectedEmoji!(EmojiIconData.emoji('📚').toSelectedResult());
      await settleFileControls(tester);
      expect(find.byKey(_previewIcon), findsOneWidget);
      expect(_glyph(tester).icon.emoji, '📚');
      expect(await tester.runAsync(text.readAsString), 'Keep me.');
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final invalidation in ['read-only', 'menu dismissed']) {
    _test('PDF picker cannot save a late selection after $invalidation',
        (tester) async {
      final fixture = _Fixture(pdf, 'report.pdf');
      try {
        await _mount(tester, fixture);
        await _openPdfMenu(tester);
        await clickFileControl(tester, find.byKey(_iconButton));
        final lateSelection = tester
            .widget<FlowyIconEmojiPicker>(
              find.byType(FlowyIconEmojiPicker),
            )
            .onSelectedEmoji!;
        final before = jsonEncode(fixture.editor.document.toJson());
        if (invalidation == 'read-only') {
          fixture.editor.editable = false;
        } else {
          tester.widget<FileBlockMenu>(find.byType(FileBlockMenu)).onClose!();
        }
        // Submit before the next frame, including the menu's closing animation.
        lateSelection(EmojiIconData.emoji('❌').toSelectedResult());
        await settleFileControls(tester);
        expect(jsonEncode(fixture.editor.document.toJson()), before);
        expect(keepEditorFocusNotifier.value, fixture.focusHolds);
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        expect(find.byKey(_previewIcon), findsNothing);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  _test('read-only PDF preserves its saved icon in More without an edit action',
      (tester) async {
    final fixture = _Fixture(pdf, 'report.pdf', editable: false);
    try {
      await _mount(tester, fixture);
      final before = jsonEncode(fixture.editor.document.toJson());
      expect(find.byKey(_previewIcon), findsNothing);
      await _openPdfMenu(tester);
      expect(_glyph(tester).icon.emoji, '📄');
      expect(
        tester.widget<TextButton>(find.byKey(_iconButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(_iconButton));
      await settleFileControls(tester);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(jsonEncode(fixture.editor.document.toJson()), before);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 30)),
    );

FileIdentityGlyph _glyph(WidgetTester tester) =>
    tester.widget<FileIdentityGlyph>(
      find.descendant(
        of: find.byKey(_iconButton),
        matching: find.byType(FileIdentityGlyph),
      ),
    );

Future<Widget>? _previewFuture(WidgetTester tester) => tester
    .widget<FutureBuilder<Widget>>(
      find
          .descendant(
            of: find.byType(FilePreview),
            matching: find.byType(FutureBuilder<Widget>),
          )
          .first,
    )
    .future;

Future<void> _openPdfMenu(WidgetTester tester) async {
  await clickFileControl(
    tester,
    find.byKey(const ValueKey('pdf-overflow-menu')),
  );
  await tester.ensureVisible(find.byKey(_iconButton));
  await settleFileControls(tester);
  expect(find.byKey(_iconButton).hitTestable(), findsOneWidget);
}

class _Fixture {
  _Fixture(File file, this.name, {bool editable = true}) {
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            Node(
              type: FileBlockKeys.type,
              attributes: {
                FileBlockKeys.url: file.path,
                FileBlockKeys.urlType: FileUrlType.local.toIntValue(),
                FileBlockKeys.name: name,
                FileBlockKeys.displayMode: 'preview',
                FileBlockKeys.width: 620.0,
                FileBlockKeys.height: 400.0,
                FileBlockKeys.previewMetadata: {'fixture': 'preserve'},
                FileBlockKeys.icon: EmojiIconData.emoji('📄').toStorageString(),
              },
            ),
            paragraphNode(text: 'Neighboring unsaved document text'),
          ],
        ),
      ),
    )
      ..disableSealTimer = true
      ..editable = editable;
  }

  final String name;
  final focusHolds = keepEditorFocusNotifier.value;
  late final EditorState editor;
  Node get node => editor.document.root.children.first;

  Future<void> dispose(WidgetTester tester) async {
    await unmountFileControls(tester);
    if (!editor.isDisposed) editor.dispose();
    expect(keepEditorFocusNotifier.value, focusHolds);
    expect(tester.takeException(), isNull);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String mode = 'light',
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = fileControlTheme(mode);
  final defaults = AppFlowyDefaultTheme();
  // The appearance provider must sit above the Navigator for the real menu.
  await tester.pumpWidget(
    Provider<AppearanceSettingsCubit>.value(
      value: _Appearance(),
      child: EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        fallbackLocale: const Locale('en', 'US'),
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: const TestBundleAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: mode == 'dark' ? defaults.dark() : defaults.light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: MediaQuery(
                data:
                    MediaQuery.of(context).copyWith(accessibleNavigation: true),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 820,
                  height: 760,
                  child: AppFlowyEditor(
                    editorState: fixture.editor,
                    editable: fixture.editor.editable,
                    disableAutoScroll: true,
                    disableKeyboardService: true,
                    editorStyle:
                        const EditorStyle.desktop(padding: EdgeInsets.all(40)),
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      FileBlockKeys.type: FileBlockComponentBuilder(),
                    },
                    contextMenuItems: const [],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  bool ready() => fixture.name.endsWith('.pdf')
      ? find.byType(PdfViewer).evaluate().isNotEmpty
      : find.byType(SelectableText).evaluate().isNotEmpty;
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
  await settleFileControls(tester);
}

class _Appearance extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => _AppearanceState();
}

class _AppearanceState extends Fake implements AppearanceSettingsState {
  @override
  UserDateFormatPB get dateFormat => UserDateFormatPB.values.first;
}

class _UnavailablePdfFactory extends Fake implements PdfDocumentFactory {
  final opened = <String>[];

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    opened.add(filePath);
    throw const FormatException('Synthetic decoder boundary');
  }
}
