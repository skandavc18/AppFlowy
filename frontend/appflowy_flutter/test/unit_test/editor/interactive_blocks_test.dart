import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_blocks.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/interactive_items.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the shared block choices', () {
    test('a size is read back, and an unknown one falls to medium', () {
      expect(InteractiveSize.fromValue('compact'), InteractiveSize.compact);
      expect(InteractiveSize.fromValue('wide'), InteractiveSize.wide);
      expect(InteractiveSize.fromValue('enormous'), InteractiveSize.medium);
      expect(InteractiveSize.fromValue(null), InteractiveSize.medium);
    });

    test('only the wide size is unbounded', () {
      expect(InteractiveSize.compact.maxWidth.isFinite, isTrue);
      expect(InteractiveSize.medium.maxWidth.isFinite, isTrue);
      expect(InteractiveSize.wide.maxWidth.isFinite, isFalse);
      expect(
        InteractiveSize.compact.maxWidth,
        lessThan(InteractiveSize.medium.maxWidth),
      );
    });

    test('an accent is read back, and an unknown one falls to neutral', () {
      expect(InteractiveAccent.fromValue('pink'), InteractiveAccent.pink);
      expect(InteractiveAccent.fromValue('teal'), InteractiveAccent.neutral);
    });
  });

  group('options', () {
    test('round trip through the attribute encoding', () {
      const options = [
        InteractiveOption(id: 'a', label: 'Backend'),
        InteractiveOption(
          id: 'b',
          label: 'Trading',
          accent: InteractiveAccent.green,
        ),
      ];
      final decoded = decodeInteractiveOptions(
        encodeInteractiveOptions(options),
      );
      expect(decoded, options);
    });

    test('anything that is not an option is dropped rather than guessed', () {
      final decoded = decodeInteractiveOptions([
        {'id': 'a', 'label': 'Kept'},
        {'label': 'No id'},
        'not a map',
        42,
      ]);
      expect(decoded.map((option) => option.id), ['a']);
    });

    test('a missing attribute reads as no options at all', () {
      expect(decodeInteractiveOptions(null), isEmpty);
      expect(decodeInteractiveOptions('options'), isEmpty);
    });

    test('the starter options each have their own id', () {
      final options = defaultInteractiveOptions();
      expect(options.length, 3);
      expect(options.map((option) => option.id).toSet().length, 3);
    });

    test('a new id is not the same twice', () {
      final ids = List.generate(50, (_) => newInteractiveOptionId()).toSet();
      expect(ids.length, 50);
    });
  });

  group('what an input bar accepts', () {
    test('an empty value is never wrong', () {
      for (final validation in InputValidation.values) {
        expect(validation.check('   '), isNull, reason: validation.name);
      }
    });

    test('a number', () {
      expect(InputValidation.number.check('42'), isNull);
      expect(InputValidation.number.check('-1.5'), isNull);
      expect(InputValidation.number.check('twelve'), isNotNull);
    });

    test('an email address', () {
      expect(InputValidation.email.check('a@b.co'), isNull);
      expect(InputValidation.email.check('a@b'), isNotNull);
      expect(InputValidation.email.check('nobody'), isNotNull);
    });

    test('plain text accepts anything', () {
      expect(InputValidation.none.check('!!!'), isNull);
    });
  });

  group('searching a page', () {
    Node paragraph(String text) => Node(
          type: ParagraphBlockKeys.type,
          attributes: {
            'delta': (Delta()..insert(text)).toJson(),
          },
        );

    Document documentWith(List<Node> nodes) {
      final document = Document.blank();
      document.insert([0], nodes);
      return document;
    }

    test('finds every match in reading order', () {
      final document = documentWith([
        paragraph('The migration design'),
        paragraph('Nothing here'),
        paragraph('design again, design twice'),
      ]);

      final hits = searchDocument(document.root, 'design');
      expect(hits.length, 3);
      expect(hits.first.path, [0]);
      expect(hits[1].path, [2]);
      expect(hits[1].start, 0);
      expect(hits[2].start, greaterThan(hits[1].start));
    });

    test('is not case sensitive and ignores an empty query', () {
      final document = documentWith([paragraph('Bengaluru')]);
      expect(searchDocument(document.root, 'BENGALURU').length, 1);
      expect(searchDocument(document.root, '   '), isEmpty);
    });

    test('reaches into nested children', () {
      final child = paragraph('nested answer');
      final parent = Node(
        type: ParagraphBlockKeys.type,
        attributes: {
          'delta': (Delta()..insert('parent')).toJson(),
        },
        children: [child],
      );
      final document = documentWith([parent]);
      expect(searchDocument(document.root, 'answer').length, 1);
    });

    test('stops at the limit rather than reading a whole book', () {
      final document = documentWith([
        for (var i = 0; i < 40; i++) paragraph('match'),
      ]);
      expect(searchDocument(document.root, 'match', limit: 5).length, 5);
    });

    test('a snippet shows the words around the match', () {
      final hit = PageSearchHit(
        path: const [0],
        text: '${'a' * 80}needle${'b' * 80}',
        start: 80,
        end: 86,
      );
      final snippet = searchHitSnippet(hit, radius: 10);
      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
      expect(snippet, contains('needle'));
    });

    test('a short paragraph is shown whole, with no ellipsis', () {
      const hit = PageSearchHit(path: [0], text: 'needle', start: 0, end: 6);
      expect(searchHitSnippet(hit), 'needle');
    });
  });

  group('a counter reads as a number', () {
    test('whole numbers keep no decimal point', () {
      expect(formatCounterValue(12), '12');
      expect(formatCounterValue(-3), '-3');
      expect(formatCounterValue(0), '0');
    });

    test('a real fraction keeps only what it needs', () {
      expect(formatCounterValue(1.5), '1.5');
      expect(formatCounterValue(0.25), '0.25');
    });
  });

  group('the presentations a block can wear', () {
    test('a control size and shape are read back', () {
      expect(
        InteractiveControlSize.fromValue('large'),
        InteractiveControlSize.large,
      );
      expect(
        InteractiveControlSize.fromValue('enormous'),
        InteractiveControlSize.medium,
      );
      expect(InteractiveShape.fromValue('pill'), InteractiveShape.pill);
      expect(InteractiveShape.fromValue('blob'), InteractiveShape.rounded);
    });

    test('a pill is as round as it is tall, a square barely at all', () {
      expect(InteractiveShape.pill.radiusFor(34), 34);
      expect(InteractiveShape.square.radiusFor(34), lessThan(8));
      expect(
        InteractiveShape.rounded.radiusFor(34),
        InteractiveMetrics.controlRadius,
      );
    });

    test('a larger control is taller and set larger', () {
      expect(
        InteractiveControlSize.small.height,
        lessThan(InteractiveControlSize.large.height),
      );
      expect(
        InteractiveControlSize.small.fontSize,
        lessThan(InteractiveControlSize.large.fontSize),
      );
    });

    test('every progress style has its own thickness reading', () {
      expect(ProgressStyle.fromValue('ring'), ProgressStyle.ring);
      expect(ProgressStyle.fromValue('nothing'), ProgressStyle.bar);
      expect(
        ProgressStyle.line.thickness,
        lessThan(ProgressStyle.thick.thickness),
      );
    });

    test('only the plain counter has no surface', () {
      expect(CounterStyle.fromValue('pill'), CounterStyle.pill);
      expect(CounterStyle.fromValue('nothing'), CounterStyle.card);
      expect(CounterStyle.plain.hasSurface, isFalse);
      expect(CounterStyle.card.hasSurface, isTrue);
    });
  });

  group('searching the workspace by name', () {
    ViewPB view(String name) => ViewPB()
      ..id = name
      ..name = name;

    test('an exact name beats a prefix, which beats anything else', () {
      final views = [
        view('Design notes'),
        view('design'),
        view('Redesign the migration'),
        view('Migration design'),
      ];
      final ranked = rankWorkspaceMatches(views, 'design');
      expect(ranked.map((v) => v.name).toList(), [
        'design',
        'Design notes',
        'Migration design',
        'Redesign the migration',
      ]);
    });

    test('is not case sensitive and ignores an empty query', () {
      expect(rankWorkspaceMatches([view('Report.pdf')], 'REPORT').length, 1);
      expect(rankWorkspaceMatches([view('Report.pdf')], '   '), isEmpty);
    });

    test('finds a file by an extension somebody typed', () {
      final ranked = rankWorkspaceMatches(
        [view('Report.pdf'), view('Notes')],
        '.pdf',
      );
      expect(ranked.single.name, 'Report.pdf');
    });

    test('an unnamed object is never offered', () {
      expect(rankWorkspaceMatches([view('')], 'a'), isEmpty);
    });

    test('stops at the limit', () {
      final views = List.generate(40, (i) => view('match $i'));
      expect(rankWorkspaceMatches(views, 'match', limit: 5).length, 5);
    });
  });

  group('the nodes a slash item inserts', () {
    test('a sticky note carries its text, its colour and its size', () {
      final node = stickyNoteNode(title: 'Important', text: 'Review it');
      expect(node.type, StickyNoteBlockKeys.type);
      expect(node.attributes[StickyNoteBlockKeys.title], 'Important');
      expect(node.attributes[StickyNoteBlockKeys.text], 'Review it');
      expect(
        InteractiveAccent.fromValue(
          node.attributes[InteractiveBlockKeys.accent],
        ),
        InteractiveAccent.yellow,
      );
      expect(
        InteractiveSize.fromValue(node.attributes[InteractiveBlockKeys.size]),
        InteractiveSize.compact,
      );
    });

    test('a progress bar starts empty against a maximum of 100', () {
      final node = progressNode();
      expect(node.attributes[ProgressBlockKeys.value], 0);
      expect(node.attributes[ProgressBlockKeys.maximum], 100);
      expect(node.attributes[ProgressBlockKeys.showPercent], isTrue);
    });

    test('a counter remembers what to reset to', () {
      final node = counterNode(value: 5);
      expect(node.attributes[CounterBlockKeys.value], 5);
      expect(node.attributes[CounterBlockKeys.initial], 5);
      expect(node.attributes[CounterBlockKeys.step], 1);
    });

    test('a selection block starts with usable options and nothing chosen',
        () {
      for (final node in [selectorNode(), radioGroupNode(), multiSelectNode()]) {
        expect(
          decodeInteractiveOptions(
            node.attributes[SelectionBlockKeys.options],
          ).length,
          3,
          reason: node.type,
        );
        expect(node.attributes[SelectionBlockKeys.selected], isEmpty);
      }
    });

    test('a search block looks at its own page first', () {
      expect(
        SearchScope.fromValue(searchNode().attributes[SearchBlockKeys.scope]),
        SearchScope.page,
      );
    });

    test('a reminder block holds an id and nothing else about the reminder',
        () {
      final node = reminderBlockNode();
      expect(node.attributes[ReminderBlockKeys.reminderId], '');
    });

    test('every block type is distinct', () {
      final types = {
        StickyNoteBlockKeys.type,
        ButtonBlockKeys.type,
        ProgressBlockKeys.type,
        CounterBlockKeys.type,
        MemoryBlockKeys.type,
        InputBlockKeys.type,
        SearchBlockKeys.type,
        SelectorBlockKeys.type,
        RadioGroupBlockKeys.type,
        MultiSelectBlockKeys.type,
        ReminderBlockKeys.type,
      };
      expect(types.length, 11);
    });
  });

  group('the Interactive slash menu section', () {
    test('offers one entry per block', () {
      expect(interactiveSlashMenuItems().length, 11);
    });

    test('the short commands in the brief all reach an item', () {
      final items = interactiveSlashMenuItems();
      for (final typed in [
        'sticky',
        'button',
        'progress',
        'counter',
        'memory',
        'input',
        'search',
        'select',
        'radio',
        'multiselect',
        'reminder',
      ]) {
        expect(
          items.any(
            (item) => item.keywords.any((keyword) => keyword.startsWith(typed)),
          ),
          isTrue,
          reason: '/$typed found nothing',
        );
      }
    });

    test('no two entries answer to the same keyword', () {
      final seen = <String, int>{};
      for (final item in interactiveSlashMenuItems()) {
        for (final keyword in item.keywords) {
          seen[keyword] = (seen[keyword] ?? 0) + 1;
        }
      }
      expect(seen.values.every((count) => count == 1), isTrue);
    });
  });

  group('the shared controls', () {
    Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          // Without this the first frame after a re-pump is still lerping
          // towards the new appearance, so the old colours are read back.
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('a button reports its press', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        host(
          InteractiveButton(
            label: 'Open',
            onPressed: () => pressed++,
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });

    testWidgets('a button with no callback cannot be pressed', (tester) async {
      await tester.pumpWidget(host(const InteractiveButton(label: 'Open')));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Nothing to assert but the absence of a crash: the point is that a
      // disabled control is still laid out and still reads as a button.
      expect(find.byType(InteractiveButton), findsOneWidget);
    });

    testWidgets('a chip can be removed', (tester) async {
      var removed = false;
      await tester.pumpWidget(
        host(
          InteractiveChip(
            label: 'Engineering',
            accent: InteractiveAccent.green,
            onRemove: () => removed = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });

    testWidgets('a colour reads differently in light and dark',
        (tester) async {
      late InteractiveTone light;
      late InteractiveTone dark;

      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              light = InteractiveAccent.blue
                  .resolve(interactivePaletteOf(context));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              dark = InteractiveAccent.blue
                  .resolve(interactivePaletteOf(context));
              return const SizedBox.shrink();
            },
          ),
          brightness: Brightness.dark,
        ),
      );

      expect(light.surface, isNot(dark.surface));
      expect(light.strong, isNot(dark.strong));
    });

    testWidgets('every accent resolves to its own surface', (tester) async {
      final surfaces = <Color>{};
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              final palette = interactivePaletteOf(context);
              for (final accent in InteractiveAccent.values) {
                surfaces.add(accent.resolve(palette).surface);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(surfaces.length, InteractiveAccent.values.length);
    });
  });
}
