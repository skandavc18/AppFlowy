import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_optical_size.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' as user;
import 'package:appflowy_editor/appflowy_editor.dart' hide UploadImageMenu;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _picture = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: 'n1',
);
const _color = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#D9C7A4',
);
const _previous = PageStyleCover(
  type: PageStyleCoverImageType.localImage,
  value: r'C:\covers\compact-old.png',
);
const _uploaded = PageStyleCover(
  type: PageStyleCoverImageType.localImage,
  value: r'C:\covers\compact-new.png',
);
const _away = Offset(-20, -20);
const _title = ValueKey('compact-title');
const _icon = ValueKey('compact-icon');
const _body = ValueKey('compact-content-start');
const _iconRow = ValueKey('workspace-page-icon-row');
const _surface = ValueKey('workspace-cover-action-surface');
const _inlineEditor = ValueKey('workspace-inline-name-editor');

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance: bare database identity has no hidden action row',
        (tester) async {
      _viewport(tester);
      final frame = _Frame()..appearance = appearance;
      final semantics = tester.ensureSemantics();
      var view = _view(cover: const PageStyleCover.none())
        ..layout = ViewLayoutPB.Calendar;
      try {
        await tester.pumpWidget(
          _app(
            frame,
            (_) => Column(
              children: [
                DatabasePageDecoration(
                  view: view,
                  userProfile: null,
                  horizontalPadding: 24,
                ),
                const SizedBox(key: _body, height: 20),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final header = tester.getRect(find.byType(WorkspacePageHeader));
        final icon = tester.getRect(
          find.byKey(const ValueKey('database-page-title-icon')),
        );
        final title = tester.getRect(
          find.byKey(const ValueKey('database-page-title')),
        );
        expect(icon.top - header.top, 20);
        expect(title.top - icon.bottom, 6);
        expect(header.bottom - title.bottom, 12);
        expect(tester.getTopLeft(find.byKey(_body)).dy, header.bottom);
        expect(header.height, lessThan(180));
        expect(find.byType(WorkspaceActionRow), findsNothing);
        expect(
          find.byKey(const ValueKey('workspace-page-actions')),
          findsNothing,
        );
        expect(find.byType(WorkspacePageCover), findsNothing);
        _inside(
          tester,
          find.byKey(const ValueKey('view-decoration-cover')),
          find.byKey(_iconRow),
        );
        final titleData = tester
            .getSemantics(find.byKey(const ValueKey('workspace-page-title')))
            .getSemanticsData();
        expect(titleData.hasFlag(ui.SemanticsFlag.isHeader), isTrue);
        expect(titleData.label, contains(view.name));

        // An old, unchosen automatic database cover remains suppressed. This
        // presentation change must not invent a hero or mark it chosen.
        view = ViewPB.fromBuffer(view.writeToBuffer())
          ..extra = ViewCoverCodec.mergeCover('', _picture);
        final saved = view.writeToBuffer();
        frame.rebuild();
        await tester.pumpAndSettle();
        expect(find.byType(WorkspacePageCover), findsNothing);
        expect(find.text('Add Cover'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('view-decoration-remove')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('view-decoration-download')),
          findsNothing,
        );
        expect(view.writeToBuffer(), saved);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeVividIconPicker(tester);
        frame.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '$appearance: header identity and image-local tools reveal without reflow',
        (tester) async {
      _viewport(tester);
      final decoded = await _decodeCover(tester);
      final frame = _Frame()..appearance = appearance;
      final semantics = tester.ensureSemantics();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await tester.pumpWidget(_app(frame, (_) => _header(frame)));
        await tester.pumpAndSettle();
        final header = tester.getRect(find.byType(WorkspacePageHeader));
        final cover = tester.getRect(find.byType(WorkspacePageCover));
        final icon = tester.getRect(find.byKey(_icon));
        final title = tester.getRect(find.byKey(_title));
        final body = tester.getRect(find.byKey(_body));
        final imageState = tester.state(find.byType(Image));
        final titleState = tester.state(find.byType(EditableText));
        final actionState = tester.state(find.byType(ViewDecorationActions));
        final change = find.byKey(const ValueKey('view-decoration-cover'));
        final changeIcon = find.byKey(const ValueKey('view-decoration-icon'));
        final remove = find.byKey(const ValueKey('view-decoration-remove'));
        final removeLabel = tester.widget<DecorationActionButton>(remove).label;
        final changeLabel = tester
            .widget<DecorationActionButton>(
              find.descendant(
                of: change,
                matching: find.byType(DecorationActionButton),
              ),
            )
            .label;
        final rawImage = await _awaitCoverFrame(tester);
        _expectCoverOf(rawImage, decoded.image);
        expect(cover.left - header.left, 8);
        expect(header.right - cover.right, 8);
        expect(cover.top - header.top, 8);
        expect(cover.height, 176);
        expect(icon.top - cover.bottom, -22);
        expect(icon.size, const Size.square(64));
        expect(title.top - icon.bottom, 6);
        expect(header.bottom - title.bottom, 12);
        expect(tester.getTopLeft(changeIcon).dx, icon.right + 8);
        expect(find.byType(WorkspaceActionRow), findsNothing);
        for (final action in [
          change,
          remove,
          find.byKey(const ValueKey('view-decoration-download')),
        ]) {
          _inside(tester, action, find.byType(WorkspacePageCover));
        }

        final context = tester.element(find.byKey(_surface));
        final palette = WorkspacePalette.of(context);
        final decoration = tester
            .widget<DecoratedBox>(find.byKey(_surface))
            .decoration as BoxDecoration;
        expect(
          decoration.color,
          palette.elevatedSurface.withValues(alpha: 0.96),
        );
        expect(PaperTheme.isEnabled(context), appearance == 'paper');
        // The nearly opaque floating surface remains distinct even over the
        // darkest/lightest possible pixels in the decoded photograph.
        for (final pixel in [Colors.black, Colors.white]) {
          final background = Color.alphaBlend(decoration.color!, pixel);
          final foreground =
              Color.alphaBlend(palette.secondaryText, background);
          final a = foreground.computeLuminance();
          final b = background.computeLuminance();
          expect(
            (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
            greaterThanOrEqualTo(3),
          );
        }
        expect(_fade(tester, change).opacity, 0);
        expect(_fade(tester, changeIcon).opacity, 0);
        expect(_button(change).hitTestable(), findsNothing);
        expect(find.semantics.byLabel(removeLabel), findsNothing);

        await mouse.moveTo(title.center);
        await tester.pumpAndSettle();
        expect(_fade(tester, change).opacity, 0);
        expect(_fade(tester, changeIcon).opacity, 1);
        await mouse.moveTo(icon.center);
        await tester.pumpAndSettle();
        expect(_fade(tester, changeIcon).opacity, 1);
        expect(_fade(tester, change).opacity, 0);

        await mouse.moveTo(cover.center);
        await tester.pump();
        expect(
          _fade(tester, change).duration,
          const Duration(milliseconds: 140),
        );
        await tester.pump(const Duration(milliseconds: 70));
        expect(_paintedOpacity(tester, change), inExclusiveRange(0, 1));
        expect(tester.getRect(find.byKey(_body)), body);
        await tester.pump(const Duration(milliseconds: 80));
        expect(_paintedOpacity(tester, change), 1);
        expect(_fade(tester, changeIcon).opacity, 1);
        expect(_button(change).hitTestable(), findsOneWidget);
        final data = tester.getSemantics(_button(change)).getSemanticsData();
        expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(data.label, changeLabel);
        expect(tester.state(find.byType(Image)), same(imageState));
        expect(tester.state(find.byType(EditableText)), same(titleState));
        expect(
          tester.state(find.byType(ViewDecorationActions)),
          same(actionState),
        );

        await mouse.moveTo(_away);
        await tester.pumpAndSettle();
        expect(_button(change).hitTestable(), findsNothing);
        expect(find.semantics.byLabel(changeLabel), findsNothing);
        // Hidden buttons remain in native traversal. The overlapping header
        // icon can precede image-local tools in reading order, so reach the
        // cover button rather than assuming it is the first Tab stop.
        final changeFocus = Focus.of(
          tester.element(
            find.descendant(of: change, matching: find.text(changeLabel)),
          ),
        );
        final toolbarFocus = Focus.of(tester.element(find.byKey(_surface)));
        for (var i = 0; i < 20 && !changeFocus.hasPrimaryFocus; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(changeFocus.hasPrimaryFocus, isTrue);
        expect(_fade(tester, change).opacity, 1);
        expect(
          tester
              .getSemantics(_button(change))
              .getSemanticsData()
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(UploadImageMenu), findsOneWidget);
        // The pointer is still away and focus belongs to the popup. Neither
        // hover nor retained toolbar focus may conceal a broken popup hold.
        expect(
          Focus.of(tester.element(find.byType(UploadImageMenu))).hasFocus,
          isTrue,
        );
        expect(toolbarFocus.hasFocus, isFalse);
        expect(_fade(tester, change).opacity, 1);
        tester.widget<AppFlowyPopover>(change).controller!.close();
        await tester.pumpAndSettle();
        frame.outside.requestFocus();
        await tester.pumpAndSettle();
        expect(_fade(tester, change).opacity, 0);
        await tester.tapAt(cover.center);
        await tester.pumpAndSettle();
        expect(_fade(tester, change).opacity, 1);
        expect(frame.backend.saves, isEmpty);

        frame
          ..editable = false
          ..accessible = true
          ..reducedMotion = true
          ..width = 320
          ..scale = 2
          ..direction = ui.TextDirection.rtl
          ..rebuild();
        await tester.pumpAndSettle();
        final download = find.byKey(const ValueKey('view-decoration-download'));
        expect(change, findsNothing);
        expect(changeIcon, findsNothing);
        expect(remove, findsNothing);
        expect(_fade(tester, download).opacity, 1);
        expect(_fade(tester, download).duration, Duration.zero);
        expect(_button(download).hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(_button(download)).getSemanticsData().label,
          tester.widget<DecorationActionButton>(download).label,
        );
        expect(
          tester
              .getSemantics(_button(download))
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        _inside(tester, download, find.byType(WorkspacePageCover));
        expect(tester.state(find.byType(Image)), same(imageState));
        expect(tester.state(find.byType(EditableText)), same(titleState));
        expect(
          tester.state(find.byType(ViewDecorationActions)),
          same(actionState),
        );
        expect(frame.updates, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        decoded.dispose();
        frame.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '$appearance: the 22px overlap has real upper/lower icon hit targets',
        (tester) async {
      _viewport(tester);
      final frame = _Frame()
        ..appearance = appearance
        ..view = _view(cover: _color);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await tester.pumpWidget(_app(frame, (_) => _header(frame)));
        await tester.pumpAndSettle();
        final iconPicker = find.ancestor(
          of: find.byKey(_icon),
          matching: find.byType(ViewIconPicker),
        );
        final iconState = tester.state(iconPicker);
        final owner = tester.state(find.byType(ViewDecorationActions));
        final titleState = tester.state(find.byType(EditableText));
        final image = tester.element(find.byType(ViewCoverImage));
        final change = find.byKey(const ValueKey('view-decoration-cover'));
        final iconTools =
            find.byKey(const ValueKey('view-decoration-icon-actions'));
        final iconAction = find.byKey(const ValueKey('view-decoration-icon'));
        for (final (width, scale, direction) in [
          (960.0, 1.0, ui.TextDirection.ltr),
          (960.0, 2.0, ui.TextDirection.rtl),
          (320.0, 2.0, ui.TextDirection.ltr),
          (320.0, 2.0, ui.TextDirection.rtl),
        ]) {
          frame
            ..width = width
            ..scale = scale
            ..direction = direction
            ..showLeading = width < 600
            ..rebuild();
          await tester.pumpAndSettle();
          final cover = tester.getRect(find.byType(WorkspacePageCover));
          final icon = tester.getRect(find.byKey(_icon));
          final body = tester.getRect(find.byKey(_body));
          expect(icon.size, const Size.square(64));
          expect(cover.bottom - icon.top, closeTo(22, .01));
          expect(icon.bottom - cover.bottom, closeTo(42, .01));
          _inside(tester, find.byKey(_icon), find.byType(WorkspacePageHeader));
          expect(
            tester.getTopLeft(iconTools).dy,
            greaterThanOrEqualTo(cover.bottom + 8),
          );
          expect(
            tester.getRect(iconTools).overlaps(tester.getRect(change)),
            isFalse,
          );
          // Both ends must really reach the native picker. A paint-only
          // translation can look right while losing the covered 22px to the
          // cover (or to the original, unshifted parent bounds).
          for (final y in [icon.top + 2, icon.bottom - 2]) {
            final point = Offset(icon.center.dx, y);
            await mouse.moveTo(point);
            await tester.pumpAndSettle();
            await tester.tapAt(point, kind: PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
            expect(find.byType(UploadImageMenu), findsNothing);
            await mouse.moveTo(_away);
            await tester.pumpAndSettle();
            expect(_fade(tester, iconAction).opacity, 1);
            tester
                .widget<AppFlowyPopover>(
                  find.descendant(
                    of: iconPicker,
                    matching: find.byType(AppFlowyPopover),
                  ),
                )
                .controller!
                .close();
            await tester.pumpAndSettle();
            frame.outside.requestFocus();
            await tester.pumpAndSettle();
            expect(_fade(tester, iconAction).opacity, 0);
          }
          await mouse.moveTo(cover.center);
          await tester.pumpAndSettle();
          expect(_button(change).hitTestable(), findsOneWidget);
          expect(_button(iconTools).hitTestable(), findsOneWidget);
          expect(tester.state(iconPicker), same(iconState));
          expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
          expect(tester.state(find.byType(EditableText)), same(titleState));
          expect(tester.element(find.byType(ViewCoverImage)), same(image));
          expect(tester.getRect(find.byKey(_body)), body);
          expect(tester.takeException(), isNull);
        }
        await tester.enterText(find.byKey(_title), 'Uncommitted title');
        frame.title.selection =
            const TextSelection(baseOffset: 2, extentOffset: 7);
        final draft = frame.title.value;
        for (final covered in [false, true, false, true]) {
          frame
            ..showCover = covered
            ..rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(iconPicker), same(iconState));
          expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
          expect(tester.state(find.byType(EditableText)), same(titleState));
          expect(frame.title.value, draft);
          expect(frame.titleFocus.hasFocus, isTrue);
        }
        frame
          ..showIcon = false
          ..rebuild();
        await tester.pumpAndSettle();
        final cover = tester.getRect(find.byType(WorkspacePageCover));
        expect(find.byKey(_icon), findsNothing);
        expect(tester.getTopLeft(iconTools).dy, closeTo(cover.bottom + 8, .01));
        expect(frame.title.value, draft);
        expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
        expect(frame.updates, isEmpty);
        expect(frame.backend.saves, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        frame.dispose();
      }
    });

    for (final host in ['folder', 'workspace']) {
      testWidgets(
          '$appearance: bare $host reveals only through header interaction',
          (tester) async {
        _viewport(tester);
        final frame = _Frame()..appearance = appearance;
        final root = _view(cover: const PageStyleCover.none())
          ..icon = EmojiIconData.none().toViewIcon();
        final saved = root.writeToBuffer();
        final controller = WorkspaceExplorerController(
          root: root,
          repository: _Repository(root),
          listenForUpdates: false,
        );
        final search = TextEditingController();
        var workspace = user.UserWorkspacePB(
          workspaceId: root.id,
          name: root.name,
          workspaceType: user.WorkspaceTypePB.LocalW,
        );
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _away);
        try {
          await controller.initialize();
          await tester.pumpWidget(
            _app(
              frame,
              (_) => Column(
                children: [
                  FolderGalleryHeader(
                    controller: controller,
                    searchController: search,
                    workspace: host == 'workspace' ? workspace : null,
                    onSearchChanged: (_) {},
                    onNavigate: (_) {},
                    onAddFile: (_) {},
                    onCreateCollection: (_) {},
                    onCreateDatabase: (_) {},
                    onMore: (_) {},
                  ),
                  TextButton(
                    focusNode: frame.outside,
                    onPressed: () {},
                    child: const Text('Outside header'),
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          final prefix = host == 'workspace' ? 'workspace' : 'view';
          final owner = host == 'workspace'
              ? find.byType(WorkspaceCoverActions)
              : find.byType(ViewDecorationActions);
          final ownerState = tester.state(owner);
          final icon = find.byKey(ValueKey('$prefix-decoration-icon'));
          final cover = find.byKey(ValueKey('$prefix-decoration-cover'));
          final header = tester.getRect(find.byType(WorkspacePageHeader));
          expect(find.byType(WorkspacePageCover), findsNothing);
          for (final action in [icon, cover]) {
            expect(_fade(tester, action).opacity, 0);
            expect(_button(action).hitTestable(), findsNothing);
          }
          expect(find.semantics.byLabel('Add Cover'), findsNothing);
          await mouse.moveTo(
            tester.getCenter(
              find.byKey(const ValueKey('folder-gallery-title')),
            ),
          );
          await tester.pumpAndSettle();
          for (final action in [icon, cover]) {
            expect(_fade(tester, action).opacity, 1);
            expect(_button(action).hitTestable(), findsOneWidget);
            final data =
                tester.getSemantics(_button(action)).getSemanticsData();
            expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          }
          expect(tester.getRect(find.byType(WorkspacePageHeader)), header);
          await mouse.moveTo(_away);
          await tester.pumpAndSettle();
          expect(_button(cover).hitTestable(), findsNothing);
          final focus = Focus.of(tester.element(find.text('Add Cover')));
          for (var i = 0; i < 20 && !focus.hasPrimaryFocus; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
          expect(focus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(find.byType(UploadImageMenu), findsOneWidget);
          expect(_fade(tester, cover).opacity, 1);
          final stale =
              tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
          if (host == 'workspace') {
            workspace =
                user.UserWorkspacePB.fromBuffer(workspace.writeToBuffer())
                  ..workspaceType = user.WorkspaceTypePB.ServerW
                  ..role = user.AFRolePB.Guest;
          } else {
            controller.updateRoot(ViewPB.fromBuffer(saved)..isLocked = true);
          }
          frame.rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(owner), same(ownerState));
          expect(find.byType(UploadImageMenu), findsNothing);
          expect(find.byType(DecorationActionButton), findsNothing);
          stale.onSelectedColor!('#123456');
          await tester.pumpAndSettle();
          expect(find.byType(WorkspacePageCover), findsNothing);
          expect(root.writeToBuffer(), saved);

          controller.updateRoot(root);
          workspace = user.UserWorkspacePB.fromBuffer(workspace.writeToBuffer())
            ..workspaceType = user.WorkspaceTypePB.LocalW;
          frame
            ..width = 320
            ..scale = 2
            ..accessible = true
            ..reducedMotion = true
            ..rebuild();
          frame.outside.requestFocus();
          await tester.pumpAndSettle();
          expect(tester.state(owner), same(ownerState));
          for (final action in [icon, cover]) {
            expect(_fade(tester, action).opacity, 1);
            expect(_fade(tester, action).duration, Duration.zero);
            expect(_button(action).hitTestable(), findsOneWidget);
          }
          expect(find.byType(WorkspacePageCover), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await disposeVividIconPicker(tester);
          controller.dispose();
          search.dispose();
          frame.dispose();
          semantics.dispose();
        }
      });
    }

    for (final host in ['folder', 'workspace', 'book', 'dashboard']) {
      testWidgets('$appearance: $host uses icon/image slots, not the page row',
          (tester) async {
        _viewport(tester);
        final frame = _Frame()..appearance = appearance;
        final root = _view(cover: _color);
        if (host == 'book') {
          root.extra = const CollectionMetadata(kind: CollectionKind.book)
              .mergeIntoExtra(root.extra);
        }
        final definition = CollectionRegistry.typeFor(CollectionKind.book);
        CollectionRegistry.register(
          definition.withViews([
            for (final mode in definition.views)
              CollectionViewDefinition(
                id: mode.id,
                labelKey: mode.labelKey,
                icon: mode.icon,
                isAvailable: mode.isAvailable,
                builder: (_, __) => ListView(children: const [Text('Content')]),
              ),
          ]),
        );
        final controller = WorkspaceExplorerController(
          root: root,
          repository: _Repository(root),
          listenForUpdates: false,
        );
        final search = TextEditingController();
        final dashboard = DashboardController(
          viewId: '',
          document: DashboardDocument.blank(),
        );
        try {
          await controller.initialize();
          await tester.pumpWidget(
            _app(
              frame,
              (_) => switch (host) {
                'book' => CollectionPage(
                    view: root,
                    controller: controller,
                    shellOwnsBreadcrumbs: true,
                  ),
                'dashboard' => DashboardPage(view: root, controller: dashboard),
                _ => FolderGalleryHeader(
                    controller: controller,
                    searchController: search,
                    workspace: host == 'workspace'
                        ? user.UserWorkspacePB(
                            workspaceId: root.id,
                            name: root.name,
                            icon: EmojiIconData.emoji('📚').toStorageString(),
                            workspaceType: user.WorkspaceTypePB.LocalW,
                            cover: WorkspaceCoverCodec.encode(_color),
                          )
                        : null,
                    onSearchChanged: (_) {},
                    onNavigate: (_) {},
                    onAddFile: (_) {},
                    onCreateCollection: (_) {},
                    onCreateDatabase: (_) {},
                    onMore: (_) {},
                  ),
              },
              scroll: host != 'book' && host != 'dashboard',
            ),
          );
          await tester.pumpAndSettle();
          final prefix = host == 'workspace' ? 'workspace' : 'view';
          final owner = host == 'workspace'
              ? find.byType(WorkspaceCoverActions)
              : find.byType(ViewDecorationActions);
          expect(owner, findsOneWidget);
          final state = tester.state(owner);
          for (final width in [960.0, 320.0]) {
            frame
              ..width = width
              ..scale = width == 320 ? 2 : 1
              ..direction =
                  width == 320 ? ui.TextDirection.rtl : ui.TextDirection.ltr
              ..rebuild();
            await tester.pumpAndSettle();
            expect(tester.state(owner), same(state));
            expect(find.byType(WorkspaceActionRow), findsOneWidget);
            final metadata =
                find.byKey(const ValueKey('workspace-page-metadata'));
            final description =
                find.byKey(const ValueKey('workspace-page-description'));
            final beforeActions = metadata.evaluate().isNotEmpty
                ? metadata
                : description.evaluate().isNotEmpty
                    ? description
                    : find.byKey(const ValueKey('workspace-page-title'));
            expect(
              tester.getTopLeft(find.byType(WorkspaceActionRow)).dy -
                  tester.getBottomLeft(beforeActions).dy,
              8,
            );
            expect(
              tester.getBottomLeft(find.byType(WorkspacePageHeader)).dy -
                  tester.getBottomLeft(find.byType(WorkspacePageIdentity)).dy,
              12,
            );
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('workspace-page-actions')),
                matching: find.byType(DecorationActionButton),
              ),
              findsNothing,
            );
            _inside(
              tester,
              find.byKey(ValueKey('$prefix-decoration-cover')),
              find.byType(WorkspacePageCover),
            );
            _inside(
              tester,
              find.byKey(ValueKey('$prefix-decoration-remove')),
              find.byType(WorkspacePageCover),
            );
            _inside(
              tester,
              find.byKey(ValueKey('$prefix-decoration-icon')),
              find.byKey(_iconRow),
            );
            expect(tester.takeException(), isNull);
          }
        } finally {
          await disposeVividIconPicker(tester);
          controller.dispose();
          dashboard.dispose();
          search.dispose();
          frame.dispose();
          CollectionRegistry.register(definition);
        }
      });
    }
  }

  testWidgets(
      'database draft and action owner survive cover/theme/access changes',
      (tester) async {
    _viewport(tester);
    final frame = _Frame()..view = _view(cover: const PageStyleCover.none());
    try {
      await tester.pumpWidget(
        _app(
          frame,
          (_) => DatabasePageDecoration(
            view: frame.view,
            userProfile: null,
            horizontalPadding: 24,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('database-page-title')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(_inlineEditor),
        'Unfinished calendar name',
      );
      final state = tester.state(find.byKey(_inlineEditor));
      final field = tester.widget<EditableText>(find.byKey(_inlineEditor));
      final actionState = tester.state(find.byType(ViewDecorationActions));
      const selection = TextSelection(baseOffset: 2, extentOffset: 7);
      field.controller.selection = selection;
      for (final appearance in vividIconTestAppearances) {
        for (final covered in [true, false]) {
          frame
            ..appearance = appearance
            ..width = covered ? 320 : 960
            ..view = (ViewPB.fromBuffer(frame.view.writeToBuffer())
              ..extra = AutomaticViewCover.markCoverChosenByHand(
                ViewCoverCodec.mergeCover(
                  frame.view.extra,
                  covered ? _color : const PageStyleCover.none(),
                ),
              ))
            ..rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(find.byKey(_inlineEditor)), same(state));
          expect(
            tester.state(find.byType(ViewDecorationActions)),
            same(actionState),
          );
          expect(field.controller.text, 'Unfinished calendar name');
          expect(field.controller.selection, selection);
          expect(field.focusNode.hasFocus, isTrue);
        }
      }
      frame.view = ViewPB.fromBuffer(frame.view.writeToBuffer())
        ..isLocked = true;
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byKey(_inlineEditor)), same(state));
      expect(field.controller.text, 'Unfinished calendar name');
      expect(field.focusNode.hasFocus, isFalse);
      expect(find.byType(DecorationActionButton), findsNothing);
      expect(find.byType(WorkspaceActionRow), findsNothing);
      frame.view = ViewPB.fromBuffer(frame.view.writeToBuffer())
        ..isLocked = false;
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byKey(_inlineEditor)), same(state));
      expect(field.controller.text, 'Unfinished calendar name');
      expect(frame.view.name, 'Compact page');
      field.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });

  testWidgets(
      'document cover slots retain renderer and title; read-only downloads',
      (tester) async {
    _viewport(tester);
    final decoded = await _decodeCover(tester);
    final frame = _Frame();
    final semantics = tester.ensureSemantics();
    final editor = EditorState.blank()..disableSealTimer = true;
    editor.document.root.updateAttributes({
      DocumentHeaderBlockKeys.coverType: CoverType.asset.toString(),
      DocumentHeaderBlockKeys.coverDetails: 'n1',
    });
    final saved = editor.document.toJson();
    final changes = <(CoverType, String?)>[];
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _away);
    try {
      await tester.pumpWidget(
        _app(
          frame,
          (_) => DocumentCover(
            view: ViewPB(id: 'compact-document'),
            node: editor.document.root,
            editorState: editor,
            coverType: CoverType.asset,
            coverDetails: 'n1',
            showCoverActions: frame.showCover,
            onChangeCover: (type, value) => changes.add((type, value)),
            layoutBuilder: (image, coverActions) => DocumentHeaderLayout(
              editorStyle: EditorStyle.desktop(maxWidth: 960),
              cover: frame.showCover ? image : null,
              coverActions:
                  coverActions.isEmpty ? null : Wrap(children: coverActions),
              icon: DocumentIcon(
                key: _icon,
                node: editor.document.root,
                editorState: editor,
                documentId: 'compact-document',
                icon: EmojiIconData.emoji('📚'),
                emojiSize: kTitleIconSize,
                opticalRole: IconOpticalRole.header,
                onChangeIcon: (_) {},
              ),
              iconActions: editor.editable
                  ? PreviewToolbar(
                      child: DocumentIcon(
                        key: const ValueKey('document-decoration-icon'),
                        node: editor.document.root,
                        editorState: editor,
                        documentId: 'compact-document',
                        icon: EmojiIconData.emoji('📚'),
                        onChangeIcon: (_) {},
                        child: const DecorationActionButton(
                          icon: FlowySvgs.add_icon_s,
                          label: 'Change Icon',
                        ),
                      ),
                    )
                  : null,
              title: TextField(
                key: _title,
                controller: frame.title,
                focusNode: frame.titleFocus,
                readOnly: !editor.editable,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(DocumentCover));
      final renderer = tester.state(find.byType(DesktopCover));
      final titleState = tester.state(find.byType(EditableText));
      final change = find.byKey(const ValueKey('document-decoration-cover'));
      final changeIcon = find.byKey(const ValueKey('document-decoration-icon'));
      final iconState = tester.state(changeIcon);
      _inside(tester, change, find.byType(WorkspacePageCover));
      expect(_button(changeIcon), findsOneWidget);
      expect(find.byType(WorkspaceActionRow), findsNothing);
      await tester.enterText(find.byKey(_title), 'Retained document draft');
      const selection = TextSelection(baseOffset: 2, extentOffset: 7);
      frame.title.selection = selection;
      expect(tester.takeException(), isNull);
      ui.Image? shown;
      for (final appearance in vividIconTestAppearances) {
        for (final direction in ui.TextDirection.values) {
          frame
            ..appearance = appearance
            ..direction = direction
            ..width = 320
            ..scale = 2
            ..rebuild();
          await tester.pumpAndSettle();
          await mouse.moveTo(tester.getCenter(find.byType(WorkspacePageCover)));
          await tester.pumpAndSettle();
          expect(_fade(tester, change).opacity, 1);
          _inside(tester, change, find.byType(WorkspacePageCover));
          _inside(tester, find.byKey(_icon), find.byKey(_iconRow));
          _inside(tester, changeIcon, find.byKey(_iconRow));
          _inside(
            tester,
            find.byKey(_iconRow),
            find.byKey(const ValueKey('document-page-identity')),
          );
          await mouse.moveTo(tester.getCenter(find.byKey(_icon)));
          await tester.pumpAndSettle();
          expect(_fade(tester, changeIcon).opacity, 1);
          expect(_button(changeIcon).hitTestable(), findsOneWidget);
          expect(tester.state(changeIcon), same(iconState));
          expect(tester.state(find.byType(DocumentCover)), same(state));
          expect(tester.state(find.byType(DesktopCover)), same(renderer));
          expect(tester.state(find.byType(EditableText)), same(titleState));
          expect(frame.title.selection, selection);
          // Hover, appearance and direction never reload the cover: the same
          // decoded frame stays on screen.
          final image = await _awaitCoverFrame(tester);
          shown ??= image;
          expect(image.isCloneOf(shown), isTrue);
          _expectCoverOf(image, decoded.image);
          expect(tester.takeException(), isNull);
        }
      }
      await mouse.moveTo(_away);
      await tester.pumpAndSettle();
      expect(_fade(tester, changeIcon).opacity, 0);
      // The last native action before the title stays in keyboard traversal,
      // including when it wraps below the icon and is hidden from the pointer.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(_fade(tester, changeIcon).opacity, 1);
      final iconData =
          tester.getSemantics(_button(changeIcon)).getSemanticsData();
      expect(iconData.hasFlag(ui.SemanticsFlag.isButton), isTrue);
      expect(iconData.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
      expect(iconData.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(
        iconData.label,
        tester
            .widget<Tooltip>(
              find.descendant(
                of: changeIcon,
                matching: find.byType(Tooltip),
              ),
            )
            .message,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
      tester
          .widget<AppFlowyPopover>(
            find.descendant(
              of: changeIcon,
              matching: find.byType(AppFlowyPopover),
            ),
          )
          .controller!
          .close();
      frame.titleFocus.requestFocus();
      await mouse.moveTo(tester.getCenter(find.byType(WorkspacePageCover)));
      await tester.pumpAndSettle();
      editor.editable = false;
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(change, findsNothing);
      final download =
          find.byKey(const ValueKey('document-decoration-download'));
      expect(_button(download).hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('document-decoration-remove-cover')),
        findsNothing,
      );
      expect(tester.state(find.byType(DesktopCover)), same(renderer));
      frame.showCover = false;
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePageCover), findsNothing);
      frame.showCover = true;
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(DocumentCover)), same(state));
      expect(tester.state(find.byType(EditableText)), same(titleState));
      expect(frame.title.text, 'Retained document draft');
      expect(editor.document.toJson(), saved);
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await disposeVividIconPicker(tester);
      decoded.dispose();
      editor.dispose();
      frame.dispose();
      semantics.dispose();
    }
  });

  for (final invalidation in ['none', 'lock', 'target', 'close', 'dispose']) {
    testWidgets(
        'pending icon save survives cover geometry; $invalidation guard',
        (tester) async {
      _viewport(tester);
      final completion = Completer<FlowyResult<void, FlowyError>>();
      final frame = _Frame()
        ..view = _view(cover: _color)
        ..iconSave = completion.future;
      try {
        await tester.pumpWidget(_app(frame, (_) => _header(frame)));
        await tester.pumpAndSettle();
        final iconPicker = find.ancestor(
          of: find.byKey(_icon),
          matching: find.byType(ViewIconPicker),
        );
        final iconState = tester.state(iconPicker);
        final owner = tester.state(find.byType(ViewDecorationActions));
        // The open icon picker adds its own search editor; retain this title,
        // not an arbitrary EditableText elsewhere in the overlay tree.
        final titleEditor = find.descendant(
          of: find.byKey(_title),
          matching: find.byType(EditableText),
        );
        expect(titleEditor, findsOneWidget);
        final titleState = tester.state(titleEditor);
        await tester.tap(find.byKey(_icon), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        final picker = tester.state(find.byType(FlowyIconEmojiPicker));
        final select = tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
            .onSelectedEmoji!;
        select(EmojiIconData.emoji('🌿').toSelectedResult(keepOpen: true));
        await tester.pump();
        expect(frame.iconWrites, hasLength(1));
        for (final covered in [false, true, false, true]) {
          frame
            ..width = covered ? 960 : 320
            ..scale = covered ? 1 : 2
            ..view = (ViewPB.fromBuffer(frame.view.writeToBuffer())
              ..name = 'Newer page name'
              ..extra = ViewCoverCodec.mergeCover(
                '{"retained":42}',
                covered ? _color : const PageStyleCover.none(),
              ))
            ..rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(iconPicker), same(iconState));
          expect(tester.state(find.byType(FlowyIconEmojiPicker)), same(picker));
          expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
          expect(titleEditor, findsOneWidget);
          expect(tester.state(titleEditor), same(titleState));
          expect(frame.updates, isEmpty);
        }
        select(EmojiIconData.emoji('📘').toSelectedResult());
        expect(frame.iconWrites, hasLength(1));
        if (invalidation == 'dispose') {
          await disposeVividIconPicker(tester);
        } else if (invalidation == 'close') {
          tester
              .widget<AppFlowyPopover>(
                find.descendant(
                  of: iconPicker,
                  matching: find.byType(AppFlowyPopover),
                ),
              )
              .controller!
              .close();
          await tester.pumpAndSettle();
        } else if (invalidation != 'none') {
          frame.view = ViewPB.fromBuffer(frame.view.writeToBuffer());
          if (invalidation == 'lock') {
            frame.view.isLocked = true;
          } else {
            frame.view.id = 'other-icon-target';
          }
          frame.rebuild();
          await tester.pumpAndSettle();
          expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        }
        completion.complete(FlowyResult.success(null));
        await tester.pumpAndSettle();
        if (invalidation == 'none') {
          expect(frame.updates, hasLength(1));
          expect(frame.updates.single.icon.value, '🌿');
          expect(frame.updates.single.name, 'Newer page name');
          expect(frame.updates.single.cover, _color);
          expect(
            ViewCoverCodec.decodeExtra(frame.updates.single.extra)['retained'],
            42,
          );
        } else {
          expect(frame.updates, isEmpty);
          select(EmojiIconData.emoji('📘').toSelectedResult());
          expect(frame.iconWrites, hasLength(1));
        }
        expect(frame.backend.saves, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (!completion.isCompleted) {
          completion.complete(FlowyResult.success(null));
        }
        await disposeVividIconPicker(tester);
        frame.dispose();
      }
    });
  }

  testWidgets(
      'presentation changes retain the picker and one in-flight request',
      (tester) async {
    _viewport(tester);
    final backend = _Backend(waitForUpload: true, waitForSave: true);
    final frame = _Frame(backend: backend)..view = _view(cover: _previous);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _away);
    try {
      await tester.pumpWidget(_app(frame, (_) => _header(frame)));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(ViewDecorationActions));
      final titleState = tester.state(find.byType(EditableText));
      await mouse.moveTo(tester.getCenter(find.byType(WorkspacePageCover)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('view-decoration-cover')));
      await tester.pumpAndSettle();
      final picker = tester.state(find.byType(UploadImageMenu));
      frame
        ..appearance = 'paper'
        ..width = 320
        ..scale = 2
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(UploadImageMenu)), same(picker));
      final menu = tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
      menu.onSelectedLocalImages([XFile(r'C:\picked\original.png')]);
      await tester.pumpAndSettle();
      expect(backend.uploads.map((view) => view.id), ['compact-page']);
      frame
        ..showCover = false
        ..appearance = 'dark'
        ..view = (ViewPB.fromBuffer(frame.view.writeToBuffer())
          ..name = 'Newer name'
          ..extra = ViewCoverCodec.mergeCover('{"retained":42}', _previous))
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ViewDecorationActions)), same(state));
      expect(tester.state(find.byType(EditableText)), same(titleState));
      menu.onSelectedColor!('#224466');
      backend.finishUpload();
      await tester.pumpAndSettle();
      expect(backend.saves, hasLength(1));
      expect(backend.saves.single.$1.id, 'compact-page');
      expect(
        ViewCoverCodec.decodeExtra(backend.saves.single.$1.extra)['retained'],
        42,
      );
      frame
        ..showCover = true
        ..width = 960
        ..rebuild();
      await tester.pumpAndSettle();
      backend.finishSave();
      await tester.pumpAndSettle();
      expect(find.byType(ViewDecorationActions), findsOneWidget);
      expect(tester.state(find.byType(ViewDecorationActions)), same(state));
      expect(frame.updates, hasLength(1));
      expect(frame.updates.single.name, 'Newer name');
      expect(frame.updates.single.cover, _uploaded);
      expect(backend.deleted, [_previous]);
      expect(tester.takeException(), isNull);
    } finally {
      backend.finishUpload();
      backend.finishSave();
      await mouse.removePointer();
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });

  for (final phase in ['upload', 'save']) {
    for (final invalidate in ['access', 'target']) {
      testWidgets(
          '$phase: $invalidate still invalidates compact cover callbacks',
          (tester) async {
        _viewport(tester);
        final backend = _Backend(
          waitForUpload: phase == 'upload',
          waitForSave: phase == 'save',
        );
        final frame = _Frame(backend: backend)..view = _view(cover: _previous);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _away);
        try {
          await tester.pumpWidget(_app(frame, (_) => _header(frame)));
          await tester.pumpAndSettle();
          final state = tester.state(find.byType(ViewDecorationActions));
          await mouse.moveTo(tester.getCenter(find.byType(WorkspacePageCover)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('view-decoration-cover')));
          await tester.pumpAndSettle();
          final menu =
              tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
          menu.onSelectedLocalImages([XFile(r'C:\picked\original.png')]);
          await tester.pumpAndSettle();
          if (invalidate == 'access') {
            frame.editable = false;
          } else {
            frame.view = ViewPB.fromBuffer(frame.view.writeToBuffer())
              ..id = 'B';
          }
          frame.rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(ViewDecorationActions)), same(state));
          menu.onSelectedColor!('#332211');
          backend.finishUpload();
          backend.finishSave();
          await tester.pumpAndSettle();
          expect(frame.updates, isEmpty);
          expect(
            backend.saves.map((save) => save.$1.id),
            phase == 'save' ? ['compact-page'] : isEmpty,
          );
          expect(backend.deleted, phase == 'upload' ? [_uploaded] : isEmpty);
          expect(backend.deleted, isNot(contains(_previous)));
          expect(tester.takeException(), isNull);
        } finally {
          backend.finishUpload();
          backend.finishSave();
          await mouse.removePointer();
          await disposeVividIconPicker(tester);
          frame.dispose();
        }
      });
    }
  }

  testWidgets(
      'empty standalone actions consume no height; custom cover height wins',
      (tester) async {
    _viewport(tester);
    final frame = _Frame();
    try {
      await tester.pumpWidget(
        _app(
          frame,
          (_) => Column(
            children: [
              ViewDecorationActions(
                view: _view(cover: const PageStyleCover.none()),
                showIconAction: false,
                showCoverAction: false,
              ),
              const WorkspacePageHeader(
                coverHeight: 244,
                cover: ColoredBox(color: Colors.red),
                identity: WorkspacePageIdentity(title: Text('Saved geometry')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ViewDecorationActions)).height, 0);
      expect(find.byType(WorkspaceActionRow), findsNothing);
      expect(tester.getSize(find.byType(WorkspacePageCover)).height, 244);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1400);
  addTearDown(tester.view.reset);
}

class _Frame extends ChangeNotifier {
  _Frame({_Backend? backend}) : backend = backend ?? _Backend();

  final _Backend backend;
  final title = TextEditingController(text: 'Compact page');
  final titleFocus = FocusNode();
  final outside = FocusNode();
  final updates = <ViewPB>[];
  final iconWrites = <EmojiIconData>[];
  Future<FlowyResult<void, FlowyError>>? iconSave;
  ViewPB view = _view();
  double width = 960;
  double scale = 1;
  String appearance = 'light';
  ui.TextDirection direction = ui.TextDirection.ltr;
  bool editable = true;
  bool showCover = true;
  bool showIcon = true;
  bool showLeading = false;
  bool accessible = false;
  bool reducedMotion = false;

  void rebuild() => notifyListeners();

  Future<FlowyResult<void, FlowyError>> writeIcon({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) {
    iconWrites.add(viewIcon);
    return iconSave ?? Future.value(FlowyResult.success(null));
  }

  @override
  void dispose() {
    title.dispose();
    titleFocus.dispose();
    outside.dispose();
    super.dispose();
  }
}

Widget _app(_Frame frame, WidgetBuilder builder, {bool scroll = true}) =>
    AnimatedBuilder(
      animation: frame,
      builder: (_, __) => vividIconTestApp(
        frame.appearance,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(frame.scale),
              accessibleNavigation: frame.accessible,
              disableAnimations: frame.reducedMotion,
            ),
            child: Directionality(
              textDirection: frame.direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: frame.width,
                  height: 1200,
                  child: scroll
                      ? SingleChildScrollView(child: Builder(builder: builder))
                      : Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Widget _header(_Frame frame) {
  final cover = frame.view.cover;
  final hasCover = frame.showCover && cover != null && !cover.isNone;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ViewDecorationActions(
        view: frame.view,
        coverBackend: frame.backend,
        visible: false,
        hasCover: hasCover,
        showIconAction: frame.editable,
        showCoverAction: frame.editable,
        showDownloadAction: true,
        onViewChanged: frame.updates.add,
        layoutBuilder: (iconActions, coverActions, pageActions) =>
            WorkspacePageHeader(
          contentInset: 24,
          leading: frame.showLeading
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('Existing page context'),
                )
              : null,
          cover: hasCover
              ? ViewCoverImage(cover: cover, width: double.infinity)
              : null,
          coverActions: coverActions,
          identity: WorkspacePageIdentity(
            icon: frame.showIcon
                ? ExcludeFocus(
                    excluding: !frame.editable,
                    child: IgnorePointer(
                      ignoring: !frame.editable,
                      child: ViewIconPicker(
                        view: frame.view,
                        onViewChanged: frame.updates.add,
                        updateIcon: frame.writeIcon,
                        child: const SizedBox.square(
                          key: _icon,
                          dimension: 64,
                          child: Icon(Icons.description_outlined),
                        ),
                      ),
                    ),
                  )
                : null,
            iconActions: iconActions,
            title: TextField(
              key: _title,
              controller: frame.title,
              focusNode: frame.titleFocus,
              readOnly: !frame.editable,
            ),
            actions: pageActions,
          ),
        ),
      ),
      const SizedBox(key: _body, height: 20),
      TextButton(
        focusNode: frame.outside,
        onPressed: () {},
        child: const Text('Outside header'),
      ),
    ],
  );
}

ViewPB _view({PageStyleCover cover = _picture}) => ViewPB(
      id: 'compact-page',
      name: 'Compact page',
      layout: ViewLayoutPB.Document,
      icon: EmojiIconData.emoji('📚').toViewIcon(),
      extra: ViewCoverCodec.mergeCover(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
        cover,
      ),
    );

Finder _button(Finder action) => find.descendant(
      of: action,
      matching: find.byType(TextButton),
    );

Finder _fadeFinder(Finder action) =>
    find.ancestor(of: action, matching: find.byType(AnimatedOpacity)).first;

AnimatedOpacity _fade(WidgetTester tester, Finder action) =>
    tester.widget<AnimatedOpacity>(_fadeFinder(action));

double _paintedOpacity(WidgetTester tester, Finder action) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: _fadeFinder(action),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void _inside(WidgetTester tester, Finder child, Finder parent) {
  final inner = tester.getRect(child);
  final outer = tester.getRect(parent);
  expect(inner.left, greaterThanOrEqualTo(outer.left - .01));
  expect(inner.right, lessThanOrEqualTo(outer.right + .01));
  expect(inner.top, greaterThanOrEqualTo(outer.top - .01));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .01));
}

// Resolve the real asset BEFORE Image mounts, so decoding never starts under
// a fake clock or gets replaced with a placeholder merely to test the toolbar.
Future<ImageInfo> _decodeCover(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final provider = AssetImage(
        PageStyleCoverImageType.builtInImagePath(_picture.value),
      );
      final stream = provider.resolve(ImageConfiguration.empty);
      final completion = Completer<ImageInfo>();
      final listener = ImageStreamListener(
        (info, _) => completion.complete(info),
        onError: completion.completeError,
      );
      try {
        stream.addListener(listener);
        return await completion.future.timeout(const Duration(seconds: 10));
      } finally {
        stream.removeListener(listener);
      }
    }))!;

/// The cover's first decoded frame, once it is on screen.
///
/// A cover is decoded at its laid-out size through a resizing provider, so it
/// cannot be warmed before layout; the engine's decode needs real time. Turns
/// alternate a bounded real-time wait with a frame, never an await of a
/// fake-clock future.
Future<ui.Image> _awaitCoverFrame(WidgetTester tester) async {
  for (var turn = 0; turn < 200; turn++) {
    final raw = find.byType(RawImage);
    if (raw.evaluate().length == 1) {
      final image = tester.widget<RawImage>(raw).image;
      if (image != null) return image;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('The cover never showed a decoded frame.');
}

/// [shown] is [source] decoded for its box: never larger, same proportions.
void _expectCoverOf(ui.Image shown, ui.Image source) {
  expect(shown.width, lessThanOrEqualTo(source.width));
  expect(shown.height, lessThanOrEqualTo(source.height));
  expect(
    shown.width / shown.height,
    closeTo(source.width / source.height, 0.02),
  );
}

class _Backend extends ViewCoverActionsBackend {
  _Backend({this.waitForUpload = false, this.waitForSave = false});

  final bool waitForUpload;
  final bool waitForSave;
  final uploads = <ViewPB>[];
  final saves = <(ViewPB, PageStyleCover)>[];
  final deleted = <PageStyleCover>[];
  final uploadGate = Completer<ViewCoverUpload>();
  final saveGate = Completer<FlowyResult<void, FlowyError>>();

  @override
  Future<FlowyResult<user.UserProfilePB, FlowyError>> currentUser() async =>
      FlowyResult.success(user.UserProfilePB());

  @override
  Future<ViewCoverUpload?> upload({
    required String path,
    required ViewPB view,
    required user.UserProfilePB profile,
  }) async {
    uploads.add(view);
    return waitForUpload
        ? await uploadGate.future
        : const ViewCoverUpload(cover: _uploaded, newlyCreated: true);
  }

  @override
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) async {
    saves.add((view, cover));
    return waitForSave ? await saveGate.future : FlowyResult.success(null);
  }

  @override
  Future<void> delete(PageStyleCover cover) async => deleted.add(cover);

  void finishUpload() {
    if (!uploadGate.isCompleted) {
      uploadGate.complete(
        const ViewCoverUpload(cover: _uploaded, newlyCreated: true),
      );
    }
  }

  void finishSave() {
    if (!saveGate.isCompleted) saveGate.complete(FlowyResult.success(null));
  }
}

class _Repository implements WorkspaceItemRepository {
  _Repository(this.root);
  final ViewPB root;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async =>
      FlowyResult.success([]);

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) async =>
      FlowyResult.success(root);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success([root]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
