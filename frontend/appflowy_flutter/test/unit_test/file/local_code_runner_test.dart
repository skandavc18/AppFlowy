import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('toolchain selection', () {
    test('every runnable extension maps to a toolchain', () {
      expect(localToolchainForName('main.py')?.label, 'Python');
      expect(localToolchainForName('main.c')?.label, 'C');
      expect(localToolchainForName('main.cpp')?.label, 'C++');
      expect(localToolchainForName('main.cxx')?.label, 'C++');
      expect(localToolchainForName('Main.java')?.label, 'Java');
      expect(localToolchainForName('main.kt')?.label, 'Kotlin');
      expect(localToolchainForName('main.rs')?.label, 'Rust');
    });

    test('non-executable files have no toolchain', () {
      expect(localToolchainForName('styles.css'), isNull);
      expect(localToolchainForName('notes.md'), isNull);
      // JavaScript stays in the WebView sandbox instead.
      expect(localToolchainForName('script.js'), isNull);
    });

    test('interpreted languages need no compiler', () {
      final python = localToolchainForName('main.py')!;
      expect(python.isCompiled, isFalse);
      expect(python.runArgs('/tmp/main.py', ''), ['/tmp/main.py']);
      // Windows would otherwise show mojibake for anything but ASCII.
      expect(python.environment['PYTHONIOENCODING'], 'utf-8');
    });

    test('compiled languages build an artifact and then run it', () {
      final rust = localToolchainForName('main.rs')!;
      expect(rust.isCompiled, isTrue);
      expect(rust.artifactName, isNotEmpty);
      expect(
        rust.compileArgs!('/tmp/main.rs', '/tmp/program'),
        ['/tmp/main.rs', '-o', '/tmp/program'],
      );
      // No runner means the produced binary is launched directly.
      expect(rust.runners, isEmpty);
    });

    test('kotlin compiles to a jar that the JVM runs', () {
      final kotlin = localToolchainForName('main.kt')!;
      expect(kotlin.artifactName, endsWith('.jar'));
      expect(kotlin.runners, contains('java'));
      expect(
        kotlin.runArgs('/tmp/main.kt', '/tmp/program.jar'),
        ['-jar', '/tmp/program.jar'],
      );
      // kotlinc boots a JVM before it compiles, so it needs real headroom.
      expect(kotlin.compileTimeout.inSeconds, greaterThan(60));
    });

    test('a running program is not put on a clock', () {
      // Someone answering a prompt may take as long as they like; only total
      // silence counts as hung.
      expect(
        localToolchainForName('main.py')!.idleTimeout,
        greaterThanOrEqualTo(const Duration(minutes: 1)),
      );
    });
  });

  group('resolving executables', () {
    test('a program that cannot exist is not found', () {
      expect(resolveExecutable(['appflowy-no-such-tool-42']), isNull);
    });

    test('finds a real program on PATH', () {
      // Present on every platform AppFlowy builds for.
      final probe = Platform.isWindows ? 'cmd' : 'sh';
      final resolved = resolveExecutable([probe]);
      expect(resolved, isNotNull);
      expect(resolved!.existsSync(), isTrue);
      expect(p.basenameWithoutExtension(resolved.path).toLowerCase(), probe);
    });

    test('reports what is missing so the message can name it', () {
      final missing = LocalToolchain(
        label: 'Nothing',
        installHint: 'hint',
        sourceName: 'main.txt',
        compilers: const ['appflowy-no-such-tool-42'],
        compileArgs: (source, artifact) => [source],
        runArgs: (source, artifact) => [source],
      );
      expect(missing.isInstalled, isFalse);
      expect(missing.missingExecutables, ['appflowy-no-such-tool-42']);
    });
  });

  group('running', () {
    test('a missing toolchain explains itself instead of failing silently',
        () async {
      final toolchain = LocalToolchain(
        label: 'Nothing',
        installHint: 'Install nothing.',
        sourceName: 'main.txt',
        runners: const ['appflowy-no-such-tool-42'],
        runArgs: (source, artifact) => [source],
      );
      final result =
          await LocalCodeRunner().run(toolchain: toolchain, code: 'x');
      expect(result.exitCode, isNot(0));
      expect(result.notice, contains('Nothing is not available'));
      expect(result.notice, contains('appflowy-no-such-tool-42'));
      expect(result.notice, contains('Install nothing.'));
    });

    test('captures stdout from a real process', () async {
      // Echoing through the platform shell proves the whole pipeline: temp
      // directory, spawn, capture, exit code, cleanup.
      final streamed = StringBuffer();
      final result = await LocalCodeRunner().run(
        toolchain: _shellToolchain(),
        code: Platform.isWindows ? '@echo hello' : 'echo hello',
        onStdout: streamed.write,
      );
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'hello');
      expect(result.stderr, isEmpty);
      // Output arrives as it is produced, not only once the program exits.
      expect(streamed.toString().trim(), 'hello');
    });

    test(
      'a program that asks for input gets it while it is still running',
      () async {
        // The whole point: reading a line must not hit end-of-file just because
        // nothing was typed before the program started.
        final runner = LocalCodeRunner();
        final seen = StringBuffer();
        final done = runner.run(
          toolchain: _shellToolchain(),
          code: Platform.isWindows
              ? '@echo off\r\nset /p name=\r\necho hello %name%'
              : 'read name\necho "hello \$name"',
          onStdout: (chunk) => seen.write(chunk),
        );

        // Answer only after the program is up and blocked on its read.
        while (!runner.acceptsInput) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        runner.sendLine('world');

        final result = await done;
        expect(result.exitCode, 0);
        expect(result.stdout, contains('hello world'));
        expect(seen.toString(), contains('hello world'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'closing the input lets a program that reads to the end finish',
      () async {
        final runner = LocalCodeRunner();
        final done = runner.run(
          toolchain: _shellToolchain(),
          code: Platform.isWindows
              ? '@echo off\r\nmore\r\necho done'
              : 'cat > /dev/null\necho done',
        );
        while (!runner.acceptsInput) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        runner.sendLine('one');
        runner.endInput();

        final result = await done;
        expect(result.stdout, contains('done'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a silent program that never ends is eventually stopped',
      () async {
        final result = await LocalCodeRunner().run(
          toolchain: _shellToolchain(idleTimeout: const Duration(seconds: 2)),
          code: Platform.isWindows
              ? '@echo off\r\n:loop\r\ngoto loop'
              : 'while true; do :; done',
        );
        expect(result.notice, contains('no output'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a program that prints without end is stopped before it fills memory',
      () async {
        final result = await LocalCodeRunner().run(
          toolchain: _shellToolchain(),
          code: Platform.isWindows
              ? '@echo off\r\n:loop\r\necho spam\r\ngoto loop'
              : 'while true; do echo spam; done',
        );
        expect(result.notice, contains('too long'));
        expect(
          result.stdout.length,
          lessThanOrEqualTo(maxLocalRunOutputCharacters),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('running a batch of cases', () {
    test(
      'each case gets its own input and its own result',
      () async {
        final finished = <int, String>{};
        final results = await LocalCodeRunner().runCases(
          toolchain: _shellToolchain(),
          code: Platform.isWindows
              ? '@echo off\r\nset /p name=\r\necho hello %name%'
              : 'read name\necho "hello \$name"',
          inputs: const ['world', 'again'],
          onCaseFinished: (index, result) =>
              finished[index] = result.stdout.trim(),
        );

        expect(results, hasLength(2));
        expect(results[0].stdout, contains('hello world'));
        expect(results[1].stdout, contains('hello again'));
        expect(results.every((result) => result.exitCode == 0), isTrue);
        // Results are reported as they land, not only at the end.
        expect(finished[0], contains('hello world'));
        expect(finished[1], contains('hello again'));
        // The runner times the program so a case can report how long it took.
        expect(results.first.duration, greaterThan(Duration.zero));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'a case that waits for input nobody will type is stopped',
      () async {
        // Nothing answers a prompt during a batch, so a program that keeps
        // reading must not hold the whole run open.
        final results = await LocalCodeRunner().runCases(
          toolchain: _shellToolchain(),
          code: Platform.isWindows
              ? '@echo off\r\n:loop\r\ngoto loop'
              : 'while true; do :; done',
          inputs: const [''],
          caseTimeout: const Duration(seconds: 2),
        );
        expect(results.single.notice, contains('timed out'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('a missing toolchain fails every case with the same reason', () async {
      final results = await LocalCodeRunner().runCases(
        toolchain: LocalToolchain(
          label: 'Nothing',
          installHint: 'Install nothing.',
          sourceName: 'main.txt',
          runners: const ['appflowy-no-such-tool-42'],
          runArgs: (source, artifact) => [source],
        ),
        code: 'x',
        inputs: const ['a', 'b'],
      );
      expect(results, hasLength(2));
      expect(
        results.every((result) => result.notice.contains('not available')),
        isTrue,
      );
    });
  });
}

/// A toolchain that runs a script with the platform's own shell, so the runner
/// can be exercised on any machine without installing anything.
LocalToolchain _shellToolchain({Duration? idleTimeout}) => Platform.isWindows
    ? LocalToolchain(
        label: 'Batch',
        installHint: '',
        sourceName: 'main.bat',
        runners: const ['cmd'],
        runArgs: (source, artifact) => ['/c', source],
        idleTimeout: idleTimeout ?? const Duration(minutes: 5),
      )
    : LocalToolchain(
        label: 'Shell',
        installHint: '',
        sourceName: 'main.sh',
        runners: const ['sh'],
        runArgs: (source, artifact) => [source],
        idleTimeout: idleTimeout ?? const Duration(minutes: 5),
      );
