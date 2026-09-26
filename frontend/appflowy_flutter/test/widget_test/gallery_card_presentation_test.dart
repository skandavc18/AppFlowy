import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_view_factory.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;

const _appearances = ['light', 'dark', 'paper'];
const _cardKey = ValueKey('gallery-presentation-card');
const _referenceKey = ValueKey('gallery-presentation-reference');
const _away = Offset(8, 8);
const _halfTransition = Duration(milliseconds: 70);
const _preview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.heading,
      runs: [FolderGalleryTextRun(text: 'A place for ideas')],
      level: 2,
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.paragraph,
      runs: [
        FolderGalleryTextRun(
          text: 'Keep the content in view. Its surface should feel distinct '
              'without moving the page beneath your pointer.',
        ),
      ],
    ),
  ],
  wordCount: 27,
  readingMinutes: 1,
  tags: ['research'],
  fileTypeLabel: 'MD',
);
const _folderPreview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.folder,
  blocks: [],
  wordCount: 0,
  readingMinutes: 0,
  tags: [],
  fileTypeLabel: 'FOLDER',
);
final _readyPreview = SynchronousFuture(_preview);
final _themes = <String, ThemeData>{};
late Map<String, dynamic> _translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool fontFetching;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final appearance in _appearances) {
      _themes[appearance] = _theme(appearance);
    }
    final families = <String>{'Inter'};
    for (final theme in _themes.values) {
      families.addAll([
        theme.textTheme.bodyMedium!.fontFamily!,
        theme.textTheme.bodySmall!.fontFamily!,
        theme.textTheme.titleMedium!.fontFamily!,
        theme.textTheme.headlineSmall!.fontFamily!,
        theme.textTheme.labelLarge!.fontFamily!,
      ]);
    }
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle.load(
                family.startsWith('Inter')
                    ? 'assets/google_fonts/Inter/Inter-Variable.ttf'
                    : 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
              ),
            ))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final appearance in _appearances) {
    _test('$appearance: gallery layers separate from both host surfaces',
        (tester) async {
      await _mount(tester, _card(), appearance: appearance);
      final context = tester.element(_surface());
      final palette = GalleryCardPalette.of(context);
      final explorer = FolderExplorerPalette.of(context);
      expect(PaperTheme.isEnabled(context), appearance == 'paper');
      expect(palette.surface.a, 1);
      expect(palette.footer.a, 1);
      expect(palette.surface, isNot(Colors.white));
      expect(palette.footer, isNot(palette.surface));
      expect(
        _contrast(palette.surface, explorer.background),
        greaterThan(1.04),
      );
      expect(
        _contrast(
          palette.surface,
          EditorSurfaceStyle.canvasBackground(context),
        ),
        greaterThan(1.02),
      );
      if (appearance == 'paper') {
        expect(
          EditorSurfaceStyle.previewBackgroundFor(
            Theme.of(context).brightness,
            explorer.surface,
            isPaper: PaperTheme.isEnabled(context),
          ),
          PaperTheme.editorPreviewBackground,
        );
        expect(palette.surface, isNot(PaperTheme.editorPreviewBackground));
        expect(palette.surface.r, greaterThan(palette.surface.g));
        expect(palette.surface.g, greaterThan(palette.surface.b));
        expect(palette.footer.r, greaterThan(palette.footer.g));
        expect(palette.footer.g, greaterThan(palette.footer.b));
      }
      _expectPaint(tester, palette, 0);
      _expectRing(tester, visible: false);
      expect(_box(tester, 'gallery-card-surface').gradient, isNull);
      expect(_box(tester, 'gallery-card-surface').border, isNull);
      final edge = _box(tester, 'gallery-card-edge').border! as Border;
      expect(edge.top.width, 0.75);
      expect(edge.top.color.a, greaterThan(0));
      expect(edge.top.color.a, lessThan(0.2));
      final footer = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(GalleryCardFooter),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((footer.decoration as BoxDecoration).color, palette.footer);
      final previewFill = tester.widget<ColoredBox>(
        find.descendant(of: _stage(), matching: find.byType(ColoredBox)).first,
      );
      expect(previewFill.color, palette.surface);
      for (final shadows in [palette.restingShadows, palette.raisedShadows]) {
        expect(shadows, hasLength(2));
        expect(shadows.first.blurRadius, lessThan(shadows.last.blurRadius));
        for (final shadow in shadows) {
          expect(
            shadow.color.withValues(alpha: 1),
            explorer.shadow.withValues(alpha: 1),
          );
          expect(shadow.color.a, greaterThan(0));
          expect(shadow.color.a, lessThanOrEqualTo(0.4));
        }
      }
      expect(
        find.descendant(
          of: find.byKey(_cardKey),
          matching: find.byType(WorkspaceSurface),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    _test('$appearance: hover and focus animate paint, not renderer geometry',
        (tester) async {
      final outside = FocusNode();
      final selected = ValueNotifier(false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      var opens = 0;
      var menus = 0;
      VoidCallback? release;
      try {
        await mouse.addPointer(location: _away);
        await _mount(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: selected,
            builder: (_, value, __) => _card(
              selected: value,
              onTap: () => opens++,
              onMore: (_) => menus++,
            ),
          ),
          appearance: appearance,
          outsideFocus: outside,
        );
        final palette = GalleryCardPalette.of(tester.element(_surface()));
        final cardState = tester.state(find.byKey(_cardKey));
        final surfaceState = tester.state(_surface());
        final renderer = _renderer(tester);
        final previewBounds = tester.getRect(_stage());
        final actionBounds = tester.getRect(_more());
        final focus = Focus.of(tester.element(_surface()));
        expect(focus.debugLabel, 'Folder gallery card');
        expect(galleryCardHoverDuration, const Duration(milliseconds: 140));

        void expectRetained() {
          expect(tester.state(find.byKey(_cardKey)), same(cardState));
          expect(tester.state(_surface()), same(surfaceState));
          expect(_renderer(tester), same(renderer));
          expect(tester.getRect(_stage()), previewBounds);
          expect(tester.getRect(_more()), actionBounds);
        }

        _expectToolbar(tester, visible: false);
        _expectPaint(tester, palette, 0);
        await mouse.moveTo(previewBounds.center);
        await tester.pump();
        await tester.pump();
        _expectPaint(tester, palette, 0);
        await tester.pump(_halfTransition);
        _expectPaint(tester, palette, WorkspaceTokens.curve.transform(0.5));
        expectRetained();
        await tester.pump(_halfTransition);
        _expectPaint(tester, palette, 1);
        await tester.pump(const Duration(microseconds: 1));
        _expectToolbar(tester, visible: true);
        _expectRing(tester, visible: false);
        expectRetained();
        await settleVividIconPictures(tester);
        final overflowGlyph = find.descendant(
          of: _more(),
          matching: find.byType(WorkspaceGlyph),
        );
        expect(tester.widget<WorkspaceGlyph>(overflowGlyph).name, 'dots-three');
        final overflowPicture = tester.widget<SvgPicture>(
          find.descendant(
            of: overflowGlyph,
            matching: find.byType(SvgPicture),
          ),
        );
        final loader = overflowPicture.bytesLoader as SvgStringLoader;
        expect(
          loader,
          SvgStringLoader(
            vividIconSvg('utility-dots-three')!,
            theme: loader.theme,
          ),
        );
        expect(overflowPicture.colorFilter, isNull);

        focus.requestFocus();
        await _finishTransitions(tester);
        expect(focus.hasPrimaryFocus, isTrue);
        _expectRing(tester, visible: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(opens, 1);
        await mouse.moveTo(_away);
        await _finishTransitions(tester);
        _expectPaint(tester, palette, 1);
        _expectToolbar(tester, visible: true);
        expectRetained();

        // Native overflow focus must keep the card raised without becoming
        // another card activation target or a second surface focus owner.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await _finishTransitions(tester);
        expect(focus.hasFocus, isTrue);
        expect(focus.hasPrimaryFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(menus, 1);
        expect(opens, 1);
        _expectPaint(tester, palette, 1);
        expectRetained();

        outside.requestFocus();
        await tester.pump();
        await tester.pump();
        _expectRing(tester, visible: false);
        await tester.pump(_halfTransition);
        _expectPaint(tester, palette, 1 - WorkspaceTokens.curve.transform(0.5));
        expectRetained();
        await tester.pump(_halfTransition);
        _expectPaint(tester, palette, 0);
        await tester.pump(const Duration(microseconds: 1));
        _expectToolbar(tester, visible: false);

        for (final value in [true, false, true, false]) {
          selected.value = value;
          await _finishTransitions(tester);
          _expectRing(tester, visible: value);
          _expectToolbar(tester, visible: value);
          _expectPaint(tester, palette, 0);
          expectRetained();
        }
        // With the pointer outside, one Tab reaches the existing card node.
        // Focus alone gets the same 140 ms paint transition as hover.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        _expectRing(tester, visible: true);
        _expectPaint(tester, palette, 0);
        await tester.pump(_halfTransition);
        _expectPaint(tester, palette, WorkspaceTokens.curve.transform(0.5));
        expectRetained();
        await tester.pump(_halfTransition);
        _expectPaint(tester, palette, 1);
        await tester.pump(const Duration(microseconds: 1));
        outside.requestFocus();
        await _finishTransitions(tester);
        _expectPaint(tester, palette, 0);
        _expectRing(tester, visible: false);
        expectRetained();

        release = PreviewToolbarRegion.hold(tester.element(_more()));
        await _finishTransitions(tester);
        _expectToolbar(tester, visible: true);
        release();
        release = null;
        await _finishTransitions(tester);
        _expectToolbar(tester, visible: false);
        expectRetained();
        expect(tester.takeException(), isNull);
      } finally {
        release?.call();
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        outside.dispose();
        selected.dispose();
      }
    });

    // Three baselines only; generation/review belongs to the main test run.
    _test('$appearance: gallery surface reference', (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await mouse.addPointer(location: _away);
        await _mount(
          tester,
          Builder(builder: (context) => _reference(context, appearance)),
          appearance: appearance,
        );
        const hoverKey = ValueKey('gallery-reference-hover');
        const focusKey = ValueKey('gallery-reference-focus');
        await mouse.moveTo(tester.getCenter(_stage(hoverKey)));
        Focus.of(tester.element(_surface(focusKey))).requestFocus();
        await _finishTransitions(tester);
        await tester.pumpAndSettle();
        _expectToolbar(tester, card: hoverKey, visible: true);
        _expectToolbar(tester, card: focusKey, visible: true);
        _expectRing(tester, card: focusKey, visible: true);
        _expectToolbar(
          tester,
          card: const ValueKey('gallery-reference-idle'),
          visible: false,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(_referenceKey),
          matchesGoldenFile(
            'goldens/gallery_card_presentation_$appearance.png',
          ),
        );
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        debugDisableShadows = previousShadows;
      }
    });
  }

  for (final accessible in [false, true]) {
    _test(
      '${accessible ? 'accessible navigation' : 'disabled animations'}: '
      'snap in-flight hover and subsequent focus without elapsed time',
      (tester) async {
        final reduced = ValueNotifier(false);
        final outside = FocusNode();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _away);
          await _mount(
            tester,
            ValueListenableBuilder<bool>(
              valueListenable: reduced,
              child: _card(),
              builder: (context, value, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: value && !accessible,
                  accessibleNavigation: value && accessible,
                ),
                child: child!,
              ),
            ),
            outsideFocus: outside,
          );
          final palette = GalleryCardPalette.of(tester.element(_surface()));
          final renderer = _renderer(tester);
          final bounds = tester.getRect(_stage());
          final focus = Focus.of(tester.element(_surface()));
          await mouse.moveTo(bounds.center);
          await tester.pump();
          await tester.pump();
          await tester.pump(_halfTransition);
          _expectPaint(tester, palette, WorkspaceTokens.curve.transform(0.5));

          reduced.value = true;
          await tester.pump();
          await tester.pump();
          _expectPaint(tester, palette, 1);
          expect(
            tester.widget<AnimatedOpacity>(_toolbarFade()).duration,
            Duration.zero,
          );
          await mouse.moveTo(_away);
          await tester.pump();
          await tester.pump();
          _expectPaint(tester, palette, 0);
          focus.requestFocus();
          await tester.pump();
          await tester.pump();
          _expectPaint(tester, palette, 1);
          _expectRing(tester, visible: true);
          outside.requestFocus();
          await tester.pump();
          await tester.pump();
          _expectPaint(tester, palette, 0);
          _expectRing(tester, visible: false);
          await tester.pump(const Duration(milliseconds: 141));
          _expectPaint(tester, palette, 0);
          expect(_renderer(tester), same(renderer));
          expect(tester.getRect(_stage()), bounds);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          outside.dispose();
          reduced.dispose();
        }
      },
    );
  }

  _test('surface owns paint only and retains its exact child through ticks',
      (tester) async {
    final hovered = ValueNotifier(false);
    var builds = 0;
    try {
      await _mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: hovered,
          child: Builder(
            builder: (_) {
              builds++;
              return const SizedBox.expand(key: ValueKey('retained-content'));
            },
          ),
          builder: (_, value, child) => SizedBox(
            width: 300,
            height: 360,
            child: GalleryCardSurface(hovered: value, child: child!),
          ),
        ),
      );
      final surface = find.byType(GalleryCardSurface);
      final content = find.byKey(const ValueKey('retained-content'));
      final element = tester.element(content);
      final bounds = tester.getRect(content);
      final initialBuilds = builds;
      for (final type in [Focus, MouseRegion, GestureDetector, Transform]) {
        expect(
          find.descendant(of: surface, matching: find.byType(type)),
          findsNothing,
        );
      }
      for (final value in [true, false, true, false]) {
        hovered.value = value;
        await tester.pump();
        await tester.pump();
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 14));
          expect(tester.element(content), same(element));
          expect(tester.getRect(content), bounds);
          expect(builds, initialBuilds);
        }
        await tester.pump(const Duration(microseconds: 1));
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      hovered.dispose();
    }
  });

  _test('loading, theme, hover and selection retain rename caret and scroll',
      (tester) async {
    final preview = Completer<FolderGalleryPreview>();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final submissions = <String>[];
    final view = _view();
    Future<bool> submit(String name) async {
      submissions.add(name);
      return true;
    }

    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        _card(
          view: view,
          preview: preview.future,
          editing: true,
          onRenameSubmitted: submit,
        ),
      );
      final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
      expect(
        find.byKey(const ValueKey('folder-gallery-preview-loading')),
        findsOneWidget,
      );
      await tester.enterText(editor, 'Uncommitted research notes.md');
      final state = tester.state<EditableTextState>(editor);
      final input = tester.widget<EditableText>(editor);
      input.controller.selection =
          const TextSelection(baseOffset: 2, extentOffset: 11);
      final value = input.controller.value;
      final cardState = tester.state(find.byKey(_cardKey));
      final surfaceState = tester.state(_surface());
      preview.complete(
        FolderGalleryPreview(
          kind: FolderGalleryPreviewKind.document,
          blocks: List.generate(50, (_) => _preview.blocks.last),
          wordCount: 1000,
          readingMinutes: 5,
          tags: const ['research'],
          fileTypeLabel: 'MD',
        ),
      );
      await _finishTransitions(tester);
      final renderer = _renderer(tester);
      // The Windows scrollbar exposes this controller-less ListView's
      // fallback controller without changing the production scrollable.
      final scrollbar = find.descendant(
        of: find.byType(FolderGalleryRichTextPreview),
        matching: find.byType(Scrollbar),
      );
      final controller = tester.widget<Scrollbar>(scrollbar).controller!;
      var position = renderer.position;
      expect(position.maxScrollExtent, greaterThan(48));
      position.jumpTo(48);
      await tester.pump();

      for (final (appearance, width, selected) in [
        ('light', 196.0, true),
        ('dark', 336.0, false),
        ('paper', 300.0, true),
        ('paper', 300.0, false),
      ]) {
        final previousTheme = Theme.of(renderer.context);
        await _mount(
          tester,
          _card(
            view: view,
            preview: preview.future,
            width: width,
            editing: true,
            selected: selected,
            onRenameSubmitted: submit,
          ),
          appearance: appearance,
        );
        expect(_renderer(tester), same(renderer));
        expect(
          tester.widget<Scrollbar>(scrollbar).controller,
          same(controller),
        );
        final nextPosition = renderer.position;
        // MaterialScrollBehavior reads Theme.of(context).platform, so a theme
        // change calls ScrollableState.didChangeDependencies even on Windows.
        // Flutter rebuilds the physics/position, absorbs the old offset and
        // disposes the old position/notifier in a microtask (flushed by _mount).
        // A selection-only rebuild under the same theme must retain it.
        if (Theme.of(renderer.context) == previousTheme) {
          expect(nextPosition, same(position));
        } else if (!identical(nextPosition, position)) {
          expect(
            () => ChangeNotifier.debugAssertNotDisposed(position),
            throwsFlutterError,
          );
          expect(
            () => ChangeNotifier.debugAssertNotDisposed(
              position.isScrollingNotifier,
            ),
            throwsFlutterError,
          );
        }
        position = nextPosition;
        expect(controller.position, same(position));
        expect(position.maxScrollExtent, greaterThan(48));
        expect(position.pixels, 48);
        final previewBounds = tester.getRect(_stage());
        final actionBounds = tester.getRect(_more());
        final editorBounds = tester.getRect(editor);
        for (final location in [previewBounds.center, _away]) {
          await mouse.moveTo(location);
          await _finishTransitions(tester);
          expect(tester.state(find.byKey(_cardKey)), same(cardState));
          expect(tester.state(_surface()), same(surfaceState));
          expect(tester.state<EditableTextState>(editor), same(state));
          expect(
            tester.widget<EditableText>(editor).controller,
            same(input.controller),
          );
          expect(input.controller.value, value);
          expect(
            tester.widget<EditableText>(editor).focusNode,
            same(input.focusNode),
          );
          expect(input.focusNode.hasFocus, isTrue);
          expect(_renderer(tester), same(renderer));
          expect(
            tester.widget<Scrollbar>(scrollbar).controller,
            same(controller),
          );
          expect(controller.position, same(position));
          expect(renderer.position, same(position));
          expect(renderer.position.pixels, 48);
          expect(
            ChangeNotifier.debugAssertNotDisposed(position.isScrollingNotifier),
            isTrue,
          );
          expect(tester.getRect(_stage()), previewBounds);
          expect(tester.getRect(_more()), actionBounds);
          expect(tester.getRect(editor), editorBounds);
          _expectToolbar(tester, visible: true);
          expect(submissions, isEmpty);
        }
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submissions, [value.text]);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  _test('compact archive cards reuse the surface without reloading previews',
      (tester) async {
    const entry = ArchiveEntry(
      path: 'Research notes.md',
      isDirectory: false,
      size: 2048,
    );
    final view = _view();
    final archiveItem = ArchiveEntryView(
      entry: entry,
      view: view,
      item: WorkspaceExplorerItem.fromView(view),
    );
    final loader = _PreviewLoader();
    final cache = FolderGalleryPreviewCache(loader: loader);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final opened = <ArchiveEntryView>[];
    final selected = <ArchiveEntryView>[];
    const card = ValueKey('archive-card-Research notes.md');
    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        SizedBox(
          width: 520,
          height: 440,
          child: ArchiveGallery(
            entries: [archiveItem],
            previewCache: cache,
            selectedPath: null,
            renamingPath: null,
            editable: true,
            compact: true,
            onSelect: selected.add,
            onOpen: opened.add,
            onRenameRequested: (_) {},
            onRenameSubmitted: (_, __) async => true,
            onRenameCancelled: () {},
            onMore: (_, __) {},
          ),
        ),
      );
      expect(_surface(card), findsOneWidget);
      final palette = GalleryCardPalette.of(tester.element(_surface(card)));
      final state = tester.state(_surface(card));
      final bounds = tester.getRect(_stage(card));
      _expectPaint(tester, palette, 0, card: card);
      await mouse.moveTo(bounds.center);
      await _finishTransitions(tester);
      _expectPaint(tester, palette, 1, card: card);
      _expectToolbar(tester, card: card, visible: true);
      await tester.tapAt(bounds.center, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(opened, [archiveItem]);
      expect(selected, [archiveItem]);
      expect(loader.loads, 1);
      expect(tester.state(_surface(card)), same(state));
      expect(tester.getRect(_stage(card)), bounds);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      cache.clear();
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await body(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 30)),
    );

Finder _inside(Key card, Finder target) =>
    find.descendant(of: find.byKey(card), matching: target);
Finder _surface([Key card = _cardKey]) =>
    _inside(card, find.byType(GalleryCardSurface));
Finder _stage([Key card = _cardKey]) =>
    _inside(card, find.byKey(const ValueKey('folder-gallery-preview-stage')));
Finder _more([Key card = _cardKey]) =>
    _inside(card, find.byKey(const ValueKey('folder-gallery-more')));
Finder _toolbarFade([Key card = _cardKey]) => find.descendant(
      of: _inside(card, find.byType(PreviewToolbar)),
      matching: find.byType(AnimatedOpacity),
    );

BoxDecoration _box(WidgetTester tester, String name, {Key card = _cardKey}) =>
    tester
        .widget<DecoratedBox>(_inside(card, find.byKey(ValueKey(name))))
        .decoration as BoxDecoration;

void _expectPaint(
  WidgetTester tester,
  GalleryCardPalette palette,
  double emphasis, {
  Key card = _cardKey,
}) {
  expect(
    _box(tester, 'gallery-card-surface', card: card),
    palette.decoration(emphasis),
  );
  expect(
    _box(tester, 'gallery-card-edge', card: card),
    palette.outline(emphasis),
  );
}

void _expectRing(
  WidgetTester tester, {
  Key card = _cardKey,
  required bool visible,
}) {
  final ring = _box(tester, 'folder-gallery-selection', card: card);
  expect(ring.borderRadius, EditorSurfaceStyle.embedBorderRadius);
  expect(
    ring.border,
    visible
        ? Border.all(
            color: WorkspacePalette.of(tester.element(_surface(card))).focus,
            width: 1.5,
          )
        : isNull,
  );
}

void _expectToolbar(
  WidgetTester tester, {
  Key card = _cardKey,
  required bool visible,
}) {
  expect(
    tester.widget<AnimatedOpacity>(_toolbarFade(card)).opacity,
    visible ? 1 : 0,
  );
  final ignore = find.descendant(
    of: _inside(card, find.byType(PreviewToolbar)),
    matching: find.byType(IgnorePointer),
  );
  expect(tester.widget<IgnorePointer>(ignore).ignoring, !visible);
  expect(_more(card).hitTestable(), visible ? findsOneWidget : findsNothing);
}

ScrollableState _renderer(WidgetTester tester) => tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(FolderGalleryRichTextPreview),
        matching: find.byType(Scrollable),
      ),
    );

Future<void> _finishTransitions(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 141));
  await tester.pump();
}

ViewPB _view({
  String id = 'presentation-page',
  String name = 'Research notes.md',
  bool folder = false,
  bool cover = false,
}) {
  var extra = folder
      ? const WorkspaceItemMetadata.folder().mergeIntoExtra('')
      : const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          size: 2048,
        ).mergeIntoExtra('');
  if (cover) {
    extra = ViewPreviewModeCodec.merge(
      ViewCoverCodec.mergeCover(
        extra,
        const PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#B8C6AF',
        ),
      ),
      ViewPreviewMode.cover,
    );
  }
  return ViewPB(
    id: id,
    name: name,
    layout: ViewLayoutPB.Document,
    extra: extra,
  );
}

Widget _card({
  Key key = _cardKey,
  ViewPB? view,
  Future<FolderGalleryPreview>? preview,
  double width = 300,
  double height = 360,
  bool selected = false,
  bool editing = false,
  int? childCount,
  VoidCallback? onTap,
  ValueChanged<Offset>? onMore,
  Future<bool> Function(String)? onRenameSubmitted,
}) {
  final page = view ?? _view();
  return SizedBox(
    width: width,
    height: height,
    child: FolderGalleryCard(
      key: key,
      item: WorkspaceExplorerItem.fromView(page),
      view: page,
      preview: preview ?? _readyPreview,
      userProfile: null,
      selected: selected,
      editing: editing,
      childCount: childCount,
      onTap: onTap ?? () {},
      onRename: () {},
      onRenameSubmitted: onRenameSubmitted ?? (_) async => true,
      onRenameCancelled: () {},
      onMore: onMore ?? (_) {},
      onContextMenu: (_) {},
    ),
  );
}

Widget _reference(BuildContext context, String appearance) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 1160,
    height: 540,
    child: RepaintBoundary(
      key: _referenceKey,
      child: Material(
        color: FolderExplorerPalette.of(context).background,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Gallery surfaces / ${appearance.toUpperCase()}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Tonal layers, a quiet edge, and grounded depth.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (sample, label) in [
                    ('idle', 'Idle'),
                    ('hover', 'Hover'),
                    ('focus', 'Keyboard focus'),
                    ('selected', 'Selected cover'),
                  ])
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _card(
                          key: ValueKey('gallery-reference-$sample'),
                          view: _view(
                            id: sample,
                            name: sample == 'hover'
                                ? 'Collected ideas'
                                : 'Research notes.md',
                            folder: sample == 'hover',
                            cover: sample == 'selected',
                          ),
                          preview: sample == 'hover'
                              ? SynchronousFuture(_folderPreview)
                              : _readyPreview,
                          childCount: sample == 'hover' ? 7 : null,
                          width: 248,
                          height: 330,
                          selected: sample == 'selected',
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

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
  Widget child, {
  String appearance = 'paper',
  FocusNode? outsideFocus,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _themes[appearance],
          themeAnimationDuration: Duration.zero,
          builder: (_, navigator) =>
              TooltipVisibility(visible: false, child: navigator!),
          home: Scaffold(
            body: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: Column(
                children: [
                  TextButton(
                    focusNode: outsideFocus,
                    onPressed: () {},
                    child: const Text('Outside card'),
                  ),
                  Expanded(child: Center(child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _finishTransitions(tester);
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

class _PreviewLoader extends FolderGalleryPreviewLoader {
  int loads = 0;

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    loads++;
    return _readyPreview;
  }
}
