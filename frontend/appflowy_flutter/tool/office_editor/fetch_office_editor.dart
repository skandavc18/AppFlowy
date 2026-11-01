// Fetches AppFlowy's built-in office editor into `office_editor/`.
//
// Run from `frontend/appflowy_flutter`:
//   dart run tool/office_editor/fetch_office_editor.dart [--force]
//       [--layer-file <layer.tar.gz>] [--output <directory>]
//
// The editor is the static build of ranuts/document (AGPL-3.0): ONLYOFFICE's
// sdkjs and web-apps with the x2t converter compiled to WebAssembly, so Word,
// Excel and PowerPoint files open, edit and save without a document server.
// The build is pinned to one image layer by digest and verified before it is
// used. The Linux and Windows CMake files and the macOS Xcode project copy the
// folder next to the executable; at runtime AppFlowy serves it over loopback.
//
// To move to a newer build, point [_imageTag], [_layerDigest] and [_revision]
// at the `public/` layer of another `ghcr.io/ranuts/document:sha-<commit>`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _registry = 'ghcr.io';
const _repository = 'ranuts/document';
const _imageTag = 'sha-e975654';
const _layerDigest =
    'sha256:5190af68b679f02829b2c6a8bbbb79ba0dc518a4fc56c094d9b00fb78755d85e';
const _revision = 'e975654679d2cc3ef61d67d93fdce2839327676c';

/// Bumped whenever the local fixes applied on top of the build change, so an
/// older copy is replaced rather than reported as up to date.
const _bundleFormat = 2;

/// Written last, so its presence marks a complete, verified copy.
const bundleManifestName = 'APPFLOWY_BUNDLE.json';

/// Files the editor cannot start without.
const _requiredFiles = [
  'editor.html',
  'web-apps/apps/api/documents/api.js',
  'sdkjs/common/AllFonts.js',
  'sdkjs/common/wasm/x2t/x2t.js',
  'sdkjs/common/wasm/x2t/x2t.wasm.br',
  'sdkjs/word/sdk-all-min.js',
  'sdkjs/cell/sdk-all-min.js',
  'sdkjs/slide/sdk-all-min.js',
  'LICENSE',
  'NOTICE',
];

/// Parts of the published site AppFlowy never loads: the localized marketing
/// pages, the opt-in on-device AI models, the Visio viewer and the mobile and
/// embedded editor shells (the desktop shell is always the one requested).
final _excluded = <RegExp>[
  RegExp('^(zh-CN|pt|es|de|ko|ja|social|open|convert|help)/'),
  RegExp(
    '^(about|contact|changelog|help|ai-document-assistant|'
    'edit-documents-without-account|embed-document-editor|'
    'no-signup-document-editor|offline-document-editor|'
    'onlyoffice-online-free|private-document-editor|'
    r'webmcp-document-editor)\.html$',
  ),
  RegExp(
    r'^(sitemap\.xml|llms\.txt|llms-full\.txt|landing\.css|'
    r'landing-prefetch\.js|home\.css|_redirects|_headers)$',
  ),
  RegExp('^assets/(wllama|webllm)'),
  RegExp('^sdkjs/visio/'),
  RegExp('^web-apps/apps/visioeditor/'),
  RegExp('^web-apps/apps/[^/]+/(mobile|embed|forms)/'),
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final output = Directory(p.absolute(options.output));
  final manifest = File(p.join(output.path, bundleManifestName));

  if (!options.force && await _isCurrent(manifest)) {
    stdout.writeln('The office editor in ${output.path} is up to date.');
    return;
  }

  final staging = Directory('${output.path}.partial');
  if (await staging.exists()) {
    await staging.delete(recursive: true);
  }
  await staging.create(recursive: true);

  try {
    final layerFile = options.layerFile;
    final layer = layerFile == null
        ? _layerFromRegistry()
        : _verified(
            File(layerFile).openRead(),
            total: await File(layerFile).length(),
          );
    final stats = await _unpack(layer, staging);

    final identity = File(p.join(staging.path, 'build-identity.json'));
    final revision = await identity.exists()
        ? (jsonDecode(await identity.readAsString()) as Map)['revision']
        : null;
    if (revision != _revision) {
      throw StateError(
        'The editor build is revision $revision, expected $_revision.',
      );
    }
    for (final required in _requiredFiles) {
      if (!await File(p.join(staging.path, required)).exists()) {
        throw StateError('The editor build is missing $required.');
      }
    }
    final completedAliases = await _completeFontAliases(staging);

    await File(p.join(staging.path, bundleManifestName)).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'source': '$_registry/$_repository:$_imageTag',
        'layer': _layerDigest,
        'revision': _revision,
        'format': _bundleFormat,
        'license': 'AGPL-3.0 (see LICENSE and NOTICE)',
        'files': stats.files,
        'bytes': stats.bytes,
        'skipped': stats.skipped,
        'completedFontAliases': completedAliases,
      }),
    );

    if (await output.exists()) {
      await output.delete(recursive: true);
    }
    await staging.rename(output.path);
    stdout.writeln(
      'Unpacked ${stats.files} files '
      '(${(stats.bytes / (1 << 20)).toStringAsFixed(1)} MiB, '
      '${stats.skipped} skipped) into ${output.path}.',
    );
  } catch (error) {
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    stderr.writeln('Unable to fetch the office editor: $error');
    exitCode = 1;
  }
}

Future<bool> _isCurrent(File manifest) async {
  if (!await manifest.exists()) {
    return false;
  }
  try {
    final json = jsonDecode(await manifest.readAsString()) as Map;
    return json['layer'] == _layerDigest &&
        json['revision'] == _revision &&
        json['format'] == _bundleFormat;
  } on FormatException {
    return false;
  }
}

/// Gives font aliases the faces of the family they stand in for.
///
/// The build's catalog points `Calibri` (Word's default face) at Carlito's
/// regular file only. Bold or italic Calibri then resolves to no face at all
/// and is drawn with mismatched glyphs. An alias is recognised by sharing its
/// regular file with a fuller family, whose missing faces it inherits.
Future<List<String>> _completeFontAliases(Directory bundle) async {
  final catalog = File(p.join(bundle.path, 'sdkjs/common/AllFonts.js'));
  final bytes = await catalog.readAsBytes();
  final hasBom = bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final source = utf8.decode(hasBom ? bytes.sublist(3) : bytes);
  final block = RegExp(
    r'window\["__fonts_infos"\]\s*=\s*\[(.*?)\];',
    dotAll: true,
  ).firstMatch(source);
  if (block == null) {
    throw StateError('The font catalog has no __fonts_infos table.');
  }
  final entryPattern = RegExp(
    r'\["((?:[^"\\]|\\.)*)",(-?\d+),(-?\d+),(-?\d+),(-?\d+),'
    r'(-?\d+),(-?\d+),(-?\d+),(-?\d+)\]',
  );
  final entries = entryPattern.allMatches(block.group(1)!).map((match) {
    return (
      text: match.group(0)!,
      name: match.group(1)!,
      faces: [for (var i = 2; i <= 9; i++) int.parse(match.group(i)!)],
    );
  }).toList();

  int faceCount(List<int> faces) =>
      [0, 2, 4, 6].where((slot) => faces[slot] >= 0).length;

  var table = block.group(1)!;
  final completed = <String>[];
  for (final entry in entries) {
    final faces = entry.faces;
    if (faces[0] < 0 || faceCount(faces) == 4) {
      continue;
    }
    final fuller = entries
        .where(
          (other) =>
              other.name != entry.name &&
              other.faces[0] == faces[0] &&
              other.faces[1] == faces[1] &&
              faceCount(other.faces) > faceCount(faces),
        )
        .fold<({String text, String name, List<int> faces})?>(
          null,
          (best, other) =>
              best == null || faceCount(other.faces) > faceCount(best.faces)
                  ? other
                  : best,
        );
    if (fuller == null) {
      continue;
    }
    final merged = [...faces];
    for (final slot in [2, 4, 6]) {
      if (merged[slot] < 0 && fuller.faces[slot] >= 0) {
        merged[slot] = fuller.faces[slot];
        merged[slot + 1] = fuller.faces[slot + 1];
      }
    }
    table = table.replaceFirst(
      entry.text,
      '["${entry.name}",${merged.join(',')}]',
    );
    completed.add('${entry.name} -> ${fuller.name}');
  }
  if (completed.isNotEmpty) {
    final original = block.group(0)!;
    final content = block.group(1)!;
    final prefix = original.substring(0, original.length - content.length - 2);
    await catalog.writeAsBytes([
      if (hasBom) ...[0xEF, 0xBB, 0xBF],
      ...utf8.encode(
        source.replaceRange(block.start, block.end, '$prefix$table];'),
      ),
    ]);
  }
  return completed;
}

Stream<List<int>> _layerFromRegistry() async* {
  final client = HttpClient()..userAgent = 'AppFlowy office editor fetcher';
  try {
    final tokenResponse = await _get(
      client,
      Uri.https(_registry, '/token', {'scope': 'repository:$_repository:pull'}),
    );
    final token = (jsonDecode(
      await utf8.decoder.bind(tokenResponse).join(),
    ) as Map)['token'] as String;

    // The registry redirects blob reads to signed storage URLs, which reject
    // a second credential, so the token goes to the registry only.
    var response = await _get(
      client,
      Uri.https(_registry, '/v2/$_repository/blobs/$_layerDigest'),
      headers: {'Authorization': 'Bearer $token'},
      followRedirects: false,
    );
    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) {
        throw StateError('The registry redirected without a location.');
      }
      response = await _get(client, Uri.parse(location));
    }
    stdout.writeln('Downloading $_repository:$_imageTag ($_layerDigest)...');
    yield* _verified(response, total: response.contentLength);
  } finally {
    client.close(force: true);
  }
}

/// Passes [source] through, failing at the end unless it hashes to the pin.
Stream<List<int>> _verified(
  Stream<List<int>> source, {
  required int total,
}) async* {
  final digest = _DigestSink();
  final hasher = sha256.startChunkedConversion(digest);
  var received = 0;
  var reported = -1;
  await for (final chunk in source) {
    hasher.add(chunk);
    received += chunk.length;
    if (total > 0) {
      final step = received * 10 ~/ total;
      if (step != reported) {
        reported = step;
        stdout.writeln('  ${step * 10}%');
      }
    }
    yield chunk;
  }
  hasher.close();
  if ('sha256:${digest.value}' != _layerDigest) {
    throw StateError('The editor layer does not match $_layerDigest.');
  }
}

Future<HttpClientResponse> _get(
  HttpClient client,
  Uri uri, {
  Map<String, String> headers = const {},
  bool followRedirects = true,
}) async {
  final request = await client.getUrl(uri);
  request.followRedirects = followRedirects;
  headers.forEach(request.headers.set);
  final response = await request.close();
  if (response.statusCode >= 400) {
    final body = await utf8.decoder.bind(response).join();
    throw HttpException(
      '${response.statusCode} from ${uri.host}${uri.path}: '
      '${body.length > 200 ? body.substring(0, 200) : body}',
      uri: uri,
    );
  }
  return response;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

typedef _UnpackStats = ({int files, int bytes, int skipped});

/// Unpacks the gzipped tar layer's `public/` tree into [target].
Future<_UnpackStats> _unpack(
  Stream<List<int>> layer,
  Directory target,
) async {
  final reader = _TarReader(gzip.decoder.bind(layer));
  var files = 0;
  var bytes = 0;
  var skipped = 0;
  await for (final entry in reader.entries()) {
    final relative = _publicPath(entry.name);
    if (relative == null || entry.type == _TarType.directory) {
      await entry.skip();
      continue;
    }
    if (entry.type != _TarType.file) {
      throw StateError(
        'Unexpected ${entry.type.name} entry in the layer: ${entry.name}',
      );
    }
    if (_excluded.any((pattern) => pattern.hasMatch(relative))) {
      skipped++;
      await entry.skip();
      continue;
    }
    final destination = p.normalize(p.join(target.path, relative));
    if (!p.isWithin(target.path, destination)) {
      throw StateError('Refusing to write outside the bundle: ${entry.name}');
    }
    await Directory(p.dirname(destination)).create(recursive: true);
    final sink = File(destination).openWrite();
    await entry.copyTo(sink);
    await sink.close();
    files++;
    bytes += entry.size;
  }
  if (files == 0) {
    throw StateError('The layer held no editor files.');
  }
  return (files: files, bytes: bytes, skipped: skipped);
}

String? _publicPath(String name) {
  var normalized = name.replaceAll('\\', '/');
  if (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (!normalized.startsWith('public/')) {
    return null;
  }
  final relative = normalized.substring('public/'.length);
  if (relative.isEmpty ||
      relative.split('/').any((part) => part == '..' || part == '.')) {
    return null;
  }
  return relative;
}

enum _TarType { file, directory, other }

class _TarEntry {
  _TarEntry(this.name, this.type, this.size, this._reader);

  final String name;
  final _TarType type;
  final int size;
  final _TarReader _reader;

  Future<void> copyTo(IOSink sink) => _reader._readBody(size, sink.add);

  Future<void> skip() => _reader._readBody(size, (_) {});
}

/// A forward-only reader for the ustar, PAX and GNU long-name tar dialects.
class _TarReader {
  _TarReader(Stream<List<int>> source) : _iterator = StreamIterator(source);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Stream<_TarEntry> entries() async* {
    String? longName;
    while (true) {
      final header = await _take(512);
      if (header == null || header.every((byte) => byte == 0)) {
        // Drain the end-of-archive padding so the digest sees every byte.
        while (await _takeUpTo(1 << 16) != null) {}
        return;
      }
      final size = _octal(header, 124, 12);
      final typeFlag = header[156];

      if (typeFlag == 0x4c /* L: GNU long name */ ||
          typeFlag == 0x78 /* x: PAX header */) {
        final body = BytesBuilder(copy: false);
        await _readBody(size, body.add);
        final text = utf8.decode(body.takeBytes(), allowMalformed: true);
        if (typeFlag == 0x4c) {
          longName = text.split('\u0000').first;
        } else {
          for (final record in text.split('\n')) {
            final match = RegExp(r'^\d+ path=(.*)$').firstMatch(record);
            if (match != null) {
              longName = match.group(1);
            }
          }
        }
        continue;
      }
      if (typeFlag == 0x67 /* g: PAX global header */) {
        await _readBody(size, (_) {});
        continue;
      }

      final type = switch (typeFlag) {
        0 || 0x30 || 0x37 => _TarType.file,
        0x35 => _TarType.directory,
        _ => _TarType.other,
      };
      yield _TarEntry(longName ?? _joinName(header), type, size, this);
      longName = null;
    }
  }

  Future<void> _readBody(int size, void Function(List<int>) onData) async {
    var remaining = size;
    while (remaining > 0) {
      final chunk = await _takeUpTo(remaining);
      if (chunk == null) {
        throw StateError('The layer ended in the middle of a file.');
      }
      onData(chunk);
      remaining -= chunk.length;
    }
    final padding = (512 - size % 512) % 512;
    if (padding > 0 && await _take(padding) == null) {
      throw StateError('The layer ended in the middle of a record.');
    }
  }

  Future<bool> _fill() async {
    if (_offset < _buffer.length) {
      return true;
    }
    if (!await _iterator.moveNext()) {
      return false;
    }
    final next = _iterator.current;
    _buffer = next is Uint8List ? next : Uint8List.fromList(next);
    _offset = 0;
    if (_buffer.isEmpty) {
      return _fill();
    }
    return true;
  }

  Future<Uint8List?> _takeUpTo(int count) async {
    if (!await _fill()) {
      return null;
    }
    final end = (_offset + count).clamp(0, _buffer.length);
    // Copied so a sink holding on to it never sees the buffer reused.
    final chunk = Uint8List.fromList(
      Uint8List.sublistView(_buffer, _offset, end),
    );
    _offset = end;
    return chunk;
  }

  Future<Uint8List?> _take(int count) async {
    final result = BytesBuilder(copy: false);
    while (result.length < count) {
      final chunk = await _takeUpTo(count - result.length);
      if (chunk == null) {
        return null;
      }
      result.add(chunk);
    }
    return result.takeBytes();
  }

  static String _joinName(Uint8List header) {
    final name = _string(header, 0, 100);
    final isUstar = ascii.decode(
          header.sublist(257, 262),
          allowInvalid: true,
        ) ==
        'ustar';
    final prefix = isUstar ? _string(header, 345, 155) : '';
    return prefix.isEmpty ? name : '$prefix/$name';
  }

  static String _string(Uint8List header, int offset, int length) {
    final field = header.sublist(offset, offset + length);
    final end = field.indexOf(0);
    return utf8.decode(
      end < 0 ? field : field.sublist(0, end),
      allowMalformed: true,
    );
  }

  static int _octal(Uint8List header, int offset, int length) {
    final text = _string(header, offset, length).trim();
    return text.isEmpty ? 0 : int.parse(text, radix: 8);
  }
}

class _Options {
  _Options({required this.output, this.layerFile, this.force = false});

  factory _Options.parse(List<String> arguments) {
    var output = 'office_editor';
    String? layerFile;
    var force = false;
    for (var i = 0; i < arguments.length; i++) {
      switch (arguments[i]) {
        case '--force':
          force = true;
        case '--output' when i + 1 < arguments.length:
          output = arguments[++i];
        case '--layer-file' when i + 1 < arguments.length:
          layerFile = arguments[++i];
        default:
          stderr.writeln(
            'Usage: dart run tool/office_editor/fetch_office_editor.dart '
            '[--force] [--layer-file <layer.tar.gz>] [--output <directory>]',
          );
          exit(64);
      }
    }
    return _Options(output: output, layerFile: layerFile, force: force);
  }

  final String output;
  final String? layerFile;
  final bool force;
}
