import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/table_views/gallery_stage.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _away = Offset(4, 4);
const _cardKey = ValueKey('workspace-gallery-card-under-test');
const _preview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.heading,
      runs: [FolderGalleryTextRun(text: 'Opening notes')],
      level: 2,
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.paragraph,
      runs: [FolderGalleryTextRun(text: 'Content leads; controls stay quiet.')],
    ),
  ],
  wordCount: 420,
  readingMinutes: 3,
  tags: ['design', 'research', 'reading', 'archive'],
  fileTypeLabel: 'PAGE',
);

const _row = TableRowCard(
  rowId: 'synthetic-workspace-gallery-row',
  title: 'A row worth reading',
  cover: TableCover(kind: TableCoverKind.colour, value: '#B8D8C4'),
  properties: [
    TableProperty(
      fieldId: 'status',
      name: 'Status',
      value: 'Ready',
      kind: TablePropertyKind.badge,
    ),
    TableProperty(
      fieldId: 'tags',
      name: 'Tags',
      value: 'Research, Draft',
      kind: TablePropertyKind.tags,
    ),
    TableProperty(
      fieldId: 'source',
      name: 'Source',
      value: 'Reading notes',
      kind: TablePropertyKind.text,
    ),
  ],
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final kind in ['folder', 'table']) {
      _test(
          '$appearance $kind: themed surface, inherited title and large preview',
          (tester) async {
        await _mount(tester, _card(kind), appearance: appearance);
        final surface = find.descendant(
          of: find.byKey(_cardKey),
          matching: find.byType(
            kind == 'folder' ? GalleryCardSurface : WorkspaceSurface,
          ),
        );
        expect(surface, findsOneWidget);
        final context = tester.element(surface);
        expect(PaperTheme.isEnabled(context), appearance == 'paper');
        final BoxDecoration decoration;
        if (kind == 'folder') {
          final palette = GalleryCardPalette.of(context);
          final sheet = tester.widget<DecoratedBox>(
            find.descendant(
              of: surface,
              matching: find.byKey(const ValueKey('gallery-card-surface')),
            ),
          );
          expect(sheet.position, DecorationPosition.background);
          decoration = sheet.decoration as BoxDecoration;
          expect(decoration.color, palette.surface);
          expect(decoration.boxShadow, palette.restingShadows);

          // The neutral hairline and selection ring paint above the sheet;
          // neither is a Container border that can inset the retained child.
          final edge = tester.widget<DecoratedBox>(
            find.descendant(
              of: surface,
              matching: find.byKey(const ValueKey('gallery-card-edge')),
            ),
          );
          expect(edge.position, DecorationPosition.foreground);
          final outline = edge.decoration as BoxDecoration;
          expect(outline.borderRadius, decoration.borderRadius);
          expect(outline.color, isNull);
          expect(
            outline.border,
            Border.all(color: palette.edge, width: galleryCardHairlineWidth),
          );
          final selection = tester.widget<DecoratedBox>(
            find.descendant(
              of: surface,
              matching: find.byKey(const ValueKey('folder-gallery-selection')),
            ),
          );
          expect(selection.position, DecorationPosition.foreground);
          final foreground = selection.decoration as BoxDecoration;
          expect(foreground.borderRadius, decoration.borderRadius);
          expect(foreground.color, isNull);
          expect(foreground.border, isNull);

          final footer = find.descendant(
            of: surface,
            matching: find.byType(GalleryCardFooter),
          );
          expect(footer, findsOneWidget);
          final footerPaint = tester.widget<DecoratedBox>(
            find
                .descendant(of: footer, matching: find.byType(DecoratedBox))
                .first,
          );
          expect(footerPaint.position, DecorationPosition.background);
          final footerDecoration = footerPaint.decoration as BoxDecoration;
          expect(footerDecoration.color, palette.footer);
          expect(footerDecoration.gradient, isNull);
          expect(
            footerDecoration.border,
            Border(
              top: BorderSide(
                color: palette.footerRule,
                width: galleryCardHairlineWidth,
              ),
            ),
          );
          if (appearance == 'paper') {
            expect(
              decoration.color,
              Color.lerp(
                PaperTheme.editorPreviewBackground,
                PaperTheme.controlBackground,
                0.75,
              ),
            );
          }
        } else {
          // Table row cards still use WorkspaceSurface, not gallery-only paint.
          expect(
            tester.widget<WorkspaceSurface>(surface).kind,
            WorkspaceSurfaceKind.card,
          );
          final palette = WorkspacePalette.of(context);
          final container = tester.widget<Container>(
            find
                .descendant(of: surface, matching: find.byType(Container))
                .first,
          );
          decoration = container.decoration! as BoxDecoration;
          expect(decoration.color, palette.surface);
          expect(decoration.boxShadow, palette.elevation());
          // The foreground stays mounted for State retention, but paints no
          // idle outline. Each card's selection/focus overlay is tested below.
          final foreground = container.foregroundDecoration! as BoxDecoration;
          expect(foreground.borderRadius, decoration.borderRadius);
          expect(foreground.color, isNull);
          final border = foreground.border! as Border;
          for (final side in [
            border.top,
            border.right,
            border.bottom,
            border.left,
          ]) {
            expect(side.color.a, 0);
          }
          if (appearance == 'paper') {
            expect(decoration.color, PaperTheme.editorPreviewBackground);
          }
        }
        expect(WorkspaceTokens.cardRadius, 20);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(WorkspaceTokens.cardRadius),
        );
        expect(decoration.gradient, isNull);
        expect(decoration.border, isNull);
        final title = tester.widget<Text>(_title(kind));
        expect(title.style!.fontFamily, 'Gallery inherited face');
        expect(title.style!.fontFamilyFallback, ['serif']);
        expect(title.style!.fontSize, 15);
        expect(
          title.style!.fontVariations,
          [const ui.FontVariation.weight(620)],
        );
        expect(
          tester.getSize(_previewFinder(kind)).height,
          greaterThan(tester.getSize(find.byKey(_cardKey)).height * 0.6),
        );
        expect(tester.takeException(), isNull);
      });

      _test(
          '$appearance $kind: hover, Tab, selection and native menu semantics',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final outside = FocusNode();
        final selected = ValueNotifier(false);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        var opens = 0;
        var menus = 0;
        final positions = <Offset>[];
        try {
          await mouse.addPointer(location: _away);
          await _mount(
            tester,
            ValueListenableBuilder<bool>(
              valueListenable: selected,
              builder: (_, value, __) => _card(
                kind,
                selected: value,
                onOpen: () => opens++,
                onMenu: (position) {
                  menus++;
                  positions.add(position);
                },
              ),
            ),
            appearance: appearance,
            outsideFocus: outside,
          );
          final cardElement = tester.element(find.byKey(_cardKey));
          final titleElement = tester.element(_title(kind));
          final renderer = _rendererState(tester, kind);
          final bounds = tester.getRect(_previewFinder(kind));
          final actionBounds = tester.getRect(_action(kind));
          // Pin each transition separately: a stable fixture root must not
          // hide a renderer remount caused by selection/focus decoration.
          void expectRetained(String transition) {
            expect(
              tester.element(find.byKey(_cardKey)),
              same(cardElement),
              reason: transition,
            );
            expect(
              tester.element(_title(kind)),
              same(titleElement),
              reason: transition,
            );
            expect(
              _rendererState(tester, kind),
              same(renderer),
              reason: transition,
            );
            expect(
              tester.getRect(_previewFinder(kind)),
              bounds,
              reason: transition,
            );
            expect(
              tester.getRect(_action(kind)),
              actionBounds,
              reason: transition,
            );
          }

          _expectReveal(tester, false);
          _expectSelectionPaint(tester, kind, false);
          expect(_action(kind).hitTestable(), findsNothing);
          expect(find.semantics.byLabel(_moreLabel), findsNothing);

          await mouse.moveTo(tester.getCenter(_previewFinder(kind)));
          await _settle(tester);
          _expectReveal(tester, true);
          expectRetained('hover enter');
          _expectSelectionPaint(tester, kind, false);
          final node = tester.getSemantics(_action(kind));
          expect(node.label, _moreLabel);
          expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          expect(actionBounds.width, greaterThanOrEqualTo(48));
          expect(actionBounds.height, greaterThanOrEqualTo(48));
          await tester.tap(_action(kind));
          await tester.pump();
          expect(menus, 1);
          expect(opens, 0);
          expectRetained('pointer menu activation');

          outside.requestFocus();
          await mouse.moveTo(_away);
          await _settle(tester);
          _expectReveal(tester, false);
          expectRetained('hover exit and blur');
          _expectSelectionPaint(tester, kind, false);
          expect(find.semantics.byLabel(_moreLabel), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _settle(tester);
          _expectReveal(tester, true);
          expectRetained('Tab to card');
          _expectSelectionPaint(tester, kind, true);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(opens, 1);
          expect(menus, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _settle(tester);
          expectRetained('Tab to overflow');
          _expectSelectionPaint(tester, kind, true);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(menus, 3);
          expect(opens, 1, reason: 'Menu activation must not open the card.');
          expectRetained('keyboard menu activation');
          expect(
            positions.every((point) => point.dx.isFinite && point.dy.isFinite),
            isTrue,
          );

          outside.requestFocus();
          await _settle(tester);
          expectRetained('keyboard blur');
          _expectSelectionPaint(tester, kind, false);
          selected.value = true;
          await _settle(tester);
          _expectReveal(tester, true);
          expectRetained('selection');
          _expectSelectionPaint(tester, kind, true);
          selected.value = false;
          await _settle(tester);
          _expectReveal(tester, false);
          expectRetained('deselection');
          _expectSelectionPaint(tester, kind, false);
          expect(_rendererState(tester, kind), same(renderer));
          expect(tester.getRect(_previewFinder(kind)), bounds);
          expect(tester.getRect(_action(kind)), actionBounds);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          outside.dispose();
          selected.dispose();
          semantics.dispose();
        }
      });

      _test(
          '$appearance $kind: reduced motion changes paint without moving content',
          (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _away);
          await _mount(
            tester,
            _card(kind),
            appearance: appearance,
            reduced: true,
          );
          final renderer = _rendererState(tester, kind);
          final bounds = tester.getRect(_previewFinder(kind));
          expect(tester.widget<AnimatedOpacity>(_fade).duration, Duration.zero);
          for (final visible in [true, false, true, false]) {
            await mouse.moveTo(visible ? bounds.center : _away);
            await tester.pump();
            await tester.pump();
            _expectReveal(tester, visible);
            expect(
              tester.renderObject<RenderAnimatedOpacity>(_fade).opacity.value,
              visible ? 1 : 0,
            );
            expect(_rendererState(tester, kind), same(renderer));
            expect(tester.getRect(_previewFinder(kind)), bounds);
          }
          expect(
            find.descendant(
              of: find.byKey(_cardKey),
              matching: find.byType(AnimatedScale),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });

      _test(
          '$appearance $kind: small cards, large text and DPR retain the title',
          (tester) async {
        for (final scale in [1.0, 2.0]) {
          for (final width in [168.0, 196.0, 336.0]) {
            final metrics = GalleryCardMetrics.resolve(
              available: width,
              size: GalleryCardSize.large,
              spacing: 18,
              maximumColumns: 1,
              textScale: scale,
            );
            for (final dpr in [1.0, 2.0]) {
              tester.view.devicePixelRatio = dpr;
              tester.view.physicalSize = const Size(1000, 800) * dpr;
              await _mount(
                tester,
                _card(kind, width: width, height: metrics.height),
                appearance: appearance,
                textScale: scale,
              );
              final cardBounds = tester.getRect(find.byKey(_cardKey));
              final titleBounds = tester.getRect(_title(kind));
              expect(cardBounds.width, width);
              expect(titleBounds.left, greaterThanOrEqualTo(cardBounds.left));
              expect(titleBounds.right, lessThanOrEqualTo(cardBounds.right));
              expect(titleBounds.bottom, lessThanOrEqualTo(cardBounds.bottom));
              expect(
                tester.getSize(_previewFinder(kind)).height,
                greaterThan(0),
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      });
    }
  }

  for (final kind in ['folder', 'table']) {
    _test('$kind: changing appearance retains the mounted preview and title',
        (tester) async {
      await _mount(tester, _card(kind));
      final state = _rendererState(tester, kind);
      final title = tester.element(_title(kind));
      for (final appearance in ['paper', 'dark', 'light', 'paper']) {
        await _mount(tester, _card(kind), appearance: appearance);
        expect(_rendererState(tester, kind), same(state));
        expect(tester.element(_title(kind)), same(title));
        expect(tester.takeException(), isNull);
      }
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      _test('$kind: $platform exposes native actions without hover',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await _mount(tester, _card(kind), platform: platform);
          _expectReveal(tester, true);
          expect(find.semantics.byLabel(_moreLabel), findsOne);
          expect(_action(kind).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      });
    }

    _test('$kind: assistive navigation exposes actions and skips their fade',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var menus = 0;
      try {
        await _mount(
          tester,
          _card(kind, onMenu: (_) => menus++),
          accessible: true,
        );
        _expectReveal(tester, true);
        expect(tester.widget<AnimatedOpacity>(_fade).duration, Duration.zero);
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          tester.getSemantics(_action(kind)).id,
          ui.SemanticsAction.tap,
        );
        await tester.pump();
        expect(menus, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });

    _test('$kind: a hidden overflow does not steal the first touch',
        (tester) async {
      var opens = 0;
      var menus = 0;
      await _mount(
        tester,
        _card(kind, onOpen: () => opens++, onMenu: (_) => menus++),
      );
      _expectReveal(tester, false);
      final contact = await tester.startGesture(
        tester.getCenter(_action(kind)),
      );
      await tester.pump();
      await contact.up();
      await _settle(tester);
      expect(opens, 1);
      expect(menus, 0);
      _expectReveal(tester, true);
      await contact.down(tester.getCenter(_action(kind)));
      await contact.up();
      await _settle(tester);
      expect(menus, 1);
      expect(opens, 1);
      await contact.removePointer();
      expect(tester.takeException(), isNull);
    });
  }

  _test(
      'folder: one metadata line preserves real size, date, path and all tags',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, _card('folder'));
      final meta = find.byKey(const ValueKey('folder-gallery-metadata'));
      expect(meta, findsOneWidget);
      final text = tester.widget<Text>(meta);
      expect(text.data, contains('2,048 B'));
      expect(
        text.data,
        contains(DateFormat.MMMd().format(DateTime(2026, 9, 20))),
      );
      for (final tag in _preview.tags) {
        expect(text.data, contains('#$tag'));
      }
      expect(find.text('Library / Research'), findsOneWidget);
      final details = tester.widgetList<Tooltip>(find.byType(Tooltip)).where(
            (tip) => tip.message?.contains('420') ?? false,
          );
      expect(details, hasLength(1));
      expect(details.single.message, contains('3'));
      expect(details.single.message, contains('#archive'));
      expect(
        find.semantics.byLabel(RegExp(RegExp.escape(details.single.message!))),
        findsOne,
      );

      await _mount(
        tester,
        _card('folder', view: _view(withMetadata: false)),
      );
      expect(tester.widget<Text>(meta).data, isNot(contains(' B')));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    }
  });

  _test('folder: focus and selection retain a nonzero preview scroll offset',
      (tester) async {
    final outside = FocusNode();
    final selected = ValueNotifier(false);
    final preview = SynchronousFuture(
      FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: List.generate(40, (_) => _preview.blocks.last),
        wordCount: 200,
        readingMinutes: 1,
        tags: const [],
        fileTypeLabel: 'PAGE',
      ),
    );
    try {
      await _mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: selected,
          builder: (_, value, __) => _card(
            'folder',
            selected: value,
            preview: preview,
          ),
        ),
        outsideFocus: outside,
      );
      final renderer = _rendererState(tester, 'folder') as ScrollableState;
      final position = renderer.position;
      expect(position.maxScrollExtent, greaterThan(40));
      position.jumpTo(40);
      await tester.pump();
      outside.requestFocus();
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
      expect(_rendererState(tester, 'folder'), same(renderer));
      expect(renderer.position, same(position));
      expect(position.pixels, 40);
      outside.requestFocus();
      await _settle(tester);
      for (final value in [true, false, true, false]) {
        selected.value = value;
        await _settle(tester);
        expect(_rendererState(tester, 'folder'), same(renderer));
        expect(renderer.position, same(position));
        expect(position.pixels, 40);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      outside.dispose();
      selected.dispose();
    }
  });

  _test(
      'folder: loading, hover and resize retain the real rename draft and caret',
      (tester) async {
    final preview = Completer<FolderGalleryPreview>();
    final width = ValueNotifier(196.0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    var submissions = 0;
    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (_, value, __) => _card(
            'folder',
            width: value,
            preview: preview.future,
            editing: true,
            onRenameSubmitted: (_) async {
              submissions++;
              return true;
            },
          ),
        ),
        reduced: true,
      );
      final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
      await tester.enterText(editor, 'Unsaved research draft.md');
      final state = tester.state<EditableTextState>(editor);
      final input = tester.widget<EditableText>(editor);
      input.controller.selection =
          const TextSelection(baseOffset: 2, extentOffset: 9);
      final value = input.controller.value;
      preview.complete(_preview);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FolderGalleryRichTextPreview), findsOneWidget);
      for (final nextWidth in [336.0, 168.0, 300.0]) {
        width.value = nextWidth;
        await tester.pump();
        await mouse.moveTo(tester.getCenter(_previewFinder('folder')));
        await tester.pump();
        await mouse.moveTo(_away);
        await tester.pump();
        expect(tester.state<EditableTextState>(editor), same(state));
        expect(
          tester.widget<EditableText>(editor).controller,
          same(input.controller),
        );
        expect(input.controller.value, value);
        expect(input.focusNode.hasFocus, isTrue);
        expect(submissions, 0);
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submissions, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      width.dispose();
    }
  });

  _test(
      'folder: preview opens immediately and title double-click still renames',
      (tester) async {
    var opens = 0;
    var renames = 0;
    await _mount(
      tester,
      _card('folder', onOpen: () => opens++, onRename: () => renames++),
    );
    await tester.tap(find.text('Opening notes'));
    expect(opens, 1);
    await tester.tap(_title('folder'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_title('folder'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
    expect(renames, 1);
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  _test('folder: saved cover and content choices remain distinct',
      (tester) async {
    final extra = ViewCoverCodec.mergeCover(
      '',
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#D9C7A4',
      ),
    );
    for (final mode in ViewPreviewMode.values) {
      final view = ViewPB(
        id: 'synthetic-card-mode',
        name: 'Research notes.md',
        layout: ViewLayoutPB.Document,
        extra: ViewPreviewModeCodec.merge(extra, mode),
      );
      await _mount(tester, _card('folder', view: view));
      expect(
        find.byType(ViewCoverImage),
        mode == ViewPreviewMode.cover ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(FolderGalleryRichTextPreview),
        mode == ViewPreviewMode.content ? findsOneWidget : findsNothing,
      );
      expect(_title('folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  _test('table: every saved face keeps its renderer and property policy',
      (tester) async {
    for (final face in GalleryCardFace.values) {
      await _mount(tester, _card('table', face: face));
      expect(_title('table'), findsOneWidget);
      expect(
        find.byType(RowPagePreview),
        face == GalleryCardFace.page || face == GalleryCardFace.content
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.byType(TableCoverView),
        face.showsCover ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(TablePropertyView),
        face == GalleryCardFace.page || face == GalleryCardFace.portrait
            ? findsNothing
            : findsWidgets,
      );
      if (face.showsCover) {
        expect(
          tester.widget<TableCoverView>(find.byType(TableCoverView)).cover,
          _row.cover,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  _test(
      'table: portrait without a cover has normal ink and no invented gradient',
      (tester) async {
    await _mount(
      tester,
      _card(
        'table',
        face: GalleryCardFace.portrait,
        row: const TableRowCard(
          rowId: 'uncovered',
          title: 'A row worth reading',
        ),
      ),
      appearance: 'paper',
      textScale: 2,
    );
    final context = tester.element(_title('table'));
    expect(
      tester.widget<Text>(_title('table')).style!.color,
      WorkspacePalette.of(context).primaryText,
    );
    expect(find.byType(TableCoverView), findsNothing);
    final decorations = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(_cardKey),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(
      decorations.where(
        (box) =>
            box.decoration is BoxDecoration &&
            (box.decoration as BoxDecoration).gradient != null,
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  _test(
      'table: scaled cover captions retain real dates and all property details',
      (tester) async {
    final modified = DateTime(2020, 4, 12, 9, 30);
    final row = TableRowCard(
      rowId: _row.rowId,
      title:
          'A much longer row title that remains readable at large text sizes',
      cover: _row.cover,
      properties: _row.properties,
      lastModified: modified,
    );
    for (final appearance in ['light', 'dark', 'paper']) {
      for (final scale in [1.0, 1.25, 1.75, 2.0, 2.5, 3.0]) {
        for (final width in [168.0, 196.0, 336.0]) {
          for (final face in [
            GalleryCardFace.cover,
            GalleryCardFace.content,
            GalleryCardFace.none,
          ]) {
            await _mount(
              tester,
              _card('table', width: width, row: row, face: face),
              textScale: scale,
              appearance: appearance,
            );
            final bounds = tester.getRect(find.byKey(_cardKey));
            expect(
              tester.getRect(_title('table')).bottom,
              lessThan(bounds.bottom),
            );
            expect(find.text('2020-04-12'), findsOneWidget);
            _expectCaptionFits(tester);
            final details =
                tester.widgetList<Tooltip>(find.byType(Tooltip)).where(
                      (tip) => tip.message?.contains('Status: Ready') ?? false,
                    );
            expect(details, hasLength(1));
            expect(details.single.message, contains('Tags: Research, Draft'));
            expect(details.single.message, contains('Source: Reading notes'));
            expect(
              details.single.message,
              contains(DateFormat.yMMMd().add_jm().format(modified)),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$appearance, $face, width $width, scale $scale',
            );
          }
        }
      }
    }
  });

  _test('table: nonlinear scaling measures the title icon and real date',
      (tester) async {
    const scaler = _CaptionTextScaler();
    final row = TableRowCard(
      rowId: _row.rowId,
      title: 'A long caption with a title icon and a real modification date',
      icon: '🔎',
      cover: _row.cover,
      properties: _row.properties,
      lastModified: DateTime(2020, 4, 12, 9, 30),
    );
    for (final direction in [ui.TextDirection.ltr, ui.TextDirection.rtl]) {
      for (final face in [
        GalleryCardFace.cover,
        GalleryCardFace.content,
        GalleryCardFace.none,
      ]) {
        await _mount(
          tester,
          Directionality(
            textDirection: direction,
            child: DefaultTextStyle.merge(
              textHeightBehavior: const ui.TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              child: _card('table', width: 168, row: row, face: face),
            ),
          ),
          textScaler: scaler,
          boldText: true,
          appearance: 'paper',
        );
        expect(find.text('🔎'), findsOneWidget);
        expect(
          MediaQuery.textScalerOf(tester.element(_title('table'))),
          same(scaler),
        );
        _expectCaptionFits(tester);
        expect(tester.takeException(), isNull);
      }
    }
  });

  _test(
      'table: an undersized host keeps its caption reachable without shrinking',
      (tester) async {
    final row = TableRowCard(
      rowId: _row.rowId,
      title: 'A long title in a deliberately short gallery host',
      cover: _row.cover,
      properties: _row.properties,
      lastModified: DateTime(2020, 4, 12, 9, 30),
    );
    var opens = 0;
    await _mount(
      tester,
      _card(
        'table',
        width: 168,
        height: 120,
        row: row,
        face: GalleryCardFace.cover,
        onOpen: () => opens++,
      ),
      textScale: 3,
      appearance: 'paper',
    );
    final bounds = tester.getRect(find.byKey(_cardKey));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('table-gallery-caption-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.getRect(_title('table')).top, greaterThan(bounds.top));
    expect(
      MediaQuery.textScalerOf(tester.element(_title('table'))).scale(15),
      45,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    final date = find.text('2020-04-12');
    expect(tester.getRect(date).top, greaterThanOrEqualTo(bounds.top));
    expect(tester.getRect(date).bottom, lessThan(bounds.bottom));
    expect(tester.takeException(), isNull);
    await tester.tap(date);
    expect(
      opens,
      1,
      reason: 'Caption scrolling must not replace card opening.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _test(
      'table: real menu keeps originating controls visible until cancellation',
      (tester) async {
    final outside = FocusNode();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    Future<void>? pending;
    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        Builder(
          builder: (context) => _card(
            'table',
            tableMenu: (_) {
              final result = showAppMenu<void>(
                context: context,
                globalPosition: const Offset(750, 620),
                entries: const [AppMenuItem(label: 'Inspect row')],
              );
              pending = result;
              return result;
            },
          ),
        ),
        outsideFocus: outside,
      );
      final renderer = _rendererState(tester, 'table');
      await mouse.moveTo(tester.getCenter(_previewFinder('table')));
      await _settle(tester);
      await tester.tap(_action('table'));
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.byType(AppMenuSurface)));
      await _settle(tester);
      _expectReveal(tester, true);
      expect(_rendererState(tester, 'table'), same(renderer));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await pending;
      outside.requestFocus();
      await mouse.moveTo(_away);
      await _settle(tester);
      _expectReveal(tester, false);
      expect(_rendererState(tester, 'table'), same(renderer));
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      outside.dispose();
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await body(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

String get _moreLabel => LocaleKeys.workspaceFolderExplorer_more.tr();

Finder _action(String kind) => find.byKey(ValueKey('$kind-gallery-more'));

Finder _title(String kind) => kind == 'folder'
    ? find.text('Research notes.md')
    : find.byKey(const ValueKey('table-gallery-title'));

Finder _previewFinder(String kind) => kind == 'folder'
    ? find.byKey(const ValueKey('folder-gallery-preview-stage'))
    : find.byType(RowPagePreview);

Finder get _fade => find
    .descendant(
      of: find.byType(PreviewToolbar),
      matching: find.byType(AnimatedOpacity),
    )
    .first;

Object _rendererState(WidgetTester tester, String kind) => kind == 'folder'
    ? tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(FolderGalleryRichTextPreview),
          matching: find.byType(Scrollable),
        ),
      )
    : tester.state(find.byType(RowPagePreview));

void _expectReveal(WidgetTester tester, bool visible) {
  expect(tester.widget<AnimatedOpacity>(_fade).opacity, visible ? 1 : 0);
  final ignore = find
      .descendant(
        of: find.byType(PreviewToolbar),
        matching: find.byType(IgnorePointer),
      )
      .first;
  expect(tester.widget<IgnorePointer>(ignore).ignoring, !visible);
}

void _expectSelectionPaint(WidgetTester tester, String kind, bool selected) {
  final ring = find.byKey(ValueKey('$kind-gallery-selection'));
  expect(ring, findsOneWidget);
  final decoration =
      tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
  expect(
    decoration.borderRadius,
    BorderRadius.circular(WorkspaceTokens.cardRadius),
  );
  expect(
    decoration.border,
    selected
        ? Border.all(
            color: WorkspacePalette.of(tester.element(ring)).focus,
            width: 1.5,
          )
        : isNull,
  );
}

void _expectCaptionFits(WidgetTester tester) {
  final bounds = tester.getRect(find.byKey(_cardKey));
  final title = tester.getRect(_title('table'));
  final date = tester.getRect(find.text('2020-04-12'));
  expect(title.bottom, lessThanOrEqualTo(date.top));
  expect(date.bottom, lessThanOrEqualTo(bounds.bottom));
  expect(date.height, greaterThan(0));
  final scrollable = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(const ValueKey('table-gallery-caption-scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  expect(scrollable.position.maxScrollExtent, 0);
  expect(
    find.ancestor(of: _title('table'), matching: find.byType(FittedBox)),
    findsNothing,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

ViewPB _view({bool withMetadata = true}) => ViewPB(
      id: 'synthetic-workspace-gallery-file',
      name: 'Research notes.md',
      layout: ViewLayoutPB.Document,
      extra: withMetadata
          ? WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.binary,
              size: 2048,
              modifiedAt: DateTime(2026, 9, 20),
            ).mergeIntoExtra('')
          : '',
    );

Widget _card(
  String kind, {
  double width = 300,
  double height = 360,
  bool selected = false,
  bool editing = false,
  ViewPB? view,
  Future<FolderGalleryPreview>? preview,
  GalleryCardFace face = GalleryCardFace.page,
  TableRowCard row = _row,
  VoidCallback? onOpen,
  VoidCallback? onRename,
  ValueChanged<Offset>? onMenu,
  Future<void> Function(Offset)? tableMenu,
  Future<bool> Function(String)? onRenameSubmitted,
}) {
  final file = view ?? _view();
  return SizedBox(
    width: width,
    height: height,
    child: kind == 'folder'
        ? FolderGalleryCard(
            key: _cardKey,
            item: WorkspaceExplorerItem.fromView(file),
            view: file,
            preview: preview ?? SynchronousFuture(_preview),
            userProfile: null,
            selected: selected,
            editing: editing,
            searchPath: 'Library / Research',
            onTap: onOpen ?? () {},
            onRename: onRename ?? () {},
            onRenameSubmitted: onRenameSubmitted ?? (_) async => true,
            onRenameCancelled: () {},
            onMore: onMenu ?? (_) {},
            onContextMenu: onMenu ?? (_) {},
          )
        : Builder(
            builder: (context) => TableGalleryCard(
              key: _cardKey,
              card: row,
              palette: tableViewPaletteOf(context),
              face: face,
              coverHeight: height * 0.6,
              showPlaceholder: true,
              quiet: false,
              selected: selected,
              onOpen: onOpen ?? () {},
              onContextMenu: tableMenu ??
                  (position) async {
                    onMenu?.call(position);
                  },
            ),
          ),
  );
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
  TargetPlatform platform = TargetPlatform.windows,
  bool reduced = false,
  bool accessible = false,
  double textScale = 1,
  TextScaler? textScaler,
  bool boldText = false,
  FocusNode? outsideFocus,
}) async {
  final base = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    preferredFontFamily,
    builtInCodeFontFamily,
  );
  final theme = base.copyWith(
    platform: platform,
    textTheme: base.textTheme.copyWith(
      bodyMedium: base.textTheme.bodyMedium!.copyWith(
        fontFamily: 'Gallery inherited face',
        fontFamilyFallback: const ['serif'],
      ),
    ),
  );
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              accessibleNavigation: accessible,
              textScaler: textScaler ?? TextScaler.linear(textScale),
              boldText: boldText,
            ),
            child: child!,
          ),
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
  await _settle(tester);
}

class _CaptionTextScaler extends TextScaler {
  const _CaptionTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 12 ? fontSize * 2.75 : 33 + (fontSize - 12) * 1.5;

  @override
  double get textScaleFactor => scale(14) / 14;
}
