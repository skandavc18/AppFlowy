// Running notebook cells on this machine.
//
// There is no execution service behind AppFlowy: nothing in the backend
// compiles or runs code, and a Jupyter server is not bundled. A notebook is
// therefore run by the Python already installed on this computer, in one long
// lived process that keeps its variables between cells — which is what makes
// a notebook a notebook rather than a folder of scripts.
//
// The process is started with an explicit argument list and never through a
// shell, it runs in the notebook's own directory, and everything it says is
// framed JSON on its standard output, so a cell's printed text can never be
// mistaken for a protocol message.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

import '../local_code_runner.dart';
import 'notebook_document.dart';

/// How much a single cell may print before the kernel is stopped.
const int maxNotebookOutputCharacters = maxLocalRunOutputCharacters;

/// What the kernel is doing.
enum NotebookKernelState {
  /// No process yet; the first run will start one.
  stopped,

  starting,

  /// Running and waiting for a cell.
  ready,

  /// Running a cell right now.
  busy,

  /// Nothing on this machine can run this notebook.
  unavailable,
}

/// What happened when one cell ran.
@immutable
class NotebookExecution {
  const NotebookExecution({
    this.executionCount,
    this.failed = false,
    this.notice = '',
  });

  /// The `In [n]` number the kernel gave this run.
  final int? executionCount;

  /// Whether the cell raised.
  final bool failed;

  /// A message from the runner itself rather than from the code: a missing
  /// interpreter, a stopped kernel, output that grew too large.
  final String notice;
}

/// A long lived Python session that runs one cell at a time.
class NotebookKernel extends ChangeNotifier {
  NotebookKernel({
    required this.language,
    required this.workingDirectory,
  });

  /// The language the notebook declares.
  final String language;

  /// Where the code runs, so `open('data.csv')` means the same thing it does
  /// in the folder the notebook was saved in.
  final String workingDirectory;

  /// The languages that can be run here.
  static bool supportsLanguage(String language) =>
      language.trim().toLowerCase().startsWith('python');

  /// The interpreters looked for, most preferred first.
  static const List<String> pythonExecutables = ['python3', 'python', 'py'];

  static const String installHint =
      'Install Python 3 from python.org and make sure it is on your PATH.';

  Process? _process;
  Directory? _workspace;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  Completer<bool>? _starting;
  _PendingRun? _run;

  NotebookKernelState _state = NotebookKernelState.stopped;
  String _detail = '';
  String _inputPrompt = '';
  bool _awaitingInput = false;
  int _executionCount = 0;

  NotebookKernelState get state => _state;

  /// What to tell the reader: the interpreter in use, or why there is none.
  String get detail => _detail;

  bool get isBusy => _state == NotebookKernelState.busy;

  bool get isRunning => _process != null;

  /// Whether a cell is blocked on `input()`.
  bool get awaitingInput => _awaitingInput;

  String get inputPrompt => _inputPrompt;

  /// How many cells this session has run.
  int get executionCount => _executionCount;

  /// Whether a run can even be attempted.
  bool get canRun =>
      supportsLanguage(language) && _state != NotebookKernelState.unavailable;

  /// Why the notebook cannot be run, or an empty string when it can.
  String get blockedReason {
    if (!supportsLanguage(language)) {
      return 'AppFlowy runs Python notebooks with the Python installed on this '
          'computer. This notebook uses $language, so its cells can be read '
          'and edited here but not run.';
    }
    if (_state == NotebookKernelState.unavailable) {
      return _detail;
    }
    return '';
  }

  /// Starts the session if it is not already running.
  Future<bool> ensureStarted() {
    if (_process != null) {
      return Future.value(true);
    }
    final starting = _starting;
    if (starting != null) {
      return starting.future;
    }
    final completer = Completer<bool>();
    _starting = completer;
    unawaited(_start(completer));
    return completer.future;
  }

  Future<void> _start(Completer<bool> completer) async {
    if (!supportsLanguage(language)) {
      _fail('This notebook does not run Python.');
      completer.complete(false);
      _starting = null;
      return;
    }
    _setState(NotebookKernelState.starting);
    // A Python installed while AppFlowy was open should be found without a
    // restart, exactly as the code runner does it.
    clearExecutableCache();
    final executable = resolveExecutable(pythonExecutables);
    if (executable == null) {
      _fail('Python was not found on your PATH. $installHint');
      completer.complete(false);
      _starting = null;
      return;
    }

    try {
      final workspace =
          await Directory.systemTemp.createTemp('appflowy_notebook_');
      _workspace = workspace;
      final driver = File('${workspace.path}${Platform.pathSeparator}'
          'appflowy_notebook_kernel.py');
      await driver.writeAsString(_driverScript, flush: true);

      final process = await Process.start(
        executable.path,
        ['-u', driver.path],
        workingDirectory: await _resolveWorkingDirectory(),
        environment: const {
          'PYTHONIOENCODING': 'utf-8',
          'PYTHONUNBUFFERED': '1',
          // Charts must render to a bitmap the notebook can show, never to a
          // window nobody asked for.
          'MPLBACKEND': 'Agg',
        },
      );
      _process = process;
      const decoder = Utf8Decoder(allowMalformed: true);
      _stdout = process.stdout
          .transform(decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      _stderr = process.stderr
          .transform(decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _emit(
              NotebookOutput.stream(name: 'stderr', text: '$line\n'),
            ),
          );
      unawaited(process.exitCode.then((code) => _onExit(process, code)));
    } on ProcessException catch (error) {
      _fail('Python could not be started: ${error.message}');
      _starting = null;
      completer.complete(false);
      return;
    } on FileSystemException catch (error) {
      _fail('The notebook kernel could not be prepared: ${error.message}');
      _starting = null;
      completer.complete(false);
      return;
    }

    // The session announces itself once it is ready to take a cell.
    Timer(const Duration(seconds: 30), () {
      if (completer.isCompleted) {
        return;
      }
      _fail('Python did not start within 30 seconds.');
      _starting = null;
      completer.complete(false);
      unawaited(_disposeProcess());
    });
  }

  Future<String> _resolveWorkingDirectory() async {
    try {
      if (await Directory(workingDirectory).exists()) {
        return workingDirectory;
      }
    } on FileSystemException {
      // An unreadable directory simply is not where the code should run.
    }
    return Directory.systemTemp.path;
  }

  /// Runs one cell and reports its outputs as they are produced.
  Future<NotebookExecution> execute(
    String code, {
    required void Function(NotebookOutput output) onOutput,
  }) async {
    if (_run != null) {
      return const NotebookExecution(
        failed: true,
        notice: 'Another cell is still running.',
      );
    }
    if (!await ensureStarted()) {
      return NotebookExecution(
        failed: true,
        notice: _detail.isEmpty ? 'The kernel is not available.' : _detail,
      );
    }
    final process = _process;
    if (process == null) {
      return const NotebookExecution(
        failed: true,
        notice: 'The kernel is not running.',
      );
    }
    final run = _PendingRun(onOutput);
    _run = run;
    _setState(NotebookKernelState.busy);
    try {
      process.stdin.writeln(jsonEncode({'op': 'run', 'code': code}));
    } on SocketException catch (error) {
      _run = null;
      _setState(NotebookKernelState.stopped);
      return NotebookExecution(
        failed: true,
        notice: 'The kernel stopped: ${error.message}',
      );
    } on StateError {
      _run = null;
      _setState(NotebookKernelState.stopped);
      return const NotebookExecution(
        failed: true,
        notice: 'The kernel stopped.',
      );
    }
    return run.completer.future;
  }

  /// Answers an `input()` prompt, as if the line had been typed at a terminal.
  void provideInput(String text) {
    final process = _process;
    if (process == null || !_awaitingInput) {
      return;
    }
    _awaitingInput = false;
    _inputPrompt = '';
    notifyListeners();
    // The prompt is echoed so the transcript reads like a terminal session.
    _emit(NotebookOutput.stream(name: 'stdout', text: '$text\n'));
    try {
      process.stdin.writeln(jsonEncode({'op': 'input', 'text': text}));
    } on SocketException {
      // The kernel has already gone; the exit handler reports it.
    } on StateError {
      // Same.
    }
  }

  /// Stops the cell that is running.
  ///
  /// Python cannot be interrupted from outside on every platform, so the
  /// session is ended instead. Saying so plainly is better than a button that
  /// sometimes does nothing.
  Future<void> interrupt() async {
    if (_process == null) {
      return;
    }
    _run?.stopped = true;
    await _disposeProcess();
  }

  /// Ends the session and forgets every variable.
  Future<void> restart() async {
    await interrupt();
    _executionCount = 0;
    _setState(NotebookKernelState.stopped);
  }

  Future<void> shutdown() async {
    final process = _process;
    if (process != null) {
      try {
        process.stdin.writeln(jsonEncode({'op': 'shutdown'}));
      } on SocketException {
        // Killing it below is the fallback.
      } on StateError {
        // Same.
      }
    }
    await _disposeProcess();
    _setState(NotebookKernelState.stopped);
  }

  @override
  void dispose() {
    unawaited(_disposeProcess());
    super.dispose();
  }

  Future<void> _disposeProcess() async {
    final process = _process;
    _process = null;
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    process?.kill(ProcessSignal.sigkill);
    final workspace = _workspace;
    _workspace = null;
    if (workspace != null) {
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        // Windows can hold the script briefly; the OS sweeps temp.
      }
    }
  }

  void _onExit(Process process, int code) {
    // A restart leaves the old process to finish dying; it must not take the
    // new session down with it.
    if (_process != null && !identical(_process, process)) {
      return;
    }
    _process = null;
    _awaitingInput = false;
    _inputPrompt = '';
    final run = _run;
    if (run != null) {
      _run = null;
      run.finish(
        NotebookExecution(
          failed: true,
          notice: run.notice.isNotEmpty
              ? run.notice
              : run.stopped
                  ? 'Execution stopped. Variables from earlier cells were lost.'
                  : 'The kernel stopped unexpectedly (exit code $code). '
                      'Variables from earlier cells were lost.',
        ),
      );
    }
    final starting = _starting;
    if (starting != null && !starting.isCompleted) {
      _starting = null;
      _fail('Python stopped before the kernel was ready (exit code $code).');
      starting.complete(false);
      return;
    }
    if (_state != NotebookKernelState.unavailable) {
      _setState(NotebookKernelState.stopped);
    }
  }

  void _onLine(String line) {
    if (!line.startsWith(_protocolMark)) {
      // Anything a library writes straight to the console is still the cell's
      // output, so it is shown rather than dropped.
      _emit(NotebookOutput.stream(name: 'stdout', text: '$line\n'));
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line.substring(_protocolMark.length));
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    switch (decoded['t']) {
      case 'ready':
        _detail = [
          'Python ${decoded['version'] ?? ''}'.trim(),
          if (decoded['executable'] is String) decoded['executable'] as String,
        ].join('  ·  ');
        _setState(NotebookKernelState.ready);
        final starting = _starting;
        _starting = null;
        if (starting != null && !starting.isCompleted) {
          starting.complete(true);
        }
      case 'stream':
        _emit(
          NotebookOutput.stream(
            name: decoded['name'] as String? ?? 'stdout',
            text: decoded['text'] as String? ?? '',
          ),
        );
      case 'display':
      case 'result':
        _emit(
          NotebookOutput(
            kind: decoded['t'] == 'result'
                ? NotebookOutputKind.result
                : NotebookOutputKind.display,
            data: _readBundle(decoded['data']),
            executionCount:
                decoded['count'] is int ? decoded['count'] as int : null,
          ),
        );
      case 'error':
        _emit(
          NotebookOutput(
            kind: NotebookOutputKind.error,
            errorName: decoded['ename'] as String? ?? 'Error',
            errorValue: decoded['evalue'] as String? ?? '',
            traceback: decoded['traceback'] is List
                ? (decoded['traceback'] as List)
                    .map((entry) => entry.toString())
                    .toList()
                : const [],
          ),
        );
      case 'input_request':
        _awaitingInput = true;
        _inputPrompt = decoded['prompt'] as String? ?? '';
        notifyListeners();
      case 'done':
        _awaitingInput = false;
        _inputPrompt = '';
        final count = decoded['count'];
        if (count is int) {
          _executionCount = count;
        }
        final run = _run;
        _run = null;
        if (_process != null) {
          _setState(NotebookKernelState.ready);
        }
        if (run != null) {
          run.finish(
            NotebookExecution(
              executionCount: count is int ? count : null,
              failed: decoded['failed'] == true,
              notice: run.notice,
            ),
          );
        }
      default:
        break;
    }
  }

  Map<String, String> _readBundle(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  }

  void _emit(NotebookOutput output) {
    final run = _run;
    if (run == null) {
      return;
    }
    if (output.kind == NotebookOutputKind.stream) {
      run.characters += output.text.length;
    } else {
      run.characters +=
          output.data.values.fold<int>(0, (sum, value) => sum + value.length);
    }
    if (run.characters > maxNotebookOutputCharacters) {
      if (!run.stopped) {
        run.stopped = true;
        run.notice = 'This cell printed too much, so the kernel was stopped.';
        Log.info('[Notebook] output cap reached; stopping the kernel');
        unawaited(_disposeProcess());
      }
      return;
    }
    run.onOutput(output);
  }

  void _fail(String message) {
    _detail = message;
    _setState(NotebookKernelState.unavailable);
  }

  void _setState(NotebookKernelState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    notifyListeners();
  }
}

/// One cell in flight.
class _PendingRun {
  _PendingRun(this.onOutput);

  final void Function(NotebookOutput output) onOutput;
  final Completer<NotebookExecution> completer = Completer<NotebookExecution>();
  int characters = 0;
  bool stopped = false;
  String notice = '';

  void finish(NotebookExecution execution) {
    if (!completer.isCompleted) {
      completer.complete(execution);
    }
  }
}

/// The marker every protocol line starts with.
///
/// A record separator followed by a tag: printable output practically never
/// contains it, and a cell that does print it only confuses its own display.
const String _protocolMark = '\x1e[appflowy-notebook]';

/// The Python side of the session.
///
/// It reads one JSON command per line, runs the cell in a namespace that lives
/// for as long as the process does, and reports everything back as framed JSON
/// so printed text and protocol messages can never be confused.
const String _driverScript = r'''
import sys, os, json, ast, io, base64, builtins, traceback

MARK = "\x1e[appflowy-notebook]"

_stdout = sys.__stdout__
_stdin = sys.__stdin__


def send(payload):
    try:
        _stdout.write(MARK + json.dumps(payload) + "\n")
        _stdout.flush()
    except Exception:
        pass


class _Stream(io.TextIOBase):
    def __init__(self, name):
        super().__init__()
        self._name = name

    def writable(self):
        return True

    def write(self, text):
        if text:
            send({"t": "stream", "name": self._name, "text": text})
        return len(text)

    def flush(self):
        pass

    def isatty(self):
        return False


def _bundle(value):
    data = {}
    for attribute, mime in (
        ("_repr_html_", "text/html"),
        ("_repr_markdown_", "text/markdown"),
        ("_repr_svg_", "image/svg+xml"),
        ("_repr_latex_", "text/latex"),
    ):
        render = getattr(value, attribute, None)
        if callable(render):
            try:
                rendered = render()
            except Exception:
                rendered = None
            if isinstance(rendered, str) and rendered.strip():
                data[mime] = rendered
    for attribute, mime in (("_repr_png_", "image/png"), ("_repr_jpeg_", "image/jpeg")):
        render = getattr(value, attribute, None)
        if callable(render):
            try:
                raw = render()
            except Exception:
                raw = None
            if isinstance(raw, (bytes, bytearray)):
                data[mime] = base64.b64encode(bytes(raw)).decode("ascii")
            elif isinstance(raw, str) and raw.strip():
                data[mime] = raw
    try:
        data["text/plain"] = repr(value)
    except Exception:
        data["text/plain"] = "<unprintable object>"
    return data


def display(*values):
    for value in values:
        send({"t": "display", "data": _bundle(value)})


def _flush_figures():
    pyplot = sys.modules.get("matplotlib.pyplot")
    if pyplot is None:
        return
    try:
        numbers = list(pyplot.get_fignums())
    except Exception:
        return
    for number in numbers:
        try:
            figure = pyplot.figure(number)
            buffer = io.BytesIO()
            figure.savefig(buffer, format="png", bbox_inches="tight")
            send(
                {
                    "t": "display",
                    "data": {
                        "image/png": base64.b64encode(buffer.getvalue()).decode("ascii"),
                        "text/plain": "<Figure %d>" % number,
                    },
                }
            )
        except Exception:
            pass
    try:
        pyplot.close("all")
    except Exception:
        pass


def _input(prompt=""):
    text = "" if prompt is None else str(prompt)
    if text:
        sys.stdout.write(text)
    send({"t": "input_request", "prompt": text})
    line = _stdin.readline()
    if not line:
        raise EOFError("no input was given")
    try:
        message = json.loads(line)
    except Exception:
        return line.rstrip("\r\n")
    if isinstance(message, dict) and message.get("op") == "input":
        return message.get("text", "")
    raise EOFError("no input was given")


builtins.input = _input

NAMESPACE = {
    "__name__": "__main__",
    "__builtins__": builtins,
    "display": display,
}


def _prepare(code):
    """Drops the notebook magics this runner cannot honour, and says so."""
    lines = code.split("\n")
    kept = []
    notes = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("%%"):
            notes.append("Cell magic '%s' was ignored." % stripped.split()[0])
            kept.append("")
        elif stripped.startswith("%"):
            name = stripped.split()[0]
            if not name.startswith("%matplotlib"):
                notes.append("Magic command '%s' was ignored." % name)
            kept.append("")
        elif stripped.startswith("!"):
            notes.append(
                "Shell command '%s' was not run: AppFlowy does not hand notebook "
                "lines to a command interpreter." % stripped[:40]
            )
            kept.append("")
        else:
            kept.append(line)
    return "\n".join(kept), notes


def _run(code):
    prepared, notes = _prepare(code)
    for note in notes:
        send({"t": "stream", "name": "stderr", "text": note + "\n"})
    module = ast.parse(prepared, filename="<cell>", mode="exec")
    body = module.body
    tail = None
    if body and isinstance(body[-1], ast.Expr):
        tail = ast.Expression(body[-1].value)
        ast.copy_location(tail, body[-1])
        body = body[:-1]
    if body:
        block = ast.Module(body=body, type_ignores=[])
        exec(compile(block, "<cell>", "exec"), NAMESPACE)
    if tail is not None:
        value = eval(compile(tail, "<cell>", "eval"), NAMESPACE)
        if value is not None:
            NAMESPACE["_"] = value
            send({"t": "result", "data": _bundle(value), "count": COUNT})
    _flush_figures()


COUNT = 0

send(
    {
        "t": "ready",
        "version": sys.version.split()[0],
        "executable": sys.executable,
    }
)

while True:
    line = _stdin.readline()
    if not line:
        break
    line = line.strip()
    if not line:
        continue
    try:
        message = json.loads(line)
    except Exception:
        continue
    if not isinstance(message, dict):
        continue
    operation = message.get("op")
    if operation == "shutdown":
        break
    if operation != "run":
        continue
    COUNT += 1
    failed = False
    sys.stdout = _Stream("stdout")
    sys.stderr = _Stream("stderr")
    try:
        _run(message.get("code", ""))
    except SystemExit:
        pass
    except BaseException:
        failed = True
        kind, value, tb = sys.exc_info()
        # A reader wants their own code, not the frames of this runner, so the
        # traceback starts at the first frame that belongs to the cell.
        cell_tb = tb
        while cell_tb is not None and cell_tb.tb_frame.f_code.co_filename != "<cell>":
            cell_tb = cell_tb.tb_next
        if cell_tb is None:
            frames = traceback.format_exception_only(kind, value)
        else:
            frames = traceback.format_exception(kind, value, cell_tb)
        lines = []
        for frame in frames:
            lines.extend(frame.rstrip("\n").split("\n"))
        send(
            {
                "t": "error",
                "ename": kind.__name__ if kind else "Error",
                "evalue": str(value),
                "traceback": lines,
            }
        )
    finally:
        try:
            sys.stdout.flush()
            sys.stderr.flush()
        except Exception:
            pass
        sys.stdout = _stdout
        sys.stderr = sys.__stderr__
        send({"t": "done", "count": COUNT, "failed": failed})
''';
