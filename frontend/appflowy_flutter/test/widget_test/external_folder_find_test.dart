import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'image_ocr_test_support.dart';

// Actual ExternalContentView, all four layouts, native fields and real router.
// The injected controller exposes only in-memory listings; no provider stores,
// account credentials, network, or backend initialization are involved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;
  late bool fontFetching;
  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    translations = await loadOcrTestTranslations();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final layout in ExternalLayout.values) {
    testWidgets(
        '${layout.name}: passive local Find keeps parent and native keys',
        (tester) async {
      final fixture = _Fixture(layout);
      final mode = switch (layout) {
        ExternalLayout.gallery || ExternalLayout.compact => 'paper',
        ExternalLayout.thumbnail => 'dark',
        ExternalLayout.list => 'light',
      };
      try {
        await fixture.mount(tester, translations, mode: mode);
        final state = tester.state(find.byType(ExternalContentView));
        final original = fixture.controller.childrenOf(null);
        expect(_fieldFinder, findsNothing);
        expect(
          find.byType(ImageOcrFindRegion),
          findsNothing,
          reason: 'Cards and thumbnails are not opened image viewers.',
        );
        fixture.navigation.requestFocus();
        await tester.pump();
        await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
        expect(fixture.parentFinds, 1);
        expect(find.byKey(const ValueKey('parent-find')), findsOneWidget);
        expect(_fieldFinder, findsNothing);

        fixture.navigation.requestFocus();
        await tester.pump();
        await fixture.hoverFolder(tester);
        expect(fixture.navigation.hasFocus, isTrue);
        await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
        expect(find.byKey(const ValueKey('parent-find')), findsNothing);
        final field = _field(tester);
        expect(field.focusNode!.hasFocus, isTrue);
        expect(field.decoration!.labelText, 'Search this folder');
        final context = tester.element(_fieldFinder);
        final palette = CollectionPalette.of(context, CollectionKind.folder);
        expect(field.decoration!.fillColor, palette.surface);
        expect(field.decoration!.hoverColor, palette.hover);
        expect(PaperTheme.isEnabled(context), mode == 'paper');
        expect(
          (field.decoration!.border! as OutlineInputBorder).borderRadius,
          BorderRadius.circular(WorkspaceChrome.controlRadius),
        );
        expect(find.byType(WorkspaceControlButton), findsOneWidget);

        await _query(tester, 'ANNUAL');
        expect(_visibleCount(tester), 1);
        expect(find.byIcon(Icons.description_rounded), findsOneWidget);
        await _query(tester, 'image');
        expect(_visibleCount(tester), 1);
        expect(find.byIcon(Icons.image_rounded), findsOneWidget);
        await _query(tester, 'IMAGE/PNG');
        expect(_visibleCount(tester), 1);

        final next = ExternalLayout.values[(layout.index + 1) % 4];
        fixture.target.value = (
          controller: fixture.controller,
          parentId: null,
          layout: next,
        );
        await tester.pump();
        expect(_field(tester).controller, same(field.controller));
        expect(_field(tester).focusNode, same(field.focusNode));
        expect(field.focusNode!.hasFocus, isTrue);
        expect(_visibleCount(tester), 1);
        expect(tester.state(find.byType(ExternalContentView)), same(state));

        await _chord(tester, LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA);
        expect(
          field.controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 9),
        );
        await tester.sendKeyEvent(
          LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
        );
        await tester.pump();
        expect(field.controller!.text, isEmpty);
        expect(_visibleCount(tester), 4);
        await _query(tester, 'Sunset');
        await _escape(tester);
        expect(_fieldFinder, findsNothing);
        expect(field.controller!.text, isEmpty);
        expect(_visibleCount(tester), 4);
        expect(fixture.controller.childrenOf(null), same(original));
        expect(fixture.controller.searches, isEmpty);
        expect(fixture.controller.loads, isEmpty);
        expect(find.byType(ImageOcrFindRegion), findsNothing);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'navigation clears only local Find and preserves the folder trail',
      (tester) async {
    final fixture = _Fixture(ExternalLayout.list);
    try {
      await fixture.mount(tester, translations);
      await fixture.openFolderFind(tester);
      await _query(tester, 'Pictures');
      final controller = _field(tester).controller!;
      await tester.tap(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Pictures'),
        ),
      );
      await tester.pump();
      expect(_fieldFinder, findsNothing);
      expect(controller.text, isEmpty);
      expect(fixture.controller.loads, ['pictures']);
      expect(find.text('Sketch.png'), findsOneWidget);
      expect(find.text(LocaleKeys.providers_root.tr()), findsOneWidget);

      await fixture.openFolderFind(tester);
      await _query(tester, 'image');
      expect(find.text('Sketch.png'), findsOneWidget);
      expect(find.text('Sunset.png'), findsNothing);
      expect(find.text('Pictures'), findsOneWidget); // Trail stays intact.
      await _escape(tester);
      expect(find.text('Sketch.png'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      await tester.tap(find.text(LocaleKeys.providers_root.tr()));
      await tester.pump();
      expect(_visibleCount(tester), 4);
      expect(find.text('Sunset.png'), findsOneWidget);
      expect(fixture.controller.loads, ['pictures']);
      expect(fixture.controller.searches, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('retained host clears Find on parent or provider target change',
      (tester) async {
    final fixture = _Fixture(ExternalLayout.list);
    final replacement = _FolderController();
    try {
      await fixture.mount(tester, translations);
      final state = tester.state(find.byType(ExternalContentView));
      await fixture.openFolderFind(tester);
      await _query(tester, 'annual');
      final controller = _field(tester).controller!;
      final oldFind = _folderRegion(tester).onFind;
      fixture.target.value = (
        controller: fixture.controller,
        parentId: 'pictures',
        layout: ExternalLayout.list,
      );
      await tester.pump();
      oldFind(); // A retained old-folder callback must not reopen the new one.
      await tester.pump();
      expect(_fieldFinder, findsNothing);
      expect(controller.text, isEmpty);
      expect(find.text('Sketch.png'), findsOneWidget);
      expect(tester.state(find.byType(ExternalContentView)), same(state));

      await fixture.openFolderFind(tester);
      await _query(tester, 'sketch');
      fixture.target.value = (
        controller: replacement,
        parentId: null,
        layout: ExternalLayout.list,
      );
      await tester.pump();
      expect(_fieldFinder, findsNothing);
      expect(controller.text, isEmpty);
      expect(_visibleCount(tester), 4);
      expect(
        tester
            .widget<ExternalContentView>(find.byType(ExternalContentView))
            .controller,
        same(replacement),
      );
      expect(fixture.controller.loads, isEmpty);
      expect(replacement.loads, isEmpty);
      expect(fixture.controller.searches, isEmpty);
      expect(replacement.searches, isEmpty);
    } finally {
      await fixture.dispose(tester);
      replacement.dispose();
    }
  });

  testWidgets(
      'dependency invalidation clears Find after build and restores the retained host',
      (tester) async {
    final fixture = _Fixture(ExternalLayout.list);
    try {
      await fixture.mount(tester, translations);
      final state = tester.state(find.byType(ExternalContentView));
      final original = fixture.controller.childrenOf(null);
      await fixture.openFolderFind(tester);
      await _query(tester, 'Sunset');
      final field = _field(tester);
      final controller = field.controller!;
      final oldFind = _folderRegion(tester).onFind;
      final clearPhases = <SchedulerPhase>[];
      void recordClear() {
        if (controller.text.isEmpty) {
          clearPhases.add(tester.binding.schedulerPhase);
        }
      }

      controller.addListener(recordClear);
      fixture.tickerEnabled.value = false;
      await tester.pump();
      controller.removeListener(recordClear);
      expect(_fieldFinder, findsNothing);
      expect(controller.text, isEmpty);
      expect(field.focusNode!.hasFocus, isFalse);
      expect(clearPhases, isNotEmpty);
      expect(clearPhases, isNot(contains(SchedulerPhase.persistentCallbacks)));
      // The same build that hides Find must not filter with its queued clear.
      expect(_visibleCount(tester), 4);
      expect(tester.takeException(), isNull);
      oldFind();
      await tester.pump();
      expect(_fieldFinder, findsNothing);

      fixture.tickerEnabled.value = true;
      await tester.pump();
      expect(_fieldFinder, findsNothing);
      expect(tester.state(find.byType(ExternalContentView)), same(state));
      await fixture.openFolderFind(tester);
      expect(_field(tester).controller, same(controller));
      expect(controller.text, isEmpty);
      await _query(tester, 'Annual');
      await tester.pump();
      expect(controller.text, 'Annual');
      expect(_visibleCount(tester), 1);
      expect(fixture.controller.childrenOf(null), same(original));
      expect(fixture.controller.searches, isEmpty);
      expect(fixture.controller.loads, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('local Find ignores global results and other cached folders',
      (tester) async {
    final fixture = _Fixture(ExternalLayout.list);
    fixture.controller.query = 'saved provider query';
    try {
      await fixture.mount(tester, translations);
      expect(find.text('Elsewhere needle.png'), findsOneWidget);
      await fixture.openFolderFind(tester);
      expect(_visibleCount(tester), 4);
      await _query(tester, 'needle');
      expect(find.text('No matches in this folder'), findsOneWidget);
      expect(find.text('Elsewhere needle.png'), findsNothing);
      expect(find.text('Sketch.png'), findsNothing);
      await _query(tester, 'image');
      expect(find.text('Sunset.png'), findsOneWidget);
      expect(_visibleCount(tester), 1);
      expect(fixture.controller.query, 'saved provider query');
      expect(fixture.controller.searches, isEmpty);
      expect(fixture.controller.loads, isEmpty);
      await _escape(tester);
      expect(find.text('Elsewhere needle.png'), findsOneWidget);
      expect(fixture.controller.query, 'saved provider query');
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'owner handoff, unrelated fields and covered routes stay isolated',
      (tester) async {
    final fixture = _Fixture(ExternalLayout.list);
    try {
      await fixture.mount(tester, translations);
      await fixture.openFolderFind(tester);
      await _query(tester, 'Sunset');
      final controller = _field(tester).controller!;
      final findFocus = _field(tester).focusNode!;
      await fixture.mouse!.moveTo(
        tester.getCenter(find.byKey(const ValueKey('page-navigation'))),
      );
      await tester.pump();
      await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
      expect(
        _fieldFinder,
        findsOneWidget,
        reason: 'Parent background cannot steal a focused child query.',
      );
      expect(controller.text, 'Sunset');
      expect(findFocus.hasPrimaryFocus, isTrue);
      expect(fixture.parentFinds, 0);

      await tester.tap(find.byKey(const ValueKey('page-navigation')));
      // The fixture's button has no navigation action; make focus intent
      // explicit rather than assuming a synthetic tap transfers keyboard focus.
      fixture.navigation.requestFocus();
      await tester.pump();
      expect(fixture.navigation.hasPrimaryFocus, isTrue);
      expect(findFocus.hasFocus, isFalse);
      await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
      expect(_fieldFinder, findsNothing);
      expect(controller.text, isEmpty);
      expect(find.byKey(const ValueKey('parent-find')), findsOneWidget);

      fixture.unrelated.requestFocus();
      await tester.pump();
      await fixture.hoverFolder(tester);
      final parentFinds = fixture.parentFinds;
      await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
      expect(fixture.unrelated.hasFocus, isTrue);
      expect(fixture.parentFinds, parentFinds);
      expect(_fieldFinder, findsNothing);

      fixture.navigation.requestFocus();
      await tester.pump();
      await fixture.openFolderFind(tester);
      await _query(tester, 'Sunset');
      unawaited(
        fixture.navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Another route')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(
          const ValueKey('external-folder-find'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
      await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
      expect(fixture.parentFinds, parentFinds);
      fixture.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await fixture.openFolderFind(tester);
      expect(_field(tester).controller!.text, isEmpty);
      expect(_visibleCount(tester), 4);
      expect(fixture.controller.searches, isEmpty);
      expect(fixture.controller.loads, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final nestedNavigator in [false, true]) {
    testWidgets(
        'root dialog clears ${nestedNavigator ? 'nested' : 'root'} folder Find and restores its trail',
        (tester) async {
      final fixture = _Fixture(ExternalLayout.list);
      final dialogQuery = TextEditingController(text: 'Modal draft');
      final dialogFocus = FocusNode();
      try {
        await fixture.mount(
          tester,
          translations,
          nestedNavigator: nestedNavigator,
        );
        final host = find.byType(ExternalContentView);
        final state = tester.state(host);
        final original = fixture.controller.childrenOf(null);
        final pictures = fixture.controller.childrenOf('pictures');
        await tester.tap(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Pictures'),
          ),
        );
        await tester.pump();
        await fixture.openFolderFind(tester);
        await _query(tester, 'Sketch');
        final controller = _field(tester).controller!;
        final region = _folderRegion(tester);
        final hostContext = tester.element(host);
        final route = ModalRoute.of(hostContext)!;
        unawaited(
          showDialog<void>(
            context: hostContext,
            builder: (context) => AlertDialog(
              title: const Text('Root dialog'),
              content: TextField(
                controller: dialogQuery,
                focusNode: dialogFocus,
                autofocus: true,
              ),
              actions: [
                TextButton(
                  key: const ValueKey('close-cover'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(route.isCurrent, nestedNavigator);
        expect(
          TickerMode.of(hostContext),
          isTrue,
          reason: 'A non-opaque dialog does not disable the folder ticker.',
        );
        expect(region.isActive!(), isFalse);
        expect(
          find.byKey(
            const ValueKey('external-folder-find'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(controller.text, isEmpty);
        expect(dialogFocus.hasPrimaryFocus, isTrue);
        expect(tester.takeException(), isNull);

        region.onFind(); // Even a retained callback must respect root coverage.
        await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
        expect(_fieldFinder, findsNothing);
        expect(fixture.parentFinds, 0);
        expect(dialogQuery.text, 'Modal draft');
        expect(dialogFocus.hasPrimaryFocus, isTrue);

        await tester.tap(find.byKey(const ValueKey('close-cover')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(route.isCurrent, isTrue);
        expect(tester.state(host), same(state));
        expect(
          _fieldFinder,
          findsNothing,
          reason: 'Route restoration must not reopen the dismissed query.',
        );
        expect(_visibleCount(tester), 2);
        expect(find.text('Pictures'), findsOneWidget);
        expect(find.text('Sketch.png'), findsOneWidget);
        expect(find.text('Notes'), findsOneWidget);
        await fixture.openFolderFind(tester);
        expect(_field(tester).controller, same(controller));
        expect(controller.text, isEmpty);
        await _query(tester, 'Notes');
        expect(_visibleCount(tester), 1);
        expect(controller.text, 'Notes');
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Notes'),
          ),
          findsOneWidget,
        );
        expect(fixture.controller.childrenOf(null), same(original));
        expect(fixture.controller.childrenOf('pictures'), same(pictures));
        expect(fixture.controller.query, isEmpty);
        expect(fixture.controller.searches, isEmpty);
        expect(fixture.controller.loads, ['pictures']);
      } finally {
        await fixture.dispose(tester);
        dialogQuery.dispose();
        dialogFocus.dispose();
      }
    });
  }
}

typedef _Target = ({
  _FolderController controller,
  String? parentId,
  ExternalLayout layout,
});

class _Fixture {
  _Fixture(ExternalLayout layout) {
    target =
        ValueNotifier((controller: controller, parentId: null, layout: layout));
  }

  final controller = _FolderController();
  late final ValueNotifier<_Target> target;
  final navigation = FocusNode();
  final unrelated = FocusNode();
  final parentFocus = FocusNode();
  final parentQuery = TextEditingController();
  final parentOpen = ValueNotifier(false);
  final tickerEnabled = ValueNotifier(true);
  final navigator = GlobalKey<NavigatorState>();
  TestGesture? mouse;
  int parentFinds = 0;

  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> translations, {
    String mode = 'light',
    bool nestedNavigator = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    final content = ContextualFindScope(
      child: ValueListenableBuilder<bool>(
        valueListenable: parentOpen,
        builder: (context, open, _) => ContextualFindRegion(
          debugLabel: 'Collection page',
          onFind: () {
            parentFinds++;
            parentOpen.value = true;
            parentFocus.requestFocus();
          },
          findOpen: open,
          findFocusNode: parentFocus,
          onDismiss: () {
            parentOpen.value = false;
            parentFocus.unfocus();
          },
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    TextButton(
                      key: const ValueKey('page-navigation'),
                      focusNode: navigation,
                      onPressed: () {},
                      child: const Text('Navigation'),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 230,
                      child: TextField(
                        focusNode: unrelated,
                        decoration:
                            const InputDecoration(hintText: 'Unrelated field'),
                      ),
                    ),
                  ],
                ),
              ),
              if (open)
                TextField(
                  key: const ValueKey('parent-find'),
                  controller: parentQuery,
                  focusNode: parentFocus,
                ),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: tickerEnabled,
                  builder: (context, enabled, child) =>
                      TickerMode(enabled: enabled, child: child!),
                  child: ValueListenableBuilder<_Target>(
                    valueListenable: target,
                    builder: (context, value, _) => ListenableBuilder(
                      listenable: value.controller,
                      builder: (context, _) => ExternalContentView(
                        controller: value.controller,
                        parentId: value.parentId,
                        layout: value.layout,
                        palette: CollectionPalette.of(
                          context,
                          CollectionKind.folder,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      ocrTestApp(
        nestedNavigator
            ? Navigator(
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => content),
              )
            : content,
        mode: mode,
        navigatorKey: navigator,
        translations: translations,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> hoverFolder(WidgetTester tester) async {
    if (mouse == null) {
      mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse!.addPointer(location: const Offset(-10, -10));
    }
    final bounds = tester.getRect(find.byType(ExternalContentView));
    // A body margin, not a scrollbar or a search TextField.
    await mouse!.moveTo(bounds.bottomLeft + const Offset(40, -40));
    await tester.pump();
  }

  Future<void> openFolderFind(WidgetTester tester) async {
    await hoverFolder(tester);
    await _chord(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
    expect(_fieldFinder, findsOneWidget);
    expect(_field(tester).focusNode!.hasFocus, isTrue);
  }

  Future<void> dispose(WidgetTester tester) async {
    await mouse?.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    target.dispose();
    controller.dispose();
    navigation.dispose();
    unrelated.dispose();
    parentFocus.dispose();
    parentQuery.dispose();
    parentOpen.dispose();
    tickerEnabled.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
    expect(tester.takeException(), isNull);
  }
}

class _FolderController extends ChangeNotifier implements ProviderController {
  static const root = [
    ProviderNode(
      id: 'pictures',
      name: 'Pictures',
      kind: ProviderNodeKind.folder,
    ),
    ProviderNode(
      id: 'sunset',
      name: 'Sunset.png',
      kind: ProviderNodeKind.image,
      mimeType: 'image/png',
    ),
    ProviderNode(
      id: 'report',
      name: 'Annual report',
      kind: ProviderNodeKind.document,
    ),
    ProviderNode(id: 'meeting', name: 'Meeting', kind: ProviderNodeKind.audio),
  ];
  static const pictures = [
    ProviderNode(
      id: 'sketch',
      name: 'Sketch.png',
      kind: ProviderNodeKind.image,
      parentId: 'pictures',
      mimeType: 'image/png',
    ),
    ProviderNode(
      id: 'notes',
      name: 'Notes',
      kind: ProviderNodeKind.document,
      parentId: 'pictures',
    ),
  ];
  static const elsewhere = [
    ProviderNode(
      id: 'foreign',
      name: 'Elsewhere needle.png',
      kind: ProviderNodeKind.image,
      parentId: 'elsewhere',
    ),
  ];

  final searches = <String>[];
  final loads = <String>[];
  @override
  String query = '';
  @override
  bool get isSearching => query.isNotEmpty;
  @override
  List<ProviderNode> get nodes => isSearching ? elsewhere : root;
  @override
  List<ProviderNode> childrenOf(String? containerId) => switch (containerId) {
        null => root,
        'pictures' => pictures,
        'elsewhere' => elsewhere,
        _ => const [],
      };
  @override
  bool isLoadingContainer(String? containerId) => false;
  @override
  String? thumbnailFor(String nodeId) => null;
  @override
  Future<void> ensureLoaded(String containerId) async => loads.add(containerId);
  @override
  Future<void> search(String rawQuery) async {
    searches.add(rawQuery);
    query = rawQuery;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'Unexpected provider IO: ${invocation.memberName}',
      );
}

Finder get _fieldFinder => find.byKey(const ValueKey('external-folder-find'));
TextField _field(WidgetTester tester) => tester.widget(_fieldFinder);

ContextualFindRegion _folderRegion(WidgetTester tester) => tester.widget(
      find.descendant(
        of: find.byType(ExternalContentView),
        matching: find.byType(ContextualFindRegion),
      ),
    );

int _visibleCount(WidgetTester tester) {
  final grids = find.descendant(
    of: find.byType(ExternalContentView),
    matching: find.byType(GridView),
  );
  if (grids.evaluate().isNotEmpty) {
    return tester.widget<GridView>(grids).childrenDelegate.estimatedChildCount!;
  }
  final lists = find.descendant(
    of: find.byType(ExternalContentView),
    matching: find.byType(ListView),
  );
  return lists.evaluate().isEmpty
      ? 0
      : tester.widget<ListView>(lists).childrenDelegate.estimatedChildCount!;
}

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(_fieldFinder, query);
  await tester.pump();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key,
  PhysicalKeyboardKey physical,
) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.sendKeyEvent(key, physicalKey: physical);
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(
    LogicalKeyboardKey.escape,
    physicalKey: PhysicalKeyboardKey.escape,
  );
  await tester.pump();
  await tester.pump();
}
