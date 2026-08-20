import 'dart:convert';
import 'dart:io';

import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// A library the host fetched once and now serves from the extension's folder.
@immutable
class CachedLibrary {
  const CachedLibrary({
    required this.name,
    required this.version,
    required this.integrity,
    required this.file,
  });

  final String name;
  final String version;
  final String integrity;
  final String file;

  Map<String, Object?> toJson() => {
        'version': version,
        'integrity': integrity,
        'file': file,
      };

  static CachedLibrary? fromJson(String name, Map<String, Object?> values) {
    final file = (values['file'] as String?) ?? '';
    if (file.isEmpty) {
      return null;
    }
    return CachedLibrary(
      name: name,
      version: (values['version'] as String?) ?? '',
      integrity: (values['integrity'] as String?) ?? '',
      file: file,
    );
  }
}

/// Fetches, verifies and keeps the JavaScript libraries an extension named.
///
/// ⚠️⚠️ **The page never reaches a CDN itself.** `connect-src 'none'` is the
/// whole sandbox, and a `<script src="https://…">` would re-open exactly the
/// outbound channel it closes — a script URL carries data in its query string
/// and the fetched code then runs with full page privileges. So the *host*
/// fetches, checks the hash, writes the file into the extension's own folder,
/// and hands the source to the worker directly.
///
/// A declared library is self-authorising: its URL is fixed in the manifest and
/// pinned by its hash, so it needs no separate `net:` permission.
class ExtensionLibraryCache {
  ExtensionLibraryCache({http.Client? client})
      : _client = client ?? http.Client();

  static final ExtensionLibraryCache instance = ExtensionLibraryCache();

  static const lockFileName = 'libraries.lock.json';
  static const folderName = 'web';
  static const librariesFolderName = 'lib';

  /// A library larger than this is refused rather than pulled into memory.
  static const maximumBytes = 8 * 1024 * 1024;

  static const fetchTimeout = Duration(seconds: 30);

  final http.Client _client;
  final Map<String, String> _sources = {};

  String _cacheKey(String extensionFolder, String id) => '$extensionFolder|$id';

  /// The source text of every library [extension] declared, in declaration
  /// order, restricted to [names] when given.
  Future<List<String>> sourcesFor(
    ExtensionManifest manifest,
    String extensionFolder, {
    List<String> names = const [],
  }) async {
    final wanted = <ExtensionLibrary>[
      for (final library in manifest.libraries)
        if (names.isEmpty ||
            names.contains(library.name) ||
            names.contains(library.id))
          library,
    ];

    final sources = <String>[];
    for (final library in wanted) {
      final source = await sourceFor(library, extensionFolder);
      if (source != null) {
        sources.add(source);
      }
    }
    return sources;
  }

  Future<String?> sourceFor(
    ExtensionLibrary library,
    String extensionFolder,
  ) async {
    final key = _cacheKey(extensionFolder, library.id);
    final held = _sources[key];
    if (held != null) {
      return held;
    }

    final lock = await _readLock(extensionFolder);
    final locked = lock[library.name];
    final file = File(
      p.join(
        extensionFolder,
        folderName,
        librariesFolderName,
        _fileNameFor(library),
      ),
    );

    if (file.existsSync() && locked != null) {
      final bytes = await file.readAsBytes();
      final digest = integrityOf(bytes);
      final expected =
          library.integrity.isNotEmpty ? library.integrity : locked.integrity;
      if (expected.isEmpty || digest == expected) {
        final source = utf8.decode(bytes, allowMalformed: true);
        _sources[key] = source;
        return source;
      }
      // A cached copy that no longer matches its pin is thrown away rather
      // than trusted; it is fetched again below.
      Log.warn(
          '${library.id} did not match its recorded hash; fetching again.');
    }

    final fetched = await _fetch(library);
    if (fetched == null) {
      return null;
    }

    final digest = integrityOf(fetched);
    if (library.integrity.isNotEmpty && digest != library.integrity) {
      Log.warn(
        '${library.id} was refused: it does not match the hash the manifest '
        'pinned it to.',
      );
      return null;
    }

    await file.parent.create(recursive: true);
    await file.writeAsBytes(fetched);
    // Trust on first use: the resolved hash is written down so the same bytes
    // are required from now on, and so the folder is reproducible.
    lock[library.name] = CachedLibrary(
      name: library.name,
      version: library.version,
      integrity: library.integrity.isEmpty ? digest : library.integrity,
      file: p.relative(file.path, from: extensionFolder).replaceAll(r'\', '/'),
    );
    await _writeLock(extensionFolder, lock);

    final source = utf8.decode(fetched, allowMalformed: true);
    _sources[key] = source;
    return source;
  }

  Future<List<int>?> _fetch(ExtensionLibrary library) async {
    final uri = Uri.tryParse(library.url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      Log.warn('${library.id} does not name an address that can be fetched.');
      return null;
    }
    try {
      final streamed =
          await _client.send(http.Request('GET', uri)).timeout(fetchTimeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        Log.warn('${library.id} could not be fetched: ${streamed.statusCode}.');
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          Log.warn('${library.id} is larger than the cache allows.');
          return null;
        }
      }
      return bytes;
    } on Object catch (error) {
      Log.warn('${library.id} could not be fetched: $error');
      return null;
    }
  }

  /// Subresource-integrity form, so a manifest can be pinned with the same
  /// string a web page would use.
  static String integrityOf(List<int> bytes) =>
      'sha384-${base64.encode(sha384.convert(bytes).bytes)}';

  static String _fileNameFor(ExtensionLibrary library) {
    final safe = library.name.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '-');
    return library.version.isEmpty ? '$safe.js' : '$safe-${library.version}.js';
  }

  Future<Map<String, CachedLibrary>> _readLock(String extensionFolder) async {
    final file = File(p.join(extensionFolder, lockFileName));
    if (!file.existsSync()) {
      return {};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return {};
      }
      final lock = <String, CachedLibrary>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) {
          continue;
        }
        final parsed = CachedLibrary.fromJson(
          '${entry.key}',
          Map<String, Object?>.from(value),
        );
        if (parsed != null) {
          lock['${entry.key}'] = parsed;
        }
      }
      return lock;
    } on Object catch (error) {
      Log.warn('A library lock file could not be read: $error');
      return {};
    }
  }

  Future<void> _writeLock(
    String extensionFolder,
    Map<String, CachedLibrary> lock,
  ) async {
    try {
      final file = File(p.join(extensionFolder, lockFileName));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          for (final entry in lock.entries) entry.key: entry.value.toJson(),
        }),
      );
    } on Object catch (error) {
      Log.warn('A library lock file could not be written: $error');
    }
  }

  @visibleForTesting
  void forget() => _sources.clear();

  void dispose() => _client.close();
}
