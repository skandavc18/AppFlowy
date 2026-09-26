import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Opt-in native diagnostic: run this file explicitly with flutter test on
/// Windows. Only generated text is sent to the real local OCR process.
void main() {
  testWidgets(
    'Windows OCR recognizes synthetic bytes with production script',
    (tester) async {
      await tester.runAsync(() async {
        expect(Platform.isWindows, isTrue);
        await (FontLoader('OCR fixture')
              ..addFont(
                rootBundle.load(
                  'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
                ),
              ))
            .load();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
        final text = TextPainter(
          text: const TextSpan(
            text: 'AppFlowy Native\nSearch 123',
            style: TextStyle(
              fontFamily: 'OCR fixture',
              fontSize: 48,
              color: Colors.black,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 820);
        text.paint(canvas, const Offset(40, 40));
        text.dispose();
        final picture = recorder.endRecording();
        final image = await picture.toImage(900, 250);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        expect(bytes, isNotNull);
        final directory =
            await Directory.systemTemp.createTemp('af-ocr-check-');
        try {
          final input = File(p.join(directory.path, 'image'));
          await input.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
          final source = await File(
            'lib/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart',
          ).readAsString();
          const marker = "const String _powershellScript = r'''";
          final start = source.indexOf(marker) + marker.length;
          expect(start, greaterThanOrEqualTo(marker.length));
          final end = source.indexOf("''';", start);
          expect(end, greaterThan(start));
          final script = File(p.join(directory.path, 'recognize.ps1'));
          final diagnosticScript = source.substring(start, end).replaceFirst(
            r"$ErrorActionPreference = 'Stop'",
            r'''$ErrorActionPreference = 'Stop'
trap {
  [Console]::Error.WriteLine($_.ScriptStackTrace)
  $failure = $_.Exception
  while ($null -ne $failure) {
    [Console]::Error.WriteLine($failure.GetType().FullName + ': ' + $failure.Message)
    $failure = $failure.InnerException
  }
  exit 1
}''',
          );
          await script.writeAsString(diagnosticScript, flush: true);
          clearExecutableCache();
          final executable = resolveExecutable(['powershell']);
          expect(executable, isNotNull);
          final process = await Process.start(executable!.path, [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script.path,
            '-ImagePath',
            // The native fixture/root may use forward slashes. WinRT needs
            // the production boundary to normalize this valid Dart file path.
            input.absolute.path.replaceAll(r'\', '/'),
          ]);
          final stdout = process.stdout.transform(utf8.decoder).join();
          final stderr = process.stderr.transform(utf8.decoder).join();
          await process.stdin.close();
          final exit = await process.exitCode.timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              process.kill();
              return -1;
            },
          );
          final diagnostic =
              (await stderr).replaceAll(directory.path, '<fixture>');
          expect(exit, 0, reason: diagnostic);
          final result = jsonDecode(await stdout) as Map<String, dynamic>;
          expect(jsonEncode(result['lines']).toLowerCase(), contains('search'));
          // Also exercise the app's process runner, cancellation scope and
          // extensionless snapshot, not just the external script invocation.
          final serviceResult = await OcrService().recognizeBytes(
            bytes.buffer.asUint8List(),
            imageSize: const Size(900, 250),
          );
          expect(serviceResult.text.toLowerCase(), contains('search'));
        } finally {
          await directory.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
