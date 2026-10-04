import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_view_options.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'file_controls_test_support.dart';
import 'vivid_icon_test_support.dart' show prepareVividIconTestAssets;

// Component review, NOT a whole-app/PDF-rendering fixture or a golden test.
// From frontend/appflowy_flutter, opt in with these flutter test arguments:
// --no-pub --dart-define=UI_REVIEW_DIRECTORY=build/performance
// test/widget_test/find_chrome_visual_review_test.dart
// Without the define, every layout/interaction assertion still runs, but no
// PNG is rasterized or written. Never reads, approves or updates a baseline.
// Fonts come from fileControlTestSetup/prepareVividIconTestAssets: bundled
// DM Sans (also under platform aliases), with bundled Roboto Mono standing in
// for JetBrains Mono. These are not screenshots of installed system fonts.
const _reviewDirectory = String.fromEnvironment('UI_REVIEW_DIRECTORY');
const _sheetSize = Size(1100, 1080);
const _deadline = Duration(seconds: 10);
const _hoverDuration = Duration(milliseconds: 140);
const _find = ValueKey('review-find');
const _sidebar = ValueKey('review-sidebar');
const _sidebarFile = ValueKey('review-sidebar-file');
const _sidebarLabel = ValueKey('review-sidebar-label');
const _sidebarMore = ValueKey('review-sidebar-more');
const _titleBar = ValueKey('review-title-bar');
const _specimenNames = [
  ('find-replace', 'Replace'),
  ('replace-all', 'Replace all'),
  ('fit-page', 'Fit page'),
  ('rotate', 'Rotate'),
  ('print', 'Print'),
  ('share', 'Share'),
];
const _findButtons = [
  'findToggleReplace',
  'findPreviousMatch',
  'findNextMatch',
  'findClose',
  'findReplaceOne',
  'findReplaceAll',
];
const _pdfTooltips = [
  'Show page thumbnails',
  'Show document outline',
  'Previous page (Page Up)',
  'Next page (Page Down)',
  'Zoom out (Ctrl/Cmd −)',
  'Zoom in (Ctrl/Cmd +)',
  'Fit whole page',
  'Fit options',
  'Search document (Ctrl/Cmd F)',
  'Rotate clockwise',
  'Download PDF',
  'Print PDF',
  'Open in full screen',
  'Reading mode',
  'More PDF options',
];

void main() {
  fileControlTestSetup();
  setUpAll(() async {
    await prepareVividIconTestAssets().timeout(_deadline);
    // Warm only actual production artwork on the real clock. No SVG is drawn
    // or substituted by this fixture, and no picker packs need opening.
    const names = {
      'workspace',
      'file-pdf',
      'folder',
      'file-code',
      'columns-2',
      'tree',
      'caret-up',
      'caret-down',
      'divider',
      'plus',
      'fit-page',
      'magnifying-glass',
      'rotate',
      'download',
      'print',
      'fullscreen',
      'density-medium',
      'dots-three',
      'copy',
      'share',
      'pen',
      'emoji',
      'image-plus',
      'x',
      'find-replace',
      'replace-all',
    };
    await Future.wait([
      for (final name in names)
        for (final theme in const <SvgTheme?>[null, SvgTheme()])
          SvgStringLoader(
            vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!,
            theme: theme,
          ).loadBytes(null),
    ]).timeout(_deadline);
  });

  for (final mode in fileControlAppearances) {
    testWidgets(
      '$mode: real Find and file chrome component review (optional PNG)',
      (tester) async {
        expect(
          _reviewDirectory,
          anyOf('', 'build/performance'),
          reason: 'Review exports may only target the app build/performance.',
        );
        final network = _NoNetwork();
        await HttpOverrides.runWithHttpOverrides(
          () async {
            tester.view.devicePixelRatio = 1;
            final semantics = tester.ensureSemantics();
            final boundaryKey = GlobalKey();
            final findKey = GlobalKey<_FindComponentState>();
            final samples = [
              _PdfSample('review-$mode-default'),
              _PdfSample('review-$mode-resized', iconSize: 112),
            ];
            final revealSheet = ValueNotifier(false);
            final pointers = <TestGesture>[];
            var pointerId = 1000 + fileControlAppearances.indexOf(mode) * 100;
            _FindComponentState? findState;

            Future<TestGesture> hover(Finder target) async {
              final mouse = _mouse(tester, pointerId++);
              await mouse.addPointer(location: const Offset(-20, -20));
              pointers.add(mouse);
              await _hover(tester, mouse, target);
              return mouse;
            }

            try {
              await mountFileControls(
                tester,
                DefaultIconStyleScope(
                  styles: const AlwaysStoppedAnimation(DefaultIconStyle.vivid),
                  child: TooltipVisibility(
                    visible: false,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: revealSheet,
                      // The helper initially creates a 1100x900 surface. Mount
                      // the sheet only AFTER enlarging it, not in an overflow
                      // box that would conceal a clipped first-frame layout.
                      builder: (_, visible, child) =>
                          visible ? child! : const SizedBox.shrink(),
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: _ReviewSheet(
                          mode: mode,
                          samples: samples,
                          findKey: findKey,
                        ),
                      ),
                    ),
                  ),
                ),
                mode: mode,
                width: _sheetSize.width,
                height: _sheetSize.height,
              );
              await tester.binding.setSurfaceSize(_sheetSize);
              revealSheet.value = true;
              await settleFileControls(tester);
              await _decodeActualPictures(tester);
              findState = findKey.currentState!;
              expect(tester.takeException(), isNull);

              // Exercise the REAL acknowledgement callback into local view
              // state, not an artificial transform. This is not a save claim.
              final first = samples.first;
              final resize =
                  _within(first.finder, find.byType(ResizablePageIcon));
              final retainedIcon = tester.element(resize);
              final retainedTitle = tester.element(
                _keyWithin(first.finder, 'workspace-file-name'),
              );
              tester.widget<ResizablePageIcon>(resize).onSizeChanged(112);
              await settleFileControls(tester);
              expect(IconSize.decode(first.view.value.extra), 112);
              expect(tester.getSize(first.frame), const Size.square(112));
              tester.widget<ResizablePageIcon>(resize).onSizeChanged(null);
              await settleFileControls(tester);
              expect(IconSize.decode(first.view.value.extra), isNull);
              expect(tester.getSize(first.frame), const Size.square(56));
              expect(tester.element(resize), same(retainedIcon));
              expect(
                tester.element(_keyWithin(first.finder, 'workspace-file-name')),
                same(retainedTitle),
              );
              expect(first.viewChanges, 2);

              // Real fractional pointer motion previews a new frame, then a
              // native cancel restores it without any metadata read or write.
              final iconMouse = await hover(first.frame);
              final origin = tester.getCenter(first.grip);
              final viewBytes = first.view.value.writeToBuffer();
              await iconMouse.down(origin);
              try {
                for (final delta in [27.375, 56.0]) {
                  await iconMouse.moveTo(origin + Offset(delta, delta));
                  await tester.pump();
                  expect(
                    tester.getSize(first.frame),
                    Size.square(56 + delta),
                    reason: 'The actual native frame must follow the pointer.',
                  );
                  expect(first.view.value.writeToBuffer(), viewBytes);
                  _expectInside(
                    tester.getRect(first.grip),
                    tester.getRect(first.frame),
                  );
                }
              } finally {
                await iconMouse.cancel();
                await tester.pump();
              }
              expect(tester.getSize(first.frame), const Size.square(56));
              expect(first.view.value.writeToBuffer(), viewBytes);
              expect(first.viewChanges, 2);
              await _hover(tester, iconMouse, first.frame);
              await hover(samples.last.frame);

              // Only local bookkeeping/fit callbacks are activated. Copy, Share,
              // Print, Download, title rename, cover and picker are never opened.
              await _click(tester, _findControl('findNextMatch'), pointerId++);
              expect(findState.currentMatch, 2);
              expect(find.text(_matchLabel(2)), findsOneWidget);
              await _click(
                tester,
                _findControl('findPreviousMatch'),
                pointerId++,
              );
              expect(findState.currentMatch, 1);
              await _click(
                tester,
                _within(first.finder, find.byTooltip('Fit whole page')),
                pointerId++,
              );
              expect(first.fitCalls, 1);
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pump();
              await tester.pump(_hoverDuration);
              // A second device leaving Fit clears the header's shared hover
              // flag. Re-enter with the retained icon pointer before capture.
              await iconMouse.moveTo(const Offset(-20, -20));
              await tester.pump();
              await _hover(tester, iconMouse, first.frame);

              final sidebarLabel = tester.getRect(find.byKey(_sidebarLabel));
              // Hit the painted label, not SidebarRow's non-opaque outer region.
              final sidebarMouse = await hover(find.byKey(_sidebarLabel));
              await _hover(tester, sidebarMouse, find.byKey(_sidebarMore));
              expect(tester.getRect(find.byKey(_sidebarLabel)), sidebarLabel);

              final findBounds = tester.getRect(find.byKey(_find));
              final controls = {
                for (final key in _findButtons)
                  key: tester.getRect(_findControl(key)),
              };
              await hover(_findControl('findNextMatch'));
              expect(tester.getRect(find.byKey(_find)), findBounds);
              for (final entry in controls.entries) {
                expect(tester.getRect(_findControl(entry.key)), entry.value);
              }
              // Includes lazy sidebar actions created by the actual hover.
              await _decodeActualPictures(tester);

              _expectFind(tester);
              _expectShell(tester, mode);
              for (final sample in samples) {
                _expectPdfHeader(tester, sample);
                sample.expectNoBackendWork();
                _expectInside(
                  tester.getRect(sample.finder),
                  tester.getRect(find.byKey(boundaryKey)),
                );
              }
              expect(find.byType(DocumentViewportHeader), findsNothing);
              expect(find.byType(FlowyIconEmojiPicker), findsNothing);
              expect(find.byType(AppMenuRow), findsNothing);
              expect(find.byType(StandaloneFileScope), findsNWidgets(2));
              expect(find.byType(PageIconBackendScope), findsOneWidget);
              expect(find.byType(DefaultIconStyleScope), findsOneWidget);
              expect(tester.getSize(find.byKey(boundaryKey)), _sheetSize);
              expect(network.attempts, 0);
              expect(tester.takeException(), isNull);
              await _captureIfRequested(tester, boundaryKey, mode);
              expect(tester.takeException(), isNull);
            } finally {
              try {
                for (final mouse in pointers.reversed) {
                  await mouse.removePointer();
                }
                await unmountFileControls(tester);
                expect(find.byType(StandaloneFileScope), findsNothing);
                expect(find.byType(PageIconBackendScope), findsNothing);
                expect(find.byType(DefaultIconStyleScope), findsNothing);
                expect(find.byType(PreviewToolbarRegion), findsNothing);
                if (findState != null) {
                  expect(findState.disposed, isTrue);
                  expect(findState.queryFocus.parent, isNull);
                  expect(findState.replaceFocus.parent, isNull);
                }
                for (final sample in samples) {
                  sample.expectNoBackendWork();
                  expect(sample.chrome.hasRegisteredListeners, isFalse);
                  expect(sample.view.hasRegisteredListeners, isFalse);
                }
                expect(network.attempts, 0);
                expect(tester.takeException(), isNull);
              } finally {
                // Dispose in the test body, before Flutter's semantics leak check.
                semantics.dispose();
                for (final sample in samples) {
                  sample.dispose();
                }
                revealSheet.dispose();
                tester.view.resetDevicePixelRatio();
                await tester.binding.setSurfaceSize(null);
              }
            }
          },
          network,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({
    required this.mode,
    required this.samples,
    required this.findKey,
  });

  final String mode;
  final List<_PdfSample> samples;
  final GlobalKey<_FindComponentState> findKey;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final caption =
        WorkspaceTypography.style(context, WorkspaceTextRole.caption);
    return ColoredBox(
      color: palette.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Find & file chrome',
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.section,
                  ),
                ),
                const Spacer(),
                Text(
                  '${mode.toUpperCase()} · COMPONENT REVIEW',
                  style: caption,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Synthetic data · real production widgets · not a whole-app screenshot',
              style: caption,
            ),
            const SizedBox(height: 12),
            WorkspaceSurface(
              kind: WorkspaceSurfaceKind.canvas,
              radius: WorkspaceTokens.inputRadius,
              child: Column(
                children: [
                  WindowTitleBar(
                    key: _titleBar,
                    showCaptionButtons: false,
                    leftChildren: const [
                      WorkspaceGlyph.named('workspace'),
                      SizedBox(width: 12),
                    ],
                    title: Text(
                      'WindowTitleBar component · native caption buttons omitted',
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.metadata,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 148,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: WorkspaceTokens.navigationWidth,
                          child: ColoredBox(
                            key: _sidebar,
                            color: SidebarPalette.of(context).background,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SidebarSectionLabel(
                                    'SIDEBAR COMPONENTS',
                                  ),
                                  const SizedBox(height: 6),
                                  SidebarRow(
                                    key: _sidebarFile,
                                    selected: true,
                                    icon: const SidebarGlyph(SidebarIcon.pdf),
                                    label: const Text(
                                      'Design notes.pdf',
                                      key: _sidebarLabel,
                                      maxLines: 1,
                                    ),
                                    onTap: _noop,
                                    trailingSlots: 1,
                                    trailingBuilder: (_) => [
                                      const SidebarIconButton(
                                        key: _sidebarMore,
                                        icon: SidebarIcon.more,
                                        tooltip: 'Component row options',
                                        onPressed: _noop,
                                      ),
                                    ],
                                  ),
                                  const SidebarRow(
                                    icon: SidebarGlyph(SidebarIcon.folder),
                                    label: Text('Review folder'),
                                    onTap: _noop,
                                  ),
                                  const SidebarRow(
                                    icon: SidebarGlyph(SidebarIcon.code),
                                    label: Text('Example.dart'),
                                    onTap: _noop,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Find / Replace component · local callbacks',
                                  style: caption,
                                ),
                                const SizedBox(height: 6),
                                _FindComponent(key: findKey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final sample in samples) ...[
              const SizedBox(height: 12),
              Text(
                sample.seededSize == null
                    ? 'FILE HEADER COMPONENT · original optical default: 56px'
                    : 'FILE HEADER COMPONENT · page_icon_size: 112px',
                style: caption,
              ),
              _PdfHeaderComponent(key: ValueKey(sample.id), sample: sample),
            ],
            const SizedBox(height: 12),
            Text('PRODUCTION GLYPHS · semantic action artwork', style: caption),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (name, label) in _specimenNames)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WorkspaceGlyph.named(
                        name,
                        key: ValueKey('review-glyph-$name'),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(label, style: caption),
                    ],
                  ),
              ],
            ),
            const Spacer(),
            Text(
              'PDF toolbar/identity only: no PDF page or native engine loaded. '
              'Independent synthetic pointers reveal the real controls.\n'
              'Bundled DM Sans + platform font aliases; mono substitute. '
              'Review PNG only — no golden comparison or approval.',
              style: caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _ObservedChromeController extends StandaloneFileChromeController {
  bool get hasRegisteredListeners => hasListeners;
}

class _ObservedNotifier<T> extends ValueNotifier<T> {
  _ObservedNotifier(super.value);

  bool get hasRegisteredListeners => hasListeners;
}

class _PdfSample {
  _PdfSample(this.id, {double? iconSize}) : seededSize = iconSize {
    file = MemoryCodeFile('', path: '/fixture/$id.pdf');
    final seed = IconSize.applyTo(
      fileControlView(id, 'Design notes.pdf', file.path),
      iconSize,
    );
    backend = FileControlBackend(seed, file);
    view = _ObservedNotifier(seed);
    originalBytes = seed.writeToBuffer();
  }

  final String id;
  final double? seededSize;
  final binding = Object();
  final chrome = _ObservedChromeController();
  late final MemoryCodeFile file;
  late final FileControlBackend backend;
  late final _ObservedNotifier<ViewPB> view;
  late final List<int> originalBytes;
  int viewChanges = 0;
  int fitCalls = 0;

  Finder get finder => find.byKey(ValueKey(id));
  Finder get frame => _keyWithin(finder, 'page-icon-frame');
  Finder get grip => _keyWithin(finder, 'page-icon-grip');

  void changed(ViewPB next) {
    viewChanges++;
    view.value = next;
  }

  void fit() => fitCalls++;

  void expectNoBackendWork() {
    expect(file.reads, 0);
    expect(file.writes, 0);
    expect(backend.loads, 0);
    expect(backend.extraWrites, isEmpty);
    expect(backend.iconWrites, isEmpty);
    expect(backend.renames, isEmpty);
    expect(backend.covers.saves, isEmpty);
    expect(backend.covers.deleted, isEmpty);
    expect(backend.media.copies, isEmpty);
    expect(backend.media.shares, isEmpty);
    expect(backend.listeners.where((listener) => !listener.stopped), isEmpty);
    expect(backend.stored.writeToBuffer(), originalBytes);
  }

  void dispose() {
    view.dispose();
    chrome.dispose();
  }
}

class _PdfHeaderComponent extends StatelessWidget {
  const _PdfHeaderComponent({super.key, required this.sample});
  final _PdfSample sample;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ViewPB>(
        valueListenable: sample.view,
        builder: (context, view, _) => PreviewToolbarRegion(
          child: StandaloneFileScope(
            canvas: DocumentViewportStyle.of(context).canvas,
            rendererName: sample.backend.stored.name,
            displayName: view.name,
            chrome: sample.chrome,
            canEdit: () => true,
            canRead: () => true,
            editable: true,
            available: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<StandaloneFileHeader>(
                  valueListenable: sample.chrome,
                  builder: (_, controls, __) => WorkspaceFileIdentityRow(
                    view: view,
                    binding: sample.binding,
                    summary:
                        'PDF · 12 pages · synthetic metadata, no file opened',
                    canRename: () => true,
                    onViewChanged: sample.changed,
                    repository: sample.backend,
                    coverBackend: sample.backend.covers,
                    updateIcon: sample.backend.writeIcon,
                    source: MediaActionSource(
                      source: sample.file.path,
                      name: view.name,
                    ),
                    mediaActions: sample.backend.media,
                    fileAvailable: true,
                    actionsVisible: true,
                    controls: controls,
                  ),
                ),
                // Deliberately outside the chrome listener's builder: a
                // publication must not rebuild/publish the renderer forever.
                // This real widget publishes a zero-size HeaderSlot here;
                // its complete control row appears in the identity above.
                PdfPreviewToolbar(
                  title: sample.backend.stored.name,
                  currentPage: 3,
                  pageCount: 12,
                  zoom: 1.25,
                  ready: true,
                  showThumbnails: false,
                  showOutline: false,
                  searchVisible: false,
                  isFullscreen: false,
                  onToggleThumbnails: _noop,
                  onToggleOutline: _noop,
                  onPreviousPage: _noop,
                  onNextPage: _noop,
                  onPageSubmitted: (_) {},
                  onZoomOut: _noop,
                  onZoomIn: _noop,
                  onFitWidth: sample.fit,
                  onFitPage: sample.fit,
                  onActualSize: sample.fit,
                  onToggleSearch: _noop,
                  onRotate: _noop,
                  onDownload: _noop,
                  onPrint: _noop,
                  onFullscreen: _noop,
                  viewMenu: PdfViewOptionsMenu(
                    preset: PdfViewPreset.continuous,
                    autoHideToolbar: false,
                    enabled: true,
                    onPresetChanged: (_) {},
                  ),
                  overflow: AppMenuIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'More PDF options',
                    size: 28,
                    iconSize: 16,
                    entries: () => [
                      AppMenuItem(
                        label: 'Fit whole page',
                        onSelected: sample.fit,
                      ),
                      AppMenuItem(
                        label: 'Fit to width',
                        onSelected: sample.fit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _FindComponent extends StatefulWidget {
  const _FindComponent({super.key});

  @override
  State<_FindComponent> createState() => _FindComponentState();
}

class _FindComponentState extends State<_FindComponent> {
  final query = TextEditingController(text: 'needle');
  final replacement = TextEditingController(text: 'match');
  final queryFocus = FocusNode(debugLabel: 'review-query');
  final replaceFocus = FocusNode(debugLabel: 'review-replacement');
  FindOptions options = const FindOptions();
  int currentMatch = 1;
  int replaceCalls = 0;
  int replaceAllCalls = 0;
  bool showReplace = true;
  bool visible = true;
  bool disposed = false;

  @override
  Widget build(BuildContext context) => visible
      ? FindReplaceBar(
          key: _find,
          findController: query,
          replaceController: replacement,
          findFocusNode: queryFocus,
          replaceFocusNode: replaceFocus,
          options: options,
          onOptionsChanged: (next) => setState(() => options = next),
          matchCount: 3,
          currentMatch: currentMatch,
          onPrevious: () =>
              setState(() => currentMatch = (currentMatch + 1) % 3 + 1),
          onNext: () => setState(() => currentMatch = currentMatch % 3 + 1),
          onClose: () => setState(() => visible = false),
          showReplace: showReplace,
          onToggleReplace: () => setState(() => showReplace = !showReplace),
          // Bookkeeping only: this specimen has no document/editor to mutate.
          onReplace: () => setState(() => replaceCalls++),
          onReplaceAll: () => setState(() => replaceAllCalls++),
          autofocus: false,
          dismissOnTapOutside: false,
        )
      : const SizedBox.shrink();

  @override
  void dispose() {
    query.dispose();
    replacement.dispose();
    queryFocus.dispose();
    replaceFocus.dispose();
    disposed = true;
    super.dispose();
  }
}

Finder _within(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);
Finder _keyWithin(Finder parent, String key) =>
    _within(parent, find.byKey(ValueKey(key)));
Finder _findControl(String key) => _keyWithin(find.byKey(_find), key);
String _matchLabel(int current) =>
    LocaleKeys.findAndReplace_matchOfTotal.tr(args: ['$current', '3']);
void _noop() {}

void _expectFind(WidgetTester tester) {
  final bar = find.byKey(_find);
  final widget = tester.widget<FindReplaceBar>(bar);
  expect(widget.findController.text, 'needle');
  expect(widget.replaceController!.text, 'match');
  expect(widget.showReplace, isTrue);
  expect(widget.matchCount, 3);
  expect(widget.currentMatch, 1);
  expect(find.text(_matchLabel(1)), findsOneWidget);
  final liveCount = find.semantics.byLabel(_matchLabel(1)).evaluate().single;
  expect(liveCount.attached, isTrue);
  expect(
    liveCount.getSemanticsData().hasFlag(ui.SemanticsFlag.isLiveRegion),
    isTrue,
  );
  final bounds = tester.getRect(bar);
  expect(bounds.width, FindBarMetrics.maxWidth);
  final queryGroup = tester.getRect(_findControl('findQueryGroup'));
  final navigation = tester.getRect(_findControl('findNavigationGroup'));
  expect(navigation.center.dy, closeTo(queryGroup.center.dy, 0.01));
  expect(navigation.left, greaterThan(queryGroup.right));
  expect(
    tester.getRect(_findControl('replaceTextField')).top,
    greaterThan(tester.getRect(_findControl('findTextField')).bottom),
  );

  final targets = <Finder>[
    _findControl('findTextField'),
    _findControl('replaceTextField'),
    for (final key in _findButtons) _findControl(key),
    for (final label in [
      LocaleKeys.findAndReplace_caseSensitive,
      LocaleKeys.findAndReplace_wholeWord,
      LocaleKeys.findAndReplace_useRegex,
    ])
      _within(bar, find.byTooltip(label.tr())),
  ];
  for (final target in targets) {
    _expectHitArea(target);
    _expectInside(tester.getRect(target), bounds);
  }
  for (final key in _findButtons) {
    final button = tester.widget<IconButton>(_findControl(key));
    expect(button.onPressed, isNotNull);
    expect(button.icon, isA<WorkspaceGlyph>());
    expect(
      tester.getSize(_findControl(key)),
      const Size.square(FindBarMetrics.controlSize),
    );
  }
  _expectDisjoint(targets.map(tester.getRect).toList());
}

void _expectShell(WidgetTester tester, String mode) {
  final context = tester.element(find.byKey(_titleBar));
  expect(PaperTheme.isEnabled(context), mode == 'paper');
  expect(
    Theme.of(context).brightness,
    mode == 'dark' ? Brightness.dark : Brightness.light,
  );
  expect(
    tester.widget<WindowTitleBar>(find.byKey(_titleBar)).showCaptionButtons,
    isFalse,
  );
  final titleSurface = tester.widget<ColoredBox>(
    _within(find.byKey(_titleBar), find.byType(ColoredBox)).first,
  );
  final sidebarSurface = tester.widget<ColoredBox>(find.byKey(_sidebar));
  expect(titleSurface.color, EditorSurfaceStyle.chromeBackground(context));
  expect(sidebarSurface.color, titleSurface.color);
  if (mode != 'dark') {
    expect(titleSurface.color.r, greaterThan(titleSurface.color.b));
    expect(titleSurface.color, isNot(Colors.white));
  }
  _expectHitArea(find.byKey(_sidebarMore));
  final sidebarGlyph = tester.widget<WorkspaceGlyph>(
    _within(find.byKey(_sidebarFile), find.byType(WorkspaceGlyph)).first,
  );
  expect(sidebarGlyph.name, 'file-pdf');
  for (final (name, _) in _specimenNames) {
    final glyph = find.byKey(ValueKey('review-glyph-$name'));
    expect(tester.widget<WorkspaceGlyph>(glyph).name, name);
    final picture =
        tester.widget<SvgPicture>(_within(glyph, find.byType(SvgPicture)));
    final loader = picture.bytesLoader as SvgStringLoader;
    expect(picture.colorFilter, isNull);
    expect(
      loader,
      SvgStringLoader(
        vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!,
        theme: loader.theme,
        colorMapper: loader.colorMapper,
      ),
    );
  }
}

void _expectPdfHeader(WidgetTester tester, _PdfSample sample) {
  final root = sample.finder;
  final header = _within(root, find.byType(WorkspaceFileIdentityRow));
  final row = _keyWithin(root, 'pdf-toolbar-controls');
  final scroll = _keyWithin(root, 'workspace-file-toolbar-scroll');
  expect(header, findsOneWidget);
  expect(row, findsOneWidget);
  expect(_within(root, find.byType(PdfPreviewToolbar)), findsOneWidget);
  expect(_within(root, find.byType(StandaloneFileHeaderSlot)), findsOneWidget);
  expect(_within(root, find.byType(WorkspacePageIdentity)), findsOneWidget);
  expect(_within(root, find.byType(MediaActionButtons)), findsOneWidget);
  expect(sample.chrome.value.toolbarBuilder, isNotNull);
  expect(_within(root, find.text('Design notes.pdf')), findsOneWidget);
  expect(_within(row, find.byType(Wrap)), findsNothing);
  final scrollWidget = tester.widget<SingleChildScrollView>(scroll);
  expect(scrollWidget.scrollDirection, Axis.horizontal);
  expect(
    scrollWidget.controller!.position.maxScrollExtent,
    closeTo(0, 0.01),
    reason: 'All PDF and original-file actions must be visible at once.',
  );

  final size = sample.seededSize ?? 56.0;
  expect(IconSize.decode(sample.view.value.extra), sample.seededSize);
  expect(tester.getSize(sample.frame), Size.square(size));
  expect(
    tester.getSize(_within(root, find.byType(PageIconArtwork))),
    Size.square(size),
  );
  final glyph = _within(
    _within(root, find.byType(FileIdentityGlyph)),
    find.byType(WorkspaceGlyph),
  );
  expect(tester.widget<WorkspaceGlyph>(glyph).name, 'file-pdf');
  _expectHitArea(sample.grip);
  _expectInside(tester.getRect(sample.grip), tester.getRect(sample.frame));
  final resizeData = tester
      .getSemantics(_keyWithin(root, 'page-icon-resize'))
      .getSemanticsData();
  expect(resizeData.hasFlag(ui.SemanticsFlag.isSlider), isTrue);
  expect(resizeData.value, '${size.toStringAsFixed(1)} pixels');
  expect(resizeData.hasAction(ui.SemanticsAction.increase), isTrue);
  final title = tester.getRect(_keyWithin(root, 'workspace-file-name'));
  expect(
    title.top,
    greaterThanOrEqualTo(
      tester.getRect(sample.frame).bottom + WorkspaceTokens.pageIconTitleGap,
    ),
  );
  for (final key in [
    'workspace-file-change-icon',
    'workspace-file-add-cover',
  ]) {
    final action = _keyWithin(root, key);
    _expectHitArea(action);
    expect(tester.getRect(action).bottom, lessThanOrEqualTo(title.top));
    expectFileControlPainted(tester, action);
  }
  expect(tester.getRect(row).top, greaterThan(title.bottom));
  _expectInside(tester.getRect(row), tester.getRect(scroll));

  for (final tooltip in _pdfTooltips) {
    final control = _within(row, find.byTooltip(tooltip));
    _expectHitArea(control);
    _expectInside(tester.getRect(control), tester.getRect(scroll));
  }
  for (final key in ['media-copy', 'media-share', 'workspace-file-rename']) {
    final control = _keyWithin(row, key);
    _expectHitArea(control);
    _expectInside(tester.getRect(control), tester.getRect(scroll));
    expectFileControlPainted(tester, control);
  }
  final page = _keyWithin(row, 'pdf-page-number-field');
  expect(tester.widget<TextField>(page).controller!.text, '3');
  _expectHitArea(page);
  final native = _within(
    row,
    find.byWidgetPredicate(
      (widget) =>
          widget is IconButton ||
          widget is TextButton ||
          widget is AppMenuIconButton,
    ),
  );
  final rects = <Rect>[tester.getRect(page)];
  for (final element in native.evaluate()) {
    final target = find.byWidget(element.widget);
    _expectHitArea(target);
    final rect = tester.getRect(target);
    _expectInside(rect, tester.getRect(scroll));
    expect(rect.center.dy, closeTo(rects.first.center.dy, 1));
    rects.add(rect);
  }
  _expectDisjoint(rects);
  final context = tester.element(header);
  expect(
    tester
        .widget<DocumentViewportBar>(
          _keyWithin(root, 'workspace-file-identity-row'),
        )
        .background,
    DocumentViewportStyle.of(context).canvas,
  );
}

void _expectInside(Rect child, Rect parent) {
  expect(child.isEmpty, isFalse);
  expect(parent.inflate(0.01).contains(child.topLeft), isTrue);
  expect(parent.inflate(0.01).contains(child.bottomRight), isTrue);
}

void _expectDisjoint(List<Rect> rects) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      expect(
        rects[i].deflate(0.1).overlaps(rects[j].deflate(0.1)),
        isFalse,
        reason: 'Native controls must not overlap each other.',
      );
    }
  }
}

void _expectHitArea(Finder target) {
  expect(target, findsOneWidget);
  for (final at in const [
    Alignment.center,
    Alignment(-0.9, 0),
    Alignment(0.9, 0),
    Alignment(0, -0.9),
    Alignment(0, 0.9),
  ]) {
    expect(target.hitTestable(at: at), findsOneWidget);
  }
}

// Distinct devices as well as pointer IDs are intentional: Flutter's default
// TestGesture mouse device is always 1, even for different pointer IDs.
TestGesture _mouse(WidgetTester tester, int id) => TestGesture(
      dispatcher: tester.sendEventToBinding,
      pointer: id,
      device: id,
      kind: PointerDeviceKind.mouse,
    );

Future<void> _hover(
  WidgetTester tester,
  TestGesture mouse,
  Finder target,
) async {
  _expectHitArea(target);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump();
  await tester.pump(_hoverDuration);
  await tester.pump();
}

Future<void> _click(WidgetTester tester, Finder target, int id) async {
  _expectHitArea(target);
  final mouse = _mouse(tester, id);
  await mouse.addPointer(location: const Offset(-20, -20));
  var down = false;
  try {
    down = true;
    await mouse.down(tester.getCenter(target));
    await mouse.up();
    down = false;
    await tester.pump();
    await tester.pump(_hoverDuration);
  } finally {
    if (down) await mouse.cancel();
    await mouse.removePointer();
    await tester.pump();
  }
}

Future<void> _decodeActualPictures(WidgetTester tester) async {
  final elements = find.byType(SvgPicture).evaluate().toList();
  expect(elements, isNotEmpty);
  final decoded = await tester.runAsync(() async {
    await Future.wait([
      for (final element in elements)
        vg
            .loadPicture((element.widget as SvgPicture).bytesLoader, element)
            // Disposal also runs for a late completion after the deadline.
            .then<void>((picture) => picture.picture.dispose()),
    ]).timeout(_deadline);
    return true;
  });
  expect(decoded, isTrue, reason: 'Every mounted production SVG must decode.');
  await tester.pump();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String mode,
) async {
  if (_reviewDirectory.isEmpty) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  expect(boundary.debugNeedsPaint, isFalse);
  final written = await tester.runAsync(() async {
    final root = Directory.current.absolute;
    if (p.basename(root.path) != 'appflowy_flutter' ||
        !await File(p.join(root.path, 'pubspec.yaml')).exists()) {
      throw StateError('Run this export from frontend/appflowy_flutter.');
    }
    final rootPath = await root.resolveSymbolicLinks();
    var directory = Directory(rootPath);
    // Fixed components, not arbitrary user input. Refuse links/junctions so a
    // build directory or old PNG cannot redirect writes into user data.
    for (final segment in const ['build', 'performance']) {
      directory = Directory(p.join(directory.path, segment));
      final type =
          await FileSystemEntity.type(directory.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw StateError('Review output directory must not be a link or file.');
      }
      await directory.create();
      if (!p.isWithin(rootPath, await directory.resolveSymbolicLinks())) {
        throw StateError('Review output must stay inside the Flutter app.');
      }
    }
    final output = File(p.join(directory.path, 'find-chrome-review-$mode.png'));
    final type = await FileSystemEntity.type(output.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Review output must be a regular PNG file.');
    }
    final image = await _ownedImage(boundary.toImage());
    try {
      final bytes = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(_deadline);
      if (bytes == null) {
        throw StateError('The component sheet produced no PNG.');
      }
      final png =
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(Size(image.width.toDouble(), image.height.toDouble()), _sheetSize);
      // This opt-in path overwrites only our synthetic review artifact, never
      // a golden. No image files are consulted as inputs or comparison oracles.
      await output.writeAsBytes(png, flush: true).timeout(_deadline);
      expect(await output.length(), png.length);
      return true;
    } finally {
      image.dispose();
    }
  });
  expect(
    written,
    isTrue,
    reason: 'The requested fresh component PNG must exist.',
  );
}

Future<ui.Image> _ownedImage(Future<ui.Image> future) {
  var timedOut = false;
  return future.then((image) {
    if (timedOut) image.dispose();
    return image;
  }).timeout(
    _deadline,
    onTimeout: () {
      timedOut = true;
      throw TimeoutException('Component review raster deadline', _deadline);
    },
  );
}

class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Component review must remain offline.');
  }
}
