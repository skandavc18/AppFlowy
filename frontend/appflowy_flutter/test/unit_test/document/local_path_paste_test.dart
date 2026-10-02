import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/local_folder_import.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/local_path_paste.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_attachments.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_plain_text.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Real files in a disposable folder, a real editor and real transactions;
// only where copies are stored (AppFlowy storage, workspace views) is faked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading a pasted path', () {
    String? windows(String text) =>
        localPathFromPastedText(text, windows: true, home: r'C:\Users\me');
    String? posix(String text) =>
        localPathFromPastedText(text, windows: false, home: '/home/me');

    test('drive paths, shares and file addresses on Windows', () {
      expect(windows(r'C:\Users\me\report.pdf'), r'C:\Users\me\report.pdf');
      expect(windows('C:/Users/me/report.pdf'), r'C:\Users\me\report.pdf');
      expect(windows(r'D:\'), r'D:\');
      expect(
        windows(r'\\server\share\Team notes'),
        r'\\server\share\Team notes',
      );
      expect(
        windows('file:///C:/Users/me/My%20Docs/a%23b.pdf'),
        r'C:\Users\me\My Docs\a#b.pdf',
      );
      expect(windows(r'~\Documents'), r'C:\Users\me\Documents');
    });

    test('"Copy as path" quotes and stray whitespace are not part of it', () {
      expect(
        windows('  "C:\\Users\\me\\My Docs\\report.pdf"\r\n'),
        r'C:\Users\me\My Docs\report.pdf',
      );
      expect(windows("'C:\\temp\\x.txt'"), r'C:\temp\x.txt');
      expect(posix("  '/tmp/a b.txt'\n"), '/tmp/a b.txt');
    });

    test('absolute and home paths elsewhere', () {
      expect(posix('/home/me/notes.md'), '/home/me/notes.md');
      expect(posix('~/notes'), '/home/me/notes');
      expect(posix('~'), '/home/me');
      expect(posix('file:///home/me/a%20b.txt'), '/home/me/a b.txt');
    });

    test('anything that is not one absolute local path stays text', () {
      for (final text in [
        '',
        '   ',
        r'Docs\report.pdf',
        r'.\report.pdf',
        'C:report.pdf',
        'https://example.com/report.pdf',
        r'C:\a|b.txt',
        'C:\\one.txt\nC:\\two.txt',
        'file:///C:/a.pdf?download=1',
        'mailto:me@example.com',
        'C:\\x\u0000y',
      ]) {
        expect(windows(text), isNull, reason: text);
      }
      for (final text in ['notes/x.md', r'C:\Users\me', 'see /tmp/x']) {
        expect(posix(text), isNull, reason: text);
      }
    });
  });

  group('on disk', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('local_path_paste_');
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('a pasted path is a file, a folder, or nothing to ask about',
        () async {
      final file = await File(p.join(sandbox.path, 'Report 2026.pdf'))
          .writeAsBytes(List.filled(1200, 7));
      final folder = await Directory(p.join(sandbox.path, 'Photos')).create();

      final pastedFile = await resolvePastedLocalPath('"${file.path}"');
      expect(pastedFile, isNotNull);
      expect(pastedFile!.isDirectory, isFalse);
      expect(pastedFile.size, 1200);
      expect(pastedFile.name, 'Report 2026.pdf');

      final pastedFolder = await resolvePastedLocalPath(folder.uri.toString());
      expect(pastedFolder, isNotNull);
      expect(pastedFolder!.isDirectory, isTrue);
      expect(pastedFolder.name, 'Photos');

      expect(
        await resolvePastedLocalPath(p.join(sandbox.path, 'missing.pdf')),
        isNull,
      );
      expect(await resolvePastedLocalPath('just words'), isNull);
    });

    group('surveying a folder before it is copied', () {
      test('counts what will be copied and leaves the litter', () async {
        await _tree(sandbox, {
          'a.txt': 10,
          'Sub/b.txt': 20,
          'Sub/Deeper/c.txt': 30,
          '.git/config': 999,
          'node_modules/x/index.js': 999,
          'Thumbs.db': 999,
        });
        final survey = await surveyLocalFolder(sandbox);
        expect(survey.fits, isTrue);
        expect(survey.files, 3);
        expect(survey.folders, 2);
        expect(survey.bytes, 60);
      });

      test('stops at the first limit it passes', () async {
        await _tree(sandbox, {'a.txt': 10, 'b.txt': 10, 'c.txt': 10});
        expect(
          (await surveyLocalFolder(
            sandbox,
            limits: const LocalFolderLimits(maximumFiles: 2),
          ))
              .exceeded,
          LocalFolderLimit.files,
        );
        expect(
          (await surveyLocalFolder(
            sandbox,
            limits: const LocalFolderLimits(maximumBytes: 25),
          ))
              .exceeded,
          LocalFolderLimit.bytes,
        );

        await _tree(sandbox, {'one/two/three/deep.txt': 1});
        expect(
          (await surveyLocalFolder(
            sandbox,
            limits: const LocalFolderLimits(maximumDepth: 2),
          ))
              .exceeded,
          LocalFolderLimit.depth,
        );
      });
    });

    test('a folder copy keeps its shape, folders first, in name order',
        () async {
      await _tree(sandbox, {
        'b.txt': 1,
        'A.txt': 1,
        'Zeta/z.txt': 1,
        'alpha/a.txt': 1,
        'alpha/.DS_Store': 1,
      });
      final destination = _FakeFolders();

      final report = await copyLocalFolderContents(
        source: sandbox,
        folderId: 'root',
        destination: destination,
      );

      expect(report.copied, 4);
      expect(report.failed, 0);
      expect(destination.log, [
        'folder root/alpha',
        'file alpha#1/a.txt',
        'folder root/Zeta',
        'file Zeta#2/z.txt',
        'file root/A.txt',
        'file root/b.txt',
      ]);
    });

    test('one file that cannot be stored does not stop the rest', () async {
      await _tree(sandbox, {'a.txt': 1, 'b.txt': 1, 'c.txt': 1});
      final destination = _FakeFolders(refuse: {'b.txt'});

      final report = await copyLocalFolderContents(
        source: sandbox,
        folderId: 'root',
        destination: destination,
      );

      expect(report.copied, 2);
      expect(report.failed, 1);
    });
  });

  group('the pasted link', () {
    late Directory sandbox;
    late PastedLocalPath report;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('local_path_link_');
      final file =
          await File(p.join(sandbox.path, 'report.pdf')).writeAsBytes(_pdf);
      report = (await resolvePastedLocalPath(file.path))!;
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('reads as the path and points at it, wherever the caret was',
        () async {
      final empty = _editor([paragraphNode()]);
      final link = await empty.pasteLocalPathLink(report);
      expect(link, isNotNull);
      expect(empty.document.root.children.single.delta!.toJson(), [
        {
          'insert': report.path,
          'attributes': {'href': report.path},
        },
      ]);
      expect(link!.locate(), _range([0], 0, report.path.length));
      expect(empty.selection, _caret([0], report.path.length));

      final words = _editor(
        [paragraphNode(text: 'see here')],
        selection: _caret([0], 4),
      );
      final inside = await words.pasteLocalPathLink(report);
      expect(
        words.document.root.children.single.delta!.toPlainText(),
        'see ${report.path}here',
      );
      expect(inside!.locate(), _range([0], 4, 4 + report.path.length));
    });

    test('is followed through edits elsewhere and lost once edited away',
        () async {
      final editor = _editor([paragraphNode(text: 'tail')]);
      final link = (await editor.pasteLocalPathLink(report))!;

      // Typing ahead of it in the same block moves it along.
      await editor.apply(
        editor.transaction..insertText(link.node, 0, 'Intro: '),
      );
      expect(link.locate(), _range([0], 7, 7 + report.path.length));

      // A block added above moves its block down.
      await editor.apply(
        editor.transaction..insertNode([0], paragraphNode(text: 'Above')),
      );
      expect(link.locate(), _range([1], 7, 7 + report.path.length));

      await editor.apply(
        editor.transaction..deleteText(link.node, 7, report.path.length),
      );
      expect(link.locate(), isNull);
    });

    test('a code block takes the path as code, not as a link', () async {
      final editor = _editor([
        Node(
          type: CodeBlockKeys.type,
          attributes: {'delta': (Delta()..insert('x = 1')).toJson()},
        ),
      ]);
      expect(await editor.pasteLocalPathLink(report), isNull);
      expect(
        editor.document.root.children.single.delta!.toPlainText(),
        'x = 1',
      );
    });

    test('keeping it as text takes the link off and keeps the words', () async {
      final editor = _editor([paragraphNode()]);
      final link = (await editor.pasteLocalPathLink(report))!;
      await unlinkPastedLocalPath(editor, link);
      expect(editor.document.root.children.single.delta!.toJson(), [
        {'insert': report.path},
      ]);
    });

    test('copying a file puts it in AppFlowy storage, in the link\'s place',
        () async {
      final managed = await Directory(p.join(sandbox.path, 'managed')).create();
      final editor = _editor(
        [paragraphNode(text: 'see  please')],
        selection: _caret([0], 4),
      );
      final link = (await editor.pasteLocalPathLink(report))!;
      final outcomes = <LocalPathPasteOutcome>[];

      await copyPastedLocalPath(
        editor,
        link,
        destination: _page,
        attachments: _storingIn(managed),
        report: outcomes.add,
      );

      expect(outcomes.single.kind, LocalPathPasteOutcomeKind.copied);
      final nodes = editor.document.root.children;
      expect(nodes.map((node) => node.type).toList(), [
        ParagraphBlockKeys.type,
        FileBlockKeys.type,
        ParagraphBlockKeys.type,
      ]);
      expect(nodes.first.delta!.toPlainText(), 'see ');
      expect(nodes.last.delta!.toPlainText(), ' please');
      final stored = nodes[1].attributes[FileBlockKeys.url] as String;
      expect(p.isWithin(managed.path, stored), isTrue);
      expect(await File(stored).readAsBytes(), _pdf);
      expect(nodes[1].attributes[FileBlockKeys.name], 'report.pdf');
      // The original is left exactly where it was.
      expect(await File(report.path).readAsBytes(), _pdf);
    });

    test('a copy whose link was edited away is thrown out, not placed',
        () async {
      final managed = await Directory(p.join(sandbox.path, 'managed')).create();
      final editor = _editor([paragraphNode()]);
      final link = (await editor.pasteLocalPathLink(report))!;
      final outcomes = <LocalPathPasteOutcome>[];

      await copyPastedLocalPath(
        editor,
        link,
        destination: _page,
        attachments: _storingIn(
          managed,
          // The link is deleted while the file is being copied.
          beforeReturning: () => editor.apply(
            editor.transaction
              ..deleteText(link.node, 0, link.node.delta!.length),
          ),
        ),
        report: outcomes.add,
      );

      expect(outcomes.single.kind, LocalPathPasteOutcomeKind.pageChanged);
      expect(
        editor.document.root.children.single.type,
        ParagraphBlockKeys.type,
      );
      expect(await managed.list().toList(), isEmpty);
    });
  });

  group('copying a pasted folder', () {
    late Directory sandbox;
    late Directory photos;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('local_folder_paste_');
      photos = Directory(p.join(sandbox.path, 'Photos'));
      await _tree(photos, {'one.txt': 3, 'Trip/two.txt': 3});
    });

    tearDown(() async {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('becomes a folder under the page, shown where the link was', () async {
      final editor = _editor([paragraphNode()]);
      final item = (await resolvePastedLocalPath(photos.path))!;
      final link = (await editor.pasteLocalPathLink(item))!;
      final folders = _FakeFolders();
      final outcomes = <LocalPathPasteOutcome>[];

      await copyPastedLocalPath(
        editor,
        link,
        destination: _page,
        folders: folders,
        report: outcomes.add,
      );

      final embed = editor.document.root.children.first;
      expect(embed.type, FolderExplorerBlockKeys.type);
      expect(embed.attributes[FolderExplorerBlockKeys.folderId], 'Photos#1');
      expect(folders.log, [
        'folder page/Photos',
        'folder Photos#1/Trip',
        'file Trip#2/two.txt',
        'file Photos#1/one.txt',
      ]);
      expect(outcomes.single.kind, LocalPathPasteOutcomeKind.copied);
      expect(outcomes.single.count, 2);
    });

    test('too big a folder is refused before anything is made', () async {
      final editor = _editor([paragraphNode()]);
      final item = (await resolvePastedLocalPath(photos.path))!;
      final link = (await editor.pasteLocalPathLink(item))!;
      final folders = _FakeFolders();
      final outcomes = <LocalPathPasteOutcome>[];

      await copyPastedLocalPath(
        editor,
        link,
        destination: _page,
        folders: folders,
        limits: const LocalFolderLimits(maximumFiles: 1),
        report: outcomes.add,
      );

      expect(outcomes.single.kind, LocalPathPasteOutcomeKind.tooManyFiles);
      expect(outcomes.single.count, 1);
      expect(folders.log, isEmpty);
      expect(link.locate(), isNotNull, reason: 'The link is kept.');
    });

    test('a folder whose link was edited away is taken back', () async {
      final editor = _editor([paragraphNode()]);
      final item = (await resolvePastedLocalPath(photos.path))!;
      final link = (await editor.pasteLocalPathLink(item))!;
      final folders = _FakeFolders(
        beforeCreating: () => editor.apply(
          editor.transaction..deleteText(link.node, 0, link.text.length),
        ),
      );
      final outcomes = <LocalPathPasteOutcome>[];

      await copyPastedLocalPath(
        editor,
        link,
        destination: _page,
        folders: folders,
        report: outcomes.add,
      );

      expect(outcomes.single.kind, LocalPathPasteOutcomeKind.pageChanged);
      expect(folders.log, ['folder page/Photos', 'remove Photos#1']);
    });
  });

  group('a pasted link', () {
    test('is read as the address it points at, not the words it shows', () {
      final titled = paragraphNode(
        delta: Delta()
          ..insert(
            'Example Domain',
            attributes: {AppFlowyRichTextKeys.href: 'https://example.com/'},
          ),
      );
      expect(
        pastedLinkOf(titled),
        (text: 'Example Domain', href: 'https://example.com/'),
      );
      expect(pastedLinkOf(paragraphNode(text: 'plain words')), isNull);
      expect(
        pastedLinkOf(
          paragraphNode(
            delta: Delta()
              ..insert('a', attributes: {AppFlowyRichTextKeys.href: 'x'})
              ..insert(' and more'),
          ),
        ),
        isNull,
      );
    });
  });
}

const _page = LocalPathPasteDestination(documentId: 'page', isLocalMode: true);

final _pdf = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x25];

/// Writes [files] (relative path to size in bytes) under [root].
Future<void> _tree(Directory root, Map<String, int> files) async {
  for (final entry in files.entries) {
    final file = File(p.joinAll([root.path, ...entry.key.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(entry.value, 1));
  }
}

/// Stores attachments by copying them into [managed], the way AppFlowy's
/// local storage does, optionally letting the page change first.
AttachmentPasteService _storingIn(
  Directory managed, {
  Future<void> Function()? beforeReturning,
}) =>
    AttachmentPasteService(
      saveFile: (
        path, {
        required documentId,
        required isLocalMode,
        required isImage,
      }) async {
        final copy = await File(path)
            .copy(p.join(managed.path, 'stored-${p.basename(path)}'));
        await beforeReturning?.call();
        return copy.path;
      },
    );

class _FakeFolders implements LocalFolderDestination {
  _FakeFolders({this.refuse = const {}, this.beforeCreating});

  final Set<String> refuse;
  final Future<void> Function()? beforeCreating;
  final log = <String>[];
  var _made = 0;

  @override
  Future<String?> createFolder({
    required String parentId,
    required String name,
  }) async {
    await beforeCreating?.call();
    log.add('folder $parentId/$name');
    return '$name#${++_made}';
  }

  @override
  Future<bool> importFile({
    required String parentId,
    required File file,
  }) async {
    final name = p.basename(file.path);
    if (refuse.contains(name)) {
      return false;
    }
    log.add('file $parentId/$name');
    return true;
  }

  @override
  Future<void> remove(String id) async => log.add('remove $id');
}

Selection _caret(List<int> path, [int offset = 0]) =>
    Selection.collapsed(Position(path: path, offset: offset));

Selection _range(List<int> path, int start, int end) => Selection(
      start: Position(path: path, offset: start),
      end: Position(path: path, offset: end),
    );

EditorState _editor(List<Node> nodes, {Selection? selection}) {
  final editor =
      EditorState(document: Document(root: pageNode(children: nodes)))
        ..disableSealTimer = true
        ..editorStyle = const EditorStyle.desktop()
        ..selectionType = SelectionType.inline
        ..selection = selection ?? _caret([0]);
  addTearDown(() {
    if (!editor.isDisposed) editor.dispose();
  });
  return editor;
}
