import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

// All children are in-memory fakes. No executable, FFI, network or user file is
// opened. The snapshot tests use only the service's own unique scratch files.
// Intentionally UNRUN in the restricted implementation session.
void main() {
  test('explicit argv, split UTF-8, stderr discarded, no kill on success',
      () async {
    final process = _Process();
    const arguments = [r'C:\synthetic image\$;& photo.png', 'stdout', 'tsv'];
    final runner = OcrProcessRunner(
      start: (executable, args) async {
        expect(executable, 'synthetic-ocr');
        expect(args, arguments);
        return process;
      },
    );
    final future = runner.run(
      File('synthetic-ocr'),
      arguments,
      timeout: const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);
    final bytes = utf8.encode('Hello 🙂');
    process.out.add(bytes.sublist(0, bytes.length - 2));
    process.out.add(bytes.sublist(bytes.length - 2));
    process.err.add(utf8.encode(r'C:\private\path must not be retained'));
    process.finish(0);
    final result = await future;
    expect(result.exitCode, 0);
    expect(result.stdout, 'Hello 🙂');
    expect(process.kills, 0);
    expect(process.input.closes, 1);
    expect(process.out.hasListener, isFalse);
    expect(process.err.hasListener, isFalse);
  });

  test('cancellation kills only the owned child and releases both pipes',
      () async {
    final child = _Process();
    final other = _Process();
    final token = OcrCancellationToken();
    final future = OcrProcessRunner(start: (_, __) async => child).run(
      File('synthetic-ocr'),
      [],
      timeout: const Duration(seconds: 2),
      cancellation: token,
    );
    final assertion =
        expectLater(future, throwsA(isA<OcrCancelledException>()));
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    token.cancel();
    await assertion;
    expect(child.kills, 1);
    expect(other.kills, 0);
    expect(child.out.hasListener, isFalse);
    expect(child.err.hasListener, isFalse);
    other.finish(0);
  });

  test('cancellation before process start disposes the late owned child',
      () async {
    final starting = Completer<Process>();
    final child = _Process();
    final token = OcrCancellationToken();
    final future = OcrProcessRunner(start: (_, __) => starting.future).run(
      File('synthetic-ocr'),
      [],
      timeout: const Duration(seconds: 2),
      cancellation: token,
    );
    final assertion =
        expectLater(future, throwsA(isA<OcrCancelledException>()));
    token.cancel();
    await assertion;
    starting.complete(child);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(child.kills, 1);
    expect(child.out.hasListener, isFalse);
    expect(child.err.hasListener, isFalse);
  });

  test('timeout really stops the spawned child rather than just ignoring it',
      () async {
    final child = _Process();
    await expectLater(
      OcrProcessRunner(start: (_, __) async => child).run(
        File('synthetic-ocr'),
        [],
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(
        isA<OcrUnavailableException>()
            .having((error) => error.kind, 'kind', OcrFailureKind.timedOut),
      ),
    );
    expect(child.kills, 1);
    expect(child.out.hasListener, isFalse);
    expect(child.err.hasListener, isFalse);
  });

  for (final stderr in [false, true]) {
    test('oversized ${stderr ? 'stderr' : 'stdout'} stops bounded collection',
        () async {
      final child = _Process();
      final future = OcrProcessRunner(start: (_, __) async => child).run(
        File('synthetic-ocr'),
        [],
        timeout: const Duration(seconds: 2),
      );
      final assertion =
          expectLater(future, throwsA(isA<OcrUnavailableException>()));
      await Future<void>.delayed(Duration.zero);
      final bytes = Uint8List(OcrProcessRunner.maxOutputCharacters + 1)
        ..fillRange(0, OcrProcessRunner.maxOutputCharacters + 1, 65);
      (stderr ? child.err : child.out).add(bytes);
      await assertion;
      expect(child.kills, 1);
      expect(child.out.hasListener, isFalse);
      expect(child.err.hasListener, isFalse);
    });
  }

  test('process startup failures never expose executable/argument paths',
      () async {
    final runner = OcrProcessRunner(
      start: (_, __) async {
        throw const FileSystemException(
          'private failure',
          r'C:\private\secret.png',
        );
      },
    );
    await expectLater(
      runner.run(
        File('synthetic-ocr'),
        [],
        timeout: const Duration(seconds: 2),
      ),
      throwsA(
        isA<OcrUnavailableException>().having(
          (error) => error.toString(),
          'safe detail',
          isNot(contains('private')),
        ),
      ),
    );
  });

  test('wait consumes a late failure and releases a late decoded value once',
      () async {
    final token = OcrCancellationToken();
    final value = Completer<int>();
    final error = Completer<int>();
    final discarded = <int>[];
    final a = expectLater(
      token.wait(value.future, onDiscard: discarded.add),
      throwsA(isA<OcrCancelledException>()),
    );
    final b = expectLater(
      token.wait(error.future),
      throwsA(isA<OcrCancelledException>()),
    );
    token.cancel();
    await Future.wait([a, b]);
    value.complete(42);
    error.completeError(StateError('obsolete synthetic failure'));
    await Future<void>.delayed(Duration.zero);
    expect(discarded, [42]);
  });

  test(
      'an unavailable Windows-style engine falls through to another local engine',
      () async {
    final first = _Engine('Windows OCR', (_, __) async {
      throw const OcrUnavailableException('No installed language');
    });
    final second = _Engine(
      'Tesseract',
      (_, __) async => const OcrResult(lines: [], engine: 'Tesseract'),
    );
    final result = await OcrService(engines: [first, second]).recognize(
      File('never-opened'),
      imageSize: const Size(1, 1),
    );
    expect(result.engine, 'Tesseract');
    expect(first.calls, 1);
    expect(second.calls, 1);
  });

  test('snapshot is exact and its unique directory is deleted after completion',
      () async {
    File? snapshot;
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final engine = _Engine('test', (file, size) async {
      snapshot = file;
      expect(size, const Size(40, 30));
      expect(await file.readAsBytes(), bytes);
      return const OcrResult(lines: [], engine: 'test');
    });
    final names = <String>[];
    await OcrService(engines: [engine]).recognizeBytes(
      bytes,
      imageSize: const Size(40, 30),
      onEngineSelected: names.add,
    );
    expect(names, ['test']);
    expect(snapshot, isNotNull);
    expect(await snapshot!.parent.exists(), isFalse);
  });

  test('cancelled injected engine cannot retain scratch files or a late result',
      () async {
    final started = Completer<File>();
    final result = Completer<OcrResult>();
    final token = OcrCancellationToken();
    final engine = _Engine('test', (file, _) {
      started.complete(file);
      return result.future;
    });
    final future = OcrService(engines: [engine]).recognizeBytes(
      Uint8List.fromList([1, 2]),
      imageSize: const Size(1, 1),
      cancellation: token,
    );
    final assertion =
        expectLater(future, throwsA(isA<OcrCancelledException>()));
    final file = await started.future;
    token.cancel();
    await assertion;
    expect(await file.parent.exists(), isFalse);
    result.complete(const OcrResult(lines: [], engine: 'obsolete'));
    await Future<void>.delayed(Duration.zero);
  });
}

class _Engine implements OcrEngine {
  _Engine(this.name, this.read);
  @override
  final String name;
  final Future<OcrResult> Function(File, Size) read;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<OcrResult> recognize(File image, {required Size imageSize}) {
    calls++;
    return read(image, imageSize);
  }
}

class _Input extends Fake implements IOSink {
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
  }
}

class _Process extends Fake implements Process {
  final out = StreamController<List<int>>.broadcast(sync: true);
  final err = StreamController<List<int>>.broadcast(sync: true);
  final input = _Input();
  final exit = Completer<int>();
  int kills = 0;

  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  IOSink get stdin => input;
  @override
  Future<int> get exitCode => exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    // Real process exit/pipe EOF cannot synchronously reenter a stdout event.
    scheduleMicrotask(() => finish(-1));
    return true;
  }

  void finish(int code) {
    if (exit.isCompleted) return;
    exit.complete(code);
    unawaited(out.close());
    unawaited(err.close());
  }
}
