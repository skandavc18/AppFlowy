import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/migration/editor_migration.dart';
import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy/shared/page_icon_size.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/page_icon_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('editor migration, from v0.1.x to 0.2', () {
    test('migrate readme', () async {
      final readme = await rootBundle.loadString('assets/template/readme.json');
      final oldDocument = DocumentV0.fromJson(json.decode(readme));
      final document = EditorMigration.migrateDocument(readme);
      expect(document.root.type, 'page');
      expect(oldDocument.root.children.length, document.root.children.length);
    });
  });

  group('legacy cover and page icon size metadata', () {
    test('size-only metadata has no cover; explicit none is present', () {
      final view = ViewPB(extra: IconSize.merge('', 113.75));
      expect(view.cover, isNull);
      view.extra = ViewCoverCodec.mergeCover(
        view.extra,
        const PageStyleCover.none(),
      );
      expect(view.cover, const PageStyleCover.none());
      expect(IconSize.decode(view.extra), 113.75);
    });

    test('migration rereads extra after a concurrent fractional icon save',
        () async {
      final stale = ViewPB(
        id: 'migration-size-race',
        name: 'Original title',
        extra: IconSize.merge('', 72.125),
      )..freeze();
      final snapshot = stale.writeToBuffer();
      final fresh = ViewPB.fromBuffer(snapshot)
        ..name = 'Newer title'
        ..extra = IconSize.merge(
          '{"font":"serif","future":{"retained":true}}',
          72.125,
        );
      final backend = PageIconMemoryBackend([fresh]);
      final barrier = Completer<void>();
      backend.readBarrier = barrier;
      final migrating = _migrateCover(stale, backend);
      await backend.readStarted.future;
      final icon = PageIconController(
        view: fresh,
        binding: Object(),
        editable: true,
        canEdit: () => true,
        onSaved: (_) {},
        isSameTarget: (_) => true,
        defaultSize: 56,
        backend: backend,
      );
      try {
        expect(await icon.saveSize(187.375), isTrue);
        barrier.complete();
        await migrating;
        expect(backend.writes, hasLength(2));
        final saved = backend.views[stale.id]!;
        expect(saved.name, 'Newer title');
        expect(
          saved.cover,
          const PageStyleCover(
            type: PageStyleCoverImageType.builtInImage,
            value: '1',
          ),
        );
        expect(ViewCoverCodec.decodeExtra(saved.extra), {
          'font': 'serif',
          'future': {'retained': true},
          IconSize.key: 187.375,
          'cover': {'type': 'built_in', 'value': '1'},
        });
        expect(stale.writeToBuffer(), snapshot);
      } finally {
        backend.releasePending();
        await migrating;
        icon.dispose();
      }
    });

    test('explicit none plus a legacy asset is never remigrated', () async {
      final view = ViewPB(
        id: 'explicit-none',
        extra: ViewCoverCodec.mergeCover(
          IconSize.merge('', 99.125),
          const PageStyleCover.none(),
        ),
      );
      final backend = PageIconMemoryBackend([view]);
      await _migrateCover(view, backend);
      expect(backend.reads, isEmpty);
      expect(backend.writes, isEmpty);
      expect(backend.views[view.id]!.cover, const PageStyleCover.none());
    });

    for (final cover in [
      const PageStyleCover.none(),
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#C0A080',
      ),
    ]) {
      test('fresh ${cover.type} overrides legacy despite a stale absent cover',
          () async {
        final stale =
            ViewPB(id: 'fresh-${cover.type}', extra: IconSize.merge('', 80));
        final fresh = ViewPB.fromBuffer(stale.writeToBuffer())
          ..extra =
              ViewCoverCodec.mergeCover(IconSize.merge('', 143.75), cover);
        final backend = PageIconMemoryBackend([fresh]);
        await _migrateCover(stale, backend);
        expect(backend.reads, [stale.id]);
        expect(backend.writes, isEmpty);
        expect(backend.views[stale.id]!.writeToBuffer(), fresh.writeToBuffer());
      });
    }

    test('an explicit cover edit still merges only cover into fresh extra',
        () async {
      final stale = ViewPB(
        id: 'cover-edit',
        extra: ViewCoverCodec.mergeCover('', const PageStyleCover.none()),
      );
      final fresh = ViewPB.fromBuffer(stale.writeToBuffer())
        ..extra = IconSize.merge(stale.extra, 205.375);
      final backend = PageIconMemoryBackend([fresh]);
      await _migrateCover(stale, backend, overwrite: true);
      expect(IconSize.decode(backend.writes.single.extra), 205.375);
      expect(backend.views[stale.id]!.cover!.value, '1');
    });

    for (final unavailable in [
      'missing',
      'locked',
      'replacement',
      'layout',
      'malformed',
    ]) {
      test('$unavailable fresh view refuses cover migration', () async {
        final stale = ViewPB(id: 'migration-$unavailable');
        final backend = PageIconMemoryBackend([stale]);
        switch (unavailable) {
          case 'missing':
            backend.views.clear();
          case 'locked':
            backend.views[stale.id]!.isLocked = true;
          case 'replacement':
            backend.views[stale.id]!.id = 'other';
          case 'layout':
            backend.views[stale.id]!.layout = ViewLayoutPB.Grid;
          case 'malformed':
            backend.views[stale.id]!.extra = 'not metadata';
        }
        await _migrateCover(stale, backend);
        expect(backend.writes, isEmpty);
      });
    }
  });
}

Future<void> _migrateCover(
  ViewPB view,
  PageIconMemoryBackend backend, {
  bool overwrite = false,
}) =>
    EditorMigration.migrateCoverIfNeeded(
      view,
      {
        DocumentHeaderBlockKeys.coverType: CoverType.asset.toString(),
        DocumentHeaderBlockKeys.coverDetails: '1',
      },
      overwrite: overwrite,
      readView: backend.readView,
      writeCover: ({required view, required cover}) => backend.updateView(
        viewId: view.id,
        extra: ViewCoverCodec.mergeCover(view.extra, cover),
      ),
    );
