import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_view_factory.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

enum _Host { folder, archive, compactArchive }

const _widths = [360.0, 680.0, 1280.0, 1697.0];
const _editorKey = ValueKey('workspace-inline-name-editor');
const _previewKey = ValueKey('folder-gallery-preview-stage');
const _choices = [
  GalleryCardSize.small,
  GalleryCardSize.medium,
  GalleryCardSize.large,
  GalleryCardSize.small,
  GalleryCardSize.large,
  GalleryCardSize.medium,
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_Storage());
    GalleryCardSizeStore.reset();
  });
  tearDown(() async {
    GalleryCardSizeStore.reset();
    await getIt.popScope();
  });

  for (final host in _Host.values) {
    for (final appearance in ['light', 'dark', 'paper']) {
      for (final width in _widths) {
        _test(
          '$host $appearance $width: notifier choices resize real cards stably',
          (tester, fixture, storage) async {
            final card = fixture.card(0);
            final element = tester.element(card);
            final state = tester.state(card);
            final renderer = _previewState(tester, card);
            final position = renderer.position;
            final preview = tester.widget<FolderGalleryCard>(card).preview;
            final key = tester.widget<FolderGalleryCard>(card).key;
            final sizes = <GalleryCardSize, Size>{};

            for (final size in _choices) {
              await GalleryCardSizeStore.write(size);
              await _frames(tester);
              _expectGeometry(tester, fixture, width, size);
              final actual = tester.getSize(card);
              if (sizes.containsKey(size)) expect(actual, sizes[size]);
              sizes[size] = actual;
              expect(tester.element(card), same(element));
              expect(tester.state(card), same(state));
              expect(_previewState(tester, card), same(renderer));
              expect(renderer.position, same(position));
              expect(
                tester.widget<FolderGalleryCard>(card).preview,
                same(preview),
              );
              expect(tester.widget<FolderGalleryCard>(card).key, key);
              expect(tester.widget<FolderGalleryCard>(card).selected, isTrue);
              expect(storage.values[kGalleryCardSizeKey], size.name);
              expect(fixture.loader.loads[fixture.views.first.id], 1);
              _expectSurface(tester, card, appearance);
              expect(tester.takeException(), isNull);
            }

            expect(
              sizes[GalleryCardSize.medium]!.width -
                  sizes[GalleryCardSize.small]!.width,
              greaterThan(24),
            );
            expect(
              sizes[GalleryCardSize.large]!.width -
                  sizes[GalleryCardSize.medium]!.width,
              greaterThan(24),
            );
            expect(fixture.repository.renames, isEmpty);
            expect(fixture.repository.moves, isEmpty);
            expect(fixture.opened, isEmpty);
          },
          host: host,
          appearance: appearance,
          width: width,
        );
      }
    }

    _test(
      '$host: sizing retains outer and preview scroll positions and selection',
      (tester, fixture, storage) async {
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(ValueKey(fixture.scrollKey)),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final outer = scrollable.position;
        final renderer = _previewState(tester, fixture.card(0));
        final inner = renderer.position;
        expect(outer.maxScrollExtent, greaterThan(80));
        expect(inner.maxScrollExtent, greaterThan(40));
        outer.jumpTo(80);
        inner.jumpTo(40);
        await tester.pump();
        final state = tester.state(fixture.card(0));
        final controller = fixture.controller;
        final cache = fixture.cache;
        final gallery = find.byType(
          host == _Host.folder ? FolderGallery : ArchiveGallery,
        );
        final galleryElement = tester.element(gallery);

        for (final size in _choices) {
          await GalleryCardSizeStore.write(size);
          await _frames(tester);
          expect(scrollable.position, same(outer));
          expect(outer.pixels, 80);
          expect(tester.state(fixture.card(0)), same(state));
          expect(_previewState(tester, fixture.card(0)), same(renderer));
          expect(renderer.position, same(inner));
          expect(inner.pixels, 40);
          expect(
            tester.widget<FolderGalleryCard>(fixture.card(0)).selected,
            isTrue,
          );
          expect(tester.element(gallery), same(galleryElement));
          if (host == _Host.folder) {
            final widget = tester.widget<FolderGallery>(gallery);
            expect(widget.controller, same(controller));
            expect(widget.previewCache, same(cache));
            expect(controller.selection.ids, [fixture.views.first.id]);
          } else {
            expect(
              tester.widget<ArchiveGallery>(gallery).previewCache,
              same(cache),
            );
          }
          expect(fixture.loader.loads[fixture.views.first.id], 1);
          expect(storage.values[kGalleryCardSizeKey], size.name);
        }
      },
      host: host,
      width: 1697,
    );

    _test(
      '$host: sizing and late preview completion retain a rename draft and caret',
      (tester, fixture, storage) async {
        final cardState = tester.state(fixture.card(0));
        final future =
            tester.widget<FolderGalleryCard>(fixture.card(0)).preview;
        fixture.beginRename();
        await _frames(tester);
        final editor = find.byKey(_editorKey);
        await tester.enterText(editor, 'Unsaved gallery notes.txt');
        final state = tester.state<EditableTextState>(editor);
        final input = tester.widget<EditableText>(editor);
        input.controller.selection =
            const TextSelection(baseOffset: 2, extentOffset: 9);
        final draft = input.controller.value;

        await GalleryCardSizeStore.write(GalleryCardSize.small);
        await _frames(tester);
        expect(tester.state<EditableTextState>(editor), same(state));
        fixture.loader.pending.complete(_longPreview);
        await _frames(tester);
        final renderer = _previewState(tester, fixture.card(0));
        for (final size in _choices) {
          await GalleryCardSizeStore.write(size);
          await _frames(tester);
          expect(tester.state(fixture.card(0)), same(cardState));
          expect(
            tester.widget<FolderGalleryCard>(fixture.card(0)).preview,
            same(future),
          );
          expect(_previewState(tester, fixture.card(0)), same(renderer));
          expect(tester.state<EditableTextState>(editor), same(state));
          expect(
            tester.widget<EditableText>(editor).controller,
            same(input.controller),
          );
          expect(
            tester.widget<EditableText>(editor).focusNode,
            same(input.focusNode),
          );
          expect(input.controller.value, draft);
          expect(input.focusNode.hasFocus, isTrue);
          expect(fixture.submittedNames, isEmpty);
          expect(storage.values[kGalleryCardSizeKey], size.name);
          expect(tester.takeException(), isNull);
        }
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _frames(tester);
        expect(fixture.submittedNames, ['Unsaved gallery notes.txt']);
      },
      host: host,
      pendingPreview: true,
    );

    _test(
      '$host: narrow reflow never rewrites the saved size or remounts the preview',
      (tester, fixture, storage) async {
        await GalleryCardSizeStore.write(GalleryCardSize.large);
        await _frames(tester);
        final state = tester.state(fixture.card(0));
        final renderer = _previewState(tester, fixture.card(0));
        final writes = storage.writes.length;
        for (final width in [..._widths.reversed, ..._widths]) {
          tester.view.physicalSize = Size(width, 800);
          await _frames(tester);
          _expectGeometry(tester, fixture, width, GalleryCardSize.large);
          expect(tester.state(fixture.card(0)), same(state));
          expect(_previewState(tester, fixture.card(0)), same(renderer));
          expect(GalleryCardSizeStore.value, GalleryCardSize.large);
          expect(storage.values[kGalleryCardSizeKey], 'large');
          expect(storage.writes.length, writes);
          expect(tester.takeException(), isNull);
        }
      },
      host: host,
      width: 1697,
    );

    _test(
      '$host: changing a personal size keeps read-only cards read-only but openable',
      (tester, fixture, storage) async {
        final semantics = tester.ensureSemantics();
        try {
          final cardState = tester.state(fixture.card(0));
          final preview =
              tester.widget<FolderGalleryCard>(fixture.card(0)).preview;
          final originalRecords = {
            for (final entry in fixture.repository.views.entries)
              entry.key: entry.value.writeToBuffer(),
          };
          for (final size in GalleryCardSize.values) {
            await GalleryCardSizeStore.write(size);
            await _frames(tester);
            _expectGeometry(tester, fixture, 680, size);
            final card = tester.widget<FolderGalleryCard>(fixture.card(0));
            expect(card.canRename, isFalse);
            expect(card.editing, isFalse);
            expect(tester.state(fixture.card(0)), same(cardState));
            expect(card.preview, same(preview));
            expect(fixture.loader.loads[fixture.views.first.id], 1);
            final title = find.descendant(
              of: fixture.card(0),
              matching: find.byType(WorkspaceInlineEditableText),
            );
            final label = tester.widget<WorkspaceInlineEditableText>(title);
            expect(label.text, fixture.views.first.name);
            expect(label.editing, isFalse);
            expect(label.onTap, isNotNull);
            expect(label.onDoubleTap, isNull);
            expect(title.hitTestable(), findsOneWidget);
            final titleAction = find.descendant(
              of: title,
              matching: find.byType(GestureDetector),
            );
            expect(titleAction, findsOneWidget);
            final data = tester.getSemantics(titleAction).getSemanticsData();
            expect(data.label, contains(fixture.views.first.name));
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
            expect(data.hasFlag(ui.SemanticsFlag.isTextField), isFalse);
            final before = List<String>.of(fixture.opened);
            final openedId = fixture.views.first.id;
            final point = tester.getCenter(title);
            await tester.tapAt(point, kind: PointerDeviceKind.mouse);
            await tester
                .pump(kDoubleTapMinTime + const Duration(milliseconds: 10));
            expect(fixture.opened, [...before, openedId]);
            await tester.tapAt(point, kind: PointerDeviceKind.mouse);
            await tester
                .pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
            await _frames(tester);
            expect(find.byKey(_editorKey), findsNothing);
            expect(fixture.renameRequests, isEmpty);
            expect(fixture.submittedNames, isEmpty);
            // Archive and folder cards share the same title: denying rename
            // removes the double-tap handler, not the ordinary Open action.
            expect(
              fixture.opened,
              [...before, openedId, openedId],
            );
            expect(
              find.byWidgetPredicate((widget) => widget is Draggable<ViewPB>),
              findsNothing,
            );
            await tester.tapAt(
              tester.getCenter(fixture.stage(0)),
              kind: PointerDeviceKind.mouse,
            );
            await _frames(tester);
            expect(fixture.opened, [...before, openedId, openedId, openedId]);
            expect(storage.values[kGalleryCardSizeKey], size.name);
            expect(fixture.controller.canWrite, isFalse);
            expect(fixture.controller.draft, isNull);
            expect(fixture.controller.editingId, isNull);
            expect(fixture.repository.renames, isEmpty);
            expect(fixture.repository.moves, isEmpty);
            expect(
              {
                for (final entry in fixture.repository.views.entries)
                  entry.key: entry.value.writeToBuffer(),
              },
              originalRecords,
            );
          }
          expect(
            fixture.opened,
            List.filled(
              GalleryCardSize.values.length * 3,
              fixture.views.first.id,
            ),
          );
          expect(fixture.repository.moves, isEmpty);
          expect(
            storage.writes.map((write) => write.$1),
            everyElement(kGalleryCardSizeKey),
            reason: 'Only the personal size preference may be written',
          );
        } finally {
          semantics.dispose();
        }
      },
      host: host,
      width: 680,
      readOnly: true,
    );

    _test(
      '$host: 360px RTL and 2x text keep every size and caption inside its card',
      (tester, fixture, storage) async {
        for (final size in GalleryCardSize.values) {
          await GalleryCardSizeStore.write(size);
          await _frames(tester);
          _expectGeometry(tester, fixture, 360, size, rtl: true);
          final card = tester.getRect(fixture.card(0));
          final title = tester.getRect(
            find.descendant(
              of: fixture.card(0),
              matching: find.byType(WorkspaceInlineEditableText),
            ),
          );
          expect(title.left, greaterThanOrEqualTo(card.left));
          expect(title.right, lessThanOrEqualTo(card.right));
          expect(title.bottom, lessThanOrEqualTo(card.bottom));
          expect(tester.getSize(fixture.stage(0)).height, greaterThan(0));
          expect(tester.takeException(), isNull);
        }
      },
      host: host,
      width: 360,
      appearance: 'paper',
      rtl: true,
      textScale: 2,
    );
  }

  _test(
    'a real folder drag survives notifier-driven column and size changes',
    (tester, fixture, storage) async {
      final draggableFinder = find.descendant(
        of: find.byKey(ValueKey('gallery-drag-${fixture.views.first.id}')),
        matching:
            find.byWidgetPredicate((widget) => widget is Draggable<ViewPB>),
      );
      final draggable = tester.widget<Draggable<ViewPB>>(draggableFinder);
      final dragState = tester.state(draggableFinder);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: tester.getCenter(fixture.stage(0)));
        await mouse.down(tester.getCenter(fixture.stage(0)));
        await tester.pump();
        await mouse.moveBy(const Offset(8, 0));
        await tester.pump();
        await mouse.moveBy(const Offset(24, 0));
        await tester.pump();
        expect(find.byWidget(draggable.feedback), findsOneWidget);
        final source = tester.state(fixture.card(0));

        for (final size in [GalleryCardSize.small, GalleryCardSize.large]) {
          await GalleryCardSizeStore.write(size);
          await _frames(tester);
          expect(tester.state(draggableFinder), same(dragState));
          expect(tester.state(fixture.card(0)), same(source));
          expect(find.byWidget(draggable.feedback), findsOneWidget);
          expect(fixture.repository.moves, isEmpty);
        }
        await mouse.moveTo(tester.getCenter(fixture.stage(1)));
        await tester.pump();
        await mouse.up();
        await _frames(tester);
        expect(fixture.repository.moves, [
          (fixture.views.first.id, fixture.views[1].id),
        ]);
        expect(
          fixture.controller.viewForId(fixture.views.first.id)!.parentViewId,
          fixture.views[1].id,
        );
        expect(fixture.opened, isEmpty);
        expect(fixture.card(0), findsNothing);
      } finally {
        await mouse.removePointer();
      }
    },
    width: 1697,
  );

  for (final host in [_Host.folder, _Host.compactArchive]) {
    _test(
      '$host: real size menu persists every choice, ticks it and restores on reopen',
      (tester, fixture, storage) async {
        for (final size in GalleryCardSize.values) {
          final current = GalleryCardSizeStore.value;
          await _openSizeMenu(tester, fixture);
          expect(
            tester.widget<AppMenuRow>(_menuRow(current.label)).selected,
            isTrue,
          );
          await tester.tap(_menuRow(size.label), kind: PointerDeviceKind.mouse);
          await _menuFrames(tester);
          expect(GalleryCardSizeStore.value, size);
          expect(storage.values[kGalleryCardSizeKey], size.name);
          _expectGeometry(tester, fixture, 680, size);
        }

        await _openSizeMenu(tester, fixture);
        expect(
          tester
              .widget<AppMenuRow>(_menuRow(GalleryCardSize.large.label))
              .selected,
          isTrue,
        );
        final writes = storage.writes.length;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _menuFrames(tester);
        expect(storage.writes.length, writes);

        await tester.pumpWidget(const SizedBox.shrink());
        GalleryCardSizeStore.reset();
        await GalleryCardSizeStore.ensureLoaded();
        await _mount(tester, fixture.build(), width: 680, appearance: 'paper');
        _expectGeometry(tester, fixture, 680, GalleryCardSize.large);
        await _openSizeMenu(tester, fixture);
        expect(
          tester
              .widget<AppMenuRow>(_menuRow(GalleryCardSize.large.label))
              .selected,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _menuFrames(tester);
        expect(fixture.submittedNames, isEmpty);
        expect(fixture.repository.moves, isEmpty);
      },
      host: host,
      settings: true,
      readOnly: true,
      width: 680,
      appearance: 'paper',
    );
  }

  _test(
    'archive size menu supports keyboard selection and reports a failed save',
    (tester, fixture, storage) async {
      await _openSizeMenu(tester, fixture);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _menuFrames(tester);
      expect(storage.values[kGalleryCardSizeKey], 'large');
      _expectGeometry(tester, fixture, 680, GalleryCardSize.large);

      final ack = Completer<void>();
      storage.writeGate = ack;
      await _openSizeMenu(tester, fixture);
      await tester.tap(_menuRow(GalleryCardSize.small.label));
      await _menuFrames(tester);
      _expectGeometry(tester, fixture, 680, GalleryCardSize.small);
      expect(storage.values[kGalleryCardSizeKey], 'large');
      ack.completeError(StateError('Preference write refused'));
      await _menuFrames(tester);
      _expectGeometry(tester, fixture, 680, GalleryCardSize.large);
      expect(GalleryCardSizeStore.value, GalleryCardSize.large);
      expect(
        find.text('Could not save card size. Please try again.'),
        findsOneWidget,
      );

      await _openSizeMenu(tester, fixture);
      expect(
        tester
            .widget<AppMenuRow>(_menuRow(GalleryCardSize.large.label))
            .selected,
        isTrue,
      );
      await tester.tap(_menuRow(GalleryCardSize.medium.label));
      await _menuFrames(tester);
      expect(storage.values[kGalleryCardSizeKey], 'medium');
      _expectGeometry(tester, fixture, 680, GalleryCardSize.medium);
    },
    host: _Host.compactArchive,
    settings: true,
    width: 680,
  );

  testWidgets(
    'one delayed preference ACK resizes a live folder and compact archive together',
    (tester) async {
      _configureView(tester, 1960);
      final folder = _Fixture(_Host.folder);
      final archive = _Fixture(_Host.compactArchive);
      final storage = getIt<KeyValueStorage>() as _Storage;
      try {
        await folder.initialize();
        await archive.initialize();
        await GalleryCardSizeStore.ensureLoaded();
        await _mount(
          tester,
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 1280, child: folder.build()),
              SizedBox(width: 680, child: archive.build()),
            ],
          ),
          width: 1960,
        );
        final folderState = tester.state(folder.card(0));
        final archiveState = tester.state(archive.card(0));
        for (final size in GalleryCardSize.values) {
          final ack = Completer<void>();
          storage.writeGate = ack;
          var completed = false;
          final saving = GalleryCardSizeStore.write(size).then((_) {
            completed = true;
          });
          await _frames(tester);
          expect(completed, isFalse);
          expect(
            tester.getSize(folder.card(0)).width,
            closeTo(size.targetWidth, 0.001),
          );
          expect(
            tester.getSize(archive.card(0)).width,
            closeTo(size.targetWidth * 0.74, 0.001),
          );
          expect(tester.state(folder.card(0)), same(folderState));
          expect(tester.state(archive.card(0)), same(archiveState));
          ack.complete();
          await saving;
          await _frames(tester);
          expect(storage.values[kGalleryCardSizeKey], size.name);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        folder.dispose();
        archive.dispose();
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

void _test(
  String name,
  Future<void> Function(WidgetTester, _Fixture, _Storage) body, {
  _Host host = _Host.folder,
  String appearance = 'light',
  double width = 1280,
  bool readOnly = false,
  bool pendingPreview = false,
  bool settings = false,
  bool rtl = false,
  double textScale = 1,
}) {
  testWidgets(
    name,
    (tester) async {
      _configureView(tester, width);
      final fixture = _Fixture(
        host,
        readOnly: readOnly,
        pendingPreview: pendingPreview,
        settings: settings,
      );
      try {
        await fixture.initialize();
        await GalleryCardSizeStore.ensureLoaded();
        await _mount(
          tester,
          fixture.build(),
          width: width,
          appearance: appearance,
          rtl: rtl,
          textScale: textScale,
        );
        await body(tester, fixture, getIt<KeyValueStorage>() as _Storage);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        await tester.pump();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

void _configureView(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  required double width,
  String appearance = 'light',
  bool rtl = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 800);
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    preferredFontFamily,
    builtInCodeFontFamily,
  );
  await tester.pumpWidget(
    WidgetTestApp(
      child: Theme(
        data: theme.copyWith(platform: TargetPlatform.windows),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Directionality(
              textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(FolderGalleryCard).evaluate().isNotEmpty) break;
  }
  await _frames(tester);
  expect(find.byType(FolderGalleryCard), findsWidgets);
  expect(tester.takeException(), isNull);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 161));
  await tester.pump();
}

Future<void> _menuFrames(WidgetTester tester) async {
  await _frames(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

ScrollableState _previewState(WidgetTester tester, Finder card) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.descendant(
          of: card,
          matching: find.byType(FolderGalleryRichTextPreview),
        ),
        matching: find.byType(Scrollable),
      ),
    );

void _expectGeometry(
  WidgetTester tester,
  _Fixture fixture,
  double paneWidth,
  GalleryCardSize size, {
  bool rtl = false,
}) {
  final padding = fixture.compact
      ? 18.0
      : KnowledgeGalleryLayout.horizontalPadding(paneWidth);
  final available = paneWidth - padding * 2;
  final spacing = fixture.compact ? 16.0 : KnowledgeGalleryLayout.cardSpacing;
  final target = size.targetWidth * (fixture.compact ? 0.74 : 1);
  final expectedWidth = math.min(available, target);
  final columns =
      math.max(1, ((available + spacing) / (target + spacing)).floor());
  final first = tester.getRect(fixture.card(0));
  final second = tester.getRect(fixture.card(1));
  final delegate = tester
      .widget<SliverGrid>(find.byType(SliverGrid))
      .gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  final textScale =
      MediaQuery.textScalerOf(tester.element(fixture.card(0))).scale(15) / 15;
  expect(first.width, closeTo(expectedWidth, 0.001));
  expect(second.width, closeTo(expectedWidth, 0.001));
  expect(
    first.height,
    closeTo(
      (expectedWidth * 1.18).clamp(208, 404) +
          (textScale - 1) * (WorkspaceTokens.space16 + WorkspaceTokens.space3),
      0.001,
    ),
  );
  expect(delegate.crossAxisCount, columns);
  expect(first.left, greaterThanOrEqualTo(padding - 0.001));
  expect(first.right, lessThanOrEqualTo(paneWidth - padding + 0.001));
  expect(rtl ? paneWidth - first.right : first.left, closeTo(padding, 0.001));
  if (columns > 1) {
    expect(second.top, closeTo(first.top, 0.001));
    expect(
      rtl ? first.left - second.right : second.left - first.right,
      closeTo(spacing, 0.001),
    );
  } else {
    expect(second.top - first.bottom, closeTo(spacing, 0.001));
  }
}

void _expectSurface(WidgetTester tester, Finder card, String appearance) {
  final surface =
      find.descendant(of: card, matching: find.byType(GalleryCardSurface));
  expect(surface, findsOneWidget);
  final context = tester.element(surface);
  final cardSurface = tester.widget<DecoratedBox>(
    find.descendant(
      of: surface,
      matching: find.byKey(const ValueKey('gallery-card-surface')),
    ),
  );
  final decoration = cardSurface.decoration as BoxDecoration;
  expect(cardSurface.position, DecorationPosition.background);
  expect(PaperTheme.isEnabled(context), appearance == 'paper');
  expect(decoration.color, GalleryCardPalette.of(context).surface);
  expect(
    decoration.borderRadius,
    BorderRadius.circular(WorkspaceTokens.cardRadius),
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
}

Finder _menuRow(String label) => find.byWidgetPredicate(
      (widget) => widget is AppMenuRow && widget.label == label,
    );

Future<void> _openSizeMenu(WidgetTester tester, _Fixture fixture) async {
  if (fixture.host == _Host.folder) {
    final bounds = tester.getRect(find.byType(FolderGallery));
    await tester.tapAt(
      bounds.topRight + const Offset(-4, 16),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await _menuFrames(tester);
    if (fixture.readOnly) {
      expect(
        tester
            .widget<AppMenuRow>(
              _menuRow(LocaleKeys.workspaceFolderExplorer_newFolder.tr()),
            )
            .enabled,
        isFalse,
      );
    }
    await tester.tap(_menuRow(GalleryCardSizeStore.value.label));
  } else {
    await tester.tap(find.byTooltip('Card size'));
  }
  await _menuFrames(tester);
  for (final size in GalleryCardSize.values) {
    expect(_menuRow(size.label), findsOneWidget);
    expect(tester.widget<AppMenuRow>(_menuRow(size.label)).enabled, isTrue);
  }
}

final _longPreview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: List.generate(
    40,
    (index) => FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.paragraph,
      runs: [
        FolderGalleryTextRun(
          text: 'Persisted preview line $index with readable content.',
        ),
      ],
    ),
  ),
  wordCount: 280,
  readingMinutes: 2,
  tags: const [],
  fileTypeLabel: 'TXT',
);

class _Fixture extends ChangeNotifier {
  _Fixture(
    this.host, {
    this.readOnly = false,
    bool pendingPreview = false,
    this.settings = false,
  }) {
    root = ViewPB(
      id: 'size-root-${host.name}',
      name: 'Gallery sizing',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    views = List.generate(60, (index) {
      final folder = index == 1 || (settings && host == _Host.folder);
      return ViewPB(
        id: 'size-${host.name}-$index',
        parentViewId: root.id,
        name: folder ? 'Folder $index' : 'Notes $index.txt',
        layout: ViewLayoutPB.Document,
        extra: (folder
                ? const WorkspaceItemMetadata.folder()
                : const WorkspaceItemMetadata.file(
                    contentKind: WorkspaceFileContentKind.binary,
                    size: 2048,
                  ))
            .mergeIntoExtra(''),
      );
    });
    entries = [
      for (final view in views)
        ArchiveEntryView(
          entry: ArchiveEntry(
            path: view.name,
            isDirectory: view.isWorkspaceFolder,
            size: 2048,
          ),
          view: view,
          item: WorkspaceExplorerItem.fromView(view),
        ),
    ];
    repository = _Repository([root, ...views]);
    controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => !readOnly,
    );
    loader = _PreviewLoader(
      firstId: views.first.id,
      pendingFirst: pendingPreview,
    );
    cache = FolderGalleryPreviewCache(loader: loader);
  }

  final _Host host;
  final bool readOnly;
  final bool settings;
  late final ViewPB root;
  late final List<ViewPB> views;
  late final List<ArchiveEntryView> entries;
  late final _Repository repository;
  late final WorkspaceExplorerController controller;
  late final _PreviewLoader loader;
  late final FolderGalleryPreviewCache cache;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final opened = <String>[];
  final renameRequests = <String>[];
  final archiveRenames = <String>[];
  String? selectedPath;
  String? renamingPath;

  bool get compact => host == _Host.compactArchive;
  String get scrollKey => host == _Host.folder
      ? 'folder-gallery-scroll-view'
      : 'archive-gallery-scroll-view';
  List<String> get submittedNames => host == _Host.folder
      ? repository.renames.map((entry) => entry.$2).toList()
      : archiveRenames;

  Finder card(int index) => find.byKey(
        ValueKey(
          host == _Host.folder
              ? 'gallery-card-${views[index].id}'
              : 'archive-card-${entries[index].entry.path}',
        ),
      );
  Finder stage(int index) =>
      find.descendant(of: card(index), matching: find.byKey(_previewKey));

  Future<void> initialize() async {
    await controller.initialize();
    controller.selection.selectOnly(views.first.id);
    selectedPath = entries.first.entry.path;
  }

  void beginRename() {
    if (host == _Host.folder) {
      controller.beginRename(views.first.id);
    } else {
      renamingPath = entries.first.entry.path;
      notifyListeners();
    }
  }

  Widget build() {
    if (host == _Host.folder) {
      if (settings) {
        // Exercise the actual folder background-menu wiring. Folders-only
        // fixtures let its own preview cache stay entirely backend-free.
        return FolderExplorer(
          rootView: root,
          controller: controller,
          showHeader: false,
          onOpen: (view) => opened.add(view.id),
        );
      }
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => FolderGallery(
          controller: controller,
          previewCache: cache,
          userProfile: null,
          onOpen: (view) => opened.add(view.id),
          onNavigate: (id) => unawaited(controller.navigateTo(id)),
          onContextMenu: (_, __) {},
          onRequestDelete: () => throw StateError('Unexpected deletion'),
          onRename: (id) {
            renameRequests.add(id);
            controller.beginRename(id);
          },
        ),
      );
    }
    return AnimatedBuilder(
      animation: this,
      builder: (context, _) => ArchiveGallery(
        entries: entries,
        previewCache: cache,
        compact: compact,
        selectedPath: selectedPath,
        renamingPath: renamingPath,
        editable: !readOnly,
        onSelect: (entry) {
          selectedPath = entry.entry.path;
          notifyListeners();
        },
        onOpen: (entry) => opened.add(entry.view.id),
        onRenameRequested: (entry) {
          renameRequests.add(entry.view.id);
          renamingPath = entry.entry.path;
          notifyListeners();
        },
        onRenameSubmitted: (entry, name) async {
          archiveRenames.add(name);
          renamingPath = null;
          notifyListeners();
          return true;
        },
        onRenameCancelled: () {
          renamingPath = null;
          notifyListeners();
        },
        onMore: (_, __) {},
        header: settings
            ? ArchiveGalleryHeader(
                title: 'Sizing.zip',
                breadcrumbs: const [''],
                rootLabel: 'Sizing.zip',
                subtitle: '60 files',
                searchController: search,
                searchFocusNode: searchFocus,
                searching: false,
                onSearchChanged: (_) {},
                onSearchDismissed: () {},
                onSearchRequested: () {},
                onNavigate: (_) {},
                editable: !readOnly,
                busy: false,
                onAddFiles: () => throw StateError('Unexpected archive write'),
                onNewFolder: () => throw StateError('Unexpected archive write'),
                onRefresh: () => throw StateError('Unexpected archive reload'),
                keepActionsVisible: true,
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    cache.clear();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }
}

class _PreviewLoader extends FolderGalleryPreviewLoader {
  _PreviewLoader({required this.firstId, required this.pendingFirst});

  final String firstId;
  final bool pendingFirst;
  final pending = Completer<FolderGalleryPreview>();
  final loads = <String, int>{};

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    loads.update(view.id, (value) => value + 1, ifAbsent: () => 1);
    if (pendingFirst && view.id == firstId) return pending.future;
    if (item.isFolder) {
      return FolderGalleryPreviewParser.withoutDocument(
        view: view,
        item: item,
      )!;
    }
    return _longPreview;
  }
}

class _Repository implements WorkspaceItemRepository {
  _Repository(List<ViewPB> entries)
      : views = {
          for (final view in entries)
            view.id: ViewPB.fromBuffer(view.writeToBuffer()),
        };

  final Map<String, ViewPB> views;
  final moves = <(String, String)>[];
  final renames = <(String, String)>[];

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async =>
      FlowyResult.success([
        for (final view in views.values)
          if (view.parentViewId == parentViewId)
            ViewPB.fromBuffer(view.writeToBuffer()),
      ]);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(
    String viewId,
  ) async {
    final result = <ViewPB>[];
    for (var view = views[viewId];
        view != null;
        view = views[view.parentViewId]) {
      result.insert(0, view);
    }
    return FlowyResult.success(result);
  }

  @override
  Future<FlowyResult<void, FlowyError>> move({
    required String viewId,
    required String parentViewId,
    String? previousViewId,
  }) async {
    moves.add((viewId, parentViewId));
    views[viewId]!.parentViewId = parentViewId;
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    renames.add((viewId, name));
    final view = views[viewId]!;
    view.name = name;
    return FlowyResult.success(view);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements KeyValueStorage {
  final values = <String, String>{kGalleryCardSizeKey: 'medium'};
  final writes = <(String, String)>[];
  Completer<void>? writeGate;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    writes.add((key, value));
    final gate = writeGate;
    writeGate = null;
    await gate?.future;
    values[key] = value;
  }

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}
