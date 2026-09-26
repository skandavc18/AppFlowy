import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';

import 'ocr_result.dart';

const maxOcrImageBytes = 32 * 1024 * 1024;
const _cancellationKey = #imageOcrCancellation;
const _engineNameKey = #imageOcrEngineName;

/// Cancellation is scoped to one scan, not an engine or the application.
class OcrCancellationToken {
  bool _cancelled = false;
  final _listeners = <VoidCallback>{};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) throw const OcrCancelledException();
  }

  void addListener(VoidCallback listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Stops awaiting obsolete work, consumes its late failures, and releases
  /// any late native image through [onDiscard]. Does not cancel shared caches.
  Future<T> wait<T>(Future<T> operation, {void Function(T)? onDiscard}) {
    final result = Completer<T>();
    void cancelled() {
      if (!result.isCompleted) {
        result.completeError(const OcrCancelledException());
      }
    }

    unawaited(
      operation.then<void>(
        (value) {
          if (result.isCompleted) {
            onDiscard?.call(value);
          } else {
            result.complete(value);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    addListener(cancelled);
    return result.future.whenComplete(() => removeListener(cancelled));
  }
}

class OcrCancelledException implements Exception {
  const OcrCancelledException();
}

OcrCancellationToken? get _cancellation =>
    Zone.current[_cancellationKey] as OcrCancellationToken?;

Future<T> _waitForScan<T>(Future<T> future) =>
    _cancellation?.wait(future) ?? future;

/// Reads the text out of a picture.
abstract class OcrEngine {
  /// Shown in the overlay so it is obvious what did the reading.
  String get name;

  /// Whether this machine can run the engine at all.
  Future<bool> isAvailable();

  /// [imageSize] is the source resolution; engines that rescale internally
  /// report their own reference frame instead.
  Future<OcrResult> recognize(File image, {required Size imageSize});
}

/// Picks the first engine this machine can actually run.
class OcrService {
  OcrService({List<OcrEngine>? engines})
      : _engines = engines ??
            [
              if (UniversalPlatform.isWindows) WindowsOcrEngine(),
              TesseractOcrEngine(),
            ];

  final List<OcrEngine> _engines;

  /// Reads exactly the bytes displayed by the overlay. Never reopens a mutable
  /// original halfway through a scan, and never caches OCR across file edits.
  /// Override this boundary in widget tests to avoid disk/native processes.
  Future<OcrResult> recognizeBytes(
    Uint8List bytes, {
    required Size imageSize,
    OcrCancellationToken? cancellation,
    ValueChanged<String>? onEngineSelected,
  }) async {
    cancellation?.throwIfCancelled();
    if (bytes.length > maxOcrImageBytes) {
      throw const OcrUnavailableException(
        'This picture is too large for text recognition.',
        kind: OcrFailureKind.tooLarge,
      );
    }
    // Each scan owns ONLY this directory. Originals and the shared image cache
    // are never deleted, including when a caller closes during preparation.
    final directory =
        await Directory.systemTemp.createTemp('appflowy-image-ocr-');
    try {
      cancellation?.throwIfCancelled();
      final file = File(p.join(directory.path, 'image'));
      await file.writeAsBytes(bytes, flush: true);
      cancellation?.throwIfCancelled();
      return await runZoned(
        () => recognize(file, imageSize: imageSize),
        zoneValues: {
          _cancellationKey: cancellation,
          _engineNameKey: onEngineSelected,
        },
      );
    } finally {
      await _deleteScratch(directory);
    }
  }

  Future<OcrResult> recognize(File image, {required Size imageSize}) async {
    // A freshly installed tool should be picked up without a restart.
    clearExecutableCache();

    OcrUnavailableException? failure;
    for (final engine in _engines) {
      _cancellation?.throwIfCancelled();
      try {
        final available = await _waitForScan(
          engine.isAvailable().timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              ),
        );
        if (!available) continue;
        _cancellation?.throwIfCancelled();
        (Zone.current[_engineNameKey] as ValueChanged<String>?)
            ?.call(engine.name);
        final recognition =
            engine.recognize(image, imageSize: imageSize).timeout(
                  const Duration(seconds: 130),
                  onTimeout: () => throw const OcrUnavailableException(
                    'Text recognition took too long and was stopped.',
                    kind: OcrFailureKind.timedOut,
                  ),
                );
        // Native engines respond to cancellation themselves and await their
        // owned child/pipe cleanup. Do not race that cleanup against deleting
        // the snapshot. Non-native injected engines may only be awaitable.
        return await (engine is WindowsOcrEngine || engine is TesseractOcrEngine
            ? recognition
            : _waitForScan(recognition));
      } on OcrCancelledException {
        rethrow;
      } on OcrUnavailableException catch (error) {
        // PowerShell can exist without an OCR language pack. Still try the
        // next installed LOCAL engine instead of giving up at that point.
        failure = error;
      } catch (_) {
        failure = const OcrUnavailableException(
          'Text recognition failed.',
          kind: OcrFailureKind.failed,
        );
      }
    }

    _cancellation?.throwIfCancelled();
    throw failure ??
        const OcrUnavailableException(
          'No text recognition engine is available on this machine.',
          hint:
              'Install Tesseract OCR and make sure "tesseract" is on your PATH. '
              'On Windows, text recognition also works out of the box once the '
              'Windows OCR language pack for your display language is installed.',
        );
  }
}

/// Windows ships an OCR engine with the OS. It is reached through Windows
/// PowerShell, which projects the WinRT API — that keeps the feature free of
/// any native plugin and of anything the user has to install.
class WindowsOcrEngine implements OcrEngine {
  @override
  String get name => 'Windows OCR';

  static const _timeout = Duration(seconds: 90);

  @override
  Future<bool> isAvailable() async =>
      UniversalPlatform.isWindows && resolveExecutable(['powershell']) != null;

  @override
  Future<OcrResult> recognize(File image, {required Size imageSize}) async {
    final powershell = resolveExecutable(['powershell']);
    if (powershell == null) {
      throw const OcrUnavailableException(
        'Windows PowerShell could not be found.',
      );
    }

    final directory =
        await Directory.systemTemp.createTemp('appflowy-ocr-engine-');
    try {
      _cancellation?.throwIfCancelled();
      final script = File(p.join(directory.path, 'recognize.ps1'));
      await script.writeAsString(_powershellScript, flush: true);
      _cancellation?.throwIfCancelled();
      final result = await const OcrProcessRunner().run(
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          // The path travels as its own argument, so nothing in it is ever
          // interpreted as script.
          '-ImagePath',
          image.absolute.path,
        ],
        timeout: _timeout,
        cancellation: _cancellation,
      );

      if (result.exitCode != 0 || result.stdout.trim().isEmpty) {
        throw const OcrUnavailableException(
          'Windows could not read this picture.',
          hint: 'Windows OCR needs the language pack for your display '
              'language. Add it in Settings → Time & language → Language.',
        );
      }

      return parseWindowsOutput(result.stdout);
    } finally {
      await _deleteScratch(directory);
    }
  }

  @visibleForTesting
  OcrResult parseWindowsOutput(String output) {
    final decoded = jsonDecode(output.trim());
    if (decoded is! Map<String, dynamic>) {
      throw const OcrUnavailableException('Unexpected response from Windows.');
    }

    final width = (decoded['width'] as num?)?.toDouble() ?? 0;
    final height = (decoded['height'] as num?)?.toDouble() ?? 0;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return const OcrResult(lines: [], engine: 'Windows OCR');
    }

    final lines = <OcrLine>[];
    for (final rawLine in _asList(decoded['lines'])) {
      if (rawLine is! Map) {
        continue;
      }
      final words = <OcrWord>[];
      for (final rawWord in _asList(rawLine['words'])) {
        if (rawWord is! Map) {
          continue;
        }
        final text = rawWord['text'] as String? ?? '';
        if (text.isEmpty) {
          continue;
        }
        words.add(
          OcrWord(
            text: text,
            bounds: normalizedOcrBounds(
              Rect.fromLTWH(
                ((rawWord['x'] as num?)?.toDouble() ?? 0) / width,
                ((rawWord['y'] as num?)?.toDouble() ?? 0) / height,
                ((rawWord['w'] as num?)?.toDouble() ?? 0) / width,
                ((rawWord['h'] as num?)?.toDouble() ?? 0) / height,
              ),
            ),
          ),
        );
      }
      final text = rawLine['text'] as String? ?? '';
      if (words.isEmpty || text.trim().isEmpty) {
        continue;
      }
      lines.add(OcrLine.fromWords(words, text: text));
    }

    return OcrResult(lines: lines, engine: 'Windows OCR');
  }
}

/// Tesseract's TSV output gives a box per word, which is exactly what the
/// selectable overlay needs.
class TesseractOcrEngine implements OcrEngine {
  @override
  String get name => 'Tesseract';

  static const _timeout = Duration(seconds: 120);

  @override
  Future<bool> isAvailable() async => resolveExecutable(['tesseract']) != null;

  @override
  Future<OcrResult> recognize(File image, {required Size imageSize}) async {
    final tesseract = resolveExecutable(['tesseract']);
    if (tesseract == null) {
      throw const OcrUnavailableException(
        'Tesseract could not be found.',
        hint: 'Install Tesseract OCR and make sure "tesseract" is on '
            'your PATH.',
      );
    }

    final result = await const OcrProcessRunner().run(
      tesseract,
      [image.absolute.path, 'stdout', 'tsv'],
      timeout: _timeout,
      cancellation: _cancellation,
    );

    if (result.exitCode != 0) {
      throw const OcrUnavailableException(
        'Tesseract could not read this picture.',
        hint:
            'Check that the picture is readable and an OCR language is installed.',
        kind: OcrFailureKind.failed,
      );
    }

    return parseTsv(result.stdout, imageSize);
  }

  @visibleForTesting
  OcrResult parseTsv(String output, Size imageSize) {
    if (!imageSize.isFinite || imageSize.isEmpty) {
      return const OcrResult(lines: [], engine: 'Tesseract');
    }

    final rows = const LineSplitter().convert(output);
    if (rows.isEmpty) {
      return const OcrResult(lines: [], engine: 'Tesseract');
    }

    final header = rows.first.split('\t');
    int columnOf(String name) => header.indexOf(name);
    final indexes = {
      for (final name in const [
        'block_num',
        'par_num',
        'line_num',
        'left',
        'top',
        'width',
        'height',
        'conf',
        'text',
      ])
        name: columnOf(name),
    };
    if (indexes.values.any((index) => index < 0)) {
      throw const OcrUnavailableException(
        'Tesseract returned an unexpected format.',
      );
    }

    final grouped = <String, List<OcrWord>>{};
    final order = <String>[];
    for (final row in rows.skip(1)) {
      final cells = row.split('\t');
      if (indexes.values.any((index) => index >= cells.length)) {
        continue;
      }
      final text = cells[indexes['text']!].trim();
      final confidence = double.tryParse(cells[indexes['conf']!]) ?? -1;
      if (text.isEmpty || !confidence.isFinite || confidence < 0) {
        continue;
      }
      final key = '${cells[indexes['block_num']!]}'
          '/${cells[indexes['par_num']!]}'
          '/${cells[indexes['line_num']!]}';
      final words = grouped.putIfAbsent(key, () {
        order.add(key);
        return <OcrWord>[];
      });
      words.add(
        OcrWord(
          text: text,
          confidence: (confidence / 100).clamp(0.0, 1.0),
          bounds: normalizedOcrBounds(
            Rect.fromLTWH(
              (double.tryParse(cells[indexes['left']!]) ?? 0) / imageSize.width,
              (double.tryParse(cells[indexes['top']!]) ?? 0) / imageSize.height,
              (double.tryParse(cells[indexes['width']!]) ?? 0) /
                  imageSize.width,
              (double.tryParse(cells[indexes['height']!]) ?? 0) /
                  imageSize.height,
            ),
          ),
        ),
      );
    }

    return OcrResult(
      lines: [
        for (final key in order)
          if (grouped[key]!.isNotEmpty) OcrLine.fromWords(grouped[key]!),
      ],
      engine: 'Tesseract',
    );
  }
}

class OcrProcessOutput {
  const OcrProcessOutput(this.exitCode, this.stdout);

  final int exitCode;
  final String stdout;
}

/// Owns exactly one explicitly spawned child per call. No shell, PID lookup,
/// process-tree kill, arbitrary application kill, or raw stderr logging.
/// The injected starter lets tests exercise timeouts using an in-memory child.
class OcrProcessRunner {
  const OcrProcessRunner({this.start});

  final Future<Process> Function(String, List<String>)? start;
  static const maxOutputCharacters = 4 * 1024 * 1024;
  static const _drainTimeout = Duration(seconds: 2);

  Future<OcrProcessOutput> run(
    File executable,
    List<String> arguments, {
    required Duration timeout,
    OcrCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final completed = Completer<OcrProcessOutput>();
    Process? process;
    var exited = false;
    var stopped = false;
    var killed = false;
    final output = StringBuffer();
    var errorLength = 0;
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;

    void stop(Object error) {
      if (completed.isCompleted) return;
      stopped = true;
      final child = process;
      if (child != null && !killed && !exited) {
        killed = true;
        child.kill(ProcessSignal.sigkill);
      }
      completed.completeError(error);
    }

    void cancel() => stop(const OcrCancelledException());
    final deadline = Timer(
      timeout,
      () => stop(
        const OcrUnavailableException(
          'Text recognition took too long and was stopped.',
          kind: OcrFailureKind.timedOut,
        ),
      ),
    );
    cancellation?.addListener(cancel);

    unawaited(() async {
      try {
        final child = await (start?.call(executable.path, arguments) ??
            Process.start(executable.path, arguments));
        process = child;
        // A start may finish after its owner has already closed/timed out.
        if (stopped) {
          await _discardProcess(child);
          return;
        }
        const decoder = Utf8Decoder(allowMalformed: true);
        void outputFailed(Object _) => stop(
              const OcrUnavailableException(
                'Text recognition failed.',
                kind: OcrFailureKind.failed,
              ),
            );
        stdoutSubscription = child.stdout.transform(decoder).listen(
              (chunk) {
                if (output.length + chunk.length > maxOutputCharacters) {
                  outputFailed(const FormatException());
                } else if (!stopped) {
                  output.write(chunk);
                }
              },
              onError: outputFailed,
              onDone: () {
                if (!stdoutDone.isCompleted) stdoutDone.complete();
              },
            );
        stderrSubscription = child.stderr.transform(decoder).listen(
              (chunk) {
                // Drain, but do not keep messages that may contain private paths.
                errorLength += chunk.length;
                if (errorLength > maxOutputCharacters) {
                  outputFailed(const FormatException());
                }
              },
              onError: outputFailed,
              onDone: () {
                if (!stderrDone.isCompleted) stderrDone.complete();
              },
            );
        unawaited(child.stdin.close().catchError((Object _) {}));
        final exitCode = await child.exitCode;
        exited = true;
        await Future.wait([stdoutDone.future, stderrDone.future])
            .timeout(_drainTimeout);
        if (!completed.isCompleted) {
          completed.complete(OcrProcessOutput(exitCode, output.toString()));
        }
      } catch (_) {
        stop(
          const OcrUnavailableException(
            'The local text recognition process failed.',
            kind: OcrFailureKind.failed,
          ),
        );
      }
    }());

    try {
      return await completed.future;
    } finally {
      deadline.cancel();
      cancellation?.removeListener(cancel);
      final child = process;
      if (child != null && !exited) {
        if (!killed) {
          killed = true;
          child.kill(ProcessSignal.sigkill);
        }
        try {
          await child.exitCode.timeout(_drainTimeout, onTimeout: () => -1);
        } catch (_) {
          // Preserve the safe scan failure, never expose an OS path here.
        }
      }
      await _cancelOutput(stdoutSubscription);
      await _cancelOutput(stderrSubscription);
      if (!stdoutDone.isCompleted) stdoutDone.complete();
      if (!stderrDone.isCompleted) stderrDone.complete();
    }
  }

  static Future<void> _discardProcess(Process process) async {
    process.kill(ProcessSignal.sigkill);
    final out = process.stdout.listen((_) {}, onError: (Object _) {});
    final err = process.stderr.listen((_) {}, onError: (Object _) {});
    unawaited(process.stdin.close().catchError((Object _) {}));
    try {
      await process.exitCode.timeout(_drainTimeout, onTimeout: () => -1);
    } finally {
      await _cancelOutput(out);
      await _cancelOutput(err);
    }
  }

  static Future<void> _cancelOutput(StreamSubscription<dynamic>? stream) async {
    try {
      await stream?.cancel().timeout(_drainTimeout);
    } catch (_) {
      // Cancellation is bounded even if a platform pipe refuses to close.
    }
  }
}

Future<void> _deleteScratch(Directory directory) async {
  // Windows can briefly retain a file handle after an owned child exits.
  // Retry only this unique scratch directory, and never hide the scan result.
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}

/// PowerShell folds a one element array into a bare object, so both shapes
/// have to be accepted.
List<dynamic> _asList(dynamic value) {
  if (value is List) {
    return value;
  }
  if (value == null) {
    return const [];
  }
  return [value];
}

const String _powershellScript = r'''
param([Parameter(Mandatory = $true)][string]$ImagePath)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and
    $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  })[0]

function Await($operation, $resultType) {
  $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
  $task.Wait(-1) | Out-Null
  $task.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) {
  throw 'No Windows OCR language pack is installed for your display language.'
}

# WinRT requires a canonical Windows path; Dart accepts mixed/forward slashes.
# Normalize here as well as keeping the filename out of executable script text.
$ImagePath = [System.IO.Path]::GetFullPath($ImagePath)
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])

$max = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
$sourceWidth = [double]$decoder.PixelWidth
$sourceHeight = [double]$decoder.PixelHeight
$scale = 1.0
if ($sourceWidth -gt $max -or $sourceHeight -gt $max) {
  $scale = [Math]::Min($max / $sourceWidth, $max / $sourceHeight)
}
$scaledWidth = [Math]::Max(1, [int][Math]::Floor($sourceWidth * $scale))
$scaledHeight = [Math]::Max(1, [int][Math]::Floor($sourceHeight * $scale))

$transform = New-Object Windows.Graphics.Imaging.BitmapTransform
$transform.ScaledWidth = $scaledWidth
$transform.ScaledHeight = $scaledHeight

$bitmap = Await ($decoder.GetSoftwareBitmapAsync(
    [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
    [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,
    $transform,
    [Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation,
    [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])

$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

$lines = New-Object System.Collections.ArrayList
foreach ($line in $result.Lines) {
  $words = New-Object System.Collections.ArrayList
  foreach ($word in $line.Words) {
    $rect = $word.BoundingRect
    [void]$words.Add([pscustomobject]@{
        text = $word.Text
        x    = [double]$rect.X
        y    = [double]$rect.Y
        w    = [double]$rect.Width
        h    = [double]$rect.Height
      })
  }
  [void]$lines.Add([pscustomobject]@{ text = $line.Text; words = @($words) })
}

[pscustomobject]@{
  width  = $bitmap.PixelWidth
  height = $bitmap.PixelHeight
  lines  = @($lines)
} | ConvertTo-Json -Depth 8 -Compress
''';
