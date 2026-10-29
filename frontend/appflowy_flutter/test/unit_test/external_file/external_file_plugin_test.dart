import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/external_file/external_file_kind.dart';
import 'package:appflowy/plugins/external_file/external_file_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('externalFilePreviewKindFromName', () {
    test('recognises the Markdown, text and HTML files AppFlowy opens', () {
      const expected = {
        'notes.md': FilePreviewKind.markdown,
        'NOTES.MARKDOWN': FilePreviewKind.markdown,
        'notes.mdown': FilePreviewKind.markdown,
        'notes.mkd': FilePreviewKind.markdown,
        'notes.mkdn': FilePreviewKind.markdown,
        'notes.mdwn': FilePreviewKind.markdown,
        'notes.mdtxt': FilePreviewKind.markdown,
        'notes.txt': FilePreviewKind.text,
        'notes.TEXT': FilePreviewKind.text,
        'server.log': FilePreviewKind.text,
        'page.html': FilePreviewKind.html,
        'page.htm': FilePreviewKind.html,
        'page.xhtml': FilePreviewKind.html,
        'page.shtml': FilePreviewKind.html,
        'archive.v2.pdf': FilePreviewKind.pdf,
      };
      for (final entry in expected.entries) {
        expect(
          externalFilePreviewKindFromName(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('leaves a name without an extension to the contents', () {
      for (final name in ['md', 'html', 'README', '.md', 'notes.']) {
        expect(externalFilePreviewKindFromName(name), isNull, reason: name);
      }
    });
  });

  group('externalFilePreviewKind', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('external_file_kind_');
    });

    tearDown(() => dir.delete(recursive: true));

    File file(String name, [List<int>? bytes]) {
      final file = File(p.join(dir.path, name));
      if (bytes != null) file.writeAsBytesSync(bytes);
      return file;
    }

    test('shows a file without an extension as text unless it is binary',
        () async {
      expect(
        await externalFilePreviewKind(file('README', '# Hello\n'.codeUnits)),
        FilePreviewKind.text,
      );
      expect(
        await externalFilePreviewKind(file('LICENSE', const [])),
        FilePreviewKind.text,
      );
      expect(
        await externalFilePreviewKind(file('blob', const [0x7f, 0x45, 0, 1])),
        isNull,
      );
      expect(await externalFilePreviewKind(file('missing')), isNull);
    });

    test('lets a known extension decide without reading the file', () async {
      expect(
        await externalFilePreviewKind(file('unwritten.md')),
        FilePreviewKind.markdown,
      );
    });

    test('reads only the opening bytes', () async {
      final bytes = [...List.filled(8 * 1024, 0x61), 0];
      expect(
        await externalFilePreviewKind(file('transcript', bytes)),
        FilePreviewKind.text,
      );
    });
  });

  group('ExternalFilePlugin', () {
    final path = p.join(p.rootPrefix(p.current), 'notes', 'todo.md');

    test('is identified by the path of its file', () {
      final plugin = ExternalFilePluginBuilder().build(path);
      addTearDown(plugin.dispose);

      expect(plugin, isA<ExternalFilePlugin>());
      plugin as ExternalFilePlugin;
      expect(plugin.path, path);
      expect(plugin.name, 'todo.md');
      expect(plugin.id, externalFilePluginId(path));
      expect(plugin.pluginType, PluginType.externalFile);
      expect(
        externalFilePluginId(path),
        isNot(externalFilePluginId(p.join(p.dirname(path), 'done.md'))),
      );
    });

    test('cannot be built without a path', () {
      final builder = ExternalFilePluginBuilder();
      for (final data in <Object?>['', null, 42]) {
        expect(
          () => builder.build(data),
          throwsA(FlowyPluginException.invalidData),
          reason: '$data',
        );
      }
    });

    test('is never offered as a new page', () {
      expect(ExternalFilePluginConfig().creatable, isFalse);
    });

    test('reload asks its tab to read the file again until it is disposed',
        () {
      final plugin = ExternalFilePlugin(path: path)
        ..reload()
        ..reload();
      expect(plugin.revision.value, 2);

      plugin.dispose();
      expect(plugin.reload, returnsNormally);
      expect(plugin.dispose, returnsNormally);
    });
  });

  group('displayExternalFileFolder', () {
    final root = p.rootPrefix(p.current);
    final home = p.join(root, 'home', 'me');

    test('writes the home folder as ~', () {
      expect(
        displayExternalFileFolder(p.join(home, 'todo.md'), home: home),
        '~',
      );
      expect(
        displayExternalFileFolder(p.join(home, 'docs', 'todo.md'), home: home),
        p.join('~', 'docs'),
      );
    });

    test('shows any other folder in full', () {
      final other = p.join(root, 'home', 'meow');
      expect(
        displayExternalFileFolder(p.join(other, 'todo.md'), home: home),
        other,
      );
      expect(
        displayExternalFileFolder(p.join(other, 'todo.md'), home: ''),
        other,
      );
    });
  });
}
