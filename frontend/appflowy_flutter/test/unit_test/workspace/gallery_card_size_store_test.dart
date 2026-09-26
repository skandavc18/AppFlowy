import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    getIt.pushNewScope();
    GalleryCardSizeStore.reset();
  });
  tearDown(() async {
    GalleryCardSizeStore.reset();
    await getIt.popScope();
  });

  for (final size in GalleryCardSize.values) {
    test('${size.name} round-trips through the real preference adapter',
        () async {
      SharedPreferences.setMockInitialValues({'unrelated-preference': 'keep'});
      getIt.registerSingleton<KeyValueStorage>(DartKeyValue());
      await GalleryCardSizeStore.ensureLoaded();
      await GalleryCardSizeStore.write(size);

      // Read through a fresh production adapter, not the notifier or a fake
      // settings payload. No native preferences or user files are touched.
      final reader = DartKeyValue();
      expect(await reader.get(kGalleryCardSizeKey), size.name);
      expect(await reader.get('unrelated-preference'), 'keep');
      GalleryCardSizeStore.reset();
      await GalleryCardSizeStore.ensureLoaded();
      expect(GalleryCardSizeStore.value, size);
    });
  }

  test('concurrent galleries await the same initial read', () async {
    final gate = Completer<String?>();
    final storage = _Storage()..readGate = gate;
    getIt.registerSingleton<KeyValueStorage>(storage);
    final first = GalleryCardSizeStore.ensureLoaded();
    var secondFinished = false;
    final second = GalleryCardSizeStore.ensureLoaded().then((_) {
      secondFinished = true;
    });
    await storage.readStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(storage.reads, 1);
    expect(secondFinished, isFalse);
    gate.complete('large');
    await Future.wait([first, second]);
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    expect(storage.writes, isEmpty);
  });

  test('a delayed initial read cannot undo a newer choice before its ACK',
      () async {
    final read = Completer<String?>();
    final ack = Completer<void>();
    final storage = _Storage()
      ..readGate = read
      ..writeGate = ack;
    getIt.registerSingleton<KeyValueStorage>(storage);
    final loading = GalleryCardSizeStore.ensureLoaded();
    var saved = false;
    final saving = GalleryCardSizeStore.write(GalleryCardSize.large).then((_) {
      saved = true;
    });
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    read.complete('small');
    await loading;
    await storage.writeStarted.future;
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    expect(saved, isFalse);
    expect(storage.values[kGalleryCardSizeKey], isNull);

    ack.complete();
    await saving;
    expect(storage.values[kGalleryCardSizeKey], 'large');
    GalleryCardSizeStore.reset();
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
  });

  test('rapid choices persist in request order and the last survives reload',
      () async {
    final ack = Completer<void>();
    final storage = _Storage()..writeGate = ack;
    getIt.registerSingleton<KeyValueStorage>(storage);
    await GalleryCardSizeStore.ensureLoaded();
    final first = GalleryCardSizeStore.write(GalleryCardSize.small);
    await storage.writeStarted.future;
    final second = GalleryCardSizeStore.write(GalleryCardSize.large);
    final third = GalleryCardSizeStore.write(GalleryCardSize.medium);
    await Future<void>.delayed(Duration.zero);
    expect(GalleryCardSizeStore.value, GalleryCardSize.medium);
    expect(storage.writes, [(kGalleryCardSizeKey, 'small')]);
    ack.complete();
    await Future.wait([first, second, third]);
    expect(storage.writes, [
      (kGalleryCardSizeKey, 'small'),
      (kGalleryCardSizeKey, 'large'),
      (kGalleryCardSizeKey, 'medium'),
    ]);
    GalleryCardSizeStore.reset();
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.medium);
  });

  test('a reentrant notifier listener cannot jump ahead of its triggering save',
      () async {
    final storage = _Storage();
    getIt.registerSingleton<KeyValueStorage>(storage);
    await GalleryCardSizeStore.ensureLoaded();
    Future<void>? next;
    void chooseAgain() {
      if (GalleryCardSizeStore.value == GalleryCardSize.small) {
        next = GalleryCardSizeStore.write(GalleryCardSize.large);
      }
    }

    GalleryCardSizeStore.notifier.addListener(chooseAgain);
    try {
      await GalleryCardSizeStore.write(GalleryCardSize.small);
      await next;
      expect(storage.writes, [
        (kGalleryCardSizeKey, 'small'),
        (kGalleryCardSizeKey, 'large'),
      ]);
      expect(storage.values[kGalleryCardSizeKey], 'large');
      expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    } finally {
      GalleryCardSizeStore.notifier.removeListener(chooseAgain);
    }
  });

  test('a failed latest save restores the last ACK and allows a retry',
      () async {
    final storage = _Storage()..values[kGalleryCardSizeKey] = 'small';
    getIt.registerSingleton<KeyValueStorage>(storage);
    await GalleryCardSizeStore.ensureLoaded();
    await GalleryCardSizeStore.write(GalleryCardSize.medium);
    final ack = Completer<void>();
    storage.writeGate = ack;
    final failed = expectLater(
      GalleryCardSizeStore.write(GalleryCardSize.large),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    ack.completeError(StateError('Rejected preference write'));
    await failed;
    expect(GalleryCardSizeStore.value, GalleryCardSize.medium);
    expect(storage.values[kGalleryCardSizeKey], 'medium');

    await GalleryCardSizeStore.write(GalleryCardSize.large);
    GalleryCardSizeStore.reset();
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
  });

  test('an older failed save does not roll back or block a newer choice',
      () async {
    final ack = Completer<void>();
    final storage = _Storage()
      ..values[kGalleryCardSizeKey] = 'small'
      ..writeGate = ack;
    getIt.registerSingleton<KeyValueStorage>(storage);
    await GalleryCardSizeStore.ensureLoaded();
    final first = expectLater(
      GalleryCardSizeStore.write(GalleryCardSize.medium),
      throwsStateError,
    );
    await storage.writeStarted.future;
    final second = GalleryCardSizeStore.write(GalleryCardSize.large);
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    ack.completeError(StateError('Older write failed'));
    await first;
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    await second;
    expect(storage.values[kGalleryCardSizeKey], 'large');
  });

  test('a slow retry read cannot replace a newer ACK used for rollback',
      () async {
    final firstAck = Completer<void>();
    final storage = _Storage()
      ..failNextRead = true
      ..writeGate = firstAck;
    getIt.registerSingleton<KeyValueStorage>(storage);
    final first = GalleryCardSizeStore.write(GalleryCardSize.small);
    await storage.writeStarted.future;

    final retryRead = Completer<String?>();
    final lastAck = Completer<void>();
    storage
      ..readGate = retryRead
      ..writeGate = lastAck;
    final failed = expectLater(
      GalleryCardSizeStore.write(GalleryCardSize.large),
      throwsStateError,
    );
    firstAck.complete();
    await first;
    expect(storage.values[kGalleryCardSizeKey], 'small');
    retryRead.complete('medium');
    await Future<void>.delayed(Duration.zero);
    expect(storage.writes, [
      (kGalleryCardSizeKey, 'small'),
      (kGalleryCardSizeKey, 'large'),
    ]);
    lastAck.completeError(StateError('Latest save failed'));
    await failed;
    expect(GalleryCardSizeStore.value, GalleryCardSize.small);
    expect(storage.values[kGalleryCardSizeKey], 'small');
  });

  test('missing storage does not permanently latch the default', () async {
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.medium);
    getIt.registerSingleton<KeyValueStorage>(
      _Storage()..values[kGalleryCardSizeKey] = 'large',
    );
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
  });

  test('missing storage never reports a transient selection as saved',
      () async {
    await expectLater(
      GalleryCardSizeStore.write(GalleryCardSize.large),
      throwsStateError,
    );
    expect(GalleryCardSizeStore.value, GalleryCardSize.medium);
  });

  test('a failed read can be retried by the next gallery or menu', () async {
    final storage = _Storage()
      ..values[kGalleryCardSizeKey] = 'large'
      ..failNextRead = true;
    getIt.registerSingleton<KeyValueStorage>(storage);
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.medium);
    await GalleryCardSizeStore.ensureLoaded();
    expect(storage.reads, 2);
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
  });

  test('a read from before reset cannot replace the freshly loaded setting',
      () async {
    final oldRead = Completer<String?>();
    final storage = _Storage()
      ..values[kGalleryCardSizeKey] = 'large'
      ..readGate = oldRead;
    getIt.registerSingleton<KeyValueStorage>(storage);
    final oldLoading = GalleryCardSizeStore.ensureLoaded();
    await storage.readStarted.future;
    GalleryCardSizeStore.reset();
    await GalleryCardSizeStore.ensureLoaded();
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
    oldRead.complete('small');
    await oldLoading;
    expect(GalleryCardSizeStore.value, GalleryCardSize.large);
  });
}

class _Storage implements KeyValueStorage {
  final values = <String, String>{};
  final writes = <(String, String)>[];
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  Completer<String?>? readGate;
  Completer<void>? writeGate;
  bool failNextRead = false;
  int reads = 0;

  @override
  Future<String?> get(String key) async {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    final gate = readGate;
    readGate = null;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('Preference read failed');
    }
    if (gate != null) return gate.future;
    return values[key];
  }

  @override
  Future<void> set(String key, String value) async {
    writes.add((key, value));
    if (!writeStarted.isCompleted) writeStarted.complete();
    final gate = writeGate;
    writeGate = null;
    await gate?.future;
    values[key] = value;
  }

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = await get(key);
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}
