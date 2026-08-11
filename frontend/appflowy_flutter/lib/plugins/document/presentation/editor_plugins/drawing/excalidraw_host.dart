import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Unpacks and serves the bundled Excalidraw editor.
///
/// The editor is the real open-source Excalidraw build, shipped as one
/// compressed asset and unpacked once into the application's data folder. It
/// is then served from a loopback HTTP server behind an unguessable path,
/// because the editor is an ES-module bundle that also spawns workers and
/// loads fonts — none of which a browser will do from `file://`.
///
/// Nothing leaves the machine: the bundle carries its own fonts and locales
/// and never reaches for a CDN.
class ExcalidrawHost {
  ExcalidrawHost._();

  static final ExcalidrawHost instance = ExcalidrawHost._();

  static const String assetPath = 'assets/excalidraw/excalidraw_host.zip';
  static const String _folderName = 'excalidraw_host';
  static const int _tokenBytes = 18;

  final Random _random = Random.secure();

  Directory? _root;
  Future<Directory>? _unpacking;
  HttpServer? _server;
  Future<HttpServer>? _starting;
  String? _token;

  /// The address of the editor page, unpacking and starting what it needs.
  Future<Uri> editorUrl() async {
    final root = await _ensureUnpacked();
    final server = await _ensureServer(root);
    final token = _token ??= _newToken();
    return Uri.parse(
      'http://127.0.0.1:${server.port}/$token/index.html',
    );
  }

  /// Whether the editor bundle is present in this build.
  Future<bool> get isAvailable async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> _ensureUnpacked() {
    final existing = _root;
    if (existing != null) {
      return Future.value(existing);
    }
    return _unpacking ??= _unpack();
  }

  Future<Directory> _unpack() async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    // The digest names the folder, so a new build unpacks beside the old one
    // rather than over it and a half-written folder is never reused.
    final stamp = sha1.convert(bytes).toString().substring(0, 16);

    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, _folderName, stamp));
    final marker = File(p.join(root.path, '.complete'));

    if (await marker.exists()) {
      _root = root;
      return root;
    }

    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final target = _safeJoin(root.path, entry.name);
      if (target == null) {
        Log.warn('Excalidraw bundle contained an unsafe path: ${entry.name}');
        continue;
      }
      if (entry.isFile) {
        final file = File(target);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(target).create(recursive: true);
      }
    }
    await marker.writeAsString(stamp);

    // Older builds are dead weight the moment a new one is unpacked.
    unawaited(_pruneOldBuilds(root.parent, stamp));

    _root = root;
    return root;
  }

  Future<void> _pruneOldBuilds(Directory parent, String keep) async {
    try {
      await for (final entry in parent.list()) {
        if (entry is Directory && p.basename(entry.path) != keep) {
          await entry.delete(recursive: true);
        }
      }
    } catch (error) {
      Log.warn('An old Excalidraw bundle could not be removed: $error');
    }
  }

  Future<HttpServer> _ensureServer(Directory root) {
    final existing = _server;
    if (existing != null) {
      return Future.value(existing);
    }
    return _starting ??= _startServer(root);
  }

  Future<HttpServer> _startServer(Directory root) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_serve(request, root)));
    _server = server;
    return server;
  }

  Future<void> _serve(HttpRequest request, Directory root) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final token = _token;
      if (token == null ||
          segments.isEmpty ||
          segments.first != token ||
          request.method != 'GET') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final relative = segments.skip(1).join('/');
      final target =
          _safeJoin(root.path, relative.isEmpty ? 'index.html' : relative);
      final file = target == null ? null : File(target);
      if (file == null || !await file.exists()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers
        ..contentType = _contentTypeFor(file.path)
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        // The page only ever loads what shipped with it.
        ..set('Cross-Origin-Opener-Policy', 'same-origin')
        ..set('X-Content-Type-Options', 'nosniff');
      await response.addStream(file.openRead());
      await response.close();
    } catch (error) {
      Log.warn('Excalidraw host could not serve a request: $error');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {
        // The connection is already gone.
      }
    }
  }

  String _newToken() {
    final bytes = List<int>.generate(_tokenBytes, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Resolves [relative] under [root], refusing anything that escapes it.
  static String? _safeJoin(String root, String relative) {
    final normalised =
        p.normalize(p.join(root, relative.replaceAll('\\', '/')));
    return p.isWithin(root, normalised) || normalised == p.normalize(root)
        ? normalised
        : null;
  }

  static ContentType _contentTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.html':
        return ContentType.html;
      case '.js':
      case '.mjs':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.json':
        return ContentType('application', 'json', charset: 'utf-8');
      case '.woff2':
        return ContentType('font', 'woff2');
      case '.woff':
        return ContentType('font', 'woff');
      case '.ttf':
        return ContentType('font', 'ttf');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.png':
        return ContentType('image', 'png');
      case '.wasm':
        return ContentType('application', 'wasm');
      default:
        return ContentType.binary;
    }
  }
}
