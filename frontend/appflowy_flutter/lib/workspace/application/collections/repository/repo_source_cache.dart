import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/source_imports.dart';
import 'package:appflowy/workspace/application/collections/repository/source_outline.dart';
import 'package:flutter/foundation.dart';

/// What could be read out of one source file.
@immutable
class RepoFileAnalysis {
  const RepoFileAnalysis({
    this.symbols = const [],
    this.imports = const [],
    this.lineCount = 0,
    this.byteSize = 0,
    this.truncated = false,
    this.failed = false,
  });

  static const pending = RepoFileAnalysis();

  final List<SourceSymbol> symbols;
  final List<SourceImport> imports;
  final int lineCount;
  final int byteSize;

  /// Whether the file was too large to read whole.
  final bool truncated;
  final bool failed;

  bool get isResolved => lineCount > 0 || failed;
}

/// Reads repository files once and remembers what they contain.
///
/// Only the head of a file is read: a source explorer needs declarations and
/// imports, both of which a generated megabyte-long file will still show in
/// its first stretch, and reading whole trees into memory is what makes tools
/// like this stall.
class RepoSourceCache {
  RepoSourceCache({this.maxBytes = 512 * 1024, this.fetch});

  final int maxBytes;

  /// Puts a file that is not on disk there, for a repository whose contents
  /// are fetched as they are read. Null when everything is already local.
  Future<String?> Function(RepoEntry entry)? fetch;

  final Map<String, RepoFileAnalysis> _analysis = {};
  final Map<String, String> _text = {};
  final Map<String, Future<RepoFileAnalysis>> _inFlight = {};

  RepoFileAnalysis? peek(String id) => _analysis[id];

  /// The text of [id] when it has already been read.
  String? textFor(String id) => _text[id];

  Future<RepoFileAnalysis> load(RepoEntry entry) {
    final cached = _analysis[entry.id];
    if (cached != null) {
      return Future.value(cached);
    }
    return _inFlight.putIfAbsent(entry.id, () async {
      final analysis = await _read(entry);
      _analysis[entry.id] = analysis;
      _inFlight.removeWhere((key, _) => key == entry.id);
      return analysis;
    });
  }

  Future<RepoFileAnalysis> _read(RepoEntry entry) async {
    if (!entry.isLocalFile || !entry.kind.isReadable) {
      return const RepoFileAnalysis(failed: true);
    }
    try {
      var file = File(entry.storageUrl);
      if (!file.existsSync()) {
        final fetched = await fetch?.call(entry);
        if (fetched == null) {
          return const RepoFileAnalysis(failed: true);
        }
        file = File(fetched);
      }
      final length = await file.length();
      final truncated = length > maxBytes;
      final bytes =
          truncated ? await _readHead(file) : await file.readAsBytes();
      final source = const Utf8Decoder(allowMalformed: true).convert(bytes);
      _text[entry.id] = source;
      return RepoFileAnalysis(
        symbols: parseSourceOutline(entry.language, source),
        imports: parseSourceImports(entry.language, source),
        lineCount: '\n'.allMatches(source).length + 1,
        byteSize: length,
        truncated: truncated,
      );
    } on Object {
      return const RepoFileAnalysis(failed: true);
    }
  }

  Future<Uint8List> _readHead(File file) async {
    final handle = await file.open();
    try {
      return await handle.read(maxBytes);
    } finally {
      await handle.close();
    }
  }

  void invalidate(String id) {
    _analysis.remove(id);
    _text.remove(id);
    _inFlight.remove(id);
  }

  void clear() {
    _analysis.clear();
    _text.clear();
    _inFlight.clear();
  }
}
