import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/page_icon_size.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/page_cover_test_support.dart';

void main() {
  test('missing, malformed and future defaults are inert safe fallbacks', () {
    for (final raw in [
      null,
      '',
      'bad',
      '[]',
      'null',
      '{"version":2,"fit":"stretch"}'
    ]) {
      expect(CoverAppearance.decode(raw), CoverAppearance.defaults);
    }
    expect(
        CoverAppearance.decode(
                '{"version":1,"aspect_ratio":"3","fit":"unknown"}')
            .aspectRatio,
        isNull);
    expect(CoverAppearance.decode('{"version":1,"aspect_ratio":0}').aspectRatio,
        isNull);
    expect(CoverAppearance.decode('{"version":1,"aspect_ratio":7}').aspectRatio,
        isNull);
  });

  test('all typed appearances roundtrip and only stretch distorts art', () {
    for (final corners in CoverCorners.values) {
      for (final fit in CoverImageFit.values) {
        for (final position in CoverPosition.values) {
          final value = CoverAppearance(
              corners: corners,
              fit: fit,
              position: position,
              aspectRatio: 2.75);
          expect(CoverAppearance.decode(value.encode()), value);
          expect(value.boxFit == BoxFit.fill, fit == CoverImageFit.stretch);
        }
      }
    }
    expect(() => const CoverAppearance(aspectRatio: double.nan).encode(),
        throwsArgumentError);
  });

  test('height validation is continuous and actual-width bounded', () {
    for (final value in ['96', '123.456', '640']) {
      expect(PageCoverHeight.decode('{"page_cover_height":$value}'),
          double.parse(value));
    }
    for (final value in ['null', '"200"', '-1', '95', '641', '{}']) {
      expect(PageCoverHeight.decode('{"page_cover_height":$value}'), isNull);
    }
    expect(PageCoverHeight.decode('broken'), isNull);
    expect(
        PageCoverHeight.resolve(
            width: 900,
            appearance: const CoverAppearance(aspectRatio: 3),
            fallback: 200),
        300);
    expect(
        PageCoverHeight.resolve(
            width: 450,
            appearance: const CoverAppearance(aspectRatio: 3),
            fallback: 200),
        150);
    expect(
        PageCoverHeight.resolve(
            width: 450,
            appearance: const CoverAppearance(aspectRatio: 3),
            fallback: 200,
            override: 240.5),
        240.5);
    expect(
        PageCoverHeight.resolve(
            width: 120,
            appearance: CoverAppearance.defaults,
            fallback: 200,
            override: 600),
        120);
    expect(
        PageCoverHeight.resolve(
            width: 20, appearance: CoverAppearance.defaults, fallback: 200),
        96);
  });

  test('metadata merge/reset preserves every other field and explicit none',
      () {
    final original = jsonEncode({
      'cover': {'type': 'none', 'value': '', 'future': true},
      'page_icon_size': 72,
      'page_cover_position': -.4,
      'file_preview_metadata': {'zoom': 1.25},
      'appflowy_collection_source': {'readOnly': true},
      'unknown': [1, 'keep'],
    });
    final resized = PageCoverHeight.merge(original, 217.125);
    expect(ViewCoverCodec.decodeCover(resized), const PageStyleCover.none());
    expect(
        jsonDecode(PageCoverHeight.merge(resized, null)), jsonDecode(original));
    expect(() => PageCoverHeight.merge('broken', 200), throwsFormatException);
    expect(() => PageCoverHeight.merge('[]', null), throwsFormatException);
    expect(() => PageCoverHeight.merge('{}', double.infinity),
        throwsArgumentError);
    expect(ViewCoverCodec.decodeCover(PageCoverHeight.merge('', 200)), isNull,
        reason: 'A height override must never migrate a legacy node cover.');
  });

  test('local store reads do not resolve storage; failed loads can retry',
      () async {
    CoverMemoryStorage? storage;
    var resolves = 0;
    final store = CoverAppearanceStore(resolveStorage: () {
      resolves++;
      return storage;
    });
    addTearDown(store.dispose);
    expect(store.value, CoverAppearance.defaults);
    expect(resolves, 0);
    expect(await store.ensureLoaded(), isFalse);
    storage = CoverMemoryStorage();
    storage.values['unrelated'] = 'kept';
    expect(await store.ensureLoaded(), isTrue);
    expect(storage.writes, isEmpty);
    expect(
        await store.update((v) => v.copyWith(fit: CoverImageFit.fit)), isTrue);
    expect(storage.values['unrelated'], 'kept');
  });

  test('load, queued transforms and reset publish only after ACK', () async {
    final storage = CoverMemoryStorage()
      ..readGate = Completer<void>()
      ..writeGate = Completer<void>();
    storage.values[CoverAppearanceStore.storageKey] =
        const CoverAppearance(position: CoverPosition.top).encode();
    final store = CoverAppearanceStore(resolveStorage: () => storage);
    addTearDown(store.dispose);
    final first = store.update((v) => v.copyWith(corners: CoverCorners.square));
    final second = store.update((v) => v.copyWith(fit: CoverImageFit.fit));
    await storage.readStarted.future;
    expect(storage.writes, isEmpty);
    storage.readGate!.complete();
    await storage.writeStarted.future;
    expect(store.value.corners, CoverCorners.rounded);
    storage.writeGate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(
        store.value,
        const CoverAppearance(
            corners: CoverCorners.square,
            fit: CoverImageFit.fit,
            position: CoverPosition.top));
    final reopened = CoverAppearanceStore(resolveStorage: () => storage);
    addTearDown(reopened.dispose);
    await reopened.ensureLoaded();
    expect(reopened.value, store.value);
    expect(await store.reset(), isTrue);
    expect(store.value, CoverAppearance.defaults);
  });

  test('failed save never publishes and does not poison the queue', () async {
    final storage = CoverMemoryStorage()..failWrite = true;
    final store = CoverAppearanceStore(resolveStorage: () => storage);
    addTearDown(store.dispose);
    expect(await store.update((v) => v.copyWith(fit: CoverImageFit.stretch)),
        isFalse);
    expect(store.value, CoverAppearance.defaults);
    expect(store.failure, CoverAppearanceFailure.save);
    storage.failWrite = false;
    expect(
        await store.update((v) => v.copyWith(position: CoverPosition.bottom)),
        isTrue);
    expect(store.value.fit, CoverImageFit.crop);
    expect(store.value.position, CoverPosition.bottom);
  });

  test('reentrant store listeners cannot overtake the initiating write',
      () async {
    final storage = CoverMemoryStorage();
    final store = CoverAppearanceStore(resolveStorage: () => storage);
    addTearDown(store.dispose);
    await store.ensureLoaded();
    Future<bool>? second;
    var queued = false;
    store.addListener(() {
      if (store.isSaving && !queued) {
        queued = true;
        second = store.update((v) => v.copyWith(fit: CoverImageFit.fit));
      }
    });
    await store.update((v) => v.copyWith(corners: CoverCorners.square));
    await second;
    expect(store.value.corners, CoverCorners.square);
    expect(store.value.fit, CoverImageFit.fit);
    expect(storage.writes, hasLength(2));
  });

  test('false preference ACK reloads cache, retains publication and retries',
      () async {
    final preferences = _CoverPreferences();
    final storage = _CoverPreferenceStorage(preferences);
    final store = CoverAppearanceStore(resolveStorage: () => storage);
    addTearDown(store.dispose);
    await store.ensureLoaded();
    final published = <CoverAppearance>[];
    store.appearances.addListener(() => published.add(store.value));
    expect(
        await store.update((value) => value.copyWith(
              corners: CoverCorners.square,
              fit: CoverImageFit.stretch,
            )),
        isFalse);
    expect(store.value, CoverAppearance.defaults);
    expect(store.failure, CoverAppearanceFailure.save);
    expect(published, isEmpty);
    expect(preferences.reloads, 1);
    expect(preferences.cached, isNull);
    expect(preferences.persisted, isNull);

    preferences.acknowledge = true;
    expect(
        await store.update((value) => value.copyWith(
              corners: CoverCorners.square,
              aspectRatio: 3.25,
              fit: CoverImageFit.fit,
              position: CoverPosition.bottom,
            )),
        isTrue);
    expect(published, [store.value]);
    final reopened = CoverAppearanceStore(resolveStorage: () => storage);
    addTearDown(reopened.dispose);
    expect(await reopened.ensureLoaded(), isTrue);
    expect(reopened.value, store.value);
    expect(preferences.writes, 2);
    expect(await store.reset(), isTrue);
    expect(CoverAppearance.decode(preferences.persisted),
        CoverAppearance.defaults);
    expect(preferences.keys.toSet(), {CoverAppearanceStore.storageKey});
  });

  test('height write shares icon queue and re-reads metadata after its ACK',
      () async {
    final view = _view();
    final io = CoverMemoryViews(view)..writeGate = Completer<void>();
    final icon = io.save(
        view: view, size: 88, isCurrent: () => true, isSameTarget: (_) => true);
    await io.writeStarted.future;
    final cover = PageCoverBackendService(views: io).save(
        view: view,
        height: 321.75,
        isCurrent: () => true,
        isSameTarget: (_) => true);
    expect(io.reads, 1);
    io.writeGate!.complete();
    expect((await icon).fold((_) => true, (_) => false), isTrue);
    expect(await cover, isTrue);
    expect(IconSize.decode(io.view.extra), 88);
    expect(PageCoverHeight.decode(io.view.extra), 321.75);
    expect(io.view.name, 'Kept title');
    expect(jsonDecode(io.view.extra)['unknown'], {'keep': true});
  });

  for (final cause in [
    'locked',
    'source',
    'removed',
    'wrong-id',
    'malformed',
    'revoked'
  ]) {
    test('fresh $cause state rejects height write', () async {
      final view = _view();
      final io = CoverMemoryViews(view)..readGate = Completer<void>();
      var allowed = true;
      final pending = PageCoverBackendService(views: io).save(
          view: view,
          height: 250,
          isCurrent: () => allowed,
          isSameTarget: (_) => true);
      await io.readStarted.future;
      switch (cause) {
        case 'locked':
          io.view = ViewPB.fromBuffer(view.writeToBuffer())..isLocked = true;
        case 'source':
          io.view = ViewPB.fromBuffer(view.writeToBuffer())
            ..extra = '{"cover":{"type":"built_in","value":"n2"}}';
        case 'removed':
          io.view = ViewPB.fromBuffer(view.writeToBuffer())
            ..extra = '{"cover":{"type":"none","value":""}}';
        case 'wrong-id':
          io.wrongReadId = true;
        case 'malformed':
          io.view = ViewPB.fromBuffer(view.writeToBuffer())..extra = 'broken';
        case 'revoked':
          allowed = false;
      }
      io.readGate!.complete();
      expect(await pending, isFalse);
      expect(io.writes, isEmpty);
    });
  }

  test('controller previews/cancel never write and release saves once',
      () async {
    final io = CoverMemoryViews(_view());
    final saves = <double?>[];
    final controller = _controller(io, saves);
    addTearDown(controller.dispose);
    expect(controller.begin(200), isTrue);
    controller.preview(200.25);
    controller.preview(230.75);
    expect(io.writes, isEmpty);
    controller.cancel();
    expect(controller.height, isNull);
    expect(io.writes, isEmpty);
    controller.begin(200);
    controller.preview(240.5);
    expect(await controller.commit(), isTrue);
    expect(await controller.commit(), isFalse);
    expect(io.writes, hasLength(1));
    expect(saves, [240.5]);
    expect(await controller.save(null), isTrue);
    expect(PageCoverHeight.decode(io.view.extra), isNull);
  });

  test('revocation followed by grant cannot revive an older queued save',
      () async {
    final io = CoverMemoryViews(_view())..readGate = Completer<void>();
    final saves = <double?>[];
    final controller = _controller(io, saves);
    addTearDown(controller.dispose);
    final pending = controller.save(250);
    await io.readStarted.future;
    controller.setEditable(false);
    controller.setEditable(true);
    io.readGate!.complete();
    expect(await pending, isFalse);
    expect(io.writes, isEmpty);
    expect(saves, isEmpty);
  });

  test('source change and deletion cancel an active drag', () {
    final io = CoverMemoryViews(_view());
    final controller = _controller(io, []);
    addTearDown(controller.dispose);
    controller.begin(200);
    controller.preview(250);
    io.emit(ViewPB.fromBuffer(io.view.writeToBuffer())
      ..extra = '{"cover":{"type":"built_in","value":"n2"}}');
    expect(controller.isResizing, isFalse);
    expect(io.writes, isEmpty);
    controller.begin(200);
    io.unavailable.single();
    expect(controller.canResize, isFalse);
    expect(controller.isResizing, isFalse);
  });

  test('disposal rejects pending preflight and releases its listener',
      () async {
    final io = CoverMemoryViews(_view())..readGate = Completer<void>();
    final controller = _controller(io, []);
    final pending = controller.save(250);
    await io.readStarted.future;
    controller.dispose();
    io.readGate!.complete();
    expect(await pending, isFalse);
    expect(io.writes, isEmpty);
    expect(io.listeners, isEmpty);
  });
}

ViewPB _view() => ViewPB(
    id: 'cover-unit',
    name: 'Kept title',
    layout: ViewLayoutPB.Document,
    extra:
        '{"cover":{"type":"built_in","value":"n1"},"unknown":{"keep":true}}');

PageCoverController _controller(CoverMemoryViews io, List<double?> saves) =>
    PageCoverController(
      view: io.view,
      binding: io,
      editable: true,
      canEdit: () => true,
      isSameTarget: (_) => true,
      onSaved: saves.add,
      backend: PageCoverBackendService(views: io),
    );

/// Only the platform preference ACK/cache boundary is replaced. The actual
/// store still takes its DartKeyValue branch, including refusal recovery.
class _CoverPreferenceStorage extends DartKeyValue {
  _CoverPreferenceStorage(this.preferences);
  final _CoverPreferences preferences;

  @override
  SharedPreferences get sharedPreferences => preferences;

  @override
  Future<String?> get(String key) async => preferences.getString(key);
}

class _CoverPreferences extends Fake implements SharedPreferences {
  bool acknowledge = false;
  String? cached;
  String? persisted;
  int reloads = 0;
  int writes = 0;
  final keys = <String>[];

  @override
  String? getString(String key) => cached;

  @override
  Future<bool> setString(String key, String value) async {
    keys.add(key);
    writes++;
    cached = value;
    if (acknowledge) persisted = value;
    return acknowledge;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cached = persisted;
  }
}
