import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'ocr_result.dart';

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

  Future<OcrResult> recognize(File image, {required Size imageSize}) async {
    // A freshly installed tool should be picked up without a restart.
    clearExecutableCache();

    for (final engine in _engines) {
      if (!await engine.isAvailable()) {
        continue;
      }
      return engine.recognize(image, imageSize: imageSize);
    }

    throw const OcrUnavailableException(
      'No text recognition engine is available on this machine.',
      hint: 'Install Tesseract OCR and make sure "tesseract" is on your PATH. '
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

    final script = await _writeScript();
    try {
      final result = await _runProcess(
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
      );

      if (result.exitCode != 0 || result.stdout.trim().isEmpty) {
        final message = result.stderr.trim();
        throw OcrUnavailableException(
          message.isEmpty
              ? 'Windows could not read this picture.'
              : _firstLine(message),
          hint: 'Windows OCR needs the language pack for your display '
              'language. Add it in Settings → Time & language → Language.',
        );
      }

      return parseWindowsOutput(result.stdout);
    } finally {
      unawaited(script.delete().catchError((_) => script));
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
    if (width <= 0 || height <= 0) {
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
            bounds: Rect.fromLTWH(
              ((rawWord['x'] as num?)?.toDouble() ?? 0) / width,
              ((rawWord['y'] as num?)?.toDouble() ?? 0) / height,
              ((rawWord['w'] as num?)?.toDouble() ?? 0) / width,
              ((rawWord['h'] as num?)?.toDouble() ?? 0) / height,
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

  Future<File> _writeScript() async {
    final directory = await getTemporaryDirectory();
    final file = File(
      p.join(
        directory.path,
        'appflowy-ocr-${DateTime.now().microsecondsSinceEpoch}.ps1',
      ),
    );
    await file.writeAsString(_powershellScript, flush: true);
    return file;
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

    final result = await _runProcess(
      tesseract,
      [image.absolute.path, 'stdout', 'tsv'],
      timeout: _timeout,
    );

    if (result.exitCode != 0) {
      throw OcrUnavailableException(
        'Tesseract could not read this picture.',
        hint: result.stderr.trim().isEmpty ? null : _firstLine(result.stderr),
      );
    }

    return parseTsv(result.stdout, imageSize);
  }

  @visibleForTesting
  OcrResult parseTsv(String output, Size imageSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
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
      if (cells.length <= indexes['text']!) {
        continue;
      }
      final text = cells[indexes['text']!].trim();
      final confidence = double.tryParse(cells[indexes['conf']!]) ?? -1;
      if (text.isEmpty || confidence < 0) {
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
          confidence: confidence / 100,
          bounds: Rect.fromLTWH(
            (double.tryParse(cells[indexes['left']!]) ?? 0) / imageSize.width,
            (double.tryParse(cells[indexes['top']!]) ?? 0) / imageSize.height,
            (double.tryParse(cells[indexes['width']!]) ?? 0) / imageSize.width,
            (double.tryParse(cells[indexes['height']!]) ?? 0) /
                imageSize.height,
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

class _ProcessOutput {
  const _ProcessOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs [executable] with an explicit argument list and no shell, so nothing
/// in a file path can be reinterpreted as a command.
Future<_ProcessOutput> _runProcess(
  File executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable.path,
    arguments,
  );

  const decoder = Utf8Decoder(allowMalformed: true);
  final stdoutFuture = process.stdout.transform(decoder).join();
  final stderrFuture = process.stderr.transform(decoder).join();
  await process.stdin.close();

  Timer? killer;
  var timedOut = false;
  killer = Timer(timeout, () {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
  });

  try {
    final exitCode = await process.exitCode;
    final out = await stdoutFuture;
    final err = await stderrFuture;
    if (timedOut) {
      throw const OcrUnavailableException(
        'Text recognition took too long and was stopped.',
      );
    }
    return _ProcessOutput(exitCode, out, err);
  } catch (e) {
    Log.error('OCR process failed: $e');
    rethrow;
  } finally {
    killer.cancel();
  }
}

String _firstLine(String value) {
  final lines = const LineSplitter()
      .convert(value)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return lines.isEmpty ? value.trim() : lines.first;
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
  width  = $scaledWidth
  height = $scaledHeight
  lines  = @($lines)
} | ConvertTo-Json -Depth 8 -Compress
''';
