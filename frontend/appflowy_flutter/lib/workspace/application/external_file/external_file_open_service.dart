import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Receives the paths of files to show.
typedef ExternalFileOpener = void Function(List<String> paths);

/// Files the operating system asks AppFlowy to open: from a file manager,
/// "Open with", or the command line.
///
/// The native runner sends them on [channelName] as `openFiles`, and holds
/// those that arrive before Dart is listening until `takePendingFiles`. They
/// wait here until the home screen can show them.
class ExternalFileOpenService {
  ExternalFileOpenService._();

  static final instance = ExternalFileOpenService._();

  static const channelName = 'appflowy/file_open';

  static const _channel = MethodChannel(channelName);

  final List<String> _pending = [];
  ExternalFileOpener? _opener;

  Future<void> start() async {
    _channel.setMethodCallHandler(_handle);
    try {
      final paths = await _channel.invokeListMethod<String>('takePendingFiles');
      receive(paths ?? const []);
    } on MissingPluginException {
      // This runner does not open files, as on mobile or in tests.
    } on PlatformException catch (error) {
      Log.warn('Could not read the files to open: $error');
    }
  }

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'openFiles') {
      throw MissingPluginException(call.method);
    }
    final arguments = call.arguments;
    if (arguments is List) {
      receive(arguments.whereType<String>());
    }
  }

  /// Shows [values], paths or `file:` URIs, once the home screen is ready.
  void receive(Iterable<String> values) {
    final paths = <String>{};
    for (final value in values) {
      final path = normalizeExternalFilePath(value);
      if (path != null) paths.add(path);
    }
    if (paths.isEmpty) return;
    final opener = _opener;
    if (opener == null) {
      _pending.addAll(paths.where((path) => !_pending.contains(path)));
      return;
    }
    opener(paths.toList());
  }

  /// Hands [opener] every file that arrived before it, then each new one.
  void attach(ExternalFileOpener opener) {
    _opener = opener;
    if (_pending.isEmpty) return;
    final paths = List.of(_pending);
    _pending.clear();
    opener(paths);
  }

  void detach(ExternalFileOpener opener) {
    if (_opener == opener) _opener = null;
  }
}

/// A URI with a scheme other than `file:`, such as a deep link. The scheme has
/// two characters at least, so a Windows drive letter never matches.
final _otherUri = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]+://');

/// An absolute, normalized path for [value], a path or a `file:` URI, or null
/// when it names no local file. [context] defaults to this platform's.
String? normalizeExternalFilePath(String value, {p.Context? context}) {
  final paths = context ?? p.context;
  var path = value.trim();
  if (path.isEmpty) return null;
  if (path.toLowerCase().startsWith('file:')) {
    try {
      path = Uri.parse(path).toFilePath(
        windows: paths.style == p.Style.windows,
      );
    } on FormatException {
      return null;
    } on UnsupportedError {
      // A URI for another host is not a local file.
      return null;
    }
  } else if (_otherUri.hasMatch(path)) {
    return null;
  }
  return paths.normalize(paths.absolute(path));
}
