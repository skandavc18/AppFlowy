import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// These are deliberately source-rendered, not missing default artwork. Never
// expand this list to silence a new action: add a semantic alias and tests.
const _sourceRendererExceptions = <String, String>{
  'Icons.add_to_drive_rounded': 'Google Drive brand mark, not a generic action',
  'Icons.adaptive':
      'Platform-selected API (adaptive.more), not an IconData name',
  'FlowySvgs.app_logo_s': 'AppFlowy brand identity',
  'FlowySvgs.app_logo_xl': 'AppFlowy brand identity',
  'FlowySvgs.m_apple_icon_xl': 'Apple sign-in brand identity',
  'FlowySvgs.m_google_icon_xl': 'Google sign-in brand identity',
  'FlowySvgs.m_github_icon_xl': 'GitHub sign-in brand identity',
  'FlowySvgs.m_discord_icon_xl': 'Discord sign-in brand identity',
  'FlowySvgs.m_page_style_unsplash_m': 'Unsplash provider identity',
  'FlowySvgs.anonymous_mode_m': 'Existing sign-in illustration, not chrome',
  'FlowySvgs.empty_shared_section_m': 'Empty-state illustration, not chrome',
  'FlowySvgs.m_empty_page_xl': 'Empty-state illustration, not chrome',
  'FlowySvgs.m_empty_trash_xl': 'Empty-state illustration, not chrome',
  'FlowySvgs.m_empty_notification_xl': 'Empty-state illustration, not chrome',
  'FlowySvgs.bulleted_list_icon_1_s': 'Structural first-level document bullet',
  'FlowySvgs.bulleted_list_icon_2_s': 'Structural second-level document bullet',
  'FlowySvgs.bulleted_list_icon_3_s': 'Structural third-level document bullet',
};

void main() {
  test('all lib Material/SVG literals have reviewed mappings or exceptions',
      () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'Run from appflowy_flutter.');
    final aliasesFile =
        File(p.join(lib.path, 'shared', 'workspace_icons.dart'));
    final aliases = _collect(aliasesFile.readAsStringSync(), aliasesFile.path);
    final materialAliases = aliases.references.keys
        .where((name) => name.startsWith('Icons.'))
        .toSet();
    expect(materialAliases.length, greaterThan(400));

    final generated = File(p.join(lib.path, 'generated', 'flowy_svgs.g.dart'))
        .readAsStringSync();
    final generatedPaths = <String, FlowySvgData>{
      for (final match in RegExp(
        r"static const (\w+)\s*=\s*FlowySvgData\('([^']+)'\)",
      ).allMatches(generated))
        'FlowySvgs.${match.group(1)}': FlowySvgData(match.group(2)!),
    };
    expect(generatedPaths.length, greaterThan(500));

    final missing = <String, Set<String>>{};
    final namedMissing = <String, Set<String>>{};
    final observed = <String>{};
    final checkedFiles = <String>{};
    for (final file in lib
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()) {
      final relative =
          p.relative(file.path, from: lib.path).replaceAll('\\', '/');
      if (!relative.endsWith('.dart') ||
          relative.startsWith('generated/') ||
          relative.endsWith('.g.dart') ||
          relative.endsWith('.freezed.dart') ||
          relative == 'shared/workspace_icons.dart') {
        continue;
      }
      final source = file.readAsStringSync();
      // Parse only possible callers; the AST (not this coarse filter) decides
      // which references are code. Comments and strings cannot inflate counts.
      if (!source.contains('Icons.') &&
          !source.contains('FlowySvgs.') &&
          !source.contains('WorkspaceGlyph')) {
        continue;
      }
      final inventory = _collect(source, 'lib/$relative');
      checkedFiles.add(relative);
      for (final entry in inventory.references.entries) {
        final name = entry.key;
        observed.add(name);
        final covered = name.startsWith('Icons.')
            ? materialAliases.contains(name)
            : generatedPaths.containsKey(name) &&
                WorkspaceGlyphs.nameForSvg(generatedPaths[name]!) != null;
        if (!covered && !_sourceRendererExceptions.containsKey(name)) {
          missing.putIfAbsent(name, () => <String>{}).addAll(entry.value);
        }
      }
      for (final entry in inventory.namedDefaults.entries) {
        if (entry.key == 'unknown' || defaultIconSvg(entry.key) == null) {
          namedMissing
              .putIfAbsent(entry.key, () => <String>{})
              .addAll(entry.value);
        }
      }
    }

    // Scope assertions prevent accidentally reducing the audit to the resolver
    // itself or to a hand-picked toolbar. Mobile and extension callers count too.
    for (final prefix in [
      'shared/',
      'workspace/',
      'plugins/document/',
      'plugins/database/',
      'plugins/collection/',
      'plugins/canvas/',
      'mobile/',
      'extensions/',
    ]) {
      expect(
        checkedFiles.any((file) => file.startsWith(prefix)),
        isTrue,
        reason: prefix,
      );
    }
    expect(
      observed,
      containsAll([
        'Icons.find_replace_rounded',
        'Icons.change_circle_rounded',
        'Icons.rotate_90_degrees_ccw_rounded',
        'Icons.flip_rounded',
        'Icons.print_rounded',
        'FlowySvgs.check_filled_s',
        'FlowySvgs.m_field_copy_s',
      ]),
    );
    expect(missing, isEmpty, reason: _describe(missing));
    expect(namedMissing, isEmpty, reason: _describe(namedMissing));
    for (final entry in _sourceRendererExceptions.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
      if (entry.key.startsWith('FlowySvgs.')) {
        expect(generatedPaths, contains(entry.key));
        expect(
          WorkspaceGlyphs.nameForSvg(generatedPaths[entry.key]!),
          isNull,
          reason: '${entry.key} must keep its intentional source renderer',
        );
      }
    }
  });

  test('inventory ignores comments/strings but catches named and raw leaves',
      () {
    final inventory = _collect(
      '''
// Icons.not_an_icon and FlowySvgs.not_a_svg
const documentation = 'Icons.also_not_an_icon';
final raw = Icon(Icons.find_replace_rounded);
final svg = FlowySvg(FlowySvgs.m_field_copy_s);
final named = WorkspaceGlyph.named('fit-page');
final constant = const WorkspaceGlyph.named('actual-size');
final alias = DSWorkspaceGlyph.named(active ? 'print' : 'width');
''',
      'fixture.dart',
    );
    expect(
      inventory.references.keys,
      unorderedEquals([
        'Icons.find_replace_rounded',
        'FlowySvgs.m_field_copy_s',
      ]),
    );
    expect(
      inventory.namedDefaults.keys,
      unorderedEquals(['fit-page', 'actual-size', 'print', 'width']),
    );
  });
}

_References _collect(String source, String path) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final result = _References(
    (offset) => '$path:${parsed.lineInfo.getLocation(offset).lineNumber}',
  );
  parsed.unit.accept(result);
  return result;
}

class _References extends RecursiveAstVisitor<void> {
  _References(this.location);

  static const _glyphTypes = {'WorkspaceGlyph', 'DSWorkspaceGlyph'};
  final String Function(int) location;
  final references = <String, Set<String>>{};
  final namedDefaults = <String, Set<String>>{};

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (const {'Icons', 'FlowySvgs'}.contains(node.prefix.name)) {
      references
          .putIfAbsent(node.toSource(), () => <String>{})
          .add(location(node.offset));
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_glyphTypes.contains(node.target?.toSource()) &&
        node.methodName.name == 'named') {
      _recordNamed(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Without resolution the parser may treat `const Type.named` as a
    // prefixed type, rather than splitting off a named constructor. Both AST
    // shapes have the same constructor source; cover the const form too.
    if (_glyphTypes.any(
      (type) => node.constructorName.toSource() == '$type.named',
    )) {
      _recordNamed(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  void _recordNamed(ArgumentList arguments) {
    if (arguments.arguments.isEmpty) return;
    _recordNameExpression(arguments.arguments.first);
  }

  void _recordNameExpression(Expression expression) {
    if (expression is StringLiteral && expression.stringValue != null) {
      namedDefaults
          .putIfAbsent(expression.stringValue!, () => <String>{})
          .add(location(expression.offset));
    } else if (expression is ConditionalExpression) {
      _recordNameExpression(expression.thenExpression);
      _recordNameExpression(expression.elseExpression);
    } else if (expression is ParenthesizedExpression) {
      _recordNameExpression(expression.expression);
    }
  }
}

String _describe(Map<String, Set<String>> missing) {
  final keys = missing.keys.toList()..sort();
  return keys.map((key) => '$key: ${missing[key]!.join(', ')}').join('\n');
}
