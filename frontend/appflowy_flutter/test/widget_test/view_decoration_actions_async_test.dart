import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

// Only the storage boundary is fake. These tests mount the real action State,
// retain its actual picker/button callbacks, and control each async boundary.
// XFile is just a selection value: no file, FFI, network or live preferences.
const _source = r'C:\picked\original.png';
const _previousA = PageStyleCover(
  type: PageStyleCoverImageType.localImage,
  value: r'C:\covers\old-a.png',
);
const _previousB = PageStyleCover(
  type: PageStyleCoverImageType.localImage,
  value: r'C:\covers\old-b.png',
);
const _otherCover = PageStyleCover(
  type: PageStyleCoverImageType.localImage,
  value: r'C:\covers\other-writer.png',
);
const _uploaded = PageStyleCover(
  type: PageStyleCoverImageType.localImage,
  value: r'C:\covers\new-copy.png',
);
const _cloudUpload = PageStyleCover(
  type: PageStyleCoverImageType.customImage,
  value: 'https://covers.invalid/A/new.png',
);
const _color = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#224466',
);

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    // This helper installs mock preferences and loads bundled assets only.
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    for (final cloud in [false, true]) {
      testWidgets(
          '$appearance: ${cloud ? 'cloud' : 'local'} replacement deletes only '
          'the captured old asset after successful save', (tester) async {
        final fixture = _Fixture();
        final backend = fixture.backend..delay(_Phase.save);
        final previous = cloud
            ? const PageStyleCover(
                type: PageStyleCoverImageType.customImage,
                value: 'https://covers.invalid/A/old.png',
              )
            : _previousA;
        final replacement = cloud ? _cloudUpload : _uploaded;
        fixture.view = _view('A', cover: previous);
        if (cloud) {
          backend.profile =
              UserProfilePB(workspaceType: WorkspaceTypePB.ServerW);
          backend.nextUpload = const ViewCoverUpload(cover: _cloudUpload);
        }
        final original = fixture.view.writeToBuffer();
        await fixture.mount(tester, appearance: appearance);
        await fixture.startLocal(tester);
        expect(backend.profileCalls, 1);
        expect(backend.uploads.single.$1, _source);
        expect(backend.uploads.single.$2.id, 'A');
        expect(backend.uploads.single.$2.cover, previous);
        expect(
          backend.uploads.single.$3.workspaceType,
          backend.profile.workspaceType,
        );
        expect(backend.saves.single.$1.id, 'A');
        expect(backend.saves.single.$1.cover, previous);
        expect(backend.saves.single.$2, replacement);
        expect(backend.saves.single.$1, isNot(same(fixture.view)));
        expect(fixture.updates, isEmpty);
        expect(backend.deleted, isEmpty);

        backend.complete(_Phase.save);
        await tester.pumpAndSettle();
        expect(fixture.callbackOwners, ['A']);
        expect(fixture.updates.single.id, 'A');
        expect(fixture.updates.single.cover, replacement);
        expect(fixture.updates.single.name, 'Page A');
        expect(backend.deleted, [previous]);
        expect(
          backend.events,
          ['profile', 'upload:A', 'save:A', 'saved:A', 'callback:A', 'delete'],
        );
        expect(fixture.view.writeToBuffer(), original);
        // Snapshotting must not freeze a protobuf owned by the host.
        expect(() => fixture.view.name = 'Still mutable', returnsNormally);
        expect(
          backend.deleted.map((cover) => cover.value),
          isNot(contains(_source)),
        );
        await fixture.dispose(tester);
      });
    }
  }

  for (final phase in _Phase.values) {
    for (final invalidation in _Invalidation.values) {
      testWidgets(
          '${phase.name}: ${invalidation.name} cancels retained cover work',
          (tester) async {
        final fixture = _Fixture();
        final backend = fixture.backend..delay(phase);
        await fixture.mount(tester);
        final state = tester.state(find.byType(ViewDecorationActions));
        await fixture.startLocal(tester);
        expect(backend.profileCalls, 1);
        expect(backend.uploads, hasLength(phase == _Phase.profile ? 0 : 1));
        expect(backend.saves, hasLength(phase == _Phase.save ? 1 : 0));
        expect(backend.deleted, isEmpty);

        await fixture.invalidate(tester, invalidation);
        if (invalidation == _Invalidation.disposed) {
          expect(state.mounted, isFalse);
        } else {
          expect(tester.state(find.byType(ViewDecorationActions)), same(state));
        }
        final authoritative = fixture.view.writeToBuffer();
        backend.complete(phase);
        await tester.pumpAndSettle();

        expect(fixture.updates, isEmpty);
        expect(fixture.callbackOwners, isEmpty);
        expect(fixture.view.writeToBuffer(), authoritative);
        expect(
          backend.saves.map((save) => save.$1.id),
          phase == _Phase.save ? ['A'] : isEmpty,
        );
        expect(backend.uploads.every((upload) => upload.$2.id == 'A'), isTrue);
        // Before dispatch a proven new copy can be discarded. After dispatch,
        // stale success may already reference it, so neither asset is removed.
        expect(backend.deleted, phase == _Phase.upload ? [_uploaded] : isEmpty);
        expect(backend.deleted, isNot(contains(_previousA)));
        expect(backend.deleted, isNot(contains(_previousB)));
        expect(find.byType(SnackBar), findsNothing);
        if (invalidation == _Invalidation.backendChanged) {
          expect(fixture.backend.events, isEmpty);
        }
        await fixture.dispose(tester);
      });
    }

    testWidgets(
        '${phase.name}: double activation cannot overlap any cover action',
        (tester) async {
      final fixture = _Fixture();
      final backend = fixture.backend..delay(phase);
      await fixture.mount(tester);
      final menu = await fixture.startLocal(tester);
      menu.onSelectedLocalImages([XFile(_source)]);
      menu.onSelectedColor!(_color.value);
      menu.onSelectedNetworkImage(_cloudUpload.value);
      // This is the NEW build's callback, not just an invalidated old menu.
      fixture.remove(tester)();
      await tester.tap(_action(FlowySvgs.add_cover_s));
      await tester.pumpAndSettle();
      expect(find.byType(UploadImageMenu), findsNothing);
      expect(backend.profileCalls, 1);
      expect(backend.uploads.length, phase == _Phase.profile ? 0 : 1);
      expect(backend.saves.length, phase == _Phase.save ? 1 : 0);
      backend.complete(phase);
      await tester.pumpAndSettle();
      expect(backend.uploads, hasLength(1));
      expect(backend.saves, hasLength(1));
      expect(backend.deleted, [_previousA]);
      expect(fixture.updates.single.cover, _uploaded);
      // A cached callback remains spent after the request finishes.
      menu.onSelectedLocalImages([XFile(_source)]);
      await tester.pumpAndSettle();
      expect(backend.profileCalls, 1);
      await fixture.dispose(tester);
    });
  }

  for (final invalidation in _Invalidation.values) {
    testWidgets(
        'callbacks selected after ${invalidation.name} do not start work',
        (tester) async {
      final fixture = _Fixture();
      final backend = fixture.backend;
      await fixture.mount(tester);
      final remove = fixture.remove(tester);
      final menu = await fixture.open(tester);
      await fixture.invalidate(tester, invalidation);
      menu.onSelectedLocalImages([XFile(_source)]);
      menu.onSelectedNetworkImage(_cloudUpload.value);
      menu.onSelectedColor!(_color.value);
      remove();
      await tester.pumpAndSettle();
      expect(backend.events, isEmpty);
      expect(fixture.backend.events, isEmpty);
      expect(fixture.updates, isEmpty);
      await fixture.dispose(tester);
    });
  }

  testWidgets('already locked or host-disabled actions cannot open an upload',
      (tester) async {
    final fixture = _Fixture()..view = (_view('A')..isLocked = true);
    await fixture.mount(tester);
    expect(_action(FlowySvgs.add_cover_s), findsNothing);
    expect(_action(FlowySvgs.delete_s), findsNothing);
    fixture.rebuild(() {
      fixture.view = _view('A');
      fixture.showCoverAction = false;
    });
    await tester.pumpAndSettle();
    expect(_action(FlowySvgs.add_cover_s), findsNothing);
    expect(_action(FlowySvgs.delete_s), findsNothing);
    expect(fixture.backend.events, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets('an empty target id cannot activate storage', (tester) async {
    final fixture = _Fixture()..view = _view('');
    await fixture.mount(tester);
    await tester.tap(_action(FlowySvgs.add_cover_s));
    fixture.remove(tester)();
    await tester.pumpAndSettle();
    expect(find.byType(UploadImageMenu), findsNothing);
    expect(fixture.backend.events, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets('same-owner metadata updates survive upload, save and callback',
      (tester) async {
    final fixture = _Fixture();
    final backend = fixture.backend..delay(_Phase.profile);
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    final renamed = _copy(fixture.view)
      ..name = 'Renamed during profile lookup'
      ..icon = EmojiIconData.emoji('🌿').toViewIcon()
      ..extra = ViewCoverCodec.mergeCover('{"unrelated":42}', _previousA);
    await fixture.setView(tester, renamed);
    backend.complete(_Phase.profile);
    // The next boundary is independently held while the same request continues.
    backend.delay(_Phase.save);
    await tester.pumpAndSettle();
    expect(backend.uploads.single.$2.name, 'Page A');
    expect(backend.uploads.single.$2.cover, _previousA);
    expect(backend.saves.single.$1.id, 'A');
    expect(
      ViewCoverCodec.decodeExtra(backend.saves.single.$1.extra)['unrelated'],
      42,
    );
    await fixture.setView(tester, _copy(renamed)..name = 'Renamed during save');
    backend.complete(_Phase.save);
    await tester.pumpAndSettle();
    expect(fixture.updates.single.name, 'Renamed during save');
    expect(fixture.updates.single.icon, renamed.icon);
    expect(
      ViewCoverCodec.decodeExtra(fixture.updates.single.extra)['unrelated'],
      42,
    );
    expect(fixture.updates.single.cover, _uploaded);
    expect(backend.deleted, [_previousA]);
    await fixture.dispose(tester);
  });

  testWidgets('table cover marker shares one save and keeps newer extra',
      (tester) async {
    final fixture = _Fixture()
      ..view = (_view('A', cover: null)
        ..layout = ViewLayoutPB.Grid
        ..extra = '{"appflowy_map":{"zoom":4},"unrelated":42}')
      ..markCoverChosen = true;
    final backend = fixture.backend..delay(_Phase.save);
    final original = fixture.view.writeToBuffer();
    await fixture.mount(tester);
    (await fixture.open(tester)).onSelectedColor!(_color.value);
    await tester.pumpAndSettle();
    expect(backend.saves, hasLength(1));
    final sent = ViewCoverCodec.decodeExtra(backend.saves.single.$1.extra);
    expect(sent[AutomaticViewCover.chosenByHandKey], isTrue);
    expect(sent['appflowy_map'], {'zoom': 4});
    expect(sent['unrelated'], 42);
    expect(fixture.view.writeToBuffer(), original);
    await fixture.setView(
      tester,
      _copy(fixture.view)
        ..name = 'Newer table name'
        ..extra = '{"appflowy_map":{"zoom":8},"unrelated":99}',
    );
    backend.complete(_Phase.save);
    await tester.pumpAndSettle();
    final updated = fixture.updates.single;
    expect(backend.saves, hasLength(1));
    expect(updated.name, 'Newer table name');
    expect(updated.cover, _color);
    expect(AutomaticViewCover.showsCover(updated), isTrue);
    expect(
      ViewCoverCodec.decodeExtra(updated.extra)['appflowy_map'],
      {'zoom': 8},
    );
    expect(ViewCoverCodec.decodeExtra(updated.extra)['unrelated'], 99);
    expect(backend.deleted, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets(
      'an in-place target mutation before rebuild cannot retarget an upload',
      (tester) async {
    final fixture = _Fixture();
    final backend = fixture.backend..delay(_Phase.upload);
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    final uploadTarget = backend.uploads.single.$2;
    fixture.view
      ..id = 'B'
      ..extra = ViewCoverCodec.mergeCover('', _previousB);
    backend.complete(_Phase.upload);
    await tester.pumpAndSettle();
    expect(uploadTarget.id, 'A');
    expect(uploadTarget.cover, _previousA);
    expect(backend.saves, isEmpty);
    expect(backend.deleted, [_uploaded]);
    expect(fixture.updates, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets(
      'a matching authoritative cover echo still invalidates old-asset cleanup',
      (tester) async {
    final fixture = _Fixture();
    final backend = fixture.backend..delay(_Phase.save);
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    await fixture.setView(tester, _view('A', cover: _uploaded));
    backend.complete(_Phase.save);
    await tester.pumpAndSettle();
    expect(fixture.view.cover, _uploaded);
    expect(fixture.updates, isEmpty);
    expect(backend.deleted, isEmpty);
    await fixture.dispose(tester);
  });

  for (final change in ['target', 'lock', 'cover']) {
    testWidgets(
        'a synchronous callback $change change suppresses old-asset deletion',
        (tester) async {
      final fixture = _Fixture();
      fixture.afterChange = (_) {
        switch (change) {
          case 'target':
            fixture.view.id = 'B';
          case 'lock':
            fixture.view.isLocked = true;
          case 'cover':
            fixture.view.extra = ViewCoverCodec.mergeCover('', _otherCover);
        }
      };
      await fixture.mount(tester);
      final menu = await fixture.open(tester);
      menu.onSelectedColor!(_color.value);
      await tester.pumpAndSettle();
      expect(fixture.updates.single.id, 'A');
      expect(fixture.updates.single.cover, _color);
      expect(fixture.backend.deleted, isEmpty);
      await fixture.dispose(tester);
    });
  }

  for (final entry in [
    (name: 'color', replacement: _color),
    (
      name: 'network',
      replacement: const PageStyleCover(
        type: PageStyleCoverImageType.unsplashImage,
        value: 'https://covers.invalid/selected.png',
      ),
    ),
    (name: 'remove', replacement: const PageStyleCover.none()),
  ]) {
    for (final rebound in [false, true]) {
      testWidgets(
          '${entry.name}: delayed save respects target (rebound=$rebound)',
          (tester) async {
        final fixture = _Fixture();
        final backend = fixture.backend..delay(_Phase.save);
        await fixture.mount(tester);
        if (entry.name == 'remove') {
          await tester.tap(_action(FlowySvgs.delete_s));
        } else {
          final menu = await fixture.open(tester);
          if (entry.name == 'color') {
            menu.onSelectedColor!(entry.replacement.value);
          } else {
            menu.onSelectedNetworkImage(entry.replacement.value);
          }
        }
        await tester.pumpAndSettle();
        fixture.remove(tester)();
        expect(backend.profileCalls, 0);
        expect(backend.uploads, isEmpty);
        expect(backend.saves.single.$1.id, 'A');
        expect(backend.saves.single.$2, entry.replacement);
        expect(backend.deleted, isEmpty);
        if (rebound) {
          await fixture.setView(tester, _view('B', cover: _previousB));
        }
        backend.complete(_Phase.save);
        await tester.pumpAndSettle();
        expect(backend.deleted, rebound ? isEmpty : [_previousA]);
        expect(fixture.updates, hasLength(rebound ? 0 : 1));
        if (!rebound) expect(fixture.updates.single.cover, entry.replacement);
        await fixture.dispose(tester);
      });
    }
  }

  for (final previous in <PageStyleCover?>[
    null,
    const PageStyleCover.none(),
    const PageStyleCover(type: PageStyleCoverImageType.localImage, value: ''),
    _color,
    const PageStyleCover(
      type: PageStyleCoverImageType.gradientColor,
      value: '1',
    ),
    const PageStyleCover(
      type: PageStyleCoverImageType.builtInImage,
      value: 'n1',
    ),
    const PageStyleCover(
      type: PageStyleCoverImageType.unsplashImage,
      value: 'https://covers.invalid/external.png',
    ),
  ]) {
    testWidgets(
        'non-owned or empty previous cover ${previous?.type} is never deleted',
        (tester) async {
      final fixture = _Fixture()..view = _view('A', cover: previous);
      await fixture.mount(tester);
      (await fixture.open(tester)).onSelectedColor!('#668844');
      await tester.pumpAndSettle();
      expect(fixture.updates, hasLength(1));
      expect(fixture.backend.deleted, isEmpty);
      await fixture.dispose(tester);
    });
  }

  testWidgets('replacement reusing the same cloud URL keeps the asset',
      (tester) async {
    final fixture = _Fixture()..view = _view('A', cover: _cloudUpload);
    await fixture.mount(tester);
    (await fixture.open(tester)).onSelectedNetworkImage(_cloudUpload.value);
    await tester.pumpAndSettle();
    expect(fixture.updates.single.cover!.isUnsplashImage, isTrue);
    expect(fixture.backend.deleted, isEmpty);
    await fixture.dispose(tester);
  });

  for (final entry in [
    (name: 'unproven copy', cover: _uploaded, owned: false),
    (name: 'cloud reuse', cover: _cloudUpload, owned: false),
    (
      name: 'original',
      cover: const PageStyleCover(
        type: PageStyleCoverImageType.localImage,
        value: _source,
      ),
      owned: true,
    ),
    (
      name: 'original file URI alias',
      cover: const PageStyleCover(
        type: PageStyleCoverImageType.localImage,
        value: 'file:///C:/picked/../picked/original.png',
      ),
      owned: true,
    ),
    (name: 'original cover', cover: _previousA, owned: true),
    (name: 'rebound page cover', cover: _previousB, owned: true),
  ]) {
    testWidgets('abandoned upload never deletes ${entry.name}', (tester) async {
      final fixture = _Fixture();
      final backend = fixture.backend
        ..delay(_Phase.upload)
        ..nextUpload =
            ViewCoverUpload(cover: entry.cover, newlyCreated: entry.owned);
      await fixture.mount(tester);
      await fixture.startLocal(tester);
      await fixture.setView(tester, _view('B', cover: _previousB));
      backend.complete(_Phase.upload);
      await tester.pumpAndSettle();
      expect(backend.saves, isEmpty);
      expect(backend.deleted, isEmpty);
      expect(fixture.updates, isEmpty);
      await fixture.dispose(tester);
    });
  }

  testWidgets(
      'an asset observed on an intermediate page is protected after another rebind',
      (tester) async {
    final fixture = _Fixture();
    final backend = fixture.backend..delay(_Phase.upload);
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    await fixture.setView(tester, _view('B', cover: _uploaded));
    await fixture.setView(tester, _view('C', cover: _previousB));
    backend.complete(_Phase.upload);
    await tester.pumpAndSettle();
    expect(backend.deleted, isEmpty);
    expect(backend.saves, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets(
      'choosing the existing cover as source never deletes the original file',
      (tester) async {
    final fixture = _Fixture()
      ..view = _view(
        'A',
        cover: const PageStyleCover(
          type: PageStyleCoverImageType.localImage,
          value: _source,
        ),
      );
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    expect(fixture.updates.single.cover, _uploaded);
    expect(fixture.backend.deleted, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets(
      'cleanup is serialized and a rebound target works once cleanup finishes',
      (tester) async {
    final fixture = _Fixture();
    final backend = fixture.backend
      ..delay(_Phase.upload)
      ..deleteGate = Completer<void>();
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    await fixture.setView(tester, _view('B', cover: _previousB));
    backend.complete(_Phase.upload);
    await tester.pumpAndSettle();
    expect(backend.deleted, [_uploaded]);
    fixture.remove(tester)();
    await tester.pumpAndSettle();
    expect(backend.saves, isEmpty);
    backend.deleteGate!.complete();
    await tester.pumpAndSettle();
    await tester.tap(_action(FlowySvgs.delete_s));
    await tester.pumpAndSettle();
    expect(backend.saves.single.$1.id, 'B');
    expect(fixture.updates.single.id, 'B');
    expect(fixture.updates.single.cover!.isNone, isTrue);
    expect(backend.deleted, [_uploaded, _previousB]);
    await fixture.dispose(tester);
  });

  for (final failure in ['profile', 'upload', 'save', 'save throw']) {
    testWidgets(
        '$failure failure protects old assets and releases the request lock',
        (tester) async {
      final fixture = _Fixture();
      final backend = fixture.backend;
      switch (failure) {
        case 'profile':
          backend.profileFailure = FlowyError(msg: 'Profile refused');
        case 'upload':
          backend.nextUpload = null;
        case 'save':
          backend.saveResult =
              FlowyResult.failure(FlowyError(msg: 'Save refused'));
        case 'save throw':
          backend.throwAt = _Phase.save;
      }
      await fixture.mount(tester);
      await fixture.startLocal(tester);
      expect(fixture.updates, isEmpty);
      expect(fixture.view.cover, _previousA);
      expect(backend.deleted, failure == 'save' ? [_uploaded] : isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      backend
        ..profileFailure = null
        ..saveResult = FlowyResult.success(null)
        ..throwAt = null;
      // Retry through a newly built native action rather than a private method.
      await tester.tap(_action(FlowySvgs.delete_s));
      await tester.pumpAndSettle();
      expect(fixture.updates.single.cover!.isNone, isTrue);
      expect(backend.deleted.last, _previousA);
      await fixture.dispose(tester);
    });
  }

  for (final phase in _Phase.values) {
    testWidgets(
        '${phase.name}: stale exceptions never report an error on the new page',
        (tester) async {
      final fixture = _Fixture();
      final backend = fixture.backend..delay(phase);
      await fixture.mount(tester);
      await fixture.startLocal(tester);
      await fixture.setView(tester, _view('B', cover: _previousB));
      backend.complete(phase, error: StateError('Old request failed'));
      await tester.pumpAndSettle();
      expect(fixture.updates, isEmpty);
      expect(backend.deleted, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await fixture.dispose(tester);
    });
  }

  testWidgets(
      'failed stale save only discards its new copy, never either previous cover',
      (tester) async {
    final fixture = _Fixture();
    final backend = fixture.backend..delay(_Phase.save);
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    await fixture.setView(tester, _view('B', cover: _previousB));
    backend.saveResult = FlowyResult.failure(FlowyError(msg: 'Save refused'));
    backend.complete(_Phase.save);
    await tester.pumpAndSettle();
    expect(backend.deleted, [_uploaded]);
    expect(fixture.updates, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets('a rejected cloud save does not roll back an unproven upload',
      (tester) async {
    final fixture = _Fixture();
    fixture.backend
      ..nextUpload = const ViewCoverUpload(cover: _cloudUpload)
      ..saveResult = FlowyResult.failure(FlowyError(msg: 'Save refused'));
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    expect(fixture.updates, isEmpty);
    expect(fixture.backend.deleted, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets('asset cleanup errors do not undo or misreport a successful save',
      (tester) async {
    final fixture = _Fixture();
    fixture.backend.deleteError = StateError('Delete refused');
    await fixture.mount(tester);
    await fixture.startLocal(tester);
    expect(fixture.updates.single.cover, _uploaded);
    expect(fixture.backend.deleted, [_previousA]);
    expect(find.byType(SnackBar), findsNothing);
    await fixture.dispose(tester);
  });

  testWidgets(
      'empty local selection performs no work and keeps the menu usable',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    final menu = await fixture.open(tester);
    menu.onSelectedLocalImages([]);
    await tester.pumpAndSettle();
    expect(fixture.backend.events, isEmpty);
    expect(find.byType(UploadImageMenu), findsOneWidget);
    menu.onSelectedColor!(_color.value);
    await tester.pumpAndSettle();
    expect(fixture.updates.single.cover, _color);
    await fixture.dispose(tester);
  });

  testWidgets(
      'cover-only rebinding retains an open icon picker and its reveal hold',
      (tester) async {
    final fixture = _Fixture()
      ..showIconAction = true
      ..visible = false;
    await fixture.mount(tester);
    // Keyboard focus reveals an otherwise hidden action row without preferences.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final pickerState = tester.state(find.byType(FlowyIconEmojiPicker));
    await fixture.setView(tester, _view('A', cover: _otherCover));
    expect(tester.state(find.byType(FlowyIconEmojiPicker)), same(pickerState));
    expect(
      tester.widget<PreviewToolbar>(find.byType(PreviewToolbar)).keepVisible,
      isTrue,
    );
    expect(fixture.backend.events, isEmpty);
    await fixture.dispose(tester);
  });

  testWidgets('icon keepOpen saves survive same-view icon and cover updates',
      (tester) async {
    var view = _view('A');
    final writes = <String>[];
    late StateSetter rebuild;
    Future<FlowyResult<void, FlowyError>> saveIcon({
      required ViewPB view,
      required EmojiIconData viewIcon,
    }) async {
      writes.add(view.id);
      return FlowyResult.success(null);
    }

    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return ViewIconPicker(
              view: view,
              updateIcon: saveIcon,
              onViewChanged: (updated) => rebuild(() => view = updated),
              child: const SizedBox.square(
                dimension: 40,
                child: Icon(Icons.folder_rounded),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ViewIconPicker));
    await tester.pumpAndSettle();
    final pickerState = tester.state(find.byType(FlowyIconEmojiPicker));
    final select = tester
        .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
        .onSelectedEmoji!;
    select(EmojiIconData.emoji('🌿').toSelectedResult(keepOpen: true));
    await tester.pumpAndSettle();
    expect(view.icon, EmojiIconData.emoji('🌿').toViewIcon());
    rebuild(
      () => view = _copy(view)
        ..extra = ViewCoverCodec.mergeCover(view.extra, _otherCover),
    );
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FlowyIconEmojiPicker)), same(pickerState));
    select(EmojiIconData.emoji('📘').toSelectedResult(keepOpen: true));
    await tester.pumpAndSettle();
    expect(writes, ['A', 'A']);
    expect(view.cover, _otherCover);
    expect(view.icon, EmojiIconData.emoji('📘').toViewIcon());
    expect(tester.state(find.byType(FlowyIconEmojiPicker)), same(pickerState));
    expect(tester.takeException(), isNull);
    await disposeVividIconPicker(tester);
  });
}

enum _Phase { profile, upload, save }

enum _Invalidation {
  rebound,
  reboundBack,
  locked,
  lockedThenUnlocked,
  hidden,
  backendChanged,
  coverChanged,
  coverTypeChanged,
  coverChangedBack,
  inPlaceCoverChanged,
  disposed,
}

Finder _action(FlowySvgData icon) => find.byWidgetPredicate(
      (widget) => widget is DecorationActionButton && widget.icon == icon,
    );

ViewPB _view(String id, {PageStyleCover? cover = _previousA}) => ViewPB(
      id: id,
      name: 'Page $id',
      extra: cover == null ? '' : ViewCoverCodec.mergeCover('', cover),
    );

ViewPB _copy(ViewPB view) => ViewPB.fromBuffer(view.writeToBuffer());

class _Fixture {
  ViewPB view = _view('A');
  _Backend backend = _Backend();
  final updates = <ViewPB>[];
  final callbackOwners = <String>[];
  ValueChanged<ViewPB>? afterChange;
  bool showCoverAction = true;
  bool showIconAction = false;
  bool markCoverChosen = false;
  bool visible = true;
  bool present = true;
  late StateSetter rebuild;

  Future<void> mount(WidgetTester tester, {String appearance = 'paper'}) async {
    await tester.pumpWidget(
      vividIconTestApp(
        appearance,
        StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            final owner = view.id;
            final ownerBackend = backend;
            return SizedBox(
              width: 720,
              child: present
                  ? ViewDecorationActions(
                      key: const ValueKey('retained-actions'),
                      view: view,
                      coverBackend: backend,
                      showCoverAction: showCoverAction,
                      showIconAction: showIconAction,
                      markCoverChosen: markCoverChosen,
                      visible: visible,
                      onViewChanged: (updated) {
                        callbackOwners.add(owner);
                        updates.add(updated);
                        ownerBackend.events.add('callback:${updated.id}');
                        afterChange?.call(updated);
                      },
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<UploadImageMenu> open(WidgetTester tester) async {
    await tester.tap(_action(FlowySvgs.add_cover_s));
    await tester.pumpAndSettle();
    expect(find.byType(UploadImageMenu), findsOneWidget);
    return tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
  }

  Future<UploadImageMenu> startLocal(WidgetTester tester) async {
    final menu = await open(tester);
    menu.onSelectedLocalImages([XFile(_source)]);
    await tester.pumpAndSettle();
    return menu;
  }

  VoidCallback remove(WidgetTester tester) =>
      tester.widget<DecorationActionButton>(_action(FlowySvgs.delete_s)).onTap!;

  Future<void> setView(WidgetTester tester, ViewPB next) async {
    rebuild(() => view = next);
    await tester.pumpAndSettle();
  }

  Future<void> invalidate(WidgetTester tester, _Invalidation reason) async {
    final before = view;
    switch (reason) {
      case _Invalidation.rebound:
      case _Invalidation.reboundBack:
        await setView(tester, _view('B', cover: _previousB));
        if (reason == _Invalidation.reboundBack) await setView(tester, before);
      case _Invalidation.locked:
      case _Invalidation.lockedThenUnlocked:
        await setView(tester, _copy(before)..isLocked = true);
        if (reason == _Invalidation.lockedThenUnlocked) {
          await setView(tester, before);
        }
      case _Invalidation.hidden:
        rebuild(() => showCoverAction = false);
      case _Invalidation.backendChanged:
        rebuild(() => backend = _Backend());
      case _Invalidation.coverChanged:
      case _Invalidation.coverChangedBack:
        await setView(tester, _view('A', cover: _otherCover));
        if (reason == _Invalidation.coverChangedBack) {
          await setView(tester, before);
        }
      case _Invalidation.coverTypeChanged:
        await setView(
          tester,
          _view(
            'A',
            cover: PageStyleCover(
              type: PageStyleCoverImageType.customImage,
              value: _previousA.value,
            ),
          ),
        );
      case _Invalidation.inPlaceCoverChanged:
        rebuild(
          () => view.extra = ViewCoverCodec.mergeCover(view.extra, _otherCover),
        );
      case _Invalidation.disposed:
        // Mirrors a host removing the decorator after edit access is revoked.
        rebuild(() => present = false);
    }
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await disposeVividIconPicker(tester);
    expect(tester.takeException(), isNull);
  }
}

class _Backend extends ViewCoverActionsBackend {
  final events = <String>[];
  final uploads = <(String, ViewPB, UserProfilePB)>[];
  final saves = <(ViewPB, PageStyleCover)>[];
  final deleted = <PageStyleCover>[];
  int profileCalls = 0;
  UserProfilePB profile = UserProfilePB();
  FlowyError? profileFailure;
  ViewCoverUpload? nextUpload =
      const ViewCoverUpload(cover: _uploaded, newlyCreated: true);
  FlowyResult<void, FlowyError> saveResult = FlowyResult.success(null);
  _Phase? delayed;
  _Phase? throwAt;
  Object? deleteError;
  final profileGate = Completer<FlowyResult<UserProfilePB, FlowyError>>();
  final uploadGate = Completer<ViewCoverUpload?>();
  final saveGate = Completer<FlowyResult<void, FlowyError>>();
  Completer<void>? deleteGate;

  void delay(_Phase phase) => delayed = phase;

  void complete(_Phase phase, {Object? error}) {
    delayed = null;
    switch (phase) {
      case _Phase.profile:
        if (error != null) {
          profileGate.completeError(error);
        } else {
          profileGate.complete(FlowyResult.success(profile));
        }
      case _Phase.upload:
        if (error != null) {
          uploadGate.completeError(error);
        } else {
          uploadGate.complete(nextUpload);
        }
      case _Phase.save:
        if (error != null) {
          saveGate.completeError(error);
        } else {
          saveGate.complete(saveResult);
        }
    }
  }

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> currentUser() async {
    profileCalls++;
    events.add('profile');
    if (throwAt == _Phase.profile) throw StateError('Profile failed');
    if (delayed == _Phase.profile) return profileGate.future;
    final failure = profileFailure;
    return failure == null
        ? FlowyResult.success(profile)
        : FlowyResult.failure(failure);
  }

  @override
  Future<ViewCoverUpload?> upload({
    required String path,
    required ViewPB view,
    required UserProfilePB profile,
  }) async {
    events.add('upload:${view.id}');
    uploads.add((path, view, profile));
    if (throwAt == _Phase.upload) throw StateError('Upload failed');
    if (delayed == _Phase.upload) return uploadGate.future;
    return nextUpload;
  }

  @override
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) async {
    events.add('save:${view.id}');
    saves.add((view, cover));
    if (throwAt == _Phase.save) throw StateError('Save outcome unknown');
    final result = delayed == _Phase.save ? await saveGate.future : saveResult;
    events.add('saved:${view.id}');
    return result;
  }

  @override
  Future<void> delete(PageStyleCover cover) async {
    events.add('delete');
    deleted.add(cover);
    final error = deleteError;
    if (error != null) throw error;
    final gate = deleteGate;
    if (gate != null) await gate.future;
  }
}
