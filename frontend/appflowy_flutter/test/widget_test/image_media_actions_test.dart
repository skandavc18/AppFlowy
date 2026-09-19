import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/image_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/layouts/image_browser_layout.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/resizeable_image.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide ResizableImage;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _copyKey = ValueKey('media-copy');
const _shareKey = ValueKey('media-share');
const _copiedKey = ValueKey('media-copied');
const _captureKey = ValueKey('image-action-capture');
const _revealKey = ValueKey('media-action-reveal');
const _frameKey = ValueKey('resizable_media');
const _fade = Duration(milliseconds: 140);
const _cloudUrl = 'https://workspace.example.test/api/file_storage/w/v1/blob/a';
const _externalUrl = 'https://images.example.test/second.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late List<File> photos;
  late List<int> photoBytes;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    temporary = await Directory.systemTemp.createTemp('image_media_actions_');
    photoBytes = await _solidPng();
    photos = [
      for (final name in ['first photo #%.png', 'second photo.png'])
        await File('${temporary.path}${Platform.pathSeparator}$name')
            .writeAsBytes(photoBytes),
    ];
    // The real browser/placeholder hosts install a drop target. No native
    // plugin, clipboard, share sheet, HTTP request or user database is used.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('desktop_drop'),
      (_) async => null,
    );
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
    await temporary.delete(recursive: true);
  });

  test('image actions accept real paths/file URIs but not invalid uploads', () {
    expect(isValidImageBlockSource(photos.first.path), isTrue);
    expect(isValidImageBlockSource(photos.first.uri.toString()), isTrue);
    expect(isValidImageBlockSource(_cloudUrl), isTrue);
    expect(isValidImageBlockSource(_externalUrl), isTrue);
    for (final source in [
      null,
      17,
      '',
      '   ',
      '${temporary.path}/missing.png',
      'https:///missing-host.png',
      'https://user:password@example.test/photo.png',
      'ftp://example.test/photo.png',
      'javascript:alert(1)',
    ]) {
      expect(isValidImageBlockSource(source), isFalse);
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$mode/$scale: actual image paints Copied inside its frame',
          (tester) async {
        final fixture = _Fixture(
          node: customImageNode(
            url: photos.first.uri.toString(),
            width: 360,
            height: 220,
          ),
          realBlock: true,
          editable: false,
        );
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(
            tester,
            fixture,
            photos: photos,
            mode: mode,
            scale: scale,
          );
          final frame = tester.getRect(find.byKey(_frameKey));
          await mouse.moveTo(frame.center);
          await _motion(tester);
          final menu = find.byKey(const ValueKey('image-menu-toolbar'));
          final bounds = tester.getRect(menu);
          final source = _buttons(tester).source;
          expect(bounds.height, 32);
          expect(bounds.right, closeTo(frame.right - 8, 0.01));
          expect(_buttons(tester).decorated, isFalse);
          expect(_buttons(tester).buttonSize, 24);
          expect(tester.getSize(find.byKey(_copyKey)), const Size.square(24));
          expect(tester.getSize(find.byKey(_shareKey)), const Size.square(24));
          expect(source.source, photos.first.uri.toString());
          expect(source.name, 'first photo #%.png');
          expect(source.isImage, isTrue);
          expect(source.httpHeaders, isEmpty);
          expect(fixture.actions.calls, isEmpty);
          final menuContext = tester.element(menu);
          final decoration =
              tester.widget<Container>(menu).decoration! as BoxDecoration;
          expect(
            decoration.color,
            EditorSurfaceStyle.previewBackgroundFor(
              Theme.of(menuContext).brightness,
              Theme.of(menuContext).cardColor,
              isPaper: PaperTheme.isEnabled(menuContext),
            ),
          );
          expect(decoration.border, isNull);
          if (mode == 'paper') {
            expect(decoration.color, PaperTheme.editorPreviewBackground);
          }

          final before = await _capture(tester);
          await tester.tap(find.byKey(_copyKey));
          await tester.pump();
          expect(fixture.actions.calls.single.source, source);
          expect(find.byKey(_copiedKey), findsNothing);
          fixture.actions.calls.single.succeed();
          await _motion(tester);

          final badge = tester.getRect(find.byKey(_copiedKey));
          expect(badge.top, greaterThanOrEqualTo(frame.top));
          expect(
            badge.bottom,
            lessThan(tester.getRect(find.byKey(_copyKey)).top),
          );
          expect(badge.right, lessThanOrEqualTo(frame.right));
          expect(frame.contains(badge.center), isTrue);
          expect(
            tester.widget<Text>(find.byKey(_copiedKey)).style!.fontSize,
            10,
          );
          expect(tester.getRect(menu), bounds);
          expect(tester.getRect(find.byKey(_frameKey)), frame);
          expect(_reveal(tester).opacity, 1);
          final after = await _capture(tester);
          final localBadge =
              badge.shift(-tester.getTopLeft(find.byKey(_captureKey)));
          expect(_changedPixels(before, after, localBadge), greaterThan(4));
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      });
    }
  }

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets('$mode: actual browser paints scaled Copied inside the photo',
        (tester) async {
      final fixture = _Fixture(
        node: _localNode(photos, gallery: true),
        realBlock: true,
        editable: false,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, photos: photos, mode: mode, scale: 2);
        final photo = tester.getRect(_photo(true));
        await mouse.moveTo(photo.center);
        await _motion(tester);
        final toolbar = find.byKey(const ValueKey('multi-image-menu-toolbar'));
        final bounds = tester.getRect(toolbar);
        expect(bounds.height, 32);
        expect(bounds.width, lessThan(photo.width));
        expect(_buttons(tester).decorated, isFalse);
        expect(_buttons(tester).buttonSize, 24);
        if (mode == 'paper') {
          expect(
            (tester.widget<Container>(toolbar).decoration! as BoxDecoration)
                .color,
            PaperTheme.editorPreviewBackground,
          );
        }
        final before = await _capture(tester);
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        expect(fixture.actions.calls.single.source.source, photos.first.path);
        fixture.actions.calls.single.succeed();
        await _motion(tester);
        final badge = tester.getRect(find.byKey(_copiedKey));
        expect(badge.top, greaterThanOrEqualTo(photo.top));
        expect(
          badge.bottom,
          lessThan(tester.getRect(find.byKey(_copyKey)).top),
        );
        expect(photo.contains(badge.center), isTrue);
        expect(tester.getRect(toolbar), bounds);
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
  }

  for (final gallery in [false, true]) {
    testWidgets('${_kind(gallery)}: real hover retains busy, success and timer',
        (tester) async {
      final fixture = _Fixture(
        node: _localNode(photos, gallery: gallery),
        realBlock: true,
        editable: false,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, photos: photos);
        final state = tester.state(find.byType(MediaActionButtons));
        expect(_reveal(tester).opacity, 0);
        expect(find.byKey(_copyKey).hitTestable(), findsNothing);
        await tester.tapAt(tester.getCenter(find.byKey(_copyKey)));
        await tester.pump();
        expect(fixture.actions.calls, isEmpty);

        final point = tester.getCenter(_photo(gallery));
        await mouse.moveTo(point);
        await _motion(tester);
        expect(_reveal(tester).opacity, 1);
        expect(
          fixture.actions.calls,
          isEmpty,
          reason: 'Hover is not activation',
        );
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        expect(fixture.actions.calls, hasLength(1));
        FocusManager.instance.primaryFocus?.unfocus();
        await mouse.moveTo(Offset.zero);
        await _motion(tester);
        expect(_reveal(tester).opacity, 0);
        expect(_button(tester, _copyKey).onPressed, isNull);
        expect(_button(tester, _shareKey).onPressed, isNull);
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        fixture.actions.calls.single.succeed();
        await tester.pump();
        await mouse.moveTo(point);
        await _motion(tester);
        expect(_reveal(tester).opacity, 1);
        expect(find.byKey(_copiedKey), findsOneWidget);
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        expect(fixture.actions.calls, hasLength(1));

        FocusManager.instance.primaryFocus?.unfocus();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await mouse.moveTo(point);
        await _motion(tester);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(_button(tester, _copyKey).tooltip, LocaleKeys.editor_copy.tr());
        expect(fixture.actions.calls, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });

    for (final workspace in [false, true]) {
      testWidgets(
          '${_kind(gallery)}: live ${workspace ? 'workspace' : 'document'} credentials',
          (tester) async {
        final fixture = _Fixture(
          node: _remoteNode(gallery: gallery),
          documentProfile: _profile('document-one'),
          workspaceProfile: workspace ? _profile('workspace-one') : null,
        );
        try {
          await _mount(tester, fixture);
          final state = tester.state(find.byType(MediaActionButtons));
          await tester.tap(find.byKey(_copyKey));
          await tester.pump();
          final first = fixture.actions.calls.single;
          expect(first.source.source, _cloudUrl);
          expect(first.source.isImage, isTrue);
          expect(first.source.shareAsLink, isFalse);
          expect(first.source.requireAuthentication, isTrue);
          expect(first.source.httpHeaders, {
            'Authorization':
                'Bearer ${workspace ? 'workspace' : 'document'}-one',
          });
          first.succeed();
          await _motion(tester);
          expect(find.byKey(_copiedKey), findsOneWidget);

          fixture.document!.updateProfile(_profile('document-two'));
          await _motion(tester);
          if (workspace) {
            expect(find.byKey(_copiedKey), findsOneWidget);
            fixture.workspace!.updateProfile(_profile('workspace-two'));
            await _motion(tester);
          }
          expect(find.byKey(_copiedKey), findsNothing);
          expect(tester.state(find.byType(MediaActionButtons)), same(state));
          await tester.tap(find.byKey(_shareKey));
          await tester.pump();
          final shared = fixture.actions.calls.last;
          expect(shared.kind, 'share');
          expect(shared.source.httpHeaders, {
            'Authorization':
                'Bearer ${workspace ? 'workspace' : 'document'}-two',
          });
          expect(shared.origin, isNotNull);
          expect(shared.origin!.isEmpty, isFalse);
          expect(
            first.source.httpHeaders,
            {
              'Authorization':
                  'Bearer ${workspace ? 'workspace' : 'document'}-one',
            },
            reason: 'In-flight targets own an immutable credential snapshot',
          );
          shared.succeed();
          await _motion(tester);
          expect(find.byKey(_copiedKey), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });
    }

    testWidgets(
        '${_kind(gallery)}: renewed credentials invalidate a pending copy',
        (tester) async {
      final fixture = _Fixture(
        node: _remoteNode(gallery: gallery),
        workspaceProfile: _profile('before-renewal'),
      );
      try {
        await _mount(tester, fixture);
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        final pending = fixture.actions.calls.single;
        fixture.workspace!.updateProfile(_profile('after-renewal'));
        await _motion(tester);
        expect(_buttons(tester).source.httpHeaders, {
          'Authorization': 'Bearer after-renewal',
        });
        expect(pending.source.httpHeaders, {
          'Authorization': 'Bearer before-renewal',
        });
        expect(_button(tester, _copyKey).onPressed, isNull);
        expect(_button(tester, _shareKey).onPressed, isNull);
        pending.succeed();
        await _motion(tester);
        expect(find.byKey(_copiedKey), findsNothing);
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        expect(fixture.actions.calls.last.source.httpHeaders, {
          'Authorization': 'Bearer after-renewal',
        });
        fixture.actions.calls.last.succeed();
        await _motion(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets(
        '${_kind(gallery)}: optional providers are safe and fail closed',
        (tester) async {
      final fixture = _Fixture(node: _remoteNode(gallery: gallery));
      try {
        await _mount(tester, fixture);
        expect(_buttons(tester).source.requireAuthentication, isTrue);
        expect(_buttons(tester).source.httpHeaders, isEmpty);
        expect(fixture.actions.calls, isEmpty);
        fixture.replaceImages([
          ImageBlockData(url: _externalUrl, type: CustomImageType.external),
        ]);
        await _motion(tester);
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        expect(fixture.actions.calls.single.source.source, _externalUrl);
        expect(fixture.actions.calls.single.source.httpHeaders, isEmpty);
        expect(
          fixture.actions.calls.single.source.requireAuthentication,
          isFalse,
        );
        fixture.actions.calls.single.succeed();
        await _motion(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    for (final fail in [false, true]) {
      testWidgets(
          '${_kind(gallery)}: rebinding rejects late ${fail ? 'failure' : 'success'}',
          (tester) async {
        final fixture = _Fixture(
          node: _remoteNode(gallery: gallery, includeExternal: gallery),
          workspaceProfile: _profile('synthetic-token'),
        );
        try {
          await _mount(tester, fixture);
          final state = tester.state(find.byType(MediaActionButtons));
          final obsoletePress = _button(tester, _shareKey).onPressed!;
          await tester.tap(find.byKey(_copyKey));
          await tester.pump();
          if (gallery) {
            fixture.index.value = 1;
          } else {
            fixture.replaceImages([
              ImageBlockData(url: _externalUrl, type: CustomImageType.external),
            ]);
          }
          await _motion(tester);
          expect(_button(tester, _copyKey).onPressed, isNull);
          expect(_button(tester, _shareKey).onPressed, isNull);
          expect(_buttons(tester).source.source, _externalUrl);
          expect(_buttons(tester).source.httpHeaders, isEmpty);
          obsoletePress();
          expect(fixture.actions.calls, hasLength(1));
          final first = fixture.actions.calls.single;
          expect(first.source.source, _cloudUrl);
          expect(
            first.source.httpHeaders['Authorization'],
            'Bearer synthetic-token',
          );
          if (fail) {
            first.fail();
          } else {
            first.succeed();
          }
          await _motion(tester);
          expect(find.byKey(_copiedKey), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
          expect(tester.state(find.byType(MediaActionButtons)), same(state));
          obsoletePress();
          expect(fixture.actions.calls, hasLength(1));
          await tester.tap(find.byKey(_shareKey));
          await tester.pump();
          expect(fixture.actions.calls.last.source.source, _externalUrl);
          expect(fixture.actions.calls.last.source.httpHeaders, isEmpty);
          expect(
            fixture.actions.calls.last.source.requireAuthentication,
            isFalse,
          );
          fixture.actions.calls.last.succeed();
          await _motion(tester);

          // Changing only the stored type must also rebind credentials.
          fixture.replaceImages([
            ImageBlockData(url: _externalUrl, type: CustomImageType.internal),
          ]);
          await _motion(tester);
          await tester.tap(find.byKey(_copyKey));
          await tester.pump();
          expect(
            fixture.actions.calls.last.source.requireAuthentication,
            isTrue,
          );
          expect(fixture.actions.calls.last.source.httpHeaders, {
            'Authorization': 'Bearer synthetic-token',
          });
          fixture.actions.calls.last.succeed();
          await _motion(tester);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });
    }

    for (final action in [_copyKey, _shareKey]) {
      testWidgets(
          '${_kind(gallery)}: removed real host ignores pending $action',
          (tester) async {
        final fixture = _Fixture(
          node: _localNode(photos, gallery: gallery),
          realBlock: true,
          editable: false,
        );
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(tester, fixture, photos: photos);
          await mouse.moveTo(tester.getCenter(_photo(gallery)));
          await _motion(tester);
          await tester.tap(find.byKey(action));
          await tester.pump();
          final pending = fixture.actions.calls.single;
          final stalePress = _button(tester, action).onPressed;
          expect(stalePress, isNull);
          fixture.show = false;
          fixture.rebuild();
          await tester.pump();
          expect(find.byType(MediaActionButtons), findsNothing);
          pending.fail();
          await _motion(tester);
          expect(fixture.actions.calls, hasLength(1));
          expect(find.byKey(_copiedKey), findsNothing);
          expect(fixture.editor.service.selections.interceptors, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      });
    }
  }

  for (final source in ['', 'not-an-uploaded-image']) {
    testWidgets('fallback $source: keeps More mounted but no media actions',
        (tester) async {
      final fixture = _Fixture(
        node: customImageNode(url: source),
        realBlock: true,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture);
        final menu = tester.state(find.byType(ImageMenu));
        expect(find.byType(MediaActionButtons), findsNothing);
        expect(
          find.byIcon(Icons.document_scanner_rounded),
          source.isEmpty ? findsNothing : findsOneWidget,
        );
        expect(_reveal(tester).opacity, 0);
        await mouse.moveTo(tester.getCenter(find.byKey(fixture.singleKey)));
        await _motion(tester);
        expect(_reveal(tester).opacity, 1);
        expect(_menuButton('More actions').hitTestable(), findsOneWidget);
        expect(tester.getSize(find.byType(ImageMenu)).height, 32);
        await mouse.moveTo(Offset.zero);
        await _motion(tester);
        expect(_reveal(tester).opacity, 0);
        expect(tester.state(find.byType(ImageMenu)), same(menu));
        expect(fixture.actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
    'read-only actual image is revealed by Tab, Enter copies and Space shares',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = _Fixture(
        node: _localNode(photos),
        realBlock: true,
        editable: false,
      );
      try {
        await _mount(tester, fixture, photos: photos, traversal: true);
        final before = jsonEncode(fixture.editor.document.toJson());
        expect(fixture.before.hasFocus, isTrue);
        expect(_reveal(tester).opacity, 0);
        expect(find.bySemanticsLabel('Copy'), findsNothing);
        await _tabUntil(tester, _button(tester, _copyKey).focusNode!);
        expect(_button(tester, _copyKey).focusNode!.hasFocus, isTrue);
        expect(_reveal(tester).opacity, 1);
        expect(find.bySemanticsLabel('Copy'), findsOneWidget);
        expect(fixture.actions.calls, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(fixture.actions.calls.single.kind, 'copy');
        fixture.actions.calls.single.succeed();
        await _motion(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await _motion(tester);
        expect(_button(tester, _shareKey).focusNode!.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(fixture.actions.calls.last.kind, 'share');
        expect(
          fixture.actions.calls.last.origin,
          tester.getRect(find.byKey(_shareKey)),
        );
        fixture.actions.calls.last.succeed();
        await _motion(tester);
        expect(find.byKey(_copiedKey), findsNothing);
        await _tabUntil(tester, fixture.after);
        expect(fixture.after.hasFocus, isTrue);
        expect(_reveal(tester).opacity, 0);
        expect(jsonEncode(fixture.editor.document.toJson()), before);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
      'real browser selection and shrinking list target the displayed image',
      (tester) async {
    final fixture = _Fixture(
      node: _localNode(photos, gallery: true),
      realBlock: true,
      editable: false,
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture, photos: photos);
      final second = find.byWidgetPredicate(
        (widget) => widget is ThumbnailItem && widget.index == 1,
      );
      await tester.tapAt(tester.getBottomLeft(second) + const Offset(12, -12));
      await _motion(tester);
      expect(fixture.index.value, 1);
      expect(
        tester.widget<ImageRender>(find.byType(ImageRender).first).image.url,
        photos[1].path,
      );
      await mouse.moveTo(tester.getCenter(_photo(true)));
      await _motion(tester);
      await tester.tap(find.byKey(_shareKey));
      await tester.pump();
      expect(fixture.actions.calls.single.source.source, photos[1].path);
      fixture.actions.calls.single.succeed();
      await _motion(tester);
      fixture.replaceImages([
        ImageBlockData(url: photos.first.path, type: CustomImageType.local),
      ]);
      await _motion(tester);
      expect(fixture.index.value, 0);
      expect(
        tester.widget<ImageRender>(find.byType(ImageRender).first).image.url,
        photos.first.path,
      );
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      expect(fixture.actions.calls.last.source.source, photos.first.path);
      fixture.actions.calls.last.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'gallery clamps both index bounds and omits empty/invalid targets',
      (tester) async {
    final fixture = _Fixture(
      node: _remoteNode(gallery: true, includeExternal: true),
      workspaceProfile: _profile('synthetic-token'),
    );
    try {
      await _mount(tester, fixture);
      for (final (index, expected) in [
        (999, _externalUrl),
        (-7, _cloudUrl),
      ]) {
        fixture.index.value = index;
        await _motion(tester);
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        expect(fixture.actions.calls.last.source.source, expected);
        fixture.actions.calls.last.succeed();
        await _motion(tester);
      }
      fixture.replaceImages([]);
      await _motion(tester);
      expect(find.byType(MediaActionButtons), findsNothing);
      expect(
        tester
            .widget<MenuBlockButton>(
              _menuButton(LocaleKeys.document_imageBlock_openFullScreen.tr()),
            )
            .onTap,
        isNull,
      );
      fixture.replaceImages([
        ImageBlockData(url: 'not-a-file', type: CustomImageType.local),
      ]);
      await _motion(tester);
      expect(find.byType(MediaActionButtons), findsNothing);
      expect(fixture.actions.calls, hasLength(2));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'gallery read-only toggle keeps copy/share and removes mutation actions',
      (tester) async {
    final fixture = _Fixture(node: _remoteNode(gallery: true));
    try {
      await _mount(tester, fixture);
      final state = tester.state(find.byType(MediaActionButtons));
      expect(
        _menuButton(
          LocaleKeys.document_plugins_photoGallery_addImageTooltip.tr(),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      fixture.editor.editable = false;
      await _motion(tester);
      expect(
        _menuButton(
          LocaleKeys.document_plugins_photoGallery_addImageTooltip.tr(),
        ),
        findsNothing,
      );
      expect(
        _menuButton(
          LocaleKeys.document_plugins_photoGallery_changeLayoutTooltip.tr(),
        ),
        findsNothing,
      );
      expect(
        _menuButton(
          LocaleKeys.document_plugins_photoGallery_deleteBlockTooltip.tr(),
        ),
        findsNothing,
      );
      expect(
        _menuButton(LocaleKeys.document_imageBlock_openFullScreen.tr()),
        findsOneWidget,
      );
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(_button(tester, _copyKey).onPressed, isNull);
      fixture.actions.calls.single.succeed();
      await _motion(tester);
      expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
      expect(find.byKey(_shareKey).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final editable in [false, true]) {
    testWidgets(
        'image More retains original actions and read-only gating: $editable',
        (tester) async {
      final fixture = _Fixture(
        node: _localNode(photos),
        editable: editable,
      );
      final foreign = SelectionGestureInterceptor(key: 'image-block-menu');
      fixture.editor.service.selections.registerGestureInterceptor(foreign);
      try {
        await _mount(tester, fixture);
        await tester.tap(_menuButton('More actions'));
        await tester.pumpAndSettle();
        expect(fixture.editor.service.selections.interceptors, hasLength(2));
        expect(find.text(LocaleKeys.editor_copy.tr()), findsOneWidget);
        expect(find.text(LocaleKeys.button_share.tr()), findsOneWidget);
        expect(find.text(LocaleKeys.button_download.tr()), findsOneWidget);
        expect(
          find.text(LocaleKeys.document_imageBlock_openFullScreen.tr()),
          findsOneWidget,
        );
        expect(find.text('Scan text'), findsOneWidget);
        for (final label in [
          'Edit image',
          'Add a caption',
          LocaleKeys.editor_cut.tr(),
          LocaleKeys.button_delete.tr(),
          LocaleKeys.document_plugins_optionAction_left.tr(),
          LocaleKeys.document_plugins_optionAction_center.tr(),
          LocaleKeys.document_plugins_optionAction_right.tr(),
        ]) {
          expect(find.text(label), editable ? findsOneWidget : findsNothing);
        }
        // Removing the host while the route still exists must release only its
        // own interceptor; the route's later finally must be harmless.
        fixture.show = false;
        fixture.rebuild();
        await tester.pump();
        expect(
          fixture.editor.service.selections.interceptors,
          {'image-block-menu': foreign},
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          fixture.editor.service.selections.interceptors,
          {'image-block-menu': foreign},
        );
        expect(fixture.actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        fixture.editor.service.selections
            .unregisterGestureInterceptor(foreign.key);
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'gallery layout popup cleanup leaves other editor interceptors intact',
      (tester) async {
    final fixture = _Fixture(node: _remoteNode(gallery: true));
    final foreign = SelectionGestureInterceptor(key: 'add-image');
    fixture.editor.service.selections.registerGestureInterceptor(foreign);
    try {
      await _mount(tester, fixture);
      final button = _menuButton(
        LocaleKeys.document_plugins_photoGallery_changeLayoutTooltip.tr(),
      );
      final popover = tester.widget<AppFlowyPopover>(
        find.ancestor(of: button, matching: find.byType(AppFlowyPopover)).first,
      );
      final closeAgain = popover.onClose!;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(fixture.editor.service.selections.interceptors, hasLength(2));
      fixture.show = false;
      fixture.rebuild();
      await tester.pumpAndSettle();
      closeAgain();
      await tester.pump();
      expect(
        fixture.editor.service.selections.interceptors,
        {'add-image': foreign},
      );
      expect(fixture.actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      fixture.editor.service.selections
          .unregisterGestureInterceptor(foreign.key);
      await fixture.dispose(tester);
    }
  });

  for (final share in [false, true]) {
    testWidgets(
        'legacy ${share ? 'shareImage' : 'copyImage'} delegates to injected service',
        (tester) async {
      final fixture = _Fixture(
        node: _remoteNode(),
        documentProfile: _profile('old-token'),
      );
      try {
        await _mount(tester, fixture);
        fixture.document!.updateProfile(_profile('new-token'));
        // Invoke the real existing menu entrypoint before a profile rebuild.
        final dynamic state = tester.state(find.byType(ImageMenu));
        final operation =
            (share ? state.shareImage() : state.copyImage()) as Future<void>;
        expect(fixture.actions.calls.single.kind, share ? 'share' : 'copy');
        expect(fixture.actions.calls.single.source.httpHeaders, {
          'Authorization': 'Bearer new-token',
        });
        fixture.show = false;
        fixture.rebuild();
        await tester.pump();
        // Complete after unmount to verify cleanup without using the app's
        // global toast host. The hover buttons have their own inline feedback.
        fixture.actions.calls.single.succeed();
        await operation;
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'cut still writes the AppFlowy block plus original bitmap before deletion',
      (tester) async {
    final clipboard = _ClipboardSpy();
    final fixture = _Fixture(
      node: customImageNode(url: photos.first.uri.toString()),
    );
    getIt.pushNewScope();
    getIt.registerSingleton<ClipboardService>(clipboard);
    try {
      await _mount(tester, fixture);
      final dynamic state = tester.state(find.byType(ImageMenu));
      final Future<void> Function() cut = state.cutBlock;
      await tester.runAsync(cut);
      await tester.pump();
      expect(clipboard.writes, hasLength(1));
      final data = clipboard.writes.single;
      expect(data.plainText, photos.first.uri.toString());
      expect(data.image!.$1, 'png');
      expect(data.image!.$2, photoBytes);
      final copied = Document.fromJson(
        jsonDecode(data.inAppJson!) as Map<String, dynamic>,
      );
      final copiedImages = copied.root.children
          .where((node) => node.type == CustomImageBlockKeys.type);
      expect(copiedImages, hasLength(1));
      expect(
        copiedImages.single.attributes[CustomImageBlockKeys.url],
        photos.first.uri.toString(),
      );
      expect(
        fixture.editor.document.root.children,
        isNot(contains(fixture.node)),
      );
      expect(
        fixture.actions.calls,
        isEmpty,
        reason: 'Cut must not degrade to a plain media copy',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      await tester.runAsync(getIt.popScope);
    }
  });
}

String _kind(bool gallery) => gallery ? 'gallery browser' : 'single image';

Node _localNode(List<File> photos, {bool gallery = false}) => gallery
    ? multiImageNode(
        images: [
          for (final photo in photos)
            ImageBlockData(url: photo.path, type: CustomImageType.local),
        ],
      )
    : customImageNode(url: photos.first.path, width: 360, height: 220);

Node _remoteNode({bool gallery = false, bool includeExternal = false}) =>
    gallery
        ? multiImageNode(
            images: [
              ImageBlockData(url: _cloudUrl, type: CustomImageType.internal),
              if (includeExternal)
                ImageBlockData(
                  url: _externalUrl,
                  type: CustomImageType.external,
                ),
            ],
          )
        : customImageNode(url: _cloudUrl, type: CustomImageType.internal);

UserProfilePB _profile(String token) =>
    UserProfilePB(token: jsonEncode({'access_token': token}));

Finder _photo(bool gallery) =>
    gallery ? find.byType(ImageRender).first : find.byKey(_frameKey);

Finder _menuButton(String tooltip) => find.byWidgetPredicate(
      (widget) => widget is MenuBlockButton && widget.tooltip == tooltip,
    );

MediaActionButtons _buttons(WidgetTester tester) =>
    tester.widget<MediaActionButtons>(find.byType(MediaActionButtons));

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

AnimatedOpacity _reveal(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_revealKey));

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
}

Future<void> _tabUntil(WidgetTester tester, FocusNode target) async {
  for (var step = 0; step < 8 && !target.hasFocus; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _motion(tester);
  }
  expect(target.hasFocus, isTrue, reason: 'The real toolbar must be tabbable');
}

/// Real document/transactions and real block widgets; only the unmounted
/// editor's selection service and document/workspace backends are substituted.
class _Fixture {
  _Fixture({
    required this.node,
    this.realBlock = false,
    bool editable = true,
    UserProfilePB? workspaceProfile,
    UserProfilePB? documentProfile,
  }) {
    editor = _Editor(node)..editable = editable;
    imageOwner = _ImageOwner(editor);
    galleryOwner = _GalleryOwner(editor);
    workspace = workspaceProfile == null ? null : _Workspace(workspaceProfile);
    document = realBlock || documentProfile != null
        ? _Document(documentProfile)
        : null;
  }

  final Node node;
  final bool realBlock;
  final actions = _MediaActions();
  final revision = ValueNotifier(0);
  final singleKey = GlobalKey<CustomImageBlockComponentState>();
  final galleryKey = GlobalKey<MultiImageBlockComponentState>();
  final before = FocusNode();
  final after = FocusNode();
  late final _Editor editor;
  late final _ImageOwner imageOwner;
  late final _GalleryOwner galleryOwner;
  late final _Workspace? workspace;
  late final _Document? document;
  bool show = true;

  bool get gallery => node.type == MultiImageBlockKeys.type;
  ValueNotifier<int> get index => realBlock
      ? galleryKey.currentState!.indexNotifier
      : galleryOwner.indexNotifier;

  void rebuild() => revision.value++;

  void replaceImages(List<ImageBlockData> images) {
    node.updateAttributes({
      ...node.attributes,
      if (gallery)
        MultiImageBlockKeys.images: MultiImageData(images: images).toJson()
      else ...{
        CustomImageBlockKeys.url: images.first.url,
        CustomImageBlockKeys.imageType: images.first.type.toIntValue(),
      },
    });
    rebuild();
  }

  Widget build({bool traversal = false}) {
    Widget child = ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (_, __, ___) => RepaintBoundary(
        key: _captureKey,
        child: SizedBox(
          width: 520,
          child: !show
              ? const SizedBox.shrink()
              : realBlock
                  ? _block()
                  : Align(
                      alignment: Alignment.topRight,
                      heightFactor: 1,
                      child: gallery
                          ? MultiImageMenu(
                              node: node,
                              state: galleryOwner,
                              indexNotifier: galleryOwner.indexNotifier,
                              onImageDeleted: () {},
                              mediaActions: actions,
                            )
                          : ImageMenu(
                              node: node,
                              state: imageOwner,
                              imageStateNotifier: imageOwner.imageStateNotifier,
                              mediaActions: actions,
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
              child: const Text('Before image'),
            ),
            child,
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After image'),
            ),
          ],
        ),
      );
    }
    if (workspace != null) {
      child = BlocProvider<UserWorkspaceBloc>.value(
        value: workspace!,
        child: child,
      );
    }
    if (document != null) {
      child = BlocProvider<DocumentBloc>.value(value: document!, child: child);
    }
    return RepositoryProvider<EditorState>.value(value: editor, child: child);
  }

  Widget _block() => gallery
      ? MultiImageBlockComponent(
          key: galleryKey,
          node: node,
          showMenu: true,
          menuBuilder: (node, state, index, onDeleted) => Positioned(
            top: 10,
            right: 10,
            child: MultiImageMenu(
              node: node,
              state: state,
              indexNotifier: index,
              onImageDeleted: onDeleted,
              mediaActions: actions,
            ),
          ),
        )
      : CustomImageBlockComponent(
          key: singleKey,
          node: node,
          showMenu: true,
          menuBuilder: (node, state, imageState) => ImageMenu(
            node: node,
            state: state,
            imageStateNotifier: imageState,
            mediaActions: actions,
          ),
        );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final call in actions.calls) {
      if (!call.completion.isCompleted) call.succeed();
    }
    await tester.pump();
    if (workspace != null) await tester.runAsync(workspace!.close);
    if (document != null) await tester.runAsync(document!.close);
    editor.dispose();
    revision.dispose();
    imageOwner.imageStateNotifier.dispose();
    galleryOwner.showActionsNotifier.dispose();
    galleryOwner.indexNotifier.dispose();
    before.dispose();
    after.dispose();
  }
}

class _Editor extends EditorState {
  _Editor(Node node)
      : super(document: Document(root: pageNode(children: [node]))) {
    editorStyle = const EditorStyle.desktop();
    disableSealTimer = true;
  }

  @override
  // ignore: overridden_fields
  final _EditorService service = _EditorService();
}

class _EditorService extends EditorService {
  final selections = _Selections();

  @override
  AppFlowySelectionService get selectionService => selections;
}

class _Selections extends Fake implements AppFlowySelectionService {
  final interceptors = <String, SelectionGestureInterceptor>{};

  @override
  void registerGestureInterceptor(SelectionGestureInterceptor interceptor) {
    interceptors[interceptor.key] = interceptor;
  }

  @override
  void unregisterGestureInterceptor(String key) => interceptors.remove(key);
}

class _ImageOwner extends Fake implements CustomImageBlockComponentState {
  _ImageOwner(this.editorState);

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_ImageOwner';

  @override
  final EditorState editorState;
  @override
  final imageStateNotifier = ValueNotifier(ResizableImageState.loading);
  @override
  bool alwaysShowMenu = false;
  @override
  void requestCaptionFocus() {}
}

class _GalleryOwner extends Fake implements MultiImageBlockComponentState {
  _GalleryOwner(this.editorState);

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_GalleryOwner';

  @override
  final EditorState editorState;
  @override
  final showActionsNotifier = ValueNotifier(true);
  @override
  final indexNotifier = ValueNotifier(0);
  @override
  bool alwaysShowMenu = false;
}

class _Workspace extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _Workspace(UserProfilePB profile)
      : super(UserWorkspaceState.initial(profile));

  void updateProfile(UserProfilePB profile) =>
      emit(state.copyWith(userProfile: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document extends Cubit<DocumentState> implements DocumentBloc {
  _Document(UserProfilePB? profile)
      : super(DocumentState.initial().copyWith(userProfilePB: profile));

  @override
  bool get isLocalMode => true;

  void updateProfile(UserProfilePB profile) =>
      emit(state.copyWith(userProfilePB: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  void fail() =>
      completion.completeError(StateError('Synthetic media failure'));
}

class _ClipboardSpy extends Fake implements ClipboardService {
  final writes = <ClipboardServiceData>[];

  @override
  Future<void> setData(ClipboardServiceData data) async => writes.add(data);
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
  _Fixture fixture, {
  List<File> photos = const [],
  String mode = 'light',
  double scale = 1,
  bool traversal = false,
}) async {
  // Warm only our synthetic local providers, on the real IO clock. This makes
  // the actual image widgets synchronous without substituting their layout.
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
          builder: (context, child) => AppFlowyTheme(
            data: appTheme,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Center(child: fixture.build(traversal: traversal)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<List<int>> _solidPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFFCA7945), BlendMode.src);
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
