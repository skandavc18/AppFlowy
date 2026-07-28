import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// The largest zip AppFlowy will open in place.
const int maxArchiveBytes = 50 * 1024 * 1024;

/// The largest amount of data the entries of one archive may expand to.
///
/// Editing an archive means holding its decompressed contents in memory, so a
/// deeply compressed file has to be refused before it is unpacked rather than
/// after.
const int maxArchiveContentBytes = 512 * 1024 * 1024;

/// The most entries AppFlowy will index for one archive.
const int maxArchiveEntryCount = 5000;

/// The container formats AppFlowy can open.
enum ArchiveFormat {
  zip,
  tar,
  tarGzip,
  tarBzip2,
  tarXz,
  gzip,
  bzip2,
  xz;

  /// Whether the format holds many entries rather than a single compressed
  /// file. A `.gz` on its own wraps exactly one file.
  bool get isContainer => switch (this) {
        ArchiveFormat.gzip || ArchiveFormat.bzip2 || ArchiveFormat.xz => false,
        _ => true,
      };

  /// Whether new folders can be stored. A single-file stream has nowhere to
  /// put them, and neither does a plain tar member list.
  bool get supportsFolders =>
      this != ArchiveFormat.gzip &&
      this != ArchiveFormat.bzip2 &&
      this != ArchiveFormat.xz;

  String get label => switch (this) {
        ArchiveFormat.zip => 'ZIP archive',
        ArchiveFormat.tar => 'TAR archive',
        ArchiveFormat.tarGzip => 'Gzipped TAR archive',
        ArchiveFormat.tarBzip2 => 'Bzip2 TAR archive',
        ArchiveFormat.tarXz => 'XZ TAR archive',
        ArchiveFormat.gzip => 'Gzip file',
        ArchiveFormat.bzip2 => 'Bzip2 file',
        ArchiveFormat.xz => 'XZ file',
      };
}

/// The container format [name] is stored in, or null when AppFlowy has no
/// codec for it — 7-Zip and RAR among them.
ArchiveFormat? archiveFormatForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.tar.gz') ||
      lower.endsWith('.tgz') ||
      lower.endsWith('.taz')) {
    return ArchiveFormat.tarGzip;
  }
  if (lower.endsWith('.tar.bz2') ||
      lower.endsWith('.tbz') ||
      lower.endsWith('.tbz2') ||
      lower.endsWith('.tb2')) {
    return ArchiveFormat.tarBzip2;
  }
  if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
    return ArchiveFormat.tarXz;
  }
  return switch (lower.split('.').last) {
    'zip' || 'jar' || 'cbz' => ArchiveFormat.zip,
    'tar' => ArchiveFormat.tar,
    'gz' || 'gzip' => ArchiveFormat.gzip,
    'bz2' || 'bzip2' => ArchiveFormat.bzip2,
    'xz' => ArchiveFormat.xz,
    _ => null,
  };
}

/// What a single-file stream holds once its compression suffix is dropped.
String archiveMemberNameFor(String archiveName) {
  final base = archiveName.split(RegExp(r'[\\/]')).last;
  final lower = base.toLowerCase();
  for (final suffix in const ['.gz', '.gzip', '.bz2', '.bzip2', '.xz']) {
    if (lower.endsWith(suffix)) {
      final stripped = base.substring(0, base.length - suffix.length);
      return stripped.isEmpty ? 'content' : stripped;
    }
  }
  return base.isEmpty ? 'content' : base;
}

/// A single item inside an archive: either a stored file or a directory.
@immutable
class ArchiveEntry {
  const ArchiveEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modified,
  });

  /// Slash separated and relative to the archive root, with no leading or
  /// trailing separator.
  final String path;

  final bool isDirectory;

  /// The uncompressed size in bytes. For a directory this is the total of
  /// everything it holds.
  final int size;

  final DateTime? modified;

  String get name => archiveEntryName(path);

  String get parentPath => archiveParentPath(path);

  bool get isFile => !isDirectory;
}

/// Reduces [value] to a safe archive-relative path.
///
/// Separators are normalised to `/`, and `.` and `..` segments are resolved
/// away so a crafted entry name can never escape the directory an entry is
/// extracted into.
String normalizeArchivePath(String value) {
  final segments = <String>[];
  for (final segment in value.replaceAll('\\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

/// The last segment of an archive path.
String archiveEntryName(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? path : path.substring(index + 1);
}

/// Everything before the last segment of an archive path.
String archiveParentPath(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? '' : path.substring(0, index);
}

/// Joins an archive directory and a child name.
String joinArchivePath(String directory, String name) {
  final normalizedName = normalizeArchivePath(name);
  if (directory.isEmpty) {
    return normalizedName;
  }
  return normalizedName.isEmpty ? directory : '$directory/$normalizedName';
}

/// An in-memory zip archive that can be browsed and edited like a folder.
///
/// The document owns the decompressed entries, so every change — adding,
/// removing, renaming or rewriting a file — is applied here first and written
/// back to disk as one atomic replacement by [saveTo].
class ArchiveDocument {
  ArchiveDocument._(this._files, this._explicitDirectories, this.format) {
    _rebuildIndex();
  }

  /// An empty archive, used when a new one is created from scratch.
  factory ArchiveDocument.empty([ArchiveFormat format = ArchiveFormat.zip]) =>
      ArchiveDocument._({}, <String>{}, format);

  factory ArchiveDocument.fromBytes(
    Uint8List bytes, {
    ArchiveFormat format = ArchiveFormat.zip,
    String? memberName,
  }) {
    if (!format.isContainer) {
      final content = Uint8List.fromList(_decompress(bytes, format));
      if (content.length > maxArchiveContentBytes) {
        throw const ArchiveDocumentException(
          'This archive expands to more data than AppFlowy can open.',
        );
      }
      final name = normalizeArchivePath(memberName ?? 'content');
      return ArchiveDocument._(
        {name: ArchiveFile(name, content.length, content)},
        <String>{},
        format,
      );
    }

    final decoded = switch (format) {
      ArchiveFormat.zip => ZipDecoder().decodeBytes(bytes),
      ArchiveFormat.tar => TarDecoder().decodeBytes(bytes),
      _ => TarDecoder().decodeBytes(_decompress(bytes, format)),
    };
    if (decoded.length > maxArchiveEntryCount) {
      throw const ArchiveDocumentException(
        'This archive holds too many entries to browse.',
      );
    }
    var contentBytes = 0;
    final files = <String, ArchiveFile>{};
    final directories = <String>{};
    for (final file in decoded.files) {
      final path = normalizeArchivePath(file.name);
      if (path.isEmpty) {
        continue;
      }
      if (file.isFile) {
        contentBytes += file.size;
        if (contentBytes > maxArchiveContentBytes) {
          throw const ArchiveDocumentException(
            'This archive expands to more data than AppFlowy can open.',
          );
        }
        // The index is keyed by the sanitised path, so the entry has to carry
        // that same name or the two disagree once anything is rewritten.
        file.name = path;
        files[path] = file;
      } else {
        directories.add(path);
      }
    }
    return ArchiveDocument._(files, directories, format);
  }

  static List<int> _decompress(Uint8List bytes, ArchiveFormat format) {
    try {
      return switch (format) {
        ArchiveFormat.tarGzip ||
        ArchiveFormat.gzip =>
          GZipDecoder().decodeBytes(bytes),
        ArchiveFormat.tarBzip2 ||
        ArchiveFormat.bzip2 =>
          BZip2Decoder().decodeBytes(bytes),
        ArchiveFormat.tarXz || ArchiveFormat.xz => XZDecoder().decodeBytes(
            bytes,
          ),
        _ => bytes,
      };
    } on ArchiveException catch (error) {
      throw ArchiveDocumentException('This archive could not be read: $error');
    }
  }

  /// Opens an archive from disk.
  ///
  /// [format] states the container outright, for a file whose extension does
  /// not name one — an Office package is a zip called `.docx`.
  static Future<ArchiveDocument> read(
    File file, {
    String? name,
    ArchiveFormat? format,
  }) async {
    final label = name ?? file.uri.pathSegments.last;
    final resolved = format ?? archiveFormatForName(label);
    if (resolved == null) {
      throw ArchiveDocumentException(
        'AppFlowy cannot open ${label.split('.').last.toUpperCase()} archives '
        'yet. Open it with another app to unpack it.',
      );
    }
    final length = await file.length();
    if (length > maxArchiveBytes) {
      throw ArchiveDocumentException(
        'This archive is too large to open (${formatArchiveBytes(length)}).',
      );
    }
    return ArchiveDocument.fromBytes(
      await file.readAsBytes(),
      format: resolved,
      memberName: archiveMemberNameFor(label),
    );
  }

  /// The container this archive is stored in.
  final ArchiveFormat format;

  /// Stored files, keyed by normalised path, in the order they will be written.
  final Map<String, ArchiveFile> _files;

  /// Directories that exist in their own right, so an empty folder survives a
  /// round trip through the zip.
  final Set<String> _explicitDirectories;

  Map<String, List<ArchiveEntry>> _childrenByParent = {};
  Set<String> _directories = {};
  bool _dirty = false;

  /// Whether the archive has unsaved changes.
  bool get isDirty => _dirty;

  int get fileCount => _files.length;

  int get folderCount => _directories.length;

  int get totalSize =>
      _files.values.fold(0, (total, file) => total + file.size);

  /// Every path in the archive, files and directories alike.
  Iterable<String> get paths => [..._files.keys, ..._directories];

  bool containsPath(String path) {
    final normalized = normalizeArchivePath(path);
    return _files.containsKey(normalized) || _directories.contains(normalized);
  }

  bool isDirectory(String path) =>
      _directories.contains(normalizeArchivePath(path));

  /// The entries directly inside [directory], folders first and then files,
  /// both in case-insensitive name order.
  List<ArchiveEntry> childrenOf(String directory) =>
      _childrenByParent[normalizeArchivePath(directory)] ?? const [];

  /// Every file whose path contains [query], searched across the whole
  /// archive rather than only the open folder.
  List<ArchiveEntry> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const [];
    }
    final matches = <ArchiveEntry>[];
    for (final entries in _childrenByParent.values) {
      for (final entry in entries) {
        if (entry.path.toLowerCase().contains(needle)) {
          matches.add(entry);
        }
      }
    }
    matches.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return matches;
  }

  ArchiveEntry? entryFor(String path) {
    final normalized = normalizeArchivePath(path);
    if (normalized.isEmpty) {
      return null;
    }
    final siblings = _childrenByParent[archiveParentPath(normalized)];
    if (siblings == null) {
      return null;
    }
    for (final entry in siblings) {
      if (entry.path == normalized) {
        return entry;
      }
    }
    return null;
  }

  /// Whether entries can be added or removed. A single compressed stream
  /// holds exactly one file, so it can only be rewritten in place.
  bool get supportsMultipleEntries => format.isContainer;

  /// The decompressed bytes of a stored file.
  Uint8List readBytes(String path) {
    final file = _files[normalizeArchivePath(path)];
    if (file == null) {
      throw ArchiveDocumentException('"$path" is not in this archive.');
    }
    return _bytesOf(file);
  }

  /// Adds or replaces a file. Missing parent directories are implied by the
  /// path, exactly as they are in a zip written by any other tool.
  void writeBytes(String path, Uint8List bytes, {DateTime? modified}) {
    final normalized = normalizeArchivePath(path);
    if (normalized.isEmpty) {
      throw const ArchiveDocumentException('A file needs a name.');
    }
    if (!supportsMultipleEntries && !_files.containsKey(normalized)) {
      throw ArchiveDocumentException(
        'A ${format.label} holds a single file, so nothing can be added to it.',
      );
    }
    if (_directories.contains(normalized)) {
      throw ArchiveDocumentException(
        'A folder named "${archiveEntryName(normalized)}" already exists here.',
      );
    }
    if (totalSize - (_files[normalized]?.size ?? 0) + bytes.length >
        maxArchiveContentBytes) {
      throw const ArchiveDocumentException(
        'This archive would grow larger than AppFlowy can hold in memory.',
      );
    }
    _files[normalized] = ArchiveFile(normalized, bytes.length, bytes)
      ..lastModTime =
          (modified ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    _dirty = true;
    _rebuildIndex();
  }

  /// Creates an empty folder.
  void createDirectory(String path) {
    if (!format.supportsFolders) {
      throw ArchiveDocumentException(
        'A ${format.label} cannot hold folders.',
      );
    }
    final normalized = normalizeArchivePath(path);
    if (normalized.isEmpty) {
      throw const ArchiveDocumentException('A folder needs a name.');
    }
    if (containsPath(normalized)) {
      throw ArchiveDocumentException(
        '"${archiveEntryName(normalized)}" already exists here.',
      );
    }
    _explicitDirectories.add(normalized);
    _dirty = true;
    _rebuildIndex();
  }

  /// Removes a file, or a folder and everything inside it.
  void remove(String path) {
    final normalized = normalizeArchivePath(path);
    if (normalized.isEmpty) {
      return;
    }
    final prefix = '$normalized/';
    _files.removeWhere(
      (key, _) => key == normalized || key.startsWith(prefix),
    );
    _explicitDirectories.removeWhere(
      (key) => key == normalized || key.startsWith(prefix),
    );
    _dirty = true;
    _rebuildIndex();
  }

  /// Renames a file or folder in place, keeping it in the same parent.
  void rename(String path, String newName) {
    final normalized = normalizeArchivePath(path);
    final name = normalizeArchivePath(newName);
    if (normalized.isEmpty || name.isEmpty || name.contains('/')) {
      throw const ArchiveDocumentException('Enter a valid name.');
    }
    final destination = joinArchivePath(archiveParentPath(normalized), name);
    if (destination == normalized) {
      return;
    }
    if (containsPath(destination)) {
      throw ArchiveDocumentException('"$name" already exists here.');
    }
    _movePrefix(normalized, destination);
  }

  /// Moves a file or folder into [directory].
  void move(String path, String directory) {
    final normalized = normalizeArchivePath(path);
    final parent = normalizeArchivePath(directory);
    if (normalized.isEmpty) {
      return;
    }
    if (parent == normalized || parent.startsWith('$normalized/')) {
      throw const ArchiveDocumentException(
        'A folder cannot be moved inside itself.',
      );
    }
    final destination = joinArchivePath(parent, archiveEntryName(normalized));
    if (destination == normalized) {
      return;
    }
    if (containsPath(destination)) {
      throw ArchiveDocumentException(
        '"${archiveEntryName(normalized)}" already exists there.',
      );
    }
    _movePrefix(normalized, destination);
  }

  void _movePrefix(String from, String to) {
    final prefix = '$from/';
    final renamedFiles = <String, ArchiveFile>{};
    for (final entry in _files.entries) {
      final key = entry.key;
      if (key == from) {
        renamedFiles[to] = _renamed(entry.value, to);
      } else if (key.startsWith(prefix)) {
        final moved = '$to/${key.substring(prefix.length)}';
        renamedFiles[moved] = _renamed(entry.value, moved);
      } else {
        renamedFiles[key] = entry.value;
      }
    }
    final renamedDirectories = _explicitDirectories.map((key) {
      if (key == from) {
        return to;
      }
      if (key.startsWith(prefix)) {
        return '$to/${key.substring(prefix.length)}';
      }
      return key;
    }).toSet();

    _files
      ..clear()
      ..addAll(renamedFiles);
    _explicitDirectories
      ..clear()
      ..addAll(renamedDirectories);
    _dirty = true;
    _rebuildIndex();
  }

  ArchiveFile _renamed(ArchiveFile file, String path) {
    final content = file.content;
    final bytes = content is Uint8List
        ? content
        : Uint8List.fromList(content as List<int>);
    return ArchiveFile(path, bytes.length, bytes)
      ..lastModTime = file.lastModTime
      ..mode = file.mode;
  }

  /// The bytes for the current contents, in the format it was read from.
  Uint8List encode() {
    if (!format.isContainer) {
      final only =
          _files.values.isEmpty ? Uint8List(0) : _bytesOf(_files.values.first);
      return Uint8List.fromList(_compress(only, format));
    }
    final archive = Archive();
    if (format.supportsFolders) {
      for (final directory in _explicitDirectories.toList()..sort()) {
        archive.addFile(ArchiveFile('$directory/', 0, <int>[])..isFile = false);
      }
    }
    for (final file in _files.values) {
      archive.addFile(file);
    }
    if (format == ArchiveFormat.zip) {
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) {
        throw const ArchiveDocumentException(
          'This archive could not be saved.',
        );
      }
      return Uint8List.fromList(encoded);
    }
    final tar = TarEncoder().encode(archive);
    return Uint8List.fromList(
      format == ArchiveFormat.tar ? tar : _compress(tar, format),
    );
  }

  static List<int> _compress(List<int> bytes, ArchiveFormat format) {
    switch (format) {
      case ArchiveFormat.tarGzip:
      case ArchiveFormat.gzip:
        final encoded = GZipEncoder().encode(bytes);
        if (encoded == null) {
          throw const ArchiveDocumentException(
            'This archive could not be saved.',
          );
        }
        return encoded;
      case ArchiveFormat.tarBzip2:
      case ArchiveFormat.bzip2:
        return BZip2Encoder().encode(bytes);
      case ArchiveFormat.tarXz:
      case ArchiveFormat.xz:
        return XZEncoder().encode(bytes);
      case ArchiveFormat.zip:
      case ArchiveFormat.tar:
        return bytes;
    }
  }

  Uint8List _bytesOf(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) {
      return content;
    }
    return Uint8List.fromList(content as List<int>);
  }

  /// Replaces [target] with the current contents.
  ///
  /// The new archive is staged beside the original and renamed over it, so an
  /// interrupted save can never leave a half-written zip behind.
  Future<void> saveTo(File target) async {
    final bytes = encode();
    final staged = File('${target.path}.appflowy.tmp');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(target.path);
    } finally {
      if (await staged.exists()) {
        await staged.delete();
      }
    }
    _dirty = false;
  }

  void _rebuildIndex() {
    final directories = <String>{};
    void addAncestors(String path) {
      var parent = archiveParentPath(path);
      while (parent.isNotEmpty) {
        if (!directories.add(parent)) {
          return;
        }
        parent = archiveParentPath(parent);
      }
    }

    for (final directory in _explicitDirectories) {
      directories.add(directory);
      addAncestors(directory);
    }
    for (final path in _files.keys) {
      addAncestors(path);
    }

    final sizes = <String, int>{};
    final modified = <String, DateTime>{};
    for (final file in _files.values) {
      final timestamp =
          DateTime.fromMillisecondsSinceEpoch(file.lastModTime * 1000);
      var parent = archiveParentPath(file.name);
      while (parent.isNotEmpty) {
        sizes[parent] = (sizes[parent] ?? 0) + file.size;
        final current = modified[parent];
        if (current == null || current.isBefore(timestamp)) {
          modified[parent] = timestamp;
        }
        parent = archiveParentPath(parent);
      }
    }

    final byParent = <String, List<ArchiveEntry>>{'': []};
    for (final directory in directories) {
      byParent.putIfAbsent(directory, () => []);
    }
    for (final directory in directories) {
      byParent.putIfAbsent(archiveParentPath(directory), () => []).add(
            ArchiveEntry(
              path: directory,
              isDirectory: true,
              size: sizes[directory] ?? 0,
              modified: modified[directory],
            ),
          );
    }
    for (final file in _files.values) {
      byParent.putIfAbsent(archiveParentPath(file.name), () => []).add(
            ArchiveEntry(
              path: file.name,
              isDirectory: false,
              size: file.size,
              modified:
                  DateTime.fromMillisecondsSinceEpoch(file.lastModTime * 1000),
            ),
          );
    }
    for (final entries in byParent.values) {
      entries.sort(_compareEntries);
    }

    _directories = directories;
    _childrenByParent = byParent;
  }

  static int _compareEntries(ArchiveEntry a, ArchiveEntry b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

class ArchiveDocumentException implements Exception {
  const ArchiveDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatArchiveBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
