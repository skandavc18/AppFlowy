import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/settings/pages/default_icon_style_setting.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'file_controls_test_support.dart';
import 'vivid_icon_test_support.dart';

// NEW references only: the coordinator must generate, inspect, then compare
// goldens/file_controls_{light,dark,paper}.png. This scoped change does not run
// tests or generate PNGs. No production widget, existing test or SDK is changed.
//
// A component sheet, not a reconstructed app: only labels/constraints and IO
// boundaries are fixtures. WorkspaceFileView supplies every header, editor,
// cover and action; ArchiveExplorer supplies the actual ArchiveGallery/cards.
// No Run, code Copy, media Copy/Share, file picker or archive mutation is invoked.
// The ZIP recipe extends archive_controls_regression_test.dart's cache.bin
// fixture with deterministic entries. All input files are synthetic; extraction
// uses ArchiveExplorer's owned temporary working copies, never workspace data.
//
// FONT LIMIT: fileControlTestSetup seeds GoogleFonts' JetBrains Mono variant
// cache with bundled Roboto Mono Regular. We explicitly load the SAME aliases
// below and verify their rendered metrics. This is NOT JetBrains typography
// verification, nor verification of genuine medium/bold monospace font faces.
const _fontNotice =
    'Code: bundled Roboto Mono Regular substituted for JetBrains '
    'Mono (all weights); UI: bundled DM Sans / Inter. No font downloads.';
const _sheetKey = ValueKey('file-controls-visual-sheet');
const _bodyKey = ValueKey('file-controls-specimen-body');
const _sheetSize = Size(2072, 1800);
const _columnWidth = 1000.0;
const _narrowWidth = 320.0;
const _textWidth = 656.0;
const _codeHeight = 440.0;
const _archiveHeight = 540.0;
const _smallHeight = 280.0;
const _ioTimeout = Duration(seconds: 10);
const _park = Offset(4, 4);
const _monoAsset = 'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf';
const _archiveName = 'Review bundle # 100%.zip';
const _code = '# Display only: never executed.\n'
    'def total(values):\n'
    '    return sum(values)\n'
    '\n'
    'result = total([12, 18, 24])';
const _notes = 'Inspection notes\n'
    'Real file controls, not drawn replicas.\n'
    'Hover reveals tools without moving the source.\n'
    'Archive previews read synthetic files only.\n'
    'Light, Dark and Paper share the same layout.';

final _loadedFamilies = <String>{};
final _monoAliases = <String>{};

void main() {
  fileControlTestSetup();
  setUpAll(() async {
    // The Vivid helper loads DM Sans under the RESOLVED UI family, not merely
    // the requested Windows face. We use its exact theme in the sheet too.
    await prepareVividIconTestAssets().timeout(_ioTimeout);
    for (final mode in fileControlAppearances) {
      final family = vividIconTestTheme(mode).textTheme.bodyMedium!.fontFamily!;
      _loadedFamilies.add(family);
    }
    await _loadFont('Inter', const [
      'assets/google_fonts/Inter/Inter-Variable.ttf',
      'assets/google_fonts/Inter/Inter-VariableItalic.ttf',
    ]);
    // Archive code previews explicitly request RobotoMono. The real expanding
    // editors request GoogleFonts variant aliases; loading only RobotoMono
    // would leave those editors using the widget-test fallback face (Ahem).
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      _monoAliases.add(
        codeUiTextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: weight,
        ).fontFamily!,
      );
    }
    for (final family in {builtInCodeFontFamily, ..._monoAliases}) {
      await _loadFont(family, const [_monoAsset]);
    }
    await _loadFont('MaterialIcons', const ['fonts/MaterialIcons-Regular.otf']);
  });

  Directory? temporary;
  var columns = <_ColumnFixture>[];
  setUp(() async {
    temporary = await Directory.systemTemp
        .createTemp('file-controls-visual-')
        .timeout(_ioTimeout);
    final model = Archive();
    // Local noon avoids a date boundary in the ZIP's local-time encoding.
    final modified = DateTime(2026, 9, 14, 12).millisecondsSinceEpoch ~/ 1000;
    for (final entry in const {
      'Examples/demo.py': _code,
      'Notes.txt': _notes,
      'summary.py': _code,
    }.entries) {
      final bytes = utf8.encode(entry.value);
      model.addFile(
        ArchiveFile(entry.key, bytes.length, bytes)..lastModTime = modified,
      );
    }
    final archive = await File('${temporary!.path}/cache.bin')
        .writeAsBytes(ZipEncoder().encode(model)!, flush: true)
        .timeout(_ioTimeout);
    columns = [
      for (final style in DefaultIconStyle.values)
        _ColumnFixture(style, archive),
    ];
    for (final column in columns) {
      expect(await column.store.ensureLoaded().timeout(_ioTimeout), isTrue);
    }
  });
  tearDown(() async {
    for (final column in columns) {
      column.dispose();
    }
    columns = [];
    final directory = temporary;
    temporary = null;
    if (directory != null) {
      await directory.delete(recursive: true).timeout(_ioTimeout);
    }
  });

  for (final mode in fileControlAppearances) {
    testWidgets(
      '$mode: actual file controls, hover and cover; Roboto Mono substitution',
      (tester) async {
        tester.view.physicalSize = _sheetSize;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final mice = <TestGesture>[];
        try {
          await tester.pumpWidget(
            vividIconTestApp(
              mode,
              Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  final defaults = AppFlowyDefaultTheme();
                  return AppFlowyTheme(
                    data: PremiumTheme.appFlowyTheme(
                      base: mode == 'dark' ? defaults.dark() : defaults.light(),
                      palette: theme.extension<PremiumThemeExtension>()!,
                      brightness: theme.brightness,
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling,
                        // No accessibility/keepVisible override: the capture
                        // must earn its visible controls through real hover.
                        accessibleNavigation: false,
                        disableAnimations: false,
                      ),
                      child: TooltipVisibility(
                        visible: false,
                        child: _ReviewSheet(mode: mode, columns: columns),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await _waitForFiles(tester);

          // Distinct DEVICE ids are necessary, not just pointer ids: Flutter
          // otherwise treats every mouse as device 1 and exits the last panel.
          // Multiple synthetic mice let one sheet show actual hover in each
          // specimen without manually invoking MouseRegion callbacks.
          for (var i = 0; i < columns.length * 4; i++) {
            final mouse = TestGesture(
              dispatcher: tester.sendEventToBinding,
              pointer: 100 + i,
              device: 100 + i,
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: _park);
            mice.add(mouse);
          }
          for (final (index, column) in columns.indexed) {
            await _exerciseRetainedCode(tester, column, mice[index * 4]);
          }

          // The click helper uses mouse device 1. Park it as well, otherwise
          // its last button could keep a toolbar visible during the idle gate.
          await tester.sendEventToBinding(
            const PointerHoverEvent(
              kind: PointerDeviceKind.mouse,
              device: 1,
              position: _park,
            ),
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await settleFileControls(tester);
          for (final column in columns) {
            for (final id in _panelIds) {
              expect(
                _keyed(column.panel(id), 'media-copy').hitTestable(),
                findsNothing,
              );
            }
          }
          final idleSources = [
            for (final element in _sourceFields.evaluate())
              (
                element: element,
                field: element.widget as TextField,
                bounds: tester.getRect(
                  find.byElementPredicate(
                    (candidate) => identical(candidate, element),
                  ),
                ),
              ),
          ];

          for (final (index, column) in columns.indexed) {
            final targets = [
              _keyed(column.panel('wide'), 'workspace-file-cover'),
              _within(
                column.panel('archive'),
                find.byTooltip('Reload archive'),
              ),
              _keyed(column.panel('narrow'), 'code-collapse'),
              _within(column.panel('text'), find.byTooltip('Show preview')),
            ];
            for (final (offset, target) in targets.indexed) {
              await mice[index * 4 + offset].moveTo(tester.getCenter(target));
              await settleFileControls(tester);
            }
          }
          await _settlePictures(tester);
          for (final saved in idleSources) {
            final finder = find.byElementPredicate(
              (element) => identical(element, saved.element),
            );
            expect(finder, findsOneWidget);
            final field = tester.widget<TextField>(finder);
            expect(field.controller, same(saved.field.controller));
            expect(field.focusNode, same(saved.field.focusNode));
            expect(field.scrollController, same(saved.field.scrollController));
            expect(field.expands, isTrue);
            expect(
              tester.getRect(finder),
              saved.bounds,
              reason: 'Hover cannot move, shrink or remount any source editor',
            );
          }
          _expectSheet(tester, mode, columns);
          await expectLater(
            find.byKey(_sheetKey),
            matchesGoldenFile('goldens/file_controls_$mode.png'),
          );
        } finally {
          for (final mouse in mice) {
            await mouse.removePointer();
          }
          await unmountFileControls(tester);
        }
        for (final column in columns) {
          column.expectIsolated(unmounted: true);
        }
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
}

const _panelIds = ['wide', 'archive', 'narrow', 'text'];

class _ColumnFixture {
  _ColumnFixture(this.style, File archive) {
    preferences = _IconPreference(style);
    store = DefaultIconStyleStore(resolveStorage: () => preferences);
    wide = _memory('wide', 'summary.py', _code);
    narrow = _memory('narrow', 'compact.py', _code);
    text = _memory('text', 'Inspection notes.txt', _notes);
    wide.stored.extra = ViewCoverCodec.mergeCover(wide.stored.extra, cover);
    bundle = FileControlBackend(
      fileControlView('${style.name}-archive', _archiveName, archive.path),
      archive,
    );
  }

  final DefaultIconStyle style;
  final width = ValueNotifier(_columnWidth);
  late final _IconPreference preferences;
  late final DefaultIconStyleStore store;
  late final FileControlBackend wide, narrow, text, bundle;
  final cover = PageStyleCover(
    type: PageStyleCoverImageType.gradientColor,
    value: FlowyGradientColor.gradient7.id,
  );

  String get label =>
      style == DefaultIconStyle.monochrome ? 'Outline' : 'Vivid';
  Iterable<FileControlBackend> get backends => [wide, bundle, narrow, text];
  Finder panel(String id) => find.byKey(ValueKey('${style.name}-$id'));

  FileControlBackend _memory(String id, String name, String contents) {
    final file = MemoryCodeFile(
      contents,
      path: '/fixture/${style.name}/$name',
    );
    return FileControlBackend(
      fileControlView('${style.name}-$id', name, file.path),
      file,
    );
  }

  Widget viewer(String id, FileControlBackend backend) => KeyedSubtree(
        key: ValueKey('${style.name}-$id'),
        child: backend.viewer(),
      );

  void expectIsolated({bool unmounted = false}) {
    expect(preferences.reads, 1);
    expect(preferences.writes, 0);
    expect(store.value, style);
    for (final backend in backends) {
      expect(backend.loads, 1);
      expect(backend.media.copies, isEmpty);
      expect(backend.media.shares, isEmpty);
      expect(backend.renames, isEmpty);
      expect(backend.iconWrites, isEmpty);
      expect(backend.covers.saves, isEmpty);
      expect(backend.covers.deleted, isEmpty);
      expect(backend.extraWrites, hasLength(identical(backend, wide) ? 2 : 0));
      expect(backend.listeners, hasLength(1));
      if (unmounted) expect(backend.listeners.single.stopped, isTrue);
      if (backend.file case final MemoryCodeFile file) {
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(file.contents, identical(backend, text) ? _notes : _code);
      }
    }
  }

  void dispose() {
    width.dispose();
    store.dispose();
  }
}

/// Only the preference's storage boundary is synthetic, not the settings UI.
class _IconPreference extends Fake implements KeyValueStorage {
  _IconPreference(this.style);
  final DefaultIconStyle style;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> get(String key) async {
    expectSync(key, DefaultIconStyleStore.storageKey);
    reads++;
    return style.name;
  }

  @override
  Future<void> set(String key, String value) async {
    writes++;
    throw StateError('Visual review must not write a device preference');
  }
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.mode, required this.columns});
  final String mode;
  final List<_ColumnFixture> columns;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        key: _sheetKey,
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SizedBox.fromSize(
            size: _sheetSize,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 88,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FILE CONTROLS · ${mode.toUpperCase()}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'Actual viewers · synthetic files · hover shown · '
                          'no execution, native handoffs or user data',
                        ),
                        Text(
                          _fontNotice,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, column) in columns.indexed) ...[
                        if (index != 0) const SizedBox(width: 24),
                        DefaultIconStyleScope(
                          styles: column.store.styles,
                          child: SizedBox(
                            width: _columnWidth,
                            child: _StyleColumn(data: column),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _StyleColumn extends StatelessWidget {
  const _StyleColumn({required this.data});
  final _ColumnFixture data;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 28,
            child:
                Text(data.label, style: Theme.of(context).textTheme.titleSmall),
          ),
          SizedBox(
            height: 216,
            child: DefaultIconStyleSetting(store: data.store),
          ),
          const SizedBox(height: 16),
          _Specimen(
            label:
                '1000 × 440 · code header + shared file actions + cover hover',
            size: const Size(_columnWidth, _codeHeight),
            child: ValueListenableBuilder<double>(
              valueListenable: data.width,
              child: data.viewer('wide', data.wide),
              builder: (_, width, child) => Align(
                alignment: Alignment.topLeft,
                child:
                    SizedBox(width: width, height: _codeHeight, child: child),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Specimen(
            label: '1000 × 540 · actual archive gallery · Reload hovered',
            size: const Size(_columnWidth, _archiveHeight),
            child: data.viewer('archive', data.bundle),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Specimen(
                label: '320 × 280 · wrapping code controls',
                size: const Size(_narrowWidth, _smallHeight),
                child: data.viewer('narrow', data.narrow),
              ),
              const SizedBox(width: 24),
              _Specimen(
                label: '656 × 280 · expanding text source · Preview hovered',
                size: const Size(_textWidth, _smallHeight),
                child: data.viewer('text', data.text),
              ),
            ],
          ),
        ],
      );
}

/// Captions and exact constraints only; never a hand-drawn control or editor.
class _Specimen extends StatelessWidget {
  const _Specimen({
    required this.label,
    required this.size,
    required this.child,
  });
  final String label;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 28,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox.fromSize(key: _bodyKey, size: size, child: child),
          ],
        ),
      );
}

Future<void> _waitForFiles(WidgetTester tester) async {
  // Same bounded real-IO/fake-frame pattern as archive_controls_regression_test.
  // A spinner can animate forever, so never use unbounded pumpAndSettle here.
  bool ready() {
    final galleries =
        tester.widgetList<ArchiveGallery>(find.byType(ArchiveGallery));
    return galleries.length == 2 &&
        galleries.every((gallery) => gallery.entries.length == 3) &&
        _sourceFields.evaluate().length == 6 &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find
            .byKey(const ValueKey('folder-gallery-preview-loading'))
            .evaluate()
            .isEmpty;
  }

  for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await settleFileControls(tester);
    expect(tester.takeException(), isNull);
  }
  expect(
    ready(),
    isTrue,
    reason: 'Real source and archive previews must finish',
  );
  await settleFileControls(tester);
}

Future<void> _settlePictures(WidgetTester tester) async {
  // The Vivid helper's actual SVG decoder recipe, with a real-time deadline
  // and the existing bounded file-control pumps instead of pumpAndSettle.
  final elements = find.byType(SvgPicture).evaluate().toList();
  await tester.runAsync(() async {
    await Future.wait(
      elements.map((element) async {
        final svg = element.widget as SvgPicture;
        final picture = await vg.loadPicture(svg.bytesLoader, element);
        picture.picture.dispose();
      }),
    ).timeout(_ioTimeout);
  });
  await settleFileControls(tester);
}

Future<void> _exerciseRetainedCode(
  WidgetTester tester,
  _ColumnFixture column,
  TestGesture mouse,
) async {
  final pane = column.panel('wide');
  final fieldFinder = _within(pane, _sourceFields);
  final field = tester.widget<TextField>(fieldFinder);
  final editor = tester.state<EditableTextState>(
    _within(fieldFinder, find.byType(EditableText)),
  );
  final preview = tester.element(_within(pane, find.byType(FilePreview)));
  final runner =
      tester.element(_within(pane, find.byType(SandboxedCodeRunner)));
  final actions = tester.state(_within(pane, find.byType(MediaActionButtons)));
  const selection = TextSelection(baseOffset: 2, extentOffset: 14);
  field.controller!.selection = selection;
  final originalRect = tester.getRect(fieldFinder);

  void retained() {
    final current = tester.widget<TextField>(fieldFinder);
    expect(current.expands, isTrue);
    expect(current.controller, same(field.controller));
    expect(current.focusNode, same(field.focusNode));
    expect(current.scrollController, same(field.scrollController));
    expect(current.controller!.text, _code);
    expect(current.controller!.selection, selection);
    expect(
      tester.state<EditableTextState>(
        _within(fieldFinder, find.byType(EditableText)),
      ),
      same(editor),
    );
    expect(
      tester.element(_within(pane, find.byType(FilePreview))),
      same(preview),
    );
    expect(
      tester.element(_within(pane, find.byType(SandboxedCodeRunner))),
      same(runner),
    );
    expect(
      tester.state(_within(pane, find.byType(MediaActionButtons))),
      same(actions),
    );
    expect((column.wide.file as MemoryCodeFile).reads, 1);
    expect((column.wide.file as MemoryCodeFile).writes, 0);
  }

  FocusManager.instance.primaryFocus?.unfocus();
  await settleFileControls(tester);
  expect(_keyed(pane, 'media-copy').hitTestable(), findsNothing);
  await mouse.moveTo(tester.getCenter(_keyed(pane, 'code-collapse')));
  await settleFileControls(tester);
  expectFileControlPainted(tester, _keyed(pane, 'media-copy'));
  expect(
    tester.getRect(fieldFinder),
    originalRect,
    reason: 'Hover must not move or shrink the source',
  );
  _expectHoveredButton(tester, _keyed(pane, 'code-collapse'));

  for (final selected in [false, true]) {
    await clickFileControl(tester, _keyed(pane, 'code-line-numbers'));
    expect(
      tester
          .widget<CodeToolbarButton>(
            _keyed(pane, 'code-line-numbers'),
          )
          .selected,
      selected,
    );
    retained();
  }
  await clickFileControl(tester, _keyed(pane, 'code-collapse'));
  expect(
    tester.widget<CodeToolbarButton>(_keyed(pane, 'code-collapse')).tooltip,
    'Expand code',
  );
  retained();
  await clickFileControl(tester, _keyed(pane, 'code-collapse'));
  expect(
    tester.widget<CodeToolbarButton>(_keyed(pane, 'code-collapse')).tooltip,
    'Collapse code',
  );
  retained();

  column.width.value = _narrowWidth;
  await settleFileControls(tester);
  expect(tester.getSize(pane).width, _narrowWidth);
  _expectCodeControls(tester, pane);
  _inside(tester, fieldFinder, pane);
  retained();
  column.width.value = _columnWidth;
  await settleFileControls(tester);

  final covered = ViewPB.fromBuffer(column.wide.stored.writeToBuffer());
  final beforeCoverChange = tester.getSize(fieldFinder);
  column.wide.publish(
    ViewPB.fromBuffer(covered.writeToBuffer())
      ..extra =
          ViewCoverCodec.mergeCover(covered.extra, const PageStyleCover.none()),
  );
  await settleFileControls(tester);
  expect(_keyed(pane, 'workspace-file-cover'), findsNothing);
  expect(
    tester.getSize(fieldFinder).height,
    greaterThan(beforeCoverChange.height),
  );
  retained();
  column.wide.publish(covered);
  await settleFileControls(tester);
  expect(tester.getSize(fieldFinder), beforeCoverChange);
  retained();
  await mouse.moveTo(_park);
  await settleFileControls(tester);
}

void _expectSheet(
  WidgetTester tester,
  String mode,
  List<_ColumnFixture> columns,
) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byType(InAppWebView), findsNothing);
  expect(find.text('Terminal'), findsNothing);
  expect(find.byKey(const ValueKey('default-icon-style-status')), findsNothing);
  expect(
    find.byKey(const ValueKey('folder-gallery-preview-loading')),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey('folder-gallery-preview-unavailable')),
    findsNothing,
  );
  expect(find.byType(WorkspaceFileView), findsNWidgets(8));
  expect(find.byType(MediaActionButtons), findsNWidgets(8));
  expect(find.byKey(const ValueKey('media-copy')), findsNWidgets(8));
  expect(find.byKey(const ValueKey('media-share')), findsNWidgets(8));
  expect(find.byType(ArchiveExplorer), findsNWidgets(2));
  expect(find.byType(ArchiveGallery), findsNWidgets(2));
  expect(find.byType(FolderGalleryCard), findsNWidgets(6));
  expect(find.byType(SandboxedCodeRunner), findsNWidgets(4));
  expect(_sourceFields, findsNWidgets(6));
  expect(tester.getSize(find.byKey(_sheetKey)), _sheetSize);
  final context = tester.element(find.byKey(_sheetKey));
  expect(PaperTheme.isEnabled(context), mode == 'paper');
  expect(
    Theme.of(context).brightness,
    mode == 'dark' ? Brightness.dark : Brightness.light,
  );
  expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
  final family = Theme.of(context).textTheme.bodyMedium!.fontFamily!;
  expect(_loadedFamilies, contains(family));
  for (final uiFamily in {family, 'Inter'}) {
    final style = TextStyle(fontFamily: uiFamily, fontSize: 16);
    expect(
      _measure('iiii', style),
      lessThan(_measure('WWWW', style)),
      reason: '$uiFamily must be a loaded UI face, not Ahem',
    );
  }
  const mono = TextStyle(fontFamily: builtInCodeFontFamily, fontSize: 16);
  expect(_measure('iiii', mono), greaterThan(0));
  expect(
    _measure('iiii', mono),
    lessThan(64),
    reason: 'Ahem is also fixed-width, but is one em per character',
  );
  expect(_measure('iiii', mono), closeTo(_measure('WWWW', mono), 0.01));
  expect(_monoAliases, hasLength(4));

  for (final column in columns) {
    for (final id in _panelIds) {
      final pane = column.panel(id);
      final identity = _within(pane, find.byType(WorkspaceFileIdentityRow));
      _inside(tester, pane, find.byKey(_sheetKey));
      _inside(tester, identity, pane);
      expect(_keyed(pane, 'media-copy'), findsOneWidget);
      expect(_keyed(pane, 'media-share'), findsOneWidget);
      expect(_keyed(identity, 'media-copy'), findsOneWidget);
      expect(_keyed(identity, 'media-share'), findsOneWidget);
      final media = tester.widget<MediaActionButtons>(
        _within(pane, find.byType(MediaActionButtons)),
      );
      expect(media.decorated, isFalse);
      final backend = switch (id) {
        'wide' => column.wide,
        'archive' => column.bundle,
        'narrow' => column.narrow,
        _ => column.text,
      };
      expect(media.source.source, backend.file.path);
      expect(media.source.name, backend.stored.name);
      for (final action in ['media-copy', 'media-share']) {
        final finder = _keyed(pane, action);
        expect(finder.hitTestable(), findsOneWidget);
        expectFileControlPainted(tester, finder);
        _inside(tester, finder, identity);
      }
      _expectIdentityArtwork(tester, pane, column.style);
      if (id != 'archive') {
        final source = _within(pane, _sourceFields);
        final field = tester.widget<TextField>(source);
        expect(field.expands, isTrue);
        expect(field.maxLines, isNull);
        expect(field.readOnly, isFalse);
        expect(field.controller!.text, id == 'text' ? _notes : _code);
        expect(_monoAliases, contains(field.style!.fontFamily));
        expect(_loadedFamilies, contains(field.style!.fontFamily));
        expect(
          _measure('iiWW 0123 {}[]', field.style!),
          closeTo(
            _measure(
              'iiWW 0123 {}[]',
              field.style!.copyWith(fontFamily: builtInCodeFontFamily),
            ),
            0.01,
          ),
          reason:
              'The actual source alias must render the disclosed Roboto Mono',
        );
        _inside(tester, source, pane);
        expect(tester.getSize(source).height, greaterThan(40));
        final preview = _within(pane, find.byType(FilePreview));
        expect(_keyed(preview, 'media-copy'), findsNothing);
        if (id != 'text') _expectCodeControls(tester, pane);
      }
      final canvas =
          tester.widget<ColoredBox>(_keyed(pane, 'workspace-file-canvas'));
      expect(
        canvas.color,
        EditorSurfaceStyle.canvasBackgroundFor(
          Theme.of(context).brightness,
          Theme.of(context).scaffoldBackgroundColor,
          isPaper: mode == 'paper',
        ),
      );
    }

    final wide = column.panel('wide');
    expect(tester.getSize(wide), const Size(_columnWidth, _codeHeight));
    final cover = _keyed(wide, 'workspace-file-cover');
    expect(
      tester
          .widget<ViewCoverImage>(
            _within(cover, find.byType(ViewCoverImage)),
          )
          .cover,
      column.cover,
    );
    _inside(tester, cover, wide);
    final coverTools = _keyed(cover, 'workspace-cover-action-surface');
    expectFileControlPainted(tester, coverTools);
    _inside(tester, coverTools, cover);

    final archive = column.panel('archive');
    final explorer = _within(archive, find.byType(ArchiveExplorer));
    final controls = _keyed(archive, 'archive-controls');
    expect(
      _keyed(explorer, 'archive-controls'),
      findsNothing,
      reason: 'The real archive publishes into the shared identity header',
    );
    expect(_keyed(archive, 'archive-fullscreen-media-actions'), findsNothing);
    expect(_keyed(controls, 'media-copy'), findsOneWidget);
    for (final button
        in _within(controls, find.byType(ArchivePillButton)).evaluate()) {
      _expectSharedButton(tester, find.byWidget(button.widget));
      _inside(tester, find.byWidget(button.widget), controls);
    }
    final gallery = tester
        .widget<ArchiveGallery>(_within(archive, find.byType(ArchiveGallery)));
    expect(
      gallery.entries.map((entry) => entry.entry.path),
      ['Examples', 'Notes.txt', 'summary.py'],
    );
    for (final entry in gallery.entries.where((entry) => entry.entry.isFile)) {
      expect(entry.item.metadata!.contentKind, WorkspaceFileContentKind.binary);
    }
    for (final card
        in _within(archive, find.byType(FolderGalleryCard)).evaluate()) {
      _inside(tester, find.byWidget(card.widget), archive);
    }
    final prose = tester.widget<FolderGalleryRichTextPreview>(
      _within(archive, find.byType(FolderGalleryRichTextPreview)),
    );
    expect(prose.blocks.first.plainText, 'Inspection notes');
    expect(
      _within(
        archive,
        find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == _code,
        ),
      ),
      findsOneWidget,
    );
    _expectHoveredButton(
      tester,
      _within(archive, find.byTooltip('Reload archive')),
    );

    final narrow = column.panel('narrow');
    expect(tester.getSize(narrow), const Size(_narrowWidth, _smallHeight));
    final rows = <double>{};
    for (final key in ['code-language-menu', 'code-collapse', 'media-copy']) {
      rows.add(tester.getTopLeft(_keyed(narrow, key)).dy);
    }
    expect(
      rows.length,
      greaterThan(1),
      reason: 'The narrow toolbar really wraps',
    );
    _expectHoveredButton(tester, _keyed(narrow, 'code-collapse'));

    final text = column.panel('text');
    expect(tester.getSize(text), const Size(_textWidth, _smallHeight));
    final sourceToggle = _within(text, find.byTooltip('Show preview'));
    expect(sourceToggle, findsOneWidget);
    expect(_within(text, find.byType(SandboxedCodeRunner)), findsNothing);
    expect(
      _within(_within(text, find.byType(FilePreview)), sourceToggle),
      findsNothing,
    );
    _inside(
      tester,
      sourceToggle,
      _within(text, find.byType(WorkspaceFileIdentityRow)),
    );
    _expectHoveredButton(tester, sourceToggle);
    column.expectIsolated();
  }

  for (final setting in tester.widgetList<DefaultIconStyleSetting>(
    find.byType(DefaultIconStyleSetting),
  )) {
    expect(columns.map((column) => column.store), contains(setting.store));
    final tiles = tester.widgetList<RadioListTile<DefaultIconStyle>>(
      _within(
        find.byWidget(setting),
        find.byType(RadioListTile<DefaultIconStyle>),
      ),
    );
    expect(tiles, hasLength(2));
    for (final tile in tiles) {
      expect(tile.groupValue, setting.store!.value);
      expect(tile.onChanged, isNotNull);
    }
  }
  for (final specimen in tester.widgetList<_Specimen>(find.byType(_Specimen))) {
    final body = _within(find.byWidget(specimen), find.byKey(_bodyKey));
    expect(tester.getSize(body), specimen.size);
    _inside(tester, body, find.byKey(_sheetKey));
  }
  expect(tester.takeException(), isNull);
}

void _expectCodeControls(WidgetTester tester, Finder pane) {
  final controls = _keyed(pane, 'code-controls');
  expect(controls, findsOneWidget);
  final preview = _within(pane, find.byType(FilePreview));
  expect(
    _keyed(preview, 'code-controls'),
    findsNothing,
    reason: 'The source renderer publishes one shared header, not a duplicate',
  );
  expect(_keyed(controls, 'media-copy'), findsOneWidget);
  expect(_keyed(controls, 'media-share'), findsOneWidget);
  for (final key in [
    'code-language-menu',
    'code-line-numbers',
    'code-tests',
    'code-run',
    'code-copy',
    'code-collapse',
    'media-copy',
    'media-share',
  ]) {
    _inside(tester, _keyed(pane, key), controls);
  }
  for (final button
      in _within(controls, find.byType(CodeToolbarButton)).evaluate()) {
    _expectSharedButton(tester, find.byWidget(button.widget));
  }
  expect(
    tester.widget<CodeToolbarButton>(_keyed(pane, 'code-run')).icon,
    Icons.play_arrow_rounded,
  );
}

void _expectSharedButton(WidgetTester tester, Finder wrapper) {
  final shared = _within(wrapper, find.byType(WorkspaceControlButton));
  expect(shared, findsOneWidget);
  final native = _within(shared, _textButtons);
  expect(native, findsOneWidget);
  final button = tester.widget<TextButton>(native);
  final context = tester.element(native);
  expect(
    button.style!.shape!.resolve({}),
    WorkspaceChrome.controlStyle(context).shape!.resolve({}),
  );
  final family = button.style!.textStyle!.resolve({})!.fontFamily;
  expect(family, Theme.of(context).textTheme.bodyMedium!.fontFamily);
  expect(_loadedFamilies, contains(family));
  expect(_within(shared, find.byType(WorkspaceGlyph)), findsOneWidget);
}

void _expectHoveredButton(WidgetTester tester, Finder wrapper) {
  final native = _within(wrapper, _textButtons);
  expect(native.hitTestable(), findsOneWidget);
  final button = tester.widget<TextButton>(native);
  final context = tester.element(native);
  final hover = WorkspaceChrome.hoverColor(context);
  expect(button.style!.backgroundColor!.resolve({WidgetState.hovered}), hover);
  expect(
    button.style!.textStyle!.resolve({})!.fontFamily,
    Theme.of(context).textTheme.bodyMedium!.fontFamily,
  );
  // Assert the rendered native Material, not just a style resolver that would
  // still pass if hover never reached the real button.
  expect(
    tester.widget<Material>(_within(native, find.byType(Material))).color,
    hover,
  );
}

void _expectIdentityArtwork(
  WidgetTester tester,
  Finder pane,
  DefaultIconStyle style,
) {
  final glyph = _within(
    _keyed(pane, 'workspace-file-identity-icon'),
    find.byType(WorkspaceGlyph),
  );
  expect(glyph, findsOneWidget);
  expect(DefaultIconStyleScope.of(tester.element(glyph)).value, style);
  final name = tester.widget<WorkspaceGlyph>(glyph).name;
  final vivid = style == DefaultIconStyle.vivid
      ? WorkspaceGlyphs.vividNameFor(name)
      : null;
  final svg =
      tester.widget<SvgPicture>(_within(glyph, find.byType(SvgPicture)));
  final loader = svg.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      (vivid == null ? defaultIconSvg(name) : vividIconSvg(vivid))!,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
}

Finder _within(Finder parent, Finder matching) =>
    find.descendant(of: parent, matching: matching);
Finder _keyed(Finder parent, String key) =>
    _within(parent, find.byKey(ValueKey(key)));
Finder get _sourceFields =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.expands);
Finder get _textButtons =>
    find.byWidgetPredicate((widget) => widget is TextButton);

void _inside(WidgetTester tester, Finder child, Finder parent) {
  expect(child, findsOneWidget);
  expect(parent, findsOneWidget);
  final rect = tester.getRect(child);
  final bounds = tester.getRect(parent);
  expect(rect.isFinite, isTrue);
  expect(bounds.isFinite, isTrue);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
  expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
  expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
  expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
}

Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load().timeout(_ioTimeout);
  _loadedFamilies.add(family);
}

double _measure(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
