import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _zip(Map<String, String> files,
    {List<String> directories = const []}) {
  final archive = Archive();
  for (final directory in directories) {
    archive.addFile(ArchiveFile('$directory/', 0, <int>[])..isFile = false);
  }
  for (final entry in files.entries) {
    final bytes = Uint8List.fromList(entry.value.codeUnits);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

ArchiveDocument _document([Map<String, String>? files]) =>
    ArchiveDocument.fromBytes(
      _zip(
        files ??
            const {
              'readme.md': '# Hello',
              'src/main.dart': 'void main() {}',
              'src/util/strings.dart': 'const a = 1;',
              'assets/logo.png': 'png',
            },
      ),
    );

void main() {
  group('archive paths', () {
    test('normalizes separators and drops traversal segments', () {
      expect(normalizeArchivePath(r'docs\notes.md'), 'docs/notes.md');
      expect(normalizeArchivePath('./docs//notes.md'), 'docs/notes.md');
      expect(normalizeArchivePath('docs/../notes.md'), 'notes.md');
      expect(normalizeArchivePath('../../etc/passwd'), 'etc/passwd');
      expect(normalizeArchivePath('/absolute/path'), 'absolute/path');
    });

    test('splits a path into a name and a parent', () {
      expect(archiveEntryName('src/util/strings.dart'), 'strings.dart');
      expect(archiveParentPath('src/util/strings.dart'), 'src/util');
      expect(archiveParentPath('readme.md'), '');
      expect(joinArchivePath('', 'readme.md'), 'readme.md');
      expect(joinArchivePath('src', 'main.dart'), 'src/main.dart');
    });
  });

  group('archive listing', () {
    test('synthesises the folders implied by entry names', () {
      final document = _document();
      final root = document.childrenOf('');
      expect(
        root.map((entry) => entry.name),
        ['assets', 'src', 'readme.md'],
      );
      expect(root.first.isDirectory, isTrue);
      expect(
        document.childrenOf('src').map((entry) => entry.name),
        ['util', 'main.dart'],
      );
      expect(
        document.childrenOf('src/util').single.path,
        'src/util/strings.dart',
      );
    });

    test('reports a folder size as the total of everything inside it', () {
      final document = _document();
      final src =
          document.childrenOf('').firstWhere((entry) => entry.name == 'src');
      expect(src.size, 'void main() {}'.length + 'const a = 1;'.length);
    });

    test('searches the whole archive, not only the open folder', () {
      final document = _document();
      expect(
        document.search('dart').map((entry) => entry.path),
        ['src/main.dart', 'src/util/strings.dart'],
      );
      expect(document.search('  '), isEmpty);
    });

    test('counts files and folders', () {
      final document = _document();
      expect(document.fileCount, 4);
      expect(document.folderCount, 3);
    });
  });

  group('archive editing', () {
    test('adds a file into the folder it was dropped in', () {
      final document = _document();
      document.writeBytes('src/added.txt', Uint8List.fromList([1, 2, 3]));
      expect(
        document.childrenOf('src').map((entry) => entry.name),
        ['util', 'added.txt', 'main.dart'],
      );
      expect(document.readBytes('src/added.txt'), [1, 2, 3]);
      expect(document.isDirty, isTrue);
    });

    test('replaces the contents of an existing entry', () {
      final document = _document();
      document.writeBytes('readme.md', Uint8List.fromList('# Bye'.codeUnits));
      expect(document.fileCount, 4);
      expect(String.fromCharCodes(document.readBytes('readme.md')), '# Bye');
    });

    test('removes a folder and everything inside it', () {
      final document = _document();
      document.remove('src');
      expect(document.fileCount, 2);
      expect(document.containsPath('src/util/strings.dart'), isFalse);
      expect(
        document.childrenOf('').map((entry) => entry.name),
        ['assets', 'readme.md'],
      );
    });

    test('renames a file without moving it', () {
      final document = _document();
      document.rename('src/main.dart', 'app.dart');
      expect(document.containsPath('src/app.dart'), isTrue);
      expect(document.containsPath('src/main.dart'), isFalse);
      expect(
        String.fromCharCodes(document.readBytes('src/app.dart')),
        'void main() {}',
      );
    });

    test('renaming a folder moves everything under it', () {
      final document = _document();
      document.rename('src', 'lib');
      expect(document.containsPath('lib/util/strings.dart'), isTrue);
      expect(document.containsPath('src/util/strings.dart'), isFalse);
    });

    test('refuses a rename that would collide', () {
      final document = _document();
      expect(
        () => document.rename('src', 'assets'),
        throwsA(isA<ArchiveDocumentException>()),
      );
    });

    test('refuses to move a folder inside itself', () {
      final document = _document();
      expect(
        () => document.move('src', 'src/util'),
        throwsA(isA<ArchiveDocumentException>()),
      );
    });

    test('moves an entry into another folder', () {
      final document = _document();
      document.move('readme.md', 'src');
      expect(document.containsPath('src/readme.md'), isTrue);
      expect(
        document.childrenOf('').map((entry) => entry.name),
        ['assets', 'src'],
      );
    });

    test('reading a missing entry reports which path failed', () {
      final document = _document();
      expect(
        () => document.readBytes('nope.txt'),
        throwsA(isA<ArchiveDocumentException>()),
      );
    });
  });

  group('archive round trips', () {
    test('survives an encode and decode with its edits', () {
      final document = _document();
      document
        ..writeBytes('notes/todo.md', Uint8List.fromList('- one'.codeUnits))
        ..remove('assets')
        ..createDirectory('empty');

      final reloaded = ArchiveDocument.fromBytes(document.encode());
      expect(reloaded.containsPath('notes/todo.md'), isTrue);
      expect(reloaded.containsPath('assets/logo.png'), isFalse);
      expect(reloaded.isDirectory('empty'), isTrue);
      expect(reloaded.childrenOf('empty'), isEmpty);
      expect(
        String.fromCharCodes(reloaded.readBytes('notes/todo.md')),
        '- one',
      );
      expect(reloaded.isDirty, isFalse);
    });

    test('an entry name that escapes its folder is made safe on load', () {
      final document = ArchiveDocument.fromBytes(
        _zip(const {'../../escaped.txt': 'nope', 'safe/./ok.txt': 'yes'}),
      );
      expect(document.containsPath('escaped.txt'), isTrue);
      expect(
        document.childrenOf('').map((entry) => entry.name),
        ['safe', 'escaped.txt'],
      );
    });

    test('writes itself back to disk atomically', () async {
      final directory =
          await Directory.systemTemp.createTemp('archive_document_test');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/bundle.zip');
      await file.writeAsBytes(_zip(const {'a.txt': 'one'}));

      final document = await ArchiveDocument.read(file);
      document.writeBytes('b.txt', Uint8List.fromList('two'.codeUnits));
      await document.saveTo(file);

      expect(File('${file.path}.appflowy.tmp').existsSync(), isFalse);
      final reloaded = await ArchiveDocument.read(file);
      expect(reloaded.fileCount, 2);
      expect(String.fromCharCodes(reloaded.readBytes('b.txt')), 'two');
      expect(document.isDirty, isFalse);
    });
  });

  group('archive formats', () {
    test('recognises every container AppFlowy can open', () {
      expect(archiveFormatForName('bundle.zip'), ArchiveFormat.zip);
      expect(archiveFormatForName('bundle.tar'), ArchiveFormat.tar);
      expect(archiveFormatForName('bundle.tar.gz'), ArchiveFormat.tarGzip);
      expect(archiveFormatForName('bundle.tgz'), ArchiveFormat.tarGzip);
      expect(archiveFormatForName('bundle.tar.bz2'), ArchiveFormat.tarBzip2);
      expect(archiveFormatForName('bundle.tar.xz'), ArchiveFormat.tarXz);
      expect(archiveFormatForName('notes.txt.gz'), ArchiveFormat.gzip);
      expect(archiveFormatForName('notes.txt.xz'), ArchiveFormat.xz);
      expect(archiveFormatForName('bundle.7z'), isNull);
      expect(archiveFormatForName('bundle.rar'), isNull);
    });

    test('names the single file a compressed stream holds', () {
      expect(archiveMemberNameFor('notes.txt.gz'), 'notes.txt');
      expect(archiveMemberNameFor('dump.sql.bz2'), 'dump.sql');
      expect(archiveMemberNameFor('archive.xz'), 'archive');
    });

    test('reads and rewrites a tar', () {
      final archive = Archive()
        ..addFile(ArchiveFile('docs/notes.md', 5, 'hello'.codeUnits));
      final document = ArchiveDocument.fromBytes(
        Uint8List.fromList(TarEncoder().encode(archive)),
        format: ArchiveFormat.tar,
      );
      expect(document.format, ArchiveFormat.tar);
      expect(document.containsPath('docs/notes.md'), isTrue);

      document.writeBytes('docs/added.txt', Uint8List.fromList('hi'.codeUnits));
      final reloaded = ArchiveDocument.fromBytes(
        document.encode(),
        format: ArchiveFormat.tar,
      );
      expect(reloaded.fileCount, 2);
      expect(String.fromCharCodes(reloaded.readBytes('docs/added.txt')), 'hi');
    });

    test('reads and rewrites a gzipped tar', () {
      final archive = Archive()
        ..addFile(ArchiveFile('a.txt', 3, 'one'.codeUnits));
      final document = ArchiveDocument.fromBytes(
        Uint8List.fromList(
          GZipEncoder().encode(TarEncoder().encode(archive))!,
        ),
        format: ArchiveFormat.tarGzip,
      );
      document.writeBytes('b.txt', Uint8List.fromList('two'.codeUnits));
      final reloaded = ArchiveDocument.fromBytes(
        document.encode(),
        format: ArchiveFormat.tarGzip,
      );
      expect(reloaded.fileCount, 2);
      expect(String.fromCharCodes(reloaded.readBytes('a.txt')), 'one');
    });

    test('a single compressed stream holds exactly one file', () {
      final document = ArchiveDocument.fromBytes(
        Uint8List.fromList(GZipEncoder().encode('report'.codeUnits)!),
        format: ArchiveFormat.gzip,
        memberName: 'notes.txt',
      );
      expect(document.supportsMultipleEntries, isFalse);
      expect(document.fileCount, 1);
      expect(String.fromCharCodes(document.readBytes('notes.txt')), 'report');
      expect(
        () => document.writeBytes('other.txt', Uint8List(1)),
        throwsA(isA<ArchiveDocumentException>()),
      );
      expect(
        () => document.createDirectory('folder'),
        throwsA(isA<ArchiveDocumentException>()),
      );

      document.writeBytes('notes.txt', Uint8List.fromList('edited'.codeUnits));
      final reloaded = ArchiveDocument.fromBytes(
        document.encode(),
        format: ArchiveFormat.gzip,
        memberName: 'notes.txt',
      );
      expect(String.fromCharCodes(reloaded.readBytes('notes.txt')), 'edited');
    });

    test('refuses a container it has no codec for', () async {
      final directory =
          await Directory.systemTemp.createTemp('archive_document_format');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/bundle.7z');
      await file.writeAsBytes(Uint8List(64));

      await expectLater(
        ArchiveDocument.read(file),
        throwsA(isA<ArchiveDocumentException>()),
      );
    });
  });

  group('archive limits', () {
    test('formats sizes for the listing', () {
      expect(formatArchiveBytes(512), '512 B');
      expect(formatArchiveBytes(2048), '2.0 KB');
      expect(formatArchiveBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatArchiveBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('refuses an archive that is too large to open', () async {
      final directory =
          await Directory.systemTemp.createTemp('archive_document_limit');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/huge.zip');
      await file.writeAsBytes(Uint8List(maxArchiveBytes + 1));

      await expectLater(
        ArchiveDocument.read(file),
        throwsA(isA<ArchiveDocumentException>()),
      );
    });
  });
}
