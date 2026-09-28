import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/bookmark/readable_article.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://news.example/article';
final _article = parseReadableArticle('<article><h1>Reader heading</h1>'
    '<p>Ordinary visible content from an already loaded page, saved without another request.</p>'
    '<img src="https://tracking.example/pixel"></article>');
BookmarkReaderCapture get _capture =>
    BookmarkReaderCapture(url: _url, generation: 1, article: _article);
ViewPB _view({String url = _url, String notes = 'Original notes'}) => ViewPB(
    id: 'bookmark',
    extra: BookmarkMetadata(
            url: url, notes: notes, readState: BookmarkReadState.reading)
        .mergeIntoExtra(''));

void main() {
  for (final denial in [
    'different captured source',
    'permission already revoked'
  ]) {
    test('$denial cannot start snapshot IO or publish metadata', () async {
      final store = _Store();
      final service = _Service();
      final controller = BookmarkController(service: service, snapshots: store)
        ..setViews([_view()]);
      try {
        final capture = denial == 'different captured source'
            ? BookmarkReaderCapture(
                url: 'https://news.example/followed',
                generation: 1,
                article: _article)
            : _capture;
        expect(
            await controller.saveReaderCapture(
                controller.entries.single, capture,
                isCurrent: () => denial != 'permission already revoked'),
            isFalse);
        expect(store.entered.isCompleted, isFalse);
        expect(service.writes, isEmpty);
        expect(controller.entries.single.metadata.snapshotPath, isNull);
        expect(controller.isWorking, isFalse);
      } finally {
        if (!store.gate.isCompleted) store.gate.complete(null);
        controller.dispose();
      }
    });
  }

  for (final invalidation in ['permission', 'url', 'removed', 'disposed']) {
    test('$invalidation while saving cannot publish or overwrite an old copy',
        () async {
      final store = _Store();
      final service = _Service();
      final controller = BookmarkController(service: service, snapshots: store)
        ..setViews([_view()]);
      var allowed = true;
      final pending = controller.saveReaderCapture(
          controller.entries.single, _capture,
          isCurrent: () => allowed);
      await store.entered.future;
      expect(store.isolated, isTrue);
      switch (invalidation) {
        case 'permission':
          allowed = false;
        case 'url':
          controller.setViews([_view(url: 'https://news.example/other')]);
        case 'removed':
          controller.setViews([]);
        case 'disposed':
          controller.dispose();
      }
      store.gate.complete(store.saved);
      expect(await pending, isFalse);
      expect(service.writes, isEmpty);
      expect(store.deleted, ['isolated-copy']);
      if (invalidation != 'disposed') controller.dispose();
    });
  }

  test('successful capture save merges latest metadata and never calls refresh',
      () async {
    final store = _Store();
    final service = _Service();
    final controller = BookmarkController(service: service, snapshots: store)
      ..setViews([_view()]);
    final pending = controller.saveReaderCapture(
        controller.entries.single, _capture,
        isCurrent: () => true);
    await store.entered.future;
    controller.setViews([_view(notes: 'A newer draft')]);
    store.gate.complete(store.saved);
    expect(await pending, isTrue);
    expect(service.writes.single.notes, 'A newer draft');
    expect(controller.entries.single.metadata.snapshotPath, 'isolated-copy');
    expect(store.deleted, isEmpty);
    expect(controller.isWorking, isFalse);
    controller.dispose();
  });

  test('backend failure cleans isolated copy and preserves metadata', () async {
    final store = _Store();
    final service = _Service()..fail = true;
    final controller = BookmarkController(service: service, snapshots: store)
      ..setViews([_view()]);
    final pending = controller.saveReaderCapture(
        controller.entries.single, _capture,
        isCurrent: () => true);
    await store.entered.future;
    store.gate.complete(store.saved);
    expect(await pending, isFalse);
    expect(controller.entries.single.metadata.snapshotPath, isNull);
    expect(store.deleted, ['isolated-copy']);
    expect(controller.isWorking, isFalse);
    controller.dispose();
  });

  test(
      'real disk copy is passive, text-only, independently readable and bounded',
      () async {
    final root = await Directory.systemTemp.createTemp('reader-offline-');
    final store = BookmarkSnapshotStore(rootOverride: root.path);
    try {
      final saved = await store.save(
          url: '$_url?token=private',
          article: _article,
          html: '<article onclick="bad()"><p>Article</p><script>secret</script>'
              '<form><input value="password"></form><img src="https://tracking.example/pixel"></article>',
          isolated: true);
      expect(saved?.articlePath, isNotNull);
      final markdown = await File(saved!.articlePath!).readAsString();
      expect(markdown, contains('Reader heading'));
      expect(markdown, isNot(contains('tracking.example')));
      expect(markdown, isNot(contains('token=private')));
      final html = await File(saved.pagePath!).readAsString();
      for (final value in [
        'onclick',
        '<script',
        '<form',
        '<img',
        'password',
        'secret'
      ]) {
        expect(html, isNot(contains(value)));
      }
      final read = await store.read(saved.directory);
      expect(await store.readArticleText(read!),
          contains('Ordinary visible content'));
      expect(
          await store.save(
              url: _url, article: _article, heroExtension: '../secret'),
          isNull);
      await File('${saved.directory}/snapshot.json')
          .writeAsString('invalid json');
      expect(await store.read(saved.directory), isNull);
    } finally {
      await root.delete(recursive: true);
    }
  });
}

class _Store extends BookmarkSnapshotStore {
  final entered = Completer<void>();
  final gate = Completer<BookmarkSnapshot?>();
  final deleted = <String?>[];
  bool isolated = false;
  final saved = BookmarkSnapshot(
      directory: 'isolated-copy',
      savedAt: DateTime(2026),
      bytes: 128,
      articlePath: 'isolated-copy/article.md');

  @override
  Future<BookmarkSnapshot?> save(
      {required String url,
      ReadableArticle? article,
      String? html,
      Uint8List? heroBytes,
      String heroExtension = 'jpg',
      bool isolated = false}) {
    this.isolated = isolated;
    entered.complete();
    return gate.future;
  }

  @override
  Future<void> delete(String? directoryPath) async {
    deleted.add(directoryPath);
  }
}

class _Service extends BookmarkService {
  final writes = <BookmarkMetadata>[];
  bool fail = false;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata(
      {required ViewPB view, required BookmarkMetadata metadata}) async {
    writes.add(metadata);
    return fail
        ? FlowyResult.failure(FlowyError(msg: 'test failure'))
        : FlowyResult.success(view);
  }
}
