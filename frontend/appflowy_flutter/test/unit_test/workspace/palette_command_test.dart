import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PaletteCommand _command(
  String id,
  String title, {
  List<String> keywords = const [],
  PaletteCommandGroup group = PaletteCommandGroup.create,
}) =>
    PaletteCommand(
      id: id,
      title: title,
      icon: Icons.abc,
      group: group,
      keywords: keywords,
      run: (_) {},
    );

void main() {
  group('what turns the palette into a command list', () {
    test('an ordinary search is not a command query', () {
      expect(paletteCommandModeQuery('design'), isNull);
      expect(paletteCommandModeQuery(''), isNull);
      expect(paletteCommandModeQuery(null), isNull);
    });

    test('a lone prefix asks for every command', () {
      expect(paletteCommandModeQuery('>'), '');
      expect(paletteCommandModeQuery('  >  '), '');
    });

    test('the prefix is stripped off what was typed after it', () {
      expect(paletteCommandModeQuery('>new page'), 'new page');
      expect(paletteCommandModeQuery('  > new page  '), 'new page');
    });
  });

  group('which command answers a query', () {
    final commands = [
      _command('new_page', 'New page', keywords: ['document', 'add']),
      _command('new_table', 'New table', keywords: ['grid', 'database']),
      _command(
        'toggle_theme',
        'Switch between light and dark',
        keywords: ['appearance', 'theme'],
        group: PaletteCommandGroup.view,
      ),
      _command(
        'ai_settings',
        'AI settings',
        keywords: ['model', 'provider'],
        group: PaletteCommandGroup.workspace,
      ),
    ];

    test('nothing typed keeps the list as it was declared', () {
      expect(
        rankPaletteCommands(commands, '').map((c) => c.id),
        ['new_page', 'new_table', 'toggle_theme', 'ai_settings'],
      );
    });

    test('a title beats a keyword', () {
      final ranked = rankPaletteCommands(commands, 'table');
      expect(ranked.first.id, 'new_table');
    });

    test('the opening of a title beats a mention inside one', () {
      final ranked = rankPaletteCommands(
        [
          _command('a', 'Reopen the last page'),
          _command('b', 'Page settings'),
        ],
        'page',
      );
      expect(ranked.map((c) => c.id), ['b', 'a']);
    });

    test('a keyword finds a command its title never mentions', () {
      final ranked = rankPaletteCommands(commands, 'appearance');
      expect(ranked.single.id, 'toggle_theme');
    });

    test('the words may be typed in any order', () {
      final ranked = rankPaletteCommands(commands, 'settings ai');
      expect(ranked.single.id, 'ai_settings');
    });

    test('a query nothing answers to comes back empty', () {
      expect(rankPaletteCommands(commands, 'zzzz'), isEmpty);
    });

    test('the list is capped', () {
      expect(rankPaletteCommands(commands, '', limit: 2).length, 2);
      expect(rankPaletteCommands(commands, 'new', limit: 1).length, 1);
    });

    test('matching ignores case', () {
      expect(rankPaletteCommands(commands, 'NEW PAGE').first.id, 'new_page');
    });
  });

  group('running a command', () {
    test('it is handed what was typed after the prefix', () {
      String? seen;
      final command = PaletteCommand(
        id: 'ask',
        title: 'Ask AI',
        icon: Icons.abc,
        group: PaletteCommandGroup.ai,
        run: (context) => seen = context.query,
      );

      command.run(
        const PaletteCommandContext(query: 'why is the sky blue', dismiss: _no),
      );

      expect(seen, 'why is the sky blue');
    });
  });
}

void _no() {}
