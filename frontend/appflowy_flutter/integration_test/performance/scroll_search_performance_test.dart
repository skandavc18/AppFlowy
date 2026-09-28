import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_embed_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
// Load bundled strings without EasyLocalization.ensureInitialized (prefs).
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

// Standalone entrypoint: no app main, shared integration startup, GetIt,
// authentication, preferences, live workspace services, native input or profiles.
// See scroll_search_performance.md for opt-in/reporting and scope limitations.
const _consent = bool.fromEnvironment('PERF_SCROLL_SEARCH');
const _appearance = String.fromEnvironment('PERF_THEME', defaultValue: 'light');
const _mode = kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
const _window = Duration(seconds: 2);
const _deadline = Duration(seconds: 10); // Event watchdog, NOT a perf target.
const _occurrences = 1000;
final _body = List.filled(_occurrences, 'needle').join(' ');

void main() {
  if (!_consent || !Platform.isWindows) {
    throw StateError(
        'Requires Windows and --dart-define=PERF_SCROLL_SEARCH=true');
  }
  if (!const {'light', 'dark', 'paper'}.contains(_appearance)) {
    throw StateError('PERF_THEME must be light, dark or paper.');
  }
  const output = String.fromEnvironment('PERF_OUTPUT_DIRECTORY');
  if ((output.isNotEmpty && !p.isAbsolute(output)) ||
      (kReleaseMode && output.isEmpty)) {
    throw StateError('Release requires an absolute PERF_OUTPUT_DIRECTORY.');
  }
  final binding = _DemandBinding();
  setUp(() {
    // Native accessibility can enable semantics after testWidgets records its
    // handle baseline. Establish the platform state first; retain the real
    // framework leak verification rather than counting that change as a leak.
    binding.platformDispatcher.semanticsEnabledTestValue = true;
  });
  tearDown(() => binding.platformDispatcher.clearSemanticsEnabledTestValue());
  final report = <String, dynamic>{
    'schema': 1,
    'fixture_revision': 3,
    'process_id': pid,
    'run':
        const String.fromEnvironment('PERF_RUN', defaultValue: 'scroll_search'),
    'mode': _mode,
    'theme': _appearance,
    'scope':
        'current-build synthetic native Flutter composition, not global FPS',
    'before_app_fps': null,
    'operation_counts': null,
    'operation_counts_reason':
        'separate unit baseline; assert-only in production',
    'window_target_us': _window.inMicroseconds,
    'frame_policy': 'fixture demand-only; no LiveTest self-scheduled idle loop',
    'input': 'Flutter PointerScrollEvent, NOT OS wheel/trackpad verification',
    'find_control': 'real controller API, NOT keyboard routing verification',
    'editor': 'real package paragraph renderer, read-only shrinkWrap preview',
    'cards': 'real DashboardCard text/unknown; not service-backed page cards',
    'covers':
        'real PNG + Image + CoverImageProvider; NOT FolderGalleryCard I/O',
    'limitations': [
      'No historical FPS, application startup, user data, HTTP, auth or FFI reads.',
      'All N cards eagerly mounted; one shared cover cache key, not N unique files.',
      'One long editor per tab; no full application editor plugins or DashboardPage.',
      'Retained tab has an open query but is Offstage/TickerMode-disabled.',
      'FrameTiming is engine build/raster work, not display presentation latency.',
      'Debug overhead and external desktop load affect results; compare modes separately.',
    ],
    'scroll': <Map<String, Object?>>[],
    'cover': <Map<String, Object?>>[],
    'measurement_complete': false,
  };
  binding.reportData = report;
  // The existing large_page driver can consume reportData in Debug/Profile.
  // A direct file receipt also works in AOT, without a VM service or new plugin.
  if (output.isNotEmpty) unawaited(_nativeReport(binding, report, output));

  testWidgets('offline scroll/search native AFTER measurements',
      (tester) async {
    final semanticsHandlesBefore = binding.debugOutstandingSemanticsHandles;
    report['semantics_handles_before_body'] = semanticsHandlesBefore;
    final elapsed = Stopwatch()..start();
    final oldFonts = GoogleFonts.config.allowRuntimeFetching;
    final oldHttp = HttpOverrides.current;
    final network = _NoNetwork();
    final frames = _Frames(binding);
    _ImageLease? preload;
    GoogleFonts.config.allowRuntimeFetching = false;
    HttpOverrides.global = network;
    // Avoid native IME side effects; no synthetic OS keys or debug-name inference.
    binding.testTextInput.register();
    try {
      await tester.runAsync(() => _loadAssets().timeout(_deadline));
      expect(tester.takeException(), isNull);
      final theme = _theme();
      final png = (await tester.runAsync(_makePng))!;
      final view = binding.platformDispatcher.implicitView!;
      final dpr = view.devicePixelRatio;
      final target = CoverImageDecodeSize.fromConstraints(
        const BoxConstraints.tightFor(width: 320, height: 180),
        dpr,
      )!;
      report['environment'] = {
        'logical_width': view.physicalSize.width / dpr,
        'logical_height': view.physicalSize.height / dpr,
        'device_pixel_ratio': dpr,
        'reported_refresh_hz':
            view.display.refreshRate.isFinite ? view.display.refreshRate : null,
        'semantics_enabled': binding.semanticsEnabled,
        'font': preferredFontFamily,
      };
      report['png'] = {
        'width': 3000,
        'height': 2000,
        'encoded_bytes': png.length,
        'pattern': 'synthetic gradient with bands, generated before timing',
        'target_width': target.width,
        'target_height': target.height,
      };
      // Cover-only probes finish before the scroll preload. Each pair has a
      // fresh identity; bypass and optimized both receive exactly these bytes.
      for (final delayed in [false, true]) {
        for (final optimized in delayed ? [true, false] : [false, true]) {
          final source = _BytesImage(
              png, delayed ? const Duration(milliseconds: 80) : Duration.zero);
          final ImageProvider provider;
          if (optimized) {
            provider = CoverImageProvider(source, target, BoxFit.cover);
          } else {
            provider = source;
          }
          final lease =
              (await tester.runAsync(() async => _ImageLease(provider)))!;
          try {
            (report['cover'] as List).add(await _coverProbe(
              tester,
              theme,
              frames,
              lease,
              source,
              target,
              optimized: optimized,
              warm: false,
              delayed: delayed,
            ));
            if (!delayed) {
              (report['cover'] as List).add(await _coverProbe(
                tester,
                theme,
                frames,
                lease,
                source,
                target,
                optimized: optimized,
                warm: true,
                delayed: false,
              ));
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            lease.dispose();
            await provider.evict(); // Only the fixture-owned key.
          }
        }
      }
      final cover = CoverImageProvider(MemoryImage(png), target, BoxFit.cover);
      // Resolve AND await before any scrolling surface mounts. Keep the stream
      // listener/ImageInfo alive throughout all windows; no fake-clock decode.
      preload = await tester.runAsync(() async {
        final lease = _ImageLease(cover);
        try {
          await lease.ready.future.timeout(_deadline);
          return lease;
        } catch (_) {
          lease.dispose();
          rethrow;
        }
      });
      expect(preload, isNotNull);
      for (final count in [10, 50, 100]) {
        await _scrollCase(tester, theme, frames, cover, count, report);
      }
      expect(network.attempts, 0);
      expect(tester.takeException(), isNull);
      report['http_attempts'] = network.attempts;
      report['measurement_complete'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      frames.dispose();
      preload?.dispose();
      if (preload != null) await preload.provider.evict();
      binding.testTextInput.unregister();
      HttpOverrides.global = oldHttp;
      GoogleFonts.config.allowRuntimeFetching = oldFonts;
      report['total_elapsed_us'] = elapsed.elapsedMicroseconds;
      report['http_attempts'] = network.attempts;
      report['cleanup_complete'] = true;
      report['remaining_transient_callbacks'] = binding.transientCallbackCount;
      report['semantics_handles_after_body'] =
          binding.debugOutstandingSemanticsHandles;
      expect(binding.debugOutstandingSemanticsHandles, semanticsHandlesBefore);
    }
  },
      variant: const DefaultTestVariant(),
      timeout: const Timeout(Duration(minutes: 2)));
}

/// Flutter 3.27's LiveTest.handleDrawFrame schedules another engine frame in
/// fullyLive/benchmarkLive, even when widgets request nothing. Benchmark mode
/// removes that harness loop, but normally suppresses widget requests too.
/// Admit those requests synchronously through the superclass, then restore
/// benchmark before drawFrame: real widgets/animations/input drive the engine.
/// No timers, persistent callbacks, custom beginFrame or manual raster pumping.
class _DemandBinding extends IntegrationTestWidgetsFlutterBinding {
  _DemandBinding() {
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
  }

  @override
  void scheduleFrame() {
    final previous = framePolicy;
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    try {
      super.scheduleFrame();
    } finally {
      framePolicy = previous;
    }
  }

  @override
  void scheduleForcedFrame() {
    final previous = framePolicy;
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    try {
      super.scheduleForcedFrame();
    } finally {
      framePolicy = previous;
    }
  }
}

Future<void> _nativeReport(IntegrationTestWidgetsFlutterBinding binding,
    Map<String, dynamic> report, String output) async {
  final passed = await binding.allTestsPassed.future;
  report['test_success'] = passed && report['measurement_complete'] == true;
  report['failed_test_count'] = binding.failureMethodsDetails.length;
  // Do not serialize test failure details, paths, widget text or stack traces.
  final directory = Directory(output);
  await directory.create(recursive: true);
  final own = await directory.createTemp('scroll_search_${_mode}_');
  await File(p.join(own.path, 'report.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  // Publish only AFTER the report writer has flushed and closed. The runner
  // watches this rename, never the creation of a partially written JSON file.
  final done = File(p.join(own.path, 'report.done.tmp'));
  await done.writeAsString('done', flush: true);
  await done.rename(p.join(own.path, 'report.done'));
  // Leave the tiny completed route open. The caller owns the fixture process;
  // no process enumeration, killing normal AppFlowy, or global window commands.
}

Future<void> _loadAssets() async {
  final translations = jsonDecode(
    await rootBundle.loadString('assets/translations/en-US.json'),
  ) as Map<String, dynamic>;
  Localization.load(const Locale('en', 'US'),
      translations: Translations(translations));
  for (final entry in {
    preferredFontFamily: 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
    builtInCodeFontFamily:
        'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load();
  }
}

ThemeData _theme() => DesktopAppearance().getThemeData(
      _appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((t) => t.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      _appearance == 'dark' ? Brightness.dark : Brightness.light,
      preferredFontFamily,
      builtInCodeFontFamily,
    );

Widget _app(ThemeData theme, Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationDuration: Duration.zero,
      localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
      home: AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: theme.brightness == Brightness.dark
              ? AppFlowyDefaultTheme().dark()
              : AppFlowyDefaultTheme().light(),
          palette: theme.extension<PremiumThemeExtension>()!,
          brightness: theme.brightness,
        ),
        child: Scaffold(
            body: Builder(
                builder: (context) => ColoredBox(
                      color: EditorSurfaceStyle.canvasBackground(context),
                      child: ContextualFindScope(
                          findInControls: true, child: child),
                    ))),
      ),
    );

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Offline fixture attempted network access.');
  }
}

/// Only authorization I/O is replaced. Search, document ownership, renderer
/// traversal, native word boxes, clipping and the Find bar are production.
class _Reads {
  final access = ValueNotifier(0);
  final changes = StreamController<String>.broadcast(sync: true);
  final scheduler = DocumentFindReadScheduler();
  int views = 0;
  int preflights = 0;
  int forbidden = 0;
  int get total => views + preflights + forbidden;
  Never _forbidden() {
    forbidden++;
    throw StateError('Unexpected secondary read in mounted editor fixture.');
  }

  late final provider = DocumentFindReadProvider(
    scheduler: scheduler,
    accessChanges: access,
    contentChanges: changes.stream,
    readView: (id) async {
      views++;
      if (id != 'synthetic-page') return _forbidden();
      return ViewPB(
          id: id, name: 'Fixture page', layout: ViewLayoutPB.Document);
    },
    preflight: (_) async {
      preflights++;
      return true;
    },
    readDocument: (_) async => _forbidden(),
    readViewRows: (_) async => _forbidden(),
    readFields: (_, __) async => _forbidden(),
    readRows: (_) async => _forbidden(),
    readCell: (_, __, ___) async => _forbidden(),
  );

  Future<void> dispose() async {
    access.dispose();
    await changes.close();
  }
}

class _Pane {
  _Pane(int count) {
    specs = List.generate(
        count,
        (i) => DashboardWidgetSpec(
              id: 'card-$i',
              type: i.isEven ? 'text' : 'unsupported-fixture',
              showTitle: false,
              settings:
                  i.isEven ? const {'text': 'needle card body'} : const {},
            ));
    dashboard = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(id: 'fixture-section', widgets: [page, ...specs])
          ],
        ))
      ..setReadOnly(true);
    controller = DashboardFindController(dashboard,
        title: () => '', readProvider: reads.provider);
    editor = EditorState(
        document: Document(
            root: pageNode(children: [
      paragraphNode(text: _body),
    ])));
    editorScroll =
        EditorScrollController(editorState: editor, shrinkWrap: true);
  }

  static const page = DashboardWidgetSpec(
    id: 'editor',
    type: 'page',
    showTitle: false,
    source: DashboardDataSource(
        kind: DashboardSourceKind.page, viewId: 'synthetic-page'),
  );
  final reads = _Reads();
  final nodeMounted = Completer<bool>();
  final coversReady = Completer<void>();
  final coverFrameIndices = <int>{};
  final key = GlobalKey();
  final embedKey = GlobalKey();
  final editorKey = GlobalKey();
  final cardsKey = GlobalKey();
  final editorViewportKey = GlobalKey();
  final focus = FocusNode();
  final cardsScroll = ScrollController();
  final bodyScroll = ScrollController();
  late final List<DashboardWidgetSpec> specs;
  late final DashboardController dashboard;
  late final DashboardFindController controller;
  late final EditorState editor;
  late final EditorScrollController editorScroll;

  Widget widget(ImageProvider cover, ThemeData theme) => SurfaceFindHost(
        key: key,
        controller: controller,
        child: Focus(
            focusNode: focus,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
              child: Row(children: [
                Expanded(
                    child: SingleChildScrollView(
                  key: cardsKey,
                  controller: cardsScroll,
                  child: Column(children: [
                    for (final (index, spec) in specs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(children: [
                          // Gallery-like image face, deliberately NOT a replacement
                          // rectangle or a claim to cover production gallery loading.
                          Image(
                              key: ValueKey((key, index)),
                              image: cover,
                              height: 90,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              frameBuilder:
                                  (context, child, frame, synchronous) {
                                // A resolved cache entry is not an ImageState frame:
                                // Flutter listens only while TickerMode is enabled.
                                if (frame != null &&
                                    TickerMode.of(context) &&
                                    coverFrameIndices.add(index)) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (context.mounted &&
                                        TickerMode.of(context) &&
                                        coverFrameIndices.length ==
                                            specs.length &&
                                        !coversReady.isCompleted) {
                                      coversReady.complete();
                                    }
                                  });
                                }
                                return child;
                              },
                              excludeFromSemantics: true),
                          SizedBox(
                              height: 110,
                              child: Builder(
                                  builder: (context) => DashboardCard(
                                      controller: dashboard,
                                      spec: spec,
                                      palette: DashboardPalette.of(context),
                                      selected: false,
                                      dragging: false))),
                        ]),
                      ),
                  ]),
                )),
                const SizedBox(width: 20),
                Expanded(
                    child: SingleChildScrollView(
                  key: editorViewportKey,
                  controller: bodyScroll,
                  child: DashboardFindEmbed(
                    key: embedKey,
                    dashboard: dashboard,
                    spec: page,
                    child: IntrinsicHeight(
                        child: AppFlowyEditor(
                      key: editorKey,
                      editorState: editor,
                      editable: false,
                      shrinkWrap: true,
                      editorScrollController: editorScroll,
                      disableAutoScroll: true,
                      blockWrapper: (context,
                              {required Node node, required Widget child}) =>
                          _NodeReceipt(
                              node: node, receipt: nodeMounted, child: child),
                      editorStyle: EditorStyle.desktop(
                        padding: const EdgeInsets.all(12),
                        textStyleConfiguration: TextStyleConfiguration(
                          text: TextStyle(
                              fontFamily: preferredFontFamily,
                              fontSize: 16,
                              color: theme.colorScheme.onSurface),
                        ),
                      ),
                    )),
                  ),
                )),
              ]),
            )),
      );

  RenderSurfaceFindHighlight paint(WidgetTester tester) =>
      tester.renderObject<RenderSurfaceFindHighlight>(find.descendant(
        of: find.byKey(embedKey, skipOffstage: false),
        matching: find.byType(SurfaceFindHighlight, skipOffstage: false),
      ));

  Future<void> dispose() async {
    controller.dispose();
    dashboard.dispose();
    editorScroll.dispose();
    editor.dispose();
    focus.dispose();
    cardsScroll.dispose();
    bodyScroll.dispose();
    await reads.dispose();
  }
}

/// One native-node attachment receipt, not a polling timer or readiness sleep.
class _NodeReceipt extends StatefulWidget {
  const _NodeReceipt(
      {required this.node, required this.receipt, required this.child});
  final Node node;
  final Completer<bool> receipt;
  final Widget child;
  @override
  State<_NodeReceipt> createState() => _NodeReceiptState();
}

class _NodeReceiptState extends State<_NodeReceipt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.receipt.isCompleted) return;
      final render = widget.node.key.currentContext?.findRenderObject();
      widget.receipt
          .complete(render is RenderBox && render.attached && render.hasSize);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _scrollCase(WidgetTester tester, ThemeData theme, _Frames frames,
    ImageProvider cover, int count, Map<String, dynamic> report) async {
  final visible = _Pane(count);
  final hidden = _Pane(count);
  final tab = ValueNotifier(1);
  try {
    // Both actual subtrees stay mounted; only offstage/focus/ticker status
    // changes. Warm the second tab with the SAME query before hiding it.
    await tester.pumpWidget(_app(
        theme,
        ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, selected, _) => Stack(children: [
            for (final (index, pane) in [(0, visible), (1, hidden)])
              Offstage(
                  offstage: selected != index,
                  child: TickerMode(
                    enabled: selected == index,
                    child: ExcludeFocus(
                        excluding: selected != index,
                        child: pane.widget(cover, theme)),
                  )),
          ]),
        )));
    expect(
        await Future.wait(
                [visible.nodeMounted.future, hidden.nodeMounted.future])
            .timeout(_deadline),
        [true, true]);
    await _setupFrames(tester);
    expect(PaperTheme.isEnabled(tester.element(find.byKey(hidden.key))),
        _appearance == 'paper');
    expect(find.byType(DashboardCard, skipOffstage: false),
        findsNWidgets(2 * count));
    expect(find.byType(AppFlowyEditor, skipOffstage: false), findsNWidgets(2));
    await hidden.coversReady.future.timeout(_deadline);
    expect(hidden.coverFrameIndices,
        unorderedEquals(List.generate(count, (i) => i)));
    expect(visible.reads.total + hidden.reads.total, 0);
    await _open(tester, hidden, count);
    _wordBoxes(tester, hidden);
    final retainedNode = hidden.editor.document.root.children.single;
    final activeNode = visible.editor.document.root.children.single;
    final retainedEditor = tester.element(find.byKey(hidden.editorKey));
    final retainedCard = tester.element(find
        .descendant(
            of: find.byKey(hidden.key), matching: find.byType(DashboardCard))
        .first);
    tab.value = 0;
    await _setupFrames(tester);
    await visible.coversReady.future.timeout(_deadline);
    expect(visible.coverFrameIndices,
        unorderedEquals(List.generate(count, (i) => i)));
    // Both panes have now had an actual onstage image lifecycle. The hidden
    // pane must retain every previous frame, not merely its decoded cache key.
    _loadedCoverFrames(tester, count);
    // One explicit owner revision causes the now-hidden bridge to revoke and
    // unsubscribe before measurements. It is not a recurring poll/refresh.
    hidden.dashboard.refresh();
    await _setupFrames(tester);
    expect(hidden.reads.changes.hasListener, isFalse);
    expect(hidden.controller.isOpen, isTrue);
    expect(hidden.controller.query, 'needle');
    expect(hidden.paint(tester).matchRects, isEmpty);
    final hiddenReads = hidden.reads.total;

    await _open(tester, visible, count);
    final boxes = _wordBoxes(tester, visible);
    final initialSelection = visible.editor.selection;
    final activeElement = tester.element(find.byKey(visible.editorKey));
    // Move focus off Find's caret without closing the bar. Do not measure a
    // cursor blink as useful scrolling throughput.
    visible.focus.requestFocus();
    await _setupFrames(tester);
    final setupReads = visible.reads.total;
    expect(setupReads, greaterThan(0));
    expect(visible.reads.forbidden + hidden.reads.forbidden, 0);
    for (final active in [true, false]) {
      if (!active) visible.controller.close();
      visible.cardsScroll.jumpTo(0);
      visible.bodyScroll.jumpTo(0);
      await _setupFrames(tester);
      if (!active) {
        expect(visible.controller.query, 'needle');
        expect(visible.controller.matches, isEmpty);
        expect(visible.paint(tester).matchRects, isEmpty);
        expect(visible.reads.changes.hasListener, isFalse);
      }
      final beforeReads = visible.reads.total;
      final sample = await _wheelWindow(tester, frames, visible);
      // All expensive tree/word-box assertions are outside the timed window.
      expect(visible.reads.total - beforeReads, 0);
      expect(hidden.reads.total - hiddenReads, 0);
      expect(visible.editor.document.root.children.single, same(activeNode));
      expect(hidden.editor.document.root.children.single, same(retainedNode));
      _loadedCoverFrames(tester, count);
      expect(visible.editor.selection, initialSelection);
      expect(
          tester.element(find.byKey(visible.editorKey)), same(activeElement));
      expect(tester.element(find.byKey(hidden.editorKey, skipOffstage: false)),
          same(retainedEditor));
      expect(
          tester.element(find
              .descendant(
                of: find.byKey(hidden.key, skipOffstage: false),
                matching: find.byType(DashboardCard, skipOffstage: false),
              )
              .first),
          same(retainedCard));
      if (active) _wordBoxes(tester, visible);
      expect(tester.takeException(), isNull);
      (report['scroll'] as List).add({
        'cards_per_tab': count,
        'mounted_cards_total': 2 * count,
        'loaded_cover_frames_total': 2 * count,
        'cover_warmup': 'each_pane_onstage_frame_receipt_before_timing',
        'text_cards_per_tab': count ~/ 2,
        'unknown_cards_per_tab': count ~/ 2,
        'embedded_editors_per_tab': 1,
        'editor_occurrences': _occurrences,
        'native_word_boxes_checked': boxes,
        'find': active ? 'active' : 'closed_same_query',
        'hidden_tab': 'retained_previously_queried_open_but_inactive',
        'setup_complete': true,
        'setup_authorization_calls': setupReads,
        'window_read_delta': visible.reads.total - beforeReads,
        'hidden_read_delta': hidden.reads.total - hiddenReads,
        ...sample,
      });
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await visible.dispose();
    await hidden.dispose();
    tab.dispose();
  }
}

void _loadedCoverFrames(WidgetTester tester, int count) {
  final coverFrames = tester
      .widgetList<RawImage>(find.byType(RawImage, skipOffstage: false))
      .toList();
  expect(coverFrames, hasLength(2 * count));
  expect(coverFrames.every((frame) => frame.image != null), isTrue);
}

Future<void> _setupFrames(WidgetTester tester) async {
  // A fixed pair of layout/publication boundaries, never an idle frame loop.
  await tester.pump().timeout(_deadline);
  await tester.pump().timeout(_deadline);
}

Future<void> _open(WidgetTester tester, _Pane pane, int count) async {
  final complete = Completer<void>();
  void changed() {
    if (pane.controller.matches.length == _occurrences + count ~/ 2 &&
        !complete.isCompleted) complete.complete();
  }

  pane.controller.addListener(changed);
  try {
    pane.controller.open();
    pane.controller.setQuery('needle');
    await tester.pump().timeout(_deadline);
    changed();
    await complete.future.timeout(_deadline);
    await _setupFrames(tester);
    // Model-owned card matches precede embedded editor matches.
    pane.controller.step(count ~/ 2);
    await _setupFrames(tester);
    // Allow the real 160ms Find entrance to finish outside the workload.
    // This timer does not request any frames and is not a readiness poll.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(pane.controller.current!.id, isA<DashboardEmbedFindId>());
    expect(pane.paint(tester).currentRect, isNotNull);
  } finally {
    pane.controller.removeListener(changed);
  }
}

int _wordBoxes(WidgetTester tester, _Pane pane) {
  final paint = pane.paint(tester);
  final node = pane.editor.document.root.children.single;
  expect(node.delta!.toPlainText().trim(), _body);
  final root = node.key.currentContext!.findRenderObject()!;
  final paragraphs = <RenderParagraph>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph &&
        object.text.toPlainText().trim() == _body) {
      paragraphs.add(object);
    }
    object.visitChildren(visit);
  }

  visit(root);
  expect(paragraphs, hasLength(1));
  final paragraph = paragraphs.single;
  final expected = <Rect>[];
  // Independent offsets from the synthetic input, not from Find's matches.
  for (var i = 0; i < _occurrences; i++) {
    for (final box in paragraph.getBoxesForSelection(TextSelection(
      baseOffset: i * 7,
      extentOffset: i * 7 + 6,
    ))) {
      expected.add(MatrixUtils.transformRect(
          paragraph.getTransformTo(paint), box.toRect()));
    }
  }
  expect(expected, hasLength(_occurrences));
  expect(expected.every((rect) => rect.isFinite && !rect.isEmpty), isTrue);
  expect(paint.matchRects, orderedEquals(expected));
  expect(paint.currentRect, expected.first);
  return expected.length;
}

Future<Map<String, Object?>> _wheelWindow(
    WidgetTester tester, _Frames frames, _Pane pane) async {
  final targets = [pane.cardsKey, pane.editorViewportKey];
  final points = targets.map((key) {
    final rect = tester.getRect(find.byKey(key));
    return Offset(rect.left + 32, rect.center.dy); // Clear of scrollbars.
  }).toList();
  final positions = [pane.cardsScroll.position, pane.bodyScroll.position];
  for (final position in positions) {
    expect(position.maxScrollExtent, greaterThan(0));
  }
  final minimum = positions.map((p) => p.pixels).toList();
  final maximum = List<double>.of(minimum);
  final startFrame = frames.currentFrame;
  final clock = Stopwatch()..start();
  final events = <Map<String, int>>[];
  // 100 scheduled slots over exactly two real seconds. If late, skip slots;
  // do not burst to catch up or stretch a slow machine's nominal window.
  for (var slot = 0; slot < 100; slot++) {
    final due = slot * 20000;
    final remaining = due - clock.elapsedMicroseconds;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(microseconds: remaining));
    }
    final now = clock.elapsedMicroseconds;
    if (now >= _window.inMicroseconds) break;
    if (now - due >= 20000) continue;
    final target = slot % 2;
    // Reverse every 500ms; enough travel to exercise both native scrollables,
    // never a jumpTo animation masquerading as user scrolling.
    final delta = (slot ~/ 25).isEven ? 72.0 : -72.0;
    await tester.sendEventToBinding(PointerScrollEvent(
      viewId: frames.binding.platformDispatcher.implicitView!.viewId,
      device: 73,
      kind: PointerDeviceKind.mouse,
      timeStamp: Duration(microseconds: now),
      position: points[target],
      scrollDelta: Offset(0, delta),
    ));
    events.add({'slot': slot, 'actual_us': now, 'target': target});
    for (var i = 0; i < positions.length; i++) {
      final value = positions[i].pixels;
      if (value < minimum[i]) minimum[i] = value;
      if (value > maximum[i]) maximum[i] = value;
    }
  }
  final remaining = _window.inMicroseconds - clock.elapsedMicroseconds;
  if (remaining > 0) {
    await Future<void>.delayed(Duration(microseconds: remaining));
  }
  final actualUs = clock.elapsedMicroseconds;
  final endFrame = frames.currentFrame;
  // Await the existing terminal frame's timing batch. No pump/scheduleFrame,
  // periodic observer or timer-generated idle frames to manufacture samples.
  await frames.through(endFrame);
  final sample = frames.between(startFrame, endFrame);
  expect(sample, isNotEmpty);
  expect(events, isNotEmpty);
  for (var i = 0; i < positions.length; i++) {
    expect(maximum[i] - minimum[i], greaterThan(0));
    expect(positions[i].pixels.isFinite, isTrue);
  }
  return {
    'actual_window_us': actualUs,
    'events': events,
    'skipped_input_slots': 100 - events.length,
    'cards_scroll_range': maximum[0] - minimum[0],
    'editor_scroll_range': maximum[1] - minimum[1],
    'frames': _frameSummary(
        sample, sample.first.timestampInMicroseconds(ui.FramePhase.buildStart)),
  };
}

/// Passive engine listener. Engine frame numbers, not callback receipt times,
/// identify windows. Durations/intervals use the timing's own raw timestamps;
/// no assumption that onBeginFrame's epoch/phase equals buildStart is needed.
class _Frames {
  _Frames(this.binding) {
    binding.addTimingsCallback(_received);
  }
  final IntegrationTestWidgetsFlutterBinding binding;
  int get currentFrame => ui.PlatformDispatcher.instance.frameData.frameNumber;
  final _values = <ui.FrameTiming>[];
  final _waiters = <(int, Completer<void>)>[];
  void _received(List<ui.FrameTiming> values) {
    _values.addAll(values);
    for (final waiter in _waiters.toList()) {
      if (_hasThrough(waiter.$1)) {
        _waiters.remove(waiter);
        waiter.$2.complete();
      }
    }
  }

  bool _hasThrough(int end) => _values.any((frame) => frame.frameNumber >= end);
  Future<void> through(int end) async {
    if (_hasThrough(end)) return;
    final waiter = (end, Completer<void>());
    _waiters.add(waiter);
    try {
      await waiter.$2.future.timeout(_deadline, onTimeout: () {
        throw StateError('FrameTiming deadline: requested=$end '
            'current=$currentFrame received=${_values.map((f) => f.frameNumber).join(",")}');
      });
    } finally {
      _waiters.remove(waiter);
    }
  }

  List<ui.FrameTiming> between(int start, int end) => _values
      .where((frame) => frame.frameNumber > start && frame.frameNumber <= end)
      .toList()
    ..sort((a, b) => a.frameNumber.compareTo(b.frameNumber));
  ui.FrameTiming at(int number) =>
      _values.singleWhere((frame) => frame.frameNumber == number);
  void dispose() => binding.removeTimingsCallback(_received);
}

Map<String, Object?> _frameSummary(List<ui.FrameTiming> values, int origin) {
  final raw = [
    for (final frame in values)
      {
        'build_start_us':
            frame.timestampInMicroseconds(ui.FramePhase.buildStart) - origin,
        'build_us': frame.buildDuration.inMicroseconds,
        'raster_us': frame.rasterDuration.inMicroseconds,
        'total_span_us': frame.totalSpan.inMicroseconds,
      }
  ];
  for (final row in raw) {
    expect(row.values.every((value) => value >= 0 && value.isFinite), isTrue);
  }
  return {
    'count': values.length,
    'raw': raw,
    'build_us': _distribution(raw.map((row) => row['build_us']!)),
    'raster_us': _distribution(raw.map((row) => row['raster_us']!)),
    'total_span_us': _distribution(raw.map((row) => row['total_span_us']!)),
    'build_start_interval_us': _distribution([
      for (var i = 1; i < raw.length; i++)
        raw[i]['build_start_us']! - raw[i - 1]['build_start_us']!,
    ]),
  };
}

Map<String, Object?> _distribution(Iterable<int> samples) {
  final sorted = samples.toList()..sort();
  if (sorted.isEmpty)
    return {'count': 0, 'p50': null, 'p95': null, 'p99': null};
  int percentile(double fraction) =>
      sorted[(fraction * sorted.length).ceil() - 1];
  return {
    'count': sorted.length,
    'min': sorted.first,
    'max': sorted.last,
    'mean': sorted.fold<int>(0, (sum, value) => sum + value) / sorted.length,
    'p50': percentile(.5),
    'p95': percentile(.95),
    'p99': percentile(.99),
  };
}

Future<Uint8List> _makePng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const rect = Rect.fromLTWH(0, 0, 3000, 2000);
  canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF34536C), Color(0xFFF3C78D), Color(0xFF668A6A)],
        ).createShader(rect));
  for (var i = 0; i < 40; i++) {
    canvas.drawCircle(Offset(i * 79.0, (i * 137 % 2000).toDouble()), 110,
        Paint()..color = const Color(0x4484A9CF));
  }
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(3000, 2000).timeout(_deadline);
    final bytes = await image
        .toByteData(format: ui.ImageByteFormat.png)
        .timeout(_deadline);
    return Uint8List.sublistView(bytes!);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Identical source boundary for both providers; only decode sizing differs.
/// The artificial delay is byte availability, NOT measured network latency.
class _BytesImage extends ImageProvider<_BytesImage> {
  _BytesImage(this.bytes, this.delay);
  final Uint8List bytes;
  final Duration delay;
  int loads = 0;
  @override
  Future<_BytesImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
          _BytesImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1);
  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    loads++;
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }
}

class _ImageLease {
  _ImageLease(this.provider) {
    stream = provider.resolve(ImageConfiguration.empty);
    listener = ImageStreamListener((value, _) {
      if (info != null) {
        value.dispose();
        return;
      }
      info = value;
      decodeUs = clock.elapsedMicroseconds;
      ready.complete();
    }, onError: (Object _, StackTrace? __) {
      if (!ready.isCompleted)
        ready.completeError(StateError('Fixture PNG decode failed.'));
    });
    stream.addListener(listener);
  }
  final ImageProvider provider;
  final clock = Stopwatch()..start();
  final ready = Completer<void>();
  late final ImageStream stream;
  late final ImageStreamListener listener;
  ImageInfo? info;
  int? decodeUs;
  void dispose() {
    stream.removeListener(listener);
    info?.dispose();
  }
}

Future<Map<String, Object?>> _coverProbe(
    WidgetTester tester,
    ThemeData theme,
    _Frames frames,
    _ImageLease lease,
    _BytesImage source,
    CoverImageDecodeSize target,
    {required bool optimized,
    required bool warm,
    required bool delayed}) async {
  final painted = Completer<int>();
  final clock = Stopwatch()..start();
  final readyBeforeMount = lease.info != null;
  int? firstUiUs;
  int? sourceToUiUs;
  var announced = false;
  // Attach failure handling before mounting; decode can finish during a pump.
  final decoded = lease.ready.future.timeout(_deadline);
  await tester.pumpWidget(_app(
      theme,
      Center(
          child: SizedBox(
        width: 320,
        height: 180,
        child: Image(
          key: UniqueKey(),
          image: lease.provider,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null && !announced) {
              announced = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                firstUiUs = clock.elapsedMicroseconds;
                sourceToUiUs = lease.clock.elapsedMicroseconds;
                painted.complete(frames.currentFrame);
              });
            }
            return child;
          },
        ),
      ))));
  await decoded;
  final stamp = await painted.future.timeout(_deadline);
  await frames.through(stamp);
  final timing = frames.at(stamp);
  final raw = tester.widget<RawImage>(find.byType(RawImage));
  expect(raw.image, isNotNull);
  final expected = target.target(3000, 2000, BoxFit.cover);
  expect((raw.image!.width, raw.image!.height),
      optimized ? (expected.width, expected.height) : (3000, 2000));
  expect(source.loads, 1,
      reason: 'Warm remount must reuse the retained cache entry');
  expect(tester.takeException(), isNull);
  final finish = timing.timestampInMicroseconds(ui.FramePhase.rasterFinish);
  final build = timing.timestampInMicroseconds(ui.FramePhase.buildStart);
  return {
    'provider':
        optimized ? 'CoverImageProvider' : 'same_source_plain_decoder_bypass',
    'cache': warm ? 'warm_retained_remount' : 'cold_unique_key',
    'injected_byte_delay_us': source.delay.inMicroseconds,
    'delayed_source': delayed,
    'ready_before_mount': readyBeforeMount,
    'source_to_decoded_us': warm ? null : lease.decodeUs,
    'source_to_first_ui_post_frame_us': warm ? null : sourceToUiUs,
    'mount_to_first_ui_post_frame_us': firstUiUs,
    // This is engine raster work for the actual frame containing the image,
    // not the delayed timing-callback arrival or an assertion about scanout.
    'first_image_frame_build_to_raster_finish_us': finish - build,
    'first_image_frame': _frameSummary([timing], build),
    'decoded_width': raw.image!.width, 'decoded_height': raw.image!.height,
    'estimated_rgba_bytes': raw.image!.width * raw.image!.height * 4,
    'source_loads': source.loads,
    'comparison': 'same-build decoder policy only; NOT old application FPS',
  };
}
