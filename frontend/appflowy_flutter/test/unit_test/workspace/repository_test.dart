import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_graph_layout.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_language.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:appflowy/workspace/application/collections/repository/source_imports.dart';
import 'package:appflowy/workspace/application/collections/repository/source_outline.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _file(String id, String name) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: 'C:/repo/$name',
      ).mergeIntoExtra(''),
    );

ViewPB _folder(String id, String name) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

RepoEntry _entry(String path, {String? language}) {
  final name = path.split('/').last;
  return RepoEntry(
    view: _file(path, name),
    kind: RepoEntryKind.source,
    path: path,
    depth: path.split('/').length - 1,
    parentPath: repoParentPath(path),
    language: language == null
        ? repoLanguageForName(name)
        : repoLanguageById(language),
    storageUrl: 'C:/repo/$path',
  );
}

void main() {
  group('repository languages', () {
    test('names a file by its extension', () {
      expect(repoLanguageForName('main.dart')?.id, 'dart');
      expect(repoLanguageForName('Widget.TSX')?.id, 'typescript');
      expect(repoLanguageForName('lib.rs')?.id, 'rust');
      expect(repoLanguageForName('README.md')?.id, 'markdown');
      expect(repoLanguageForName('notes')?.id, isNull);
    });

    test('knows the files that carry no extension', () {
      expect(repoLanguageForName('Dockerfile')?.id, 'bash');
      expect(repoLanguageForName('Gemfile')?.id, 'ruby');
    });

    test('separates code from prose and configuration', () {
      expect(repoLanguageById('dart')!.isCode, isTrue);
      expect(repoLanguageById('markdown')!.isMarkup, isTrue);
      expect(repoLanguageById('yaml')!.isData, isTrue);
      expect(repoLanguageById('yaml')!.isCode, isFalse);
    });
  });

  group('repository entries', () {
    test('sorts a file by what it is for', () {
      expect(repoEntryKindOf(_folder('a', 'lib')), RepoEntryKind.folder);
      expect(repoEntryKindOf(_file('b', 'main.dart')), RepoEntryKind.source);
      expect(
        repoEntryKindOf(_file('c', 'README.md')),
        RepoEntryKind.documentation,
      );
      expect(repoEntryKindOf(_file('d', 'pubspec.yaml')), RepoEntryKind.data);
      expect(repoEntryKindOf(_file('e', 'logo.png')), RepoEntryKind.asset);
      expect(
        repoEntryKindOf(ViewPB(id: 'f', name: 'A page')),
        RepoEntryKind.page,
      );
    });

    test('walks nested folders into one listing with real paths', () {
      final children = <String, List<ViewPB>>{
        'root': [_folder('lib', 'lib'), _file('readme', 'README.md')],
        'lib': [_folder('src', 'src'), _file('main', 'main.dart')],
        'src': [_file('util', 'util.dart')],
      };

      final entries = buildRepoTree(
        rootId: 'root',
        childrenOf: (id) => children[id] ?? const [],
      );

      expect(
        entries.map((entry) => entry.path),
        ['lib', 'lib/src', 'lib/src/util.dart', 'lib/main.dart', 'README.md'],
      );
      expect(entries.last.depth, 0);
      expect(entries[2].depth, 2);
      expect(entries[2].parentPath, 'lib/src');
    });

    test('a folder that contains itself does not loop forever', () {
      final children = <String, List<ViewPB>>{
        'root': [_folder('loop', 'loop')],
        'loop': [_folder('loop', 'loop')],
      };

      final entries = buildRepoTree(
        rootId: 'root',
        childrenOf: (id) => children[id] ?? const [],
      );

      expect(entries.map((entry) => entry.path), ['loop', 'loop/loop']);
    });

    test('resolves relative paths and refuses to climb out', () {
      expect(resolveRepoPath('lib/src', './util.dart'), 'lib/src/util.dart');
      expect(resolveRepoPath('lib/src', '../main.dart'), 'lib/main.dart');
      expect(resolveRepoPath('lib', '../../escape.dart'), isNull);
      expect(resolveRepoPath('', 'main.dart'), 'main.dart');
    });
  });

  group('source outline', () {
    test('reads Dart declarations and their nesting', () {
      const source = '''
import 'dart:async';

/// A comment that declares nothing.
abstract class Shape {
  double area();
}

class Circle extends Shape {
  Circle(this.radius);

  final double radius;

  @override
  double area() => 3.14 * radius * radius;
}

mixin Loggable {}

enum Colour { red, green }

typedef Handler = void Function(int);

void main() {
  if (true) {
    print('hello');
  }
}
''';

      final symbols = parseSourceOutline(repoLanguageById('dart'), source);
      final names = symbols.map((symbol) => symbol.name).toList();

      expect(names, contains('Shape'));
      expect(names, contains('Circle'));
      expect(names, contains('Loggable'));
      expect(names, contains('Colour'));
      expect(names, contains('Handler'));
      expect(names, contains('main'));
      expect(names, contains('area'));
      // `if` and `print` open blocks but declare nothing.
      expect(names, isNot(contains('if')));
      expect(names, isNot(contains('print')));

      final area = symbols.firstWhere((symbol) => symbol.name == 'area');
      expect(area.kind, SymbolKind.function);
      expect(area.depth, 1);
      final circle = symbols.firstWhere((symbol) => symbol.name == 'Circle');
      expect(circle.kind, SymbolKind.classType);
      expect(circle.depth, 0);
    });

    test('does not read declarations out of a block comment', () {
      const source = '''
/*
class Ghost {}
*/
class Real {}
''';

      final names = parseSourceOutline(repoLanguageById('dart'), source)
          .map((symbol) => symbol.name);

      expect(names, ['Real']);
    });

    test('reads Python by indentation', () {
      const source = '''
import os


class Repo:
    def __init__(self, path):
        self.path = path

    async def walk(self):
        return []


def main():
    pass
''';

      final symbols = parseSourceOutline(repoLanguageById('python'), source);

      expect(
        symbols.map((symbol) => symbol.name),
        ['Repo', '__init__', 'walk', 'main'],
      );
      expect(symbols[1].depth, 1);
      expect(symbols[3].depth, 0);
    });

    test('reads Rust items', () {
      const source = '''
pub struct Repo {
    path: String,
}

pub trait Walk {
    fn walk(&self);
}

impl Walk for Repo {
    fn walk(&self) {}
}

pub async fn open(path: &str) -> Repo {
    Repo { path: path.into() }
}
''';

      final symbols = parseSourceOutline(repoLanguageById('rust'), source);

      expect(
        symbols.map((symbol) => (symbol.name, symbol.kind)),
        [
          ('Repo', SymbolKind.structType),
          ('Walk', SymbolKind.traitType),
          ('walk', SymbolKind.function),
          // `impl Walk for Repo` adds to a type rather than declaring one.
          ('Repo', SymbolKind.extensionType),
          ('walk', SymbolKind.function),
          ('open', SymbolKind.function),
        ],
      );
    });

    test('reads markdown headings, skipping fenced code', () {
      const source = '''
# Title

Some prose.

## Install

```
# not a heading
```

### Details
''';

      final symbols = parseSourceOutline(repoLanguageById('markdown'), source);

      expect(
        symbols.map((symbol) => symbol.name),
        ['Title', 'Install', 'Details'],
      );
      expect(symbols.first.depth, 0);
      expect(symbols.last.depth, 2);
      expect(
        symbols.every((symbol) => symbol.kind == SymbolKind.heading),
        true,
      );
    });

    test('a language with no rules yields nothing rather than guessing', () {
      expect(parseSourceOutline(repoLanguageById('json'), '{"a": 1}'), isEmpty);
      expect(parseSourceOutline(null, 'anything at all'), isEmpty);
    });
  });

  group('source imports', () {
    test('reads Dart imports and tells packages from paths', () {
      const source = '''
import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/util.dart';
export 'src/api.dart';
''';

      final imports = parseSourceImports(repoLanguageById('dart'), source);

      expect(imports.length, 4);
      expect(imports[1].packageName, 'flutter');
      expect(imports[2].isRelative, isTrue);
      expect(imports[2].packageName, isNull);
      expect(imports[3].target, 'src/api.dart');
    });

    test('reads the several ways JavaScript names a module', () {
      const source = '''
import React from 'react';
import './styles.css';
const fs = require('node:fs');
export { thing } from '@scope/pkg';
''';

      final imports =
          parseSourceImports(repoLanguageById('typescript'), source);

      expect(
        imports.map((it) => it.target),
        ['react', './styles.css', 'node:fs', '@scope/pkg'],
      );
      expect(imports.last.packageName, '@scope/pkg');
    });

    test('reads a Go grouped import block', () {
      const source = '''
package main

import (
	"fmt"
	"github.com/user/project/pkg"
)

func main() {}
''';

      final imports = parseSourceImports(repoLanguageById('go'), source);

      expect(
        imports.map((it) => it.target),
        ['fmt', 'github.com/user/project/pkg'],
      );
    });

    test('follows a relative import to the file it names', () {
      final entries = [
        _entry('lib/main.dart'),
        _entry('lib/shared/util.dart'),
      ];
      final index = RepoPathIndex(entries);

      final resolution = resolveRepoImports(
        from: entries.first,
        imports: const [
          SourceImport(target: './shared/util.dart', line: 1, isRelative: true),
          SourceImport(
            target: 'package:flutter/material.dart',
            line: 2,
            isRelative: false,
          ),
        ],
        index: index,
      );

      expect(resolution.internal, {'lib/shared/util.dart'});
      expect(resolution.external, {'flutter'});
      expect(resolution.unresolved, isEmpty);
    });

    test('a package import that names a file in the project follows it', () {
      final entries = [
        _entry('lib/main.dart'),
        _entry('lib/api/client.dart'),
      ];

      final resolution = resolveRepoImports(
        from: entries.first,
        imports: const [
          SourceImport(
            target: 'package:app/api/client.dart',
            line: 1,
            isRelative: false,
          ),
        ],
        index: RepoPathIndex(entries),
      );

      expect(resolution.internal, {'lib/api/client.dart'});
    });

    test('a Python module resolves to its file', () {
      final entries = [
        _entry('app/main.py'),
        _entry('app/util.py'),
      ];

      final resolution = resolveRepoImports(
        from: entries.first,
        imports: const [
          SourceImport(target: 'app.util', line: 1, isRelative: false),
        ],
        index: RepoPathIndex(entries),
      );

      expect(resolution.internal, {'app/util.py'});
    });
  });

  group('repository state', () {
    test('survives a round trip through the collection envelope', () {
      const state = RepoState(
        settings: RepoSettings(
          sort: RepoSort.size,
          showHidden: true,
          showOutline: false,
          graphLayout: RepoGraphLayout.layered,
        ),
        expandedPaths: {'lib', 'lib/src'},
        activeFileId: 'file-1',
        browserPath: 'lib',
      );

      final restored = RepoState.fromJson(state.toJson());

      expect(restored.settings.sort, RepoSort.size);
      expect(restored.settings.showHidden, isTrue);
      expect(restored.settings.showOutline, isFalse);
      expect(restored.settings.graphLayout, RepoGraphLayout.layered);
      expect(restored.expandedPaths, {'lib', 'lib/src'});
      expect(restored.activeFileId, 'file-1');
      expect(restored.browserPath, 'lib');
    });

    test('forgets what the repository no longer holds', () {
      const state = RepoState(
        expandedPaths: {'lib', 'gone'},
        activeFileId: 'file-1',
        browserPath: 'gone',
      );

      final pruned = state.prunedTo(paths: {'lib'}, ids: {'file-2'});

      expect(pruned.expandedPaths, {'lib'});
      expect(pruned.activeFileId, isNull);
      expect(pruned.browserPath, '');
    });

    test('opening a nested path opens every folder above it', () {
      var state = const RepoState();
      for (final path in ['lib', 'lib/src']) {
        state = state.toggleExpanded(path);
      }

      expect(state.isExpanded('lib'), isTrue);
      expect(state.isExpanded('lib/src'), isTrue);
      expect(state.toggleExpanded('lib').isExpanded('lib'), isFalse);
    });
  });

  group('dependency graph layout', () {
    const size = Size(600, 400);
    final degrees = {
      'lib/main.dart': 3,
      'lib/a.dart': 2,
      'lib/b.dart': 1,
      'lib/c.dart': 1,
    };
    final edges = <(String, String)>[
      ('lib/main.dart', 'lib/a.dart'),
      ('lib/main.dart', 'lib/b.dart'),
      ('lib/a.dart', 'lib/c.dart'),
    ];

    test('places every node inside the box', () {
      for (final layout in RepoGraphLayout.values) {
        final result = layoutRepoGraph(
          degrees: degrees,
          edges: edges,
          layout: layout,
          size: size,
        );

        expect(result.nodes.length, degrees.length, reason: '$layout');
        for (final node in result.nodes.values) {
          expect(node.position.dx, inInclusiveRange(0, size.width));
          expect(node.position.dy, inInclusiveRange(0, size.height));
        }
      }
    });

    test('is deterministic, so a project keeps its shape', () {
      final first = layoutRepoGraph(
        degrees: degrees,
        edges: edges,
        layout: RepoGraphLayout.force,
        size: size,
      );
      final second = layoutRepoGraph(
        degrees: degrees,
        edges: edges,
        layout: RepoGraphLayout.force,
        size: size,
      );

      for (final path in degrees.keys) {
        expect(first.nodes[path]!.position, second.nodes[path]!.position);
      }
    });

    test('the most connected file is drawn biggest', () {
      final result = layoutRepoGraph(
        degrees: degrees,
        edges: edges,
        layout: RepoGraphLayout.radial,
        size: size,
      );

      expect(
        result.nodes['lib/main.dart']!.radius,
        greaterThan(result.nodes['lib/b.dart']!.radius),
      );
    });

    test('drops edges that point outside the graph', () {
      final result = layoutRepoGraph(
        degrees: const {'a': 1},
        edges: const [('a', 'missing'), ('a', 'a')],
        layout: RepoGraphLayout.force,
        size: size,
      );

      expect(result.edges, isEmpty);
      expect(result.nodes.keys, ['a']);
    });

    test('an empty graph lays out to nothing', () {
      expect(
        layoutRepoGraph(
          degrees: const {},
          edges: const [],
          layout: RepoGraphLayout.force,
          size: size,
        ).isEmpty,
        isTrue,
      );
    });
  });
}
