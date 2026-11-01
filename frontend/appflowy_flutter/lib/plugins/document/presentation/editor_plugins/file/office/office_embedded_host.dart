import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'office_embedded_page.dart';

/// Points AppFlowy at an unpacked editor, for development and tests.
const kOfficeEditorDirectoryEnvironment = 'APPFLOWY_OFFICE_EDITOR_DIR';

/// The folder the platform builds install next to the executable.
const kOfficeEditorFolderName = 'office_editor';

/// Files without which the bundled editor cannot start.
const _requiredBundleFiles = [
  'editor.html',
  'web-apps/apps/api/documents/api.js',
  'sdkjs/common/wasm/x2t/x2t.wasm.br',
];

/// Formats the bundled editor reads, keyed by extension.
const _embeddedReadable = {
  'docx',
  'doc',
  'odt',
  'rtf',
  'txt',
  'xlsx',
  'xls',
  'ods',
  'csv',
  'pptx',
  'ppt',
  'odp',
};

/// Formats the bundled editor writes back in the same format. The legacy
/// binary formats (doc, xls, ppt) can only be saved as their OOXML
/// successors, so they open read only rather than change format on save.
const _embeddedWritable = {
  'docx',
  'odt',
  'rtf',
  'txt',
  'xlsx',
  'ods',
  'csv',
  'pptx',
  'odp',
};

String _extensionOf(String name) =>
    p.extension(name).replaceFirst('.', '').toLowerCase();

/// Whether the bundled editor can open [name].
bool canEmbedOfficeFile(String name) =>
    _embeddedReadable.contains(_extensionOf(name));

/// Whether the bundled editor can save [name] without changing its format.
bool canEmbedOfficeFileForEditing(String name) =>
    _embeddedWritable.contains(_extensionOf(name));

/// Where a build installs the editor, most specific first.
@visibleForTesting
List<String> officeEditorBundleCandidates({
  required String executable,
  required Map<String, String> environment,
  required bool isMacOS,
}) {
  final executableDirectory = p.dirname(executable);
  return [
    if ((environment[kOfficeEditorDirectoryEnvironment] ?? '')
        .trim()
        .isNotEmpty)
      environment[kOfficeEditorDirectoryEnvironment]!.trim(),
    if (isMacOS)
      p.normalize(
        p.join(executableDirectory, '..', 'Resources', kOfficeEditorFolderName),
      ),
    p.join(executableDirectory, 'data', kOfficeEditorFolderName),
  ];
}

/// Finds the bundled editor, or null when this build ships without it.
///
/// A handful of stat calls, done synchronously so the answer is ready on the
/// first frame.
Directory? locateOfficeEditorBundle({
  String? executable,
  Map<String, String>? environment,
  bool? isMacOS,
}) {
  if (kIsWeb) {
    return null;
  }
  final candidates = officeEditorBundleCandidates(
    executable: executable ?? Platform.resolvedExecutable,
    environment: environment ?? Platform.environment,
    isMacOS: isMacOS ?? Platform.isMacOS,
  );
  for (final candidate in candidates) {
    final directory = Directory(candidate);
    final complete = _requiredBundleFiles.every(
      (required) => File(p.join(directory.path, required)).existsSync(),
    );
    if (complete) {
      return directory;
    }
  }
  return null;
}

/// Where an embedded editing session stands.
enum EmbeddedOfficePhase { loading, ready, failed }

@immutable
class EmbeddedOfficeStatus {
  const EmbeddedOfficeStatus({
    this.phase = EmbeddedOfficePhase.loading,
    this.dirty = false,
    this.saving = false,
    this.lastSaved,
    this.error,
  });

  final EmbeddedOfficePhase phase;

  /// Edits the file on disk does not have yet.
  final bool dirty;
  final bool saving;
  final DateTime? lastSaved;
  final String? error;

  bool get settled => !dirty && !saving;

  EmbeddedOfficeStatus copyWith({
    EmbeddedOfficePhase? phase,
    bool? dirty,
    bool? saving,
    DateTime? lastSaved,
    String? error,
    bool clearError = false,
  }) =>
      EmbeddedOfficeStatus(
        phase: phase ?? this.phase,
        dirty: dirty ?? this.dirty,
        saving: saving ?? this.saving,
        lastSaved: lastSaved ?? this.lastSaved,
        error: clearError ? null : error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      other is EmbeddedOfficeStatus &&
      other.phase == phase &&
      other.dirty == dirty &&
      other.saving == saving &&
      other.lastSaved == lastSaved &&
      other.error == error;

  @override
  int get hashCode => Object.hash(phase, dirty, saving, lastSaved, error);
}

/// One document open in the bundled editor.
///
/// A session outlives the widget that opened it: a window or a WebView that
/// is still saving keeps it alive, and it writes straight to [file].
class EmbeddedOfficeSession {
  EmbeddedOfficeSession._({
    required this.token,
    required this.host,
    required this.file,
    required this.fileName,
    required this.editable,
    required this.relayScroll,
    required OfficeEmbeddedTheme theme,
  })  : _theme = theme,
        status = ValueNotifier(const EmbeddedOfficeStatus());

  final String token;
  final EmbeddedOfficeHost host;
  final File file;
  final String fileName;
  final bool editable;

  /// Whether the page forwards editor scroll state to a Flutter WebView.
  final bool relayScroll;
  final ValueNotifier<EmbeddedOfficeStatus> status;

  OfficeEmbeddedTheme _theme;
  OfficeEmbeddedTheme get theme => _theme;

  final _commandStreams = <HttpResponse>{};
  bool _closed = false;

  /// The newest page event applied; older ones arriving late are ignored.
  int _lastSequence = -1;

  bool get isClosed => _closed;

  /// The page that boots the editor for this document.
  Uri get pageUrl => host.origin.replace(path: '/__appflowy__/office/$token/');

  String get identity => officeFileIdentity(file);

  /// Saves outstanding edits, resolving once the file on disk has them.
  Future<bool> flush({Duration timeout = const Duration(seconds: 30)}) async {
    if (!editable || _closed) {
      return true;
    }
    if (status.value.settled) {
      return true;
    }
    final settled = Completer<bool>();
    void listener() {
      final value = status.value;
      if (value.settled && !settled.isCompleted) {
        settled.complete(true);
      } else if (value.error != null && !value.saving && !settled.isCompleted) {
        settled.complete(false);
      }
    }

    status.addListener(listener);
    try {
      if (!status.value.saving) {
        _send({'type': 'save'});
      }
      return await settled.future.timeout(timeout, onTimeout: () => false);
    } finally {
      status.removeListener(listener);
    }
  }

  /// Repaints the editor with [theme], saving first so nothing is lost when
  /// the editor reloads the file. [force] reloads even for the same theme,
  /// for changes such as new user scripts that only a fresh page picks up.
  Future<void> updateTheme(
    OfficeEmbeddedTheme theme, {
    bool force = false,
  }) async {
    if (_closed || (theme == _theme && !force)) {
      return;
    }
    _theme = theme;
    await flush();
    if (_closed) {
      return;
    }
    _update((status) => status.copyWith(phase: EmbeddedOfficePhase.loading));
    _send({'type': 'reload', 'theme': theme.toJson()});
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final response in _commandStreams.toList()) {
      unawaited(response.close().catchError((_) {}));
    }
    _commandStreams.clear();
    host._sessions.remove(token);
  }

  void _send(Map<String, Object?> command) {
    final line = 'data: ${jsonEncode(command)}\n\n';
    for (final response in _commandStreams.toList()) {
      try {
        response.write(line);
        unawaited(response.flush().catchError((_) {}));
      } catch (_) {
        _commandStreams.remove(response);
      }
    }
  }

  void _update(
    EmbeddedOfficeStatus Function(EmbeddedOfficeStatus) change, {
    int? sequence,
  }) {
    if (_closed) {
      return;
    }
    if (sequence != null) {
      if (sequence <= _lastSequence) {
        return;
      }
      _lastSequence = sequence;
    }
    final next = change(status.value);
    if (next != status.value) {
      status.value = next;
    }
  }
}

/// Compares files by path, the way the platform's file system does.
String officeFileIdentity(File file) {
  final path = p.normalize(p.absolute(file.path));
  return Platform.isWindows || Platform.isMacOS ? path.toLowerCase() : path;
}

/// Serves the bundled office editor and the documents open in it over a
/// loopback HTTP origin.
///
/// The editor is a static web app, but it compiles WebAssembly with threads,
/// spawns workers and loads fonts on demand, none of which a WebView will do
/// from `file://`. The server sends the cross-origin isolation headers those
/// threads need, and each open document gets an unguessable token through
/// which its page reads the file, saves it and receives commands.
class EmbeddedOfficeHost {
  EmbeddedOfficeHost({Directory? Function()? locate})
      : _locate = locate ?? locateOfficeEditorBundle;

  static final EmbeddedOfficeHost instance = EmbeddedOfficeHost();

  static const _tokenBytes = 24;
  static const _maxDocumentBytes = 512 * 1024 * 1024;

  final Directory? Function() _locate;
  final Random _random = Random.secure();
  final Map<String, EmbeddedOfficeSession> _sessions = {};

  bool _located = false;
  Directory? _bundle;
  HttpServer? _server;
  Future<HttpServer>? _starting;
  Timer? _heartbeat;

  /// Whether this build ships the editor.
  Future<bool> get isAvailable => SynchronousFuture(bundle != null);

  /// The unpacked editor, looked up once.
  Directory? get bundle {
    if (!_located) {
      _located = true;
      try {
        _bundle = _locate();
      } catch (error) {
        Log.error('Unable to locate the bundled office editor: $error');
      }
    }
    return _bundle;
  }

  Uri get origin {
    final server = _server;
    if (server == null) {
      throw StateError('The office editor host is not running.');
    }
    return Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
  }

  Iterable<EmbeddedOfficeSession> get sessions => _sessions.values;

  /// Opens [file] in the bundled editor.
  Future<EmbeddedOfficeSession> open({
    required File file,
    required String fileName,
    required bool editable,
    required OfficeEmbeddedTheme theme,
    bool relayScroll = false,
  }) async {
    final root = bundle;
    if (root == null) {
      throw StateError('This build does not include the office editor.');
    }
    await _ensureServer(root);
    final session = EmbeddedOfficeSession._(
      token: _newToken(),
      host: this,
      file: file,
      fileName: fileName,
      editable: editable && canEmbedOfficeFileForEditing(fileName),
      relayScroll: relayScroll,
      theme: theme,
    );
    _sessions[session.token] = session;
    return session;
  }

  /// The open session for [file] that edits it, if any.
  EmbeddedOfficeSession? editingSessionFor(File file) {
    final identity = officeFileIdentity(file);
    for (final session in _sessions.values) {
      if (session.editable && session.identity == identity) {
        return session;
      }
    }
    return null;
  }

  Future<void> shutdown() async {
    for (final session in _sessions.values.toList()) {
      session.close();
    }
    _heartbeat?.cancel();
    _heartbeat = null;
    final server = _server;
    _server = null;
    _starting = null;
    await server?.close(force: true);
  }

  Future<HttpServer> _ensureServer(Directory root) {
    final running = _server;
    if (running != null) {
      return Future.value(running);
    }
    return _starting ??= () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.autoCompress = false;
      server.idleTimeout = const Duration(minutes: 2);
      server.listen(
        (request) => unawaited(_handle(request, root)),
        onError: (Object error) =>
            Log.error('The office editor host failed: $error'),
      );
      _server = server;
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        for (final session in _sessions.values) {
          for (final response in session._commandStreams.toList()) {
            try {
              response.write(': keep-alive\n\n');
              unawaited(response.flush().catchError((_) {}));
            } catch (_) {
              session._commandStreams.remove(response);
            }
          }
        }
      });
      return server;
    }();
  }

  Future<void> _handle(HttpRequest request, Directory root) async {
    final response = request.response;
    try {
      _setCommonHeaders(response);
      if (!_isOwnHost(request)) {
        return _status(response, HttpStatus.forbidden);
      }
      final path = request.uri.path;
      if (path == '/__appflowy__/shim.js') {
        return _sendText(
          request,
          officeEmbeddedShimScript,
          ContentType('text', 'javascript', charset: 'utf-8'),
        );
      }
      if (path.startsWith('/__appflowy__/office/')) {
        return await _handleSession(request);
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        return _status(response, HttpStatus.methodNotAllowed);
      }
      return await _serveBundleFile(request, root);
    } catch (error) {
      Log.error(
        'The office editor host could not answer ${request.uri}: $error',
      );
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  bool _isOwnHost(HttpRequest request) {
    final port = _server?.port;
    final host = request.headers.value(HttpHeaders.hostHeader);
    return host == '127.0.0.1:$port' || host == 'localhost:$port';
  }

  /// Writes need the page's own origin, so no other site can post to a
  /// document even with its token.
  bool _isOwnOrigin(HttpRequest request) =>
      request.headers.value('origin') == origin.toString();

  Future<void> _handleSession(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    // __appflowy__ / office / <token> / [resource]
    if (segments.length < 3) {
      return _status(response, HttpStatus.notFound);
    }
    final session = _sessions[segments[2]];
    if (session == null || session.isClosed) {
      return _status(response, HttpStatus.notFound);
    }
    final resource = segments.length > 3 ? segments[3] : '';

    switch ((request.method, resource)) {
      case ('GET' || 'HEAD', ''):
        return _sendText(
          request,
          buildOfficeEmbeddedPage(
            fileName: session.fileName,
            editable: session.editable,
            theme: session.theme,
            origin: origin.toString(),
            relayScroll: session.relayScroll,
          ),
          ContentType.html,
        );
      case ('GET' || 'HEAD', 'document'):
        return _sendDocument(request, session);
      case ('PUT', 'document'):
        return _receiveDocument(request, session);
      case ('POST', 'events'):
        return _receiveEvent(request, session);
      case ('GET', 'commands'):
        return _openCommandStream(request, session);
    }
    return _status(response, HttpStatus.notFound);
  }

  Future<void> _sendDocument(
    HttpRequest request,
    EmbeddedOfficeSession session,
  ) async {
    final response = request.response;
    final Uint8List bytes;
    try {
      bytes = await session.file.readAsBytes();
    } on FileSystemException catch (error) {
      Log.error('Unable to read ${session.fileName}: $error');
      return _status(response, HttpStatus.notFound);
    }
    response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..contentLength = bytes.length;
    if (request.method != 'HEAD') {
      response.add(bytes);
    }
    await response.close();
  }

  Future<void> _receiveDocument(
    HttpRequest request,
    EmbeddedOfficeSession session,
  ) async {
    final response = request.response;
    if (!_isOwnOrigin(request)) {
      return _status(response, HttpStatus.forbidden);
    }
    if (!session.editable) {
      return _status(response, HttpStatus.methodNotAllowed);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > _maxDocumentBytes) {
        return _status(response, HttpStatus.requestEntityTooLarge);
      }
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      return _status(response, HttpStatus.badRequest);
    }
    final stillDirty = request.headers.value('x-appflowy-dirty') == 'true';
    final sequence =
        int.tryParse(request.headers.value('x-appflowy-seq') ?? '');
    try {
      await writeOfficeFileAtomically(session.file, bytes);
    } on FileSystemException catch (error) {
      Log.error('Unable to save ${session.fileName}: $error');
      session._update(
        (status) => status.copyWith(
          saving: false,
          dirty: true,
          error: 'AppFlowy could not save ${session.fileName}.',
        ),
        sequence: sequence,
      );
      return _status(response, HttpStatus.conflict);
    }
    session._update(
      (status) => status.copyWith(
        saving: false,
        dirty: stillDirty,
        lastSaved: DateTime.now(),
        clearError: true,
      ),
      sequence: sequence,
    );
    // Other views of the same file pick the new bytes up.
    for (final other in _sessions.values.toList()) {
      if (other != session && other.identity == session.identity) {
        other._send({'type': 'external-change'});
      }
    }
    await _status(response, HttpStatus.noContent);
  }

  Future<void> _receiveEvent(
    HttpRequest request,
    EmbeddedOfficeSession session,
  ) async {
    final response = request.response;
    if (!_isOwnOrigin(request)) {
      return _status(response, HttpStatus.forbidden);
    }
    final body = await utf8.decoder.bind(request).join();
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return _status(response, HttpStatus.badRequest);
    }
    if (decoded is! Map) {
      return _status(response, HttpStatus.badRequest);
    }
    final message =
        decoded['message'] is String ? decoded['message'] as String : null;
    final sequence = decoded['seq'] is int ? decoded['seq'] as int : null;
    switch (decoded['type']) {
      case 'opened':
        session._update(
          (status) => status.copyWith(
            phase: EmbeddedOfficePhase.ready,
            dirty: false,
            saving: false,
            clearError: true,
          ),
          sequence: sequence,
        );
      case 'open-failed':
        Log.error('The office editor could not open ${session.fileName}: '
            '$message');
        session._update(
          (status) => status.copyWith(
            phase: EmbeddedOfficePhase.failed,
            error: message ?? 'The document could not be opened.',
          ),
          sequence: sequence,
        );
      case 'dirty':
        final dirty = decoded['dirty'] == true;
        session._update(
          (status) => status.copyWith(dirty: dirty),
          sequence: sequence,
        );
      case 'saving':
        session._update(
          (status) => status.copyWith(saving: true),
          sequence: sequence,
        );
      case 'clean':
        session._update(
          (status) => status.copyWith(dirty: false, saving: false),
          sequence: sequence,
        );
      case 'save-failed':
        Log.error('The office editor could not save ${session.fileName}: '
            '$message');
        session._update(
          (status) => status.copyWith(
            saving: false,
            dirty: true,
            error: message ?? 'The document could not be saved.',
          ),
          sequence: sequence,
        );
      default:
        return _status(response, HttpStatus.badRequest);
    }
    await _status(response, HttpStatus.noContent);
  }

  Future<void> _openCommandStream(
    HttpRequest request,
    EmbeddedOfficeSession session,
  ) async {
    final response = request.response;
    response.bufferOutput = false;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    session._commandStreams.add(response);
    response.write(': connected\n\n');
    await response.flush();
    unawaited(
      response.done.catchError((_) {}).whenComplete(
            () => session._commandStreams.remove(response),
          ),
    );
  }

  Future<void> _serveBundleFile(HttpRequest request, Directory root) async {
    final response = request.response;
    var relative = Uri.decodeComponent(request.uri.path);
    if (relative == '/' || relative == '/editor') {
      relative = '/editor.html';
    }
    final segments = relative.split('/').where((part) => part.isNotEmpty);
    if (segments
        .any((part) => part == '..' || part == '.' || part.contains('\\'))) {
      return _status(response, HttpStatus.notFound);
    }
    final path = p.normalize(p.joinAll([root.path, ...segments]));
    if (!p.isWithin(root.path, path)) {
      return _status(response, HttpStatus.notFound);
    }
    final file = File(path);
    if (!await file.exists()) {
      return _status(response, HttpStatus.notFound);
    }

    final name = p.basename(path);
    final isEditorPage = relative == '/editor.html';
    final headers = response.headers;
    // Every launch serves from a new port, so a cached copy could never be
    // used again: storing the bundle (x2t alone is 42 MB decoded) would only
    // fill the user's cache directory.
    headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (isEditorPage) {
      final html = await file.readAsString();
      return _sendText(
        request,
        injectOfficeEmbeddedShim(html),
        ContentType.html,
      );
    }

    final length = await file.length();
    if (relative.startsWith('/fonts/')) {
      headers.contentType = ContentType('font', 'ttf');
    } else if (name.endsWith('.br')) {
      // x2t ships as `.br` but the published bundle holds gzip bytes; the
      // header has to describe what is actually sent.
      final head = await _readHead(file, 2);
      headers
        ..contentType = ContentType.binary
        ..set(
          HttpHeaders.contentEncodingHeader,
          head.length == 2 && head[0] == 0x1f && head[1] == 0x8b
              ? 'gzip'
              : 'br',
        );
    } else {
      headers.contentType = _contentTypeFor(name);
    }
    headers.contentLength = length;
    if (request.method == 'HEAD') {
      return response.close();
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  static Future<List<int>> _readHead(File file, int count) async {
    final handle = await file.open();
    try {
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  void _setCommonHeaders(HttpResponse response) {
    response.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer');
  }

  Future<void> _sendText(
    HttpRequest request,
    String text,
    ContentType type,
  ) async {
    final response = request.response;
    final bytes = utf8.encode(text);
    response.headers
      ..contentType = type
      ..contentLength = bytes.length
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (request.method != 'HEAD') {
      response.add(bytes);
    }
    await response.close();
  }

  Future<void> _status(HttpResponse response, int code) async {
    response.statusCode = code;
    response.headers.contentLength = 0;
    await response.close();
  }

  String _newToken() {
    final bytes = List<int>.generate(_tokenBytes, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Replaces [file] with [bytes] without leaving it half written.
Future<void> writeOfficeFileAtomically(File file, List<int> bytes) async {
  final temporary = File(
    p.join(
      p.dirname(file.path),
      '.${p.basename(file.path)}.appflowy-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  } on FileSystemException {
    // A file another program holds open cannot be replaced, but it can
    // usually still be overwritten in place.
    if (await temporary.exists()) {
      await temporary.delete().catchError((_) => temporary);
    }
    await file.writeAsBytes(bytes, flush: true);
  }
}

ContentType _contentTypeFor(String name) {
  final extension = p.extension(name).toLowerCase();
  return switch (extension) {
    '.html' || '.htm' => ContentType.html,
    '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
    '.css' => ContentType('text', 'css', charset: 'utf-8'),
    '.json' => ContentType.json,
    '.wasm' => ContentType('application', 'wasm'),
    '.svg' => ContentType('image', 'svg+xml'),
    '.png' => ContentType('image', 'png'),
    '.jpg' || '.jpeg' => ContentType('image', 'jpeg'),
    '.gif' => ContentType('image', 'gif'),
    '.ico' => ContentType('image', 'x-icon'),
    '.woff' => ContentType('font', 'woff'),
    '.woff2' => ContentType('font', 'woff2'),
    '.ttf' => ContentType('font', 'ttf'),
    '.otf' => ContentType('font', 'otf'),
    '.txt' => ContentType.text,
    '.xml' => ContentType('application', 'xml', charset: 'utf-8'),
    '.dic' || '.aff' || '.bin' => ContentType.binary,
    _ => ContentType.binary,
  };
}
