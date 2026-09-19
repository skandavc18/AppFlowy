import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/image_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/layouts/image_grid_layout.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/layouts/multi_image_layouts.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _copyKey = ValueKey('media-copy');
const _shareKey = ValueKey('media-share');
const _copiedKey = ValueKey('media-copied');
const _captureKey = ValueKey('grid-action-capture');
const _fade = Duration(milliseconds: 140);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late List<File> photos;
  late List<ImageBlockData> images;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    temporary = await Directory.systemTemp.createTemp('multi_image_grid_');
    photos = [
      for (var index = 0; index < 8; index++)
        await File(
          '${temporary.path}${Platform.pathSeparator}photo $index #%.png',
        ).writeAsBytes(await _png(index.isEven)),
    ];
    images = [
      for (final photo in photos)
        ImageBlockData(url: photo.path, type: CustomImageType.local),
    ];
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = ['light', 'dark', 'paper']
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await temporary.delete(recursive: true);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$mode/$scale: photos reveal and act independently',
          (tester) async {
        final fixture = _Fixture(images.take(2).toList(), withHeader: true);
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(tester, fixture, photos, mode: mode, scale: scale);
          expect(find.byType(ImageGridLayout), findsOneWidget);
          expect(find.byType(MediaActionButtons), findsNWidgets(2));
          expect(
            find.descendant(
              of: find.byType(MultiImageMenu),
              matching: find.byType(MediaActionButtons),
            ),
            findsNothing,
            reason: 'The browser toolbar must not duplicate grid actions',
          );
          final first = _bar(images[0]);
          final second = _bar(images[1]);
          final firstState = tester.state(first);
          final firstPhoto = tester.getRect(_photo(images[0]));
          final secondPhoto = tester.getRect(_photo(images[1]));
          final documentBefore = fixture.snapshot;
          expect(_reveal(tester, first).opacity, 0);
          expect(_reveal(tester, second).opacity, 0);
          expect(_control(first, _copyKey).hitTestable(), findsNothing);
          expect(fixture.actions.calls, isEmpty);
          for (final raw
              in tester.widgetList<RawImage>(find.byType(RawImage))) {
            expect(raw.image, isNotNull);
          }

          await mouse.moveTo(firstPhoto.center);
          await _motion(tester);
          expect(_reveal(tester, first).opacity, 1);
          expect(_reveal(tester, second).opacity, 0);
          expect(_control(first, _copyKey).hitTestable(), findsOneWidget);
          expect(_control(second, _copyKey).hitTestable(), findsNothing);
          final buttons = tester.widget<MediaActionButtons>(first);
          expect(buttons.actions, same(fixture.actions));
          expect(buttons.decorated, isTrue);
          expect(buttons.buttonSize, 24);
          expect(tester.getSize(first), const Size(60, 32));
          expect(
            tester.getSize(_control(first, _copyKey)),
            const Size.square(24),
          );
          final surface = tester
              .widget<DecoratedBox>(
                _control(first, const ValueKey('media-action-surface')),
              )
              .decoration as BoxDecoration;
          expect(surface.border, isNull);
          expect(
            surface.color,
            PremiumThemeExtension.of(tester.element(first)).floatingSurface,
          );
          if (mode == 'paper') {
            expect(surface.color, PaperTheme.popupBackground);
          }
          expect(
            fixture.actions.calls,
            isEmpty,
            reason: 'Hover performs no IO',
          );

          final before = await _capture(tester);
          await _click(tester, mouse, _control(first, _copyKey));
          final copied = fixture.actions.calls.single;
          expect(copied.kind, 'copy');
          expect(copied.source.source, images[0].url);
          expect(copied.source.name, 'photo 0 #%.png');
          expect(copied.source.isImage, isTrue);
          expect(copied.source.shareAsLink, isFalse);
          expect(copied.source.httpHeaders, isEmpty);
          expect(copied.source.requireAuthentication, isFalse);
          expect(_control(first, _copiedKey), findsNothing);
          expect(_button(tester, first, _copyKey).onPressed, isNull);

          FocusManager.instance.primaryFocus?.unfocus();
          await mouse.moveTo(secondPhoto.center);
          await _motion(tester);
          expect(_reveal(tester, first).opacity, 0);
          expect(_reveal(tester, second).opacity, 1);
          expect(tester.state(first), same(firstState));
          final header = tester.getRect(find.byType(MultiImageMenu));
          expect(header.overlaps(tester.getRect(second)), isFalse);
          await _click(tester, mouse, _control(second, _shareKey));
          final shared = fixture.actions.calls.last;
          expect(shared.kind, 'share');
          expect(shared.source.source, images[1].url);
          expect(
            shared.origin,
            _globalRect(tester, _control(second, _shareKey)),
          );
          expect(shared.origin!.isEmpty, isFalse);

          copied.succeed();
          shared.succeed();
          await _motion(tester);
          expect(_control(first, _copiedKey), findsOneWidget);
          expect(_control(second, _copiedKey), findsNothing);
          FocusManager.instance.primaryFocus?.unfocus();
          await mouse.moveTo(firstPhoto.center);
          await _motion(tester);
          final badge = tester.getRect(_control(first, _copiedKey));
          expect(badge.top, greaterThanOrEqualTo(firstPhoto.top));
          expect(badge.bottom, lessThan(tester.getRect(first).top));
          expect(badge.right, lessThanOrEqualTo(firstPhoto.right));
          expect(firstPhoto.contains(badge.center), isTrue);
          final after = await _capture(tester);
          expect(
            _changedPixels(
              before,
              after,
              badge.shift(-tester.getTopLeft(find.byKey(_captureKey))),
            ),
            greaterThan(4),
            reason:
                'Copied must actually paint, not merely exist behind a clip',
          );
          expect(tester.getRect(_photo(images[0])), firstPhoto);
          expect(tester.getRect(_photo(images[1])), secondPhoto);
          expect(
            fixture.index.value,
            1,
            reason: 'Browser selection is not a tile target',
          );
          expect(fixture.indexChanges, isEmpty);
          expect(fixture.navigation.pushes, isEmpty);
          expect(find.byType(InteractiveImageViewer), findsNothing);
          expect(fixture.snapshot, documentBefore);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      });
    }
  }

  testWidgets(
      'same-length replacement rejects old completion and stale presses',
      (tester) async {
    final fixture = _Fixture(images.take(2).toList());
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture, photos);
      await mouse.moveTo(tester.getCenter(_photo(images[0])));
      await _motion(tester);
      final stalePress = _button(tester, _bar(images[0]), _shareKey).onPressed!;
      await _click(tester, mouse, _control(_bar(images[0]), _copyKey));
      final pending = fixture.actions.calls.single;
      fixture.replaceImages([images[2], images[1]]);
      await _motion(tester);
      expect(_photos(images[0]), findsNothing);
      expect(_bars(images[0]), findsNothing);
      expect(_photo(images[2]), findsOneWidget);
      stalePress();
      expect(fixture.actions.calls, hasLength(1));
      pending.succeed();
      await _motion(tester);
      expect(find.byKey(_copiedKey), findsNothing);
      await mouse.moveTo(tester.getCenter(_photo(images[2])));
      await _motion(tester);
      await _click(tester, mouse, _control(_bar(images[2]), _shareKey));
      expect(fixture.actions.calls.last.source.source, images[2].url);
      fixture.actions.calls.last.succeed();
      await _motion(tester);
      expect(fixture.navigation.pushes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  testWidgets('a last-row pending copy follows its photo across a grid reorder',
      (tester) async {
    final fixture = _Fixture(images, width: 360);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture, photos);
      final target = _bar(images.last);
      final originalState = tester.state(target);
      await mouse.moveTo(tester.getCenter(_photo(images.last)));
      await _motion(tester);
      await _click(tester, mouse, _control(target, _copyKey));
      final pending = fixture.actions.calls.single;
      expect(pending.source.source, images.last.url);
      FocusManager.instance.primaryFocus?.unfocus();
      await mouse.moveTo(Offset.zero);
      fixture.replaceImages([images.last, ...images.take(7)]);
      await _motion(tester);
      expect(tester.state(target), same(originalState));
      expect(_button(tester, target, _copyKey).onPressed, isNull);
      pending.succeed();
      await _motion(tester);
      expect(_control(target, _copiedKey), findsOneWidget);
      expect(_control(_bar(images[6]), _copiedKey), findsNothing);
      expect(find.byKey(_copiedKey), findsOneWidget);
      expect(
        tester.getRect(_photo(images.last)).top,
        lessThan(tester.getRect(_photo(images[6])).top),
      );
      expect(fixture.navigation.pushes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'duplicate photo URLs have separate hover and feedback identities',
      (tester) async {
    final fixture = _Fixture([images[0], images[0], images[1]]);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture, photos);
      final duplicates = _bars(images[0]);
      final first = duplicates.at(0);
      final second = duplicates.at(1);
      expect(duplicates, findsNWidgets(2));
      expect(tester.widget(first).key, isNot(tester.widget(second).key));
      await mouse.moveTo(tester.getCenter(_photos(images[0]).at(1)));
      await _motion(tester);
      expect(_reveal(tester, first).opacity, 0);
      expect(_reveal(tester, second).opacity, 1);
      await _click(tester, mouse, _control(second, _copyKey));
      fixture.actions.calls.single.succeed();
      await _motion(tester);
      expect(_control(first, _copiedKey), findsNothing);
      expect(_control(second, _copiedKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  testWidgets('narrow four-up tiles fit both actions and scaled feedback',
      (tester) async {
    // A quarter-width tile is 72px, while its large neighbour is 150px.
    final fixture = _Fixture(images.take(4).toList(), width: 306);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture, photos, mode: 'paper', scale: 2);
      final target = _bar(images[1]);
      final photo = tester.getRect(_photo(images[1]));
      expect(photo.width, closeTo(72, 0.01));
      await mouse.moveTo(photo.center);
      await _motion(tester);
      for (final action in [_copyKey, _shareKey]) {
        final bounds = _globalRect(tester, _control(target, action));
        expect(bounds.left, greaterThanOrEqualTo(photo.left));
        expect(bounds.right, lessThanOrEqualTo(photo.right));
        expect(bounds.width, greaterThan(20));
        expect(bounds.width, lessThanOrEqualTo(24));
        expect(_control(target, action).hitTestable(), findsOneWidget);
      }
      final before = await _capture(tester);
      await _click(tester, mouse, _control(target, _copyKey));
      fixture.actions.calls.single.succeed();
      await _motion(tester);
      final badge = _globalRect(tester, _control(target, _copiedKey));
      expect(badge.top, greaterThanOrEqualTo(photo.top));
      expect(badge.bottom, lessThan(_globalRect(tester, target).top));
      expect(badge.right, lessThanOrEqualTo(photo.right));
      final after = await _capture(tester);
      expect(
        _changedPixels(
          before,
          after,
          badge.shift(-tester.getTopLeft(find.byKey(_captureKey))),
        ),
        greaterThan(4),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  testWidgets(
    'read-only tiles support Tab, Enter and Space without mutations',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture(
        images.take(2).toList(),
        editable: false,
        withHeader: true,
        traversal: true,
      );
      try {
        await _mount(tester, fixture, photos);
        final before = fixture.snapshot;
        final first = _bar(images[0]);
        final second = _bar(images[1]);
        expect(fixture.before.hasFocus, isTrue);
        expect(find.bySemanticsLabel('Copy'), findsNothing);
        expect(_reveal(tester, first).opacity, 0);
        expect(_reveal(tester, second).opacity, 0);
        for (final label in [
          LocaleKeys.document_plugins_photoGallery_addImageTooltip.tr(),
          LocaleKeys.document_plugins_photoGallery_changeLayoutTooltip.tr(),
          LocaleKeys.document_plugins_photoGallery_deleteBlockTooltip.tr(),
        ]) {
          expect(_menuButton(label), findsNothing);
        }
        await _tabUntil(tester, _button(tester, first, _copyKey).focusNode!);
        expect(_reveal(tester, first).opacity, 1);
        expect(_reveal(tester, second).opacity, 0);
        expect(find.bySemanticsLabel('Copy'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(fixture.actions.calls.single.source.source, images[0].url);
        fixture.actions.calls.single.succeed();
        await _motion(tester);
        await _tabUntil(tester, _button(tester, second, _shareKey).focusNode!);
        expect(_reveal(tester, first).opacity, 0);
        expect(_reveal(tester, second).opacity, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(fixture.actions.calls.last.kind, 'share');
        expect(fixture.actions.calls.last.source.source, images[1].url);
        fixture.actions.calls.last.succeed();
        await _motion(tester);
        await _tabUntil(tester, fixture.after);
        expect(_reveal(tester, second).opacity, 0);
        expect(fixture.snapshot, before);
        expect(fixture.indexChanges, isEmpty);
        expect(fixture.navigation.pushes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final editable in [false, true]) {
    testWidgets(
        'photo double-click keeps fullscreen and delete permission: $editable',
        (tester) async {
      final fixture = _Fixture(images.take(2).toList(), editable: editable);
      try {
        await _mount(tester, fixture, photos);
        final before = fixture.snapshot;
        final point = tester.getCenter(_photo(images[1]));
        await tester.tapAt(point);
        await tester.pump(kDoubleTapMinTime + const Duration(milliseconds: 20));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        final viewer = tester.widget<InteractiveImageViewer>(
          find.byType(InteractiveImageViewer),
        );
        final provider = viewer.imageProvider as AFBlockImageProvider;
        expect(provider.initialIndex, 1);
        expect(provider.getImage(provider.initialIndex).url, images[1].url);
        expect(viewer.actions, same(fixture.actions));
        final toolbar = tester.widget<InteractiveImageToolbar>(
          find.byType(InteractiveImageToolbar),
        );
        expect(toolbar.onDelete, editable ? isNotNull : isNull);
        expect(fixture.navigation.pushes, hasLength(1));
        expect(fixture.actions.calls, isEmpty);
        if (editable) {
          final retainedDelete = provider.onDeleteImage!;
          fixture.editor.editable = false;
          await Future<void>.sync(() async {
            await retainedDelete(1);
          });
        } else {
          expect(provider.onDeleteImage, isNull);
        }
        expect(fixture.snapshot, before);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveImageViewer), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'optional document profile is read again after refresh and sign-out',
      (tester) async {
    final firstProfile =
        UserProfilePB(token: jsonEncode({'access_token': 'first'}));
    final nextProfile =
        UserProfilePB(token: jsonEncode({'access_token': 'next'}));
    final fixture = _Fixture(images.take(2).toList(), profile: firstProfile);
    try {
      await _mount(tester, fixture, photos);
      final state = tester.state(_bar(images[0]));
      expect(
        tester.widget<ImageRender>(_photo(images[0])).userProfile,
        same(firstProfile),
      );
      fixture.document!.updateProfile(nextProfile);
      await _motion(tester);
      for (final image in images.take(2)) {
        expect(
          tester.widget<ImageRender>(_photo(image)).userProfile,
          same(nextProfile),
        );
        expect(
          tester.widget<MediaActionButtons>(_bar(image)).source.httpHeaders,
          isEmpty,
        );
      }
      fixture.document!.updateProfile(null);
      await _motion(tester);
      expect(tester.widget<ImageRender>(_photo(images[0])).userProfile, isNull);
      expect(tester.state(_bar(images[0])), same(state));
      expect(fixture.actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'all staggered patterns retain dimensions, image fit and tile targets',
      (tester) async {
    final fixture = _Fixture(images, width: 360);
    try {
      await _mount(tester, fixture, photos);
      const even = {
        1: [(4, 2)],
        2: [(2, 2), (2, 2)],
        3: [(2, 2), (2, 1), (2, 1)],
        4: [(2, 2), (1, 1), (1, 1), (2, 1)],
      };
      const odd = {
        1: [(4, 2)],
        2: [(2, 2), (2, 2)],
        3: [(2, 1), (2, 2), (2, 1)],
        4: [(1, 1), (1, 1), (2, 2), (2, 1)],
      };
      for (var count = 1; count <= 8; count++) {
        fixture.replaceImages(images.take(count).toList());
        await _motion(tester);
        final tiles = tester
            .widgetList<StaggeredGridTile>(find.byType(StaggeredGridTile));
        expect(
          tiles
              .map((tile) => (tile.crossAxisCellCount, tile.mainAxisCellCount))
              .toList(),
          count <= 4 ? even[count] : [...even[4]!, ...odd[count - 4]!],
        );
        final renders =
            tester.widgetList<ImageRender>(find.byType(ImageRender));
        expect(
          renders.map((image) => image.image.url),
          images.take(count).map((image) => image.url),
        );
        expect(renders.every((image) => image.fit == BoxFit.cover), isTrue);
        expect(
          renders.every((image) => image.borderRadius == BorderRadius.zero),
          isTrue,
        );
        expect(find.byType(MediaActionButtons), findsNWidgets(count));
        expect(tester.takeException(), isNull);
      }
      fixture.replaceImages([]);
      await _motion(tester);
      expect(find.byType(MediaActionButtons), findsNothing);
      expect(find.byType(ImageRender), findsNothing);
      expect(fixture.actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

Finder _bars(ImageBlockData image) => find.byWidgetPredicate(
      (widget) =>
          widget is MediaActionButtons && widget.source.source == image.url,
    );

Finder _bar(ImageBlockData image) => _bars(image).first;

Finder _photos(ImageBlockData image) => find.byWidgetPredicate(
      (widget) => widget is ImageRender && widget.image.url == image.url,
    );

Finder _photo(ImageBlockData image) => _photos(image).first;

Finder _control(Finder bar, Key key) =>
    find.descendant(of: bar, matching: find.byKey(key));

IconButton _button(WidgetTester tester, Finder bar, Key key) =>
    tester.widget<IconButton>(_control(bar, key));

AnimatedOpacity _reveal(WidgetTester tester, Finder bar) =>
    tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: bar,
            matching: find.byKey(const ValueKey('media-action-reveal')),
          )
          .first,
    );

Finder _menuButton(String tooltip) => find.byWidgetPredicate(
      (widget) => widget is MenuBlockButton && widget.tooltip == tooltip,
    );

Rect _globalRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
}

Future<void> _click(
  WidgetTester tester,
  TestGesture mouse,
  Finder finder,
) async {
  final point = tester.getCenter(finder);
  await mouse.moveTo(point);
  await mouse.down(point);
  await mouse.up();
  await tester.pump();
}

Future<void> _tabUntil(WidgetTester tester, FocusNode target) async {
  for (var step = 0; step < 12 && !target.hasFocus; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _motion(tester);
  }
  expect(target.hasFocus, isTrue);
}

/// The renderer, menu and document are real. Only media IO and the optional
/// document bloc are substituted; no native backend or HTTP client is started.
class _Fixture {
  _Fixture(
    List<ImageBlockData> images, {
    bool editable = true,
    UserProfilePB? profile,
    this.width = 520,
    this.withHeader = false,
    this.traversal = false,
  }) : node = multiImageNode(images: images) {
    node.updateAttributes({
      ...node.attributes,
      MultiImageBlockKeys.layout: MultiImageLayout.grid.toIntValue(),
    });
    editor = EditorState(document: Document(root: pageNode(children: [node])))
      ..editorStyle = const EditorStyle.desktop()
      ..disableSealTimer = true
      ..editable = editable;
    owner = _MenuOwner(editor, index);
    document = profile == null ? null : _Document(profile);
  }

  final Node node;
  final double width;
  final bool withHeader;
  final bool traversal;
  final actions = _MediaActions();
  final revision = ValueNotifier(0);
  final index = ValueNotifier(1);
  final indexChanges = <int>[];
  final before = FocusNode();
  final after = FocusNode();
  final navigation = _Navigation();
  late final EditorState editor;
  late final _MenuOwner owner;
  late final _Document? document;

  String get snapshot => jsonEncode(editor.document.toJson());

  void replaceImages(List<ImageBlockData> images) {
    node.updateAttributes({
      ...node.attributes,
      MultiImageBlockKeys.images: MultiImageData(images: images).toJson(),
    });
    revision.value++;
  }

  Widget build() {
    Widget child = ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (_, __, ___) => MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => owner.showActionsNotifier.value = true,
        onExit: (_) => owner.showActionsNotifier.value = false,
        child: RepaintBoundary(
          key: _captureKey,
          child: SizedBox(
            width: width,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ImageLayoutRender(
                  node: node,
                  editorState: editor,
                  images: MultiImageData.fromJson(
                    node.attributes[MultiImageBlockKeys.images],
                  ).images,
                  indexNotifier: index,
                  isLocalMode: true,
                  mediaActions: actions,
                  onIndexChanged: (value) {
                    indexChanges.add(value);
                    index.value = value;
                  },
                ),
                if (withHeader)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: MultiImageMenu(
                      node: node,
                      state: owner,
                      indexNotifier: index,
                      onImageDeleted: () {},
                      mediaActions: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (traversal) {
      child = FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              autofocus: true,
              focusNode: before,
              onPressed: () {},
              child: const Text('Before grid'),
            ),
            child,
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After grid'),
            ),
          ],
        ),
      );
    }
    if (document != null) {
      child = BlocProvider<DocumentBloc>.value(value: document!, child: child);
    }
    return RepositoryProvider<EditorState>.value(value: editor, child: child);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final call in actions.calls) {
      if (!call.completion.isCompleted) call.succeed();
    }
    await tester.pump();
    if (document != null) await tester.runAsync(document!.close);
    editor.dispose();
    owner.showActionsNotifier.dispose();
    index.dispose();
    revision.dispose();
    before.dispose();
    after.dispose();
  }
}

class _MenuOwner extends Fake implements MultiImageBlockComponentState {
  _MenuOwner(this.editorState, this.indexNotifier);

  @override
  final EditorState editorState;
  @override
  final ValueNotifier<int> indexNotifier;
  @override
  final showActionsNotifier = ValueNotifier(false);
  @override
  bool alwaysShowMenu = false;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_MenuOwner';
}

class _Document extends Cubit<DocumentState> implements DocumentBloc {
  _Document(UserProfilePB profile)
      : super(DocumentState.initial().copyWith(userProfilePB: profile));

  void updateProfile(UserProfilePB? profile) =>
      emit(state.copyWith(userProfilePB: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Navigation extends NavigatorObserver {
  final pushes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes.add(route);
}

class _MediaActions extends Fake implements MediaActionService {
  final calls = <_MediaCall>[];

  @override
  Future<void> copy(MediaActionSource source) => _begin('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _begin('share', source, sharePositionOrigin);

  Future<void> _begin(String kind, MediaActionSource source, Rect? origin) {
    final call = _MediaCall(kind, source, origin);
    calls.add(call);
    return call.completion.future;
  }
}

class _MediaCall {
  _MediaCall(this.kind, this.source, this.origin);

  final String kind;
  final MediaActionSource source;
  final Rect? origin;
  final completion = Completer<void>();

  void succeed() => completion.complete();
}

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  List<File> photos, {
  String mode = 'light',
  double scale = 1,
}) async {
  // Prewarm real FileImage providers on the IO clock; subsequent widget builds
  // decode neither network URLs nor user data and keep the production layout.
  for (final photo in photos) {
    await tester.runAsync(() async {
      final stream = FileImage(photo).resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      final listener = ImageStreamListener(
        (image, _) {
          image.dispose();
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        await ready.future;
      } finally {
        stream.removeListener(listener);
      }
    });
  }
  final theme = _theme(mode);
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
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
          navigatorObservers: [fixture.navigation],
          builder: (context, child) => AppFlowyTheme(
            data: appTheme,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: Scaffold(body: Center(child: fixture.build())),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  fixture.navigation.pushes.clear();
}

Future<List<int>> _png(bool warm) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(
    warm ? const Color(0xFFCA7945) : const Color(0xFF426D9D),
    BlendMode.src,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 30);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _Pixels {
  _Pixels(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final List<int> bytes;
}

Future<_Pixels> _capture(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  final image = (await tester.runAsync(boundary.toImage))!;
  try {
    final bytes = (await tester.runAsync(image.toByteData))!;
    return _Pixels(image.width, image.height, bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

int _changedPixels(_Pixels before, _Pixels after, Rect region) {
  expect(after.width, before.width);
  expect(after.height, before.height);
  final left = region.left.floor().clamp(0, before.width).toInt();
  final right = region.right.ceil().clamp(0, before.width).toInt();
  final top = region.top.floor().clamp(0, before.height).toInt();
  final bottom = region.bottom.ceil().clamp(0, before.height).toInt();
  var changed = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * before.width + x) * 4;
      if (before.bytes[offset] != after.bytes[offset] ||
          before.bytes[offset + 1] != after.bytes[offset + 1] ||
          before.bytes[offset + 2] != after.bytes[offset + 2]) {
        changed++;
      }
    }
  }
  return changed;
}
