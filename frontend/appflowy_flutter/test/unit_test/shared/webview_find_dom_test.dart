import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/shared/find_replace/webview_find.dart';
import 'package:flutter_test/flutter_test.dart';

// Separate opt-in-by-file integration test for the main toolchain. Requires
// Node and jsdom already installed/resolvable; never installs dependencies.
// jsdom supplies a DOM, NOT a substitute find engine or a native WebView2.
void main() {
  test(
    'production JavaScript finds readable DOM and preserves inline elements',
    () async {
      const danger = 'a.b "quoted" \\ path\nline\u2028 </script>';
      final payload = {
        'install': buildWebViewFindInstallScript(
          matchColor: '#ffe599',
          currentColor: '#e0ad42',
          currentTextColor: '#221c14',
          additionalScripts: [buildHtmlPreviewScrollbarAutoHideScript()],
        ),
        'reinstall': buildWebViewFindInstallScript(
          matchColor: "red'); globalThis.injected = true; //",
          currentColor: '#e0ad42',
          currentTextColor: '#221c14',
        ),
        'find': {
          for (final entry in <String, (String, FindOptions)>{
            'inline': ('appflowy', const FindOptions()),
            'inlineCase': ('appflowy', const FindOptions(caseSensitive: true)),
            'phrase': ('hello world', const FindOptions()),
            'spaces': ('hello wide world', const FindOptions()),
            'word': ('formatted', const FindOptions()),
            'literal': ('a.b', const FindOptions()),
            'regex': ('a.b', const FindOptions(useRegex: true)),
            'case': ('Alpha', const FindOptions(caseSensitive: true)),
            'whole': ('alpha', const FindOptions(wholeWord: true)),
            'subword': ('alpha', const FindOptions()),
            'hidden': ('ghost', const FindOptions()),
            'boundary': ('differentparagraph', const FindOptions()),
            'zero': ('0', const FindOptions()),
            'none': ('does not exist', const FindOptions()),
            'empty': ('', const FindOptions()),
            'invalid': ('[', const FindOptions(useRegex: true)),
            'zeroWidth': ('(?=alpha)', const FindOptions(useRegex: true)),
            'danger': (danger, const FindOptions()),
            'cap': ('hit', const FindOptions(wholeWord: true)),
          }.entries)
            entry.key: buildWebViewFindCommand(entry.value.$1, entry.value.$2),
        },
        'next': buildWebViewFindMoveCommand(forward: true),
        'previous': buildWebViewFindMoveCommand(forward: false),
        'clear': buildWebViewFindClearCommand(),
        'danger': danger,
        'binding': webViewFindBindingName,
        'handler': webViewFindOpenHandlerName,
      };
      final fixture =
          File('test/unit_test/shared/fixtures/webview_find_dom.cjs');
      final process = await Process.start('node', [fixture.absolute.path]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      var phase = 'sending scripts';
      Future<(int, String, String)> execute() async {
        process.stdin.write(jsonEncode(payload));
        await process.stdin.close();
        phase = 'running DOM assertions';
        final exit = await process.exitCode;
        phase = 'collecting process output';
        return (exit, await output, await errors);
      }

      try {
        // Include pipe transfer and output draining in the existing deadline,
        // not just exitCode. A failed test must not leave its Node child alive.
        final (exit, capturedOutput, capturedErrors) = await execute().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'Webview DOM fixture did not finish: $phase',
          ),
        );
        expect(exit, 0, reason: '$capturedOutput\n$capturedErrors');
      } finally {
        process.kill();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
