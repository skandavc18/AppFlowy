import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';

/// Output is captured into memory, so a runaway loop must not be able to grow
/// without bound.
const int maxLocalRunOutputCharacters = 200000;

/// How one language is built and run with the tools installed on this machine.
///
/// There is no remote execution service: AppFlowy Cloud stores and syncs
/// documents, it does not compile or run code. JavaScript runs inside the
/// WebView sandbox; every other language needs a real toolchain on PATH.
class LocalToolchain {
  LocalToolchain({
    required this.label,
    required this.installHint,
    required this.sourceName,
    required this.runArgs,
    this.compilers = const [],
    this.compileArgs,
    this.runners = const [],
    this.artifactName = '',
    this.environment = const {},
    this.compileTimeout = const Duration(seconds: 90),
    this.idleTimeout = const Duration(minutes: 5),
  });

  /// Human name of the toolchain, e.g. `Python`.
  final String label;

  /// Shown when nothing usable is found on PATH.
  final String installHint;

  /// Name the code is written to inside a private temporary directory.
  final String sourceName;

  /// Compilers to look for, most preferred first. Empty when interpreted.
  final List<String> compilers;

  /// Arguments for the compile step.
  final List<String> Function(String source, String artifact)? compileArgs;

  /// Programs that run the result. Empty means the compiler produced a native
  /// executable, which is launched directly.
  final List<String> runners;

  /// Arguments for the run step.
  final List<String> Function(String source, String artifact) runArgs;

  /// Name of the build product, if the compiler makes one.
  final String artifactName;

  /// Extra environment entries, merged over the inherited environment.
  final Map<String, String> environment;

  /// Hard limit on the compile step, which is never interactive.
  final Duration compileTimeout;

  /// How long the program may go without printing anything or being given
  /// input before it is treated as hung.
  ///
  /// A running program is not on a clock: a person may take as long as they
  /// like to answer a prompt, and a long calculation is allowed to finish.
  final Duration idleTimeout;

  bool get isCompiled => compilers.isNotEmpty;

  /// Whether every program this toolchain needs is present on PATH.
  bool get isInstalled => missingExecutables.isEmpty;

  /// The programs that could not be found, named as the user would install
  /// them.
  List<String> get missingExecutables => [
        if (compilers.isNotEmpty && resolveExecutable(compilers) == null)
          compilers.first,
        if (runners.isNotEmpty && resolveExecutable(runners) == null)
          runners.first,
      ];
}

/// The result of one local run, mirroring a process exit.
class LocalCodeResult {
  const LocalCodeResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.notice = '',
  });

  final String stdout;
  final String stderr;
  final int exitCode;

  /// A message from the runner itself rather than from the program: a missing
  /// toolchain, a failed compile, a timeout, a cancellation.
  final String notice;
}

/// The toolchain that can run [name], or null when the extension is not
/// executable here.
LocalToolchain? localToolchainForName(String name) {
  final nativeArtifact =
      UniversalPlatform.isWindows ? 'program.exe' : 'program';
  return switch (p.extension(name).toLowerCase()) {
    '.py' => LocalToolchain(
        label: 'Python',
        installHint: 'Install Python 3 from python.org and make sure it is on '
            'your PATH.',
        sourceName: 'main.py',
        runners: const ['python3', 'python', 'py'],
        runArgs: (source, _) => [source],
        // Unbuffered output is what makes `input("name? ")` show its prompt
        // before the program blocks; UTF-8 keeps non-ASCII readable.
        environment: const {
          'PYTHONIOENCODING': 'utf-8',
          'PYTHONUNBUFFERED': '1',
        },
      ),
    '.c' => LocalToolchain(
        label: 'C',
        installHint: 'Install a C compiler (gcc, clang, or MSYS2/MinGW on '
            'Windows) and make sure it is on your PATH.',
        sourceName: 'main.c',
        compilers: const ['gcc', 'clang', 'cc'],
        compileArgs: (source, artifact) => [source, '-o', artifact],
        artifactName: nativeArtifact,
        runArgs: (_, __) => const [],
      ),
    '.cc' || '.cpp' || '.cxx' => LocalToolchain(
        label: 'C++',
        installHint: 'Install a C++ compiler (g++, clang++, or MSYS2/MinGW on '
            'Windows) and make sure it is on your PATH.',
        sourceName: 'main.cpp',
        compilers: const ['g++', 'clang++'],
        compileArgs: (source, artifact) =>
            [source, '-std=c++17', '-o', artifact],
        artifactName: nativeArtifact,
        runArgs: (_, __) => const [],
      ),
    // Java 11+ runs a single source file without a separate compile step.
    '.java' => LocalToolchain(
        label: 'Java',
        installHint: 'Install a JDK 11 or newer and make sure `java` is on '
            'your PATH.',
        sourceName: 'Main.java',
        runners: const ['java'],
        runArgs: (source, _) => [source],
      ),
    '.kt' => LocalToolchain(
        label: 'Kotlin',
        installHint: 'Install the Kotlin compiler and a JDK, and make sure '
            '`kotlinc` and `java` are on your PATH.',
        sourceName: 'main.kt',
        compilers: const ['kotlinc'],
        compileArgs: (source, artifact) => [
          source,
          '-include-runtime',
          '-nowarn',
          '-d',
          artifact,
        ],
        artifactName: 'program.jar',
        runners: const ['java'],
        runArgs: (_, artifact) => ['-jar', artifact],
        // kotlinc starts a JVM before it compiles anything.
        compileTimeout: const Duration(minutes: 4),
      ),
    '.rs' => LocalToolchain(
        label: 'Rust',
        installHint: 'Install Rust from rustup.rs and make sure `rustc` is on '
            'your PATH.',
        sourceName: 'main.rs',
        compilers: const ['rustc'],
        compileArgs: (source, artifact) => [source, '-o', artifact],
        artifactName: nativeArtifact,
        runArgs: (_, __) => const [],
      ),
    _ => null,
  };
}

final Map<String, File?> _executableCache = {};

/// Finds the first of [candidates] on PATH.
///
/// PATH is walked directly rather than shelling out to `where`/`which`, so
/// nothing is handed to a command interpreter.
File? resolveExecutable(List<String> candidates) {
  for (final candidate in candidates) {
    final resolved =
        _executableCache.putIfAbsent(candidate, () => _search(candidate));
    if (resolved != null) {
      return resolved;
    }
  }
  return null;
}

/// Forgets what was found on PATH, so a toolchain installed while AppFlowy is
/// running can be picked up.
void clearExecutableCache() => _executableCache.clear();

File? _search(String executable) {
  final path = Platform.environment['PATH'] ?? Platform.environment['Path'];
  if (path == null || path.isEmpty) {
    return null;
  }
  final extensions = UniversalPlatform.isWindows
      ? (Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD').split(';')
      : const [''];
  for (final directory in path.split(UniversalPlatform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) {
      continue;
    }
    for (final extension in extensions) {
      final candidate = File(p.join(directory, '$executable$extension'));
      try {
        if (candidate.existsSync()) {
          return candidate;
        }
      } on FileSystemException {
        // An unreadable PATH entry is simply not a match.
      }
    }
  }
  return null;
}

/// Runs one program in a private temporary directory and keeps talking to it
/// while it lives.
///
/// Output is delivered as it is produced and input is delivered as it is
/// typed, so a program that prompts and waits behaves the way it would in a
/// terminal instead of reaching end-of-file immediately.
///
/// The code is written to a file and the toolchain is invoked with an explicit
/// argument list, never through a shell, so nothing in the source or the file
/// name can be read as a command.
class LocalCodeRunner {
  Process? _process;
  bool _cancelled = false;
  bool _acceptsInput = false;
  void Function()? _keepAlive;

  /// Whether the program is running and still reading its input.
  bool get acceptsInput => _acceptsInput;

  Future<LocalCodeResult> run({
    required LocalToolchain toolchain,
    required String code,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) async {
    final missing = toolchain.missingExecutables;
    if (missing.isNotEmpty) {
      return LocalCodeResult(
        stdout: '',
        stderr: '',
        exitCode: -1,
        notice: '${toolchain.label} is not available on this computer.\n'
            'Looked for ${missing.join(', ')} on your PATH.\n'
            '${toolchain.installHint}\n',
      );
    }

    final directory =
        await Directory.systemTemp.createTemp('appflowy_code_run_');
    try {
      final source = File(p.join(directory.path, toolchain.sourceName));
      await source.writeAsString(code);
      final artifact = toolchain.artifactName.isEmpty
          ? ''
          : p.join(directory.path, toolchain.artifactName);

      if (toolchain.isCompiled) {
        final compiler = resolveExecutable(toolchain.compilers)!;
        final compiled = await _spawn(
          executable: compiler,
          arguments: toolchain.compileArgs!(source.path, artifact),
          workingDirectory: directory.path,
          environment: toolchain.environment,
          hardTimeout: toolchain.compileTimeout,
          onStdout: onStdout,
          onStderr: onStderr,
        );
        if (_cancelled) {
          return _stopped(compiled);
        }
        if (compiled.exitCode != 0) {
          return LocalCodeResult(
            stdout: compiled.stdout,
            stderr: compiled.stderr,
            exitCode: compiled.exitCode,
            notice: compiled.notice.isEmpty
                ? '${toolchain.label} failed to compile the code.\n'
                : compiled.notice,
          );
        }
      }

      final runner = toolchain.runners.isEmpty
          ? File(artifact)
          : resolveExecutable(toolchain.runners)!;
      final result = await _spawn(
        executable: runner,
        arguments: toolchain.runArgs(source.path, artifact),
        workingDirectory: directory.path,
        environment: toolchain.environment,
        idleTimeout: toolchain.idleTimeout,
        interactive: true,
        onStdout: onStdout,
        onStderr: onStderr,
      );
      return _cancelled ? _stopped(result) : result;
    } on ProcessException catch (error) {
      return LocalCodeResult(
        stdout: '',
        stderr: '',
        exitCode: -1,
        notice: '${error.message}\n',
      );
    } finally {
      _acceptsInput = false;
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Windows can still hold the executable briefly; the OS sweeps temp.
      }
    }
  }

  /// Hands one line to the running program, as if it had been typed at a
  /// terminal.
  void sendLine(String line) {
    if (!_acceptsInput) {
      return;
    }
    try {
      _process?.stdin.writeln(line);
      _keepAlive?.call();
    } on SocketException {
      _acceptsInput = false;
    } on StateError {
      _acceptsInput = false;
    }
  }

  /// Closes the input stream, which is what Ctrl+D does in a terminal.
  ///
  /// Programs that read until end-of-file need this to move on.
  void endInput() {
    if (!_acceptsInput) {
      return;
    }
    _acceptsInput = false;
    unawaited(_process?.stdin.close().catchError((_) {}));
  }

  /// Ends the run, if one is in flight.
  void cancel() {
    _cancelled = true;
    _acceptsInput = false;
    _process?.kill(ProcessSignal.sigkill);
  }

  LocalCodeResult _stopped(LocalCodeResult result) => LocalCodeResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        notice: '${result.notice}Execution stopped.\n',
      );

  Future<LocalCodeResult> _spawn({
    required File executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    Duration? hardTimeout,
    Duration? idleTimeout,
    bool interactive = false,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) async {
    if (_cancelled) {
      return const LocalCodeResult(stdout: '', stderr: '', exitCode: -1);
    }
    // Batch shims (kotlinc.bat) cannot be launched directly on Windows; Dart
    // routes them through the command processor and escapes the arguments.
    final isBatch = UniversalPlatform.isWindows &&
        const ['.bat', '.cmd'].contains(p.extension(executable.path));
    final process = await Process.start(
      executable.path,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment.isEmpty ? null : environment,
      runInShell: isBatch,
    );
    _process = process;
    _acceptsInput = interactive;
    if (!interactive) {
      unawaited(process.stdin.close().catchError((_) {}));
    }

    var timedOut = false;
    var truncated = false;
    Timer? idleTimer;
    void keepAlive() {
      if (idleTimeout == null) {
        return;
      }
      idleTimer?.cancel();
      idleTimer = Timer(idleTimeout, () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
      });
    }

    _keepAlive = keepAlive;
    keepAlive();

    final out = StringBuffer();
    final err = StringBuffer();
    void collect(
      StringBuffer buffer,
      String chunk,
      void Function(String chunk)? sink,
    ) {
      keepAlive();
      final room = maxLocalRunOutputCharacters - buffer.length;
      if (room <= 0) {
        return;
      }
      final text = chunk.length > room ? chunk.substring(0, room) : chunk;
      buffer.write(text);
      sink?.call(text);
      if (chunk.length > room) {
        // A program printing without end would otherwise fill memory.
        truncated = true;
        process.kill(ProcessSignal.sigkill);
      }
    }

    // Compiler diagnostics are not always valid UTF-8 on Windows.
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutDone = process.stdout
        .transform(decoder)
        .forEach((chunk) => collect(out, chunk, onStdout));
    final stderrDone = process.stderr
        .transform(decoder)
        .forEach((chunk) => collect(err, chunk, onStderr));

    final exitCode = hardTimeout == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            hardTimeout,
            onTimeout: () {
              timedOut = true;
              process.kill(ProcessSignal.sigkill);
              return process.exitCode;
            },
          );
    await stdoutDone;
    await stderrDone;
    idleTimer?.cancel();
    _keepAlive = null;
    _process = null;
    _acceptsInput = false;

    final notice = StringBuffer();
    if (timedOut) {
      notice.write(
        hardTimeout != null
            ? 'Execution timed out after ${hardTimeout.inSeconds} seconds.\n'
            : 'Stopped after ${idleTimeout!.inMinutes} minutes with no output '
                'and no input.\n',
      );
    }
    if (truncated) {
      notice.write('Output was too long, so the program was stopped.\n');
    }
    return LocalCodeResult(
      stdout: out.toString(),
      stderr: err.toString(),
      exitCode: exitCode,
      notice: notice.toString(),
    );
  }
}
