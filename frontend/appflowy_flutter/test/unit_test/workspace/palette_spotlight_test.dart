import 'dart:async';

import 'package:appflowy/workspace/application/command_palette/palette_ai.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/palette_scope.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PaletteCommand _command(
  String id,
  String title, {
  List<String> keywords = const [],
  bool takesArgument = false,
  List<String> phrases = const [],
  bool searchOnly = false,
}) =>
    PaletteCommand(
      id: id,
      title: title,
      icon: Icons.abc,
      group: PaletteCommandGroup.create,
      keywords: keywords,
      takesArgument: takesArgument,
      argumentPhrases: phrases,
      searchOnly: searchOnly,
      run: (_) {},
    );

PaletteSetting _setting(
  String id,
  String title, {
  String description = '',
  List<String> keywords = const [],
  PaletteSettingControl? control,
}) =>
    PaletteSetting(
      id: id,
      title: title,
      description: description,
      section: PaletteSettingSection.appearance,
      icon: Icons.abc,
      keywords: keywords,
      control: control ?? PaletteToggle(value: false, onChanged: (_) {}),
    );

/// Answers with whatever the test hands it, when the test says so.
class _ScriptedEngine implements PaletteAIEngine {
  final requests = <PaletteAIRequest>[];
  int stops = 0;
  void Function(String delta)? _delta;
  void Function()? _done;
  void Function(PaletteAIFailure failure)? _error;

  @override
  String get label => 'Scripted';

  @override
  bool get canContinueInChat => false;

  @override
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  }) async {
    requests.add(request);
    _delta = onDelta;
    _done = onDone;
    _error = onError;
  }

  void say(String text) => _delta!(text);

  void finish() => _done!();

  void fail(String message) => _error!(PaletteAIFailure(message));

  @override
  Future<void> stop() async => stops++;
}

void main() {
  group('reading what was typed into the palette', () {
    test('a plain search stays in the scope it was typed into', () {
      final query = parsePaletteQuery('  meeting notes ');
      expect(query.scope, PaletteScope.all);
      expect(query.text, 'meeting notes');
      expect(query.fromPrefix, isFalse);
    });

    test('> lists commands and ? asks the assistant', () {
      final commands = parsePaletteQuery('> zoom');
      expect(commands.scope, PaletteScope.commands);
      expect(commands.text, 'zoom');
      expect(commands.fromPrefix, isTrue);

      final question = parsePaletteQuery('?what changed this week');
      expect(question.scope, PaletteScope.ai);
      expect(question.text, 'what changed this week');
      expect(question.fromPrefix, isTrue);
    });

    test('a scope chosen on purpose keeps every character typed into it', () {
      final settings = parsePaletteQuery(
        '?dark',
        selected: PaletteScope.settings,
      );
      expect(settings.scope, PaletteScope.settings);
      expect(settings.text, '?dark');

      final pages = parsePaletteQuery('> zoom', selected: PaletteScope.pages);
      expect(pages.scope, PaletteScope.commands);
    });

    test('commands and questions are never searched for in the workspace', () {
      expect(isPaletteLocalQuery('>new'), isTrue);
      expect(isPaletteLocalQuery('?why'), isTrue);
      expect(isPaletteLocalQuery('why?'), isFalse);
      expect(isPaletteLocalQuery(''), isFalse);
    });
  });

  group('what a command is handed after its name', () {
    final newPage = _command(
      'new_page',
      'New page',
      takesArgument: true,
      phrases: ['create page'],
    );

    test('the words after the name, or after another way of saying it', () {
      expect(
        paletteCommandArgument(newPage, 'new page Meeting notes'),
        'Meeting notes',
      );
      expect(paletteCommandArgument(newPage, 'NEW PAGE  Ideas  '), 'Ideas');
      expect(
        paletteCommandArgument(newPage, 'create page: Roadmap'),
        'Roadmap',
      );
    });

    test('nothing when only the name, or part of a longer word, was typed',
        () {
      expect(paletteCommandArgument(newPage, 'new page'), isNull);
      expect(paletteCommandArgument(newPage, 'new page   '), isNull);
      expect(paletteCommandArgument(newPage, 'new pages'), isNull);
      expect(paletteCommandArgument(newPage, 'page Ideas'), isNull);
    });

    test('a command that takes nothing is never handed anything', () {
      final zoom = _command('zoom', 'Zoom in');
      expect(paletteCommandArgument(zoom, 'zoom in please'), isNull);
    });

    test('a command handed an argument is the best match there is', () {
      final commands = [
        _command('new_table', 'New table'),
        newPage,
      ];
      final ranked = rankPaletteCommands(commands, 'new page Ideas');
      expect(ranked.first.id, 'new_page');
    });
  });

  group('the long tail of commands', () {
    final commands = [
      _command('new_page', 'New page'),
      _command('new_markdown', 'New Markdown', searchOnly: true),
    ];

    test('waits to be searched for', () {
      expect(rankPaletteCommands(commands, '').map((c) => c.id), ['new_page']);
    });

    test('is found once something is typed', () {
      expect(
        rankPaletteCommands(commands, 'markdown').map((c) => c.id),
        ['new_markdown'],
      );
    });
  });

  group('finding a setting', () {
    final settings = [
      _setting(
        'theme_mode',
        'Appearance',
        description: 'Light, dark, or follow the system',
        control: PaletteChoice(
          options: const [
            PaletteSettingOption(id: 'light', label: 'Light'),
            PaletteSettingOption(id: 'dark', label: 'Dark'),
          ],
          selectedId: 'light',
          onSelected: (_) {},
        ),
      ),
      _setting(
        'theme',
        'Color theme',
        keywords: ['colors'],
        control: PaletteChoice(
          options: const [
            PaletteSettingOption(id: 'Default', label: 'Default'),
            PaletteSettingOption(id: 'Lavender', label: 'Lavender'),
          ],
          selectedId: 'Default',
          onSelected: (_) {},
        ),
      ),
      _setting('spell_check', 'Check spelling', keywords: ['typos']),
    ];

    test('by its title first', () {
      expect(rankPaletteSettings(settings, 'color').first.id, 'theme');
    });

    test('by a value it can take', () {
      expect(rankPaletteSettings(settings, 'lavender').single.id, 'theme');
      expect(rankPaletteSettings(settings, 'dark').first.id, 'theme_mode');
    });

    test('by a word it answers to', () {
      expect(rankPaletteSettings(settings, 'typos').single.id, 'spell_check');
    });

    test('long lists of choices are searched the same way', () {
      const options = [
        PaletteSettingOption(id: 'en-US', label: 'English'),
        PaletteSettingOption(
          id: 'de-DE',
          label: 'Deutsch',
          keywords: ['german'],
        ),
      ];
      expect(rankPaletteOptions(options, 'germ').single.id, 'de-DE');
      expect(rankPaletteOptions(options, '').length, 2);
    });
  });

  group('changing a setting from its row', () {
    test('a choice steps round its options in either direction', () {
      final choice = PaletteChoice(
        options: const [
          PaletteSettingOption(id: 'system', label: 'System'),
          PaletteSettingOption(id: 'light', label: 'Light'),
          PaletteSettingOption(id: 'dark', label: 'Dark'),
        ],
        selectedId: 'dark',
        onSelected: (_) {},
      );
      expect(choice.step(1)!.id, 'system');
      expect(choice.step(-1)!.id, 'light');
      expect(choice.isInline, isTrue);
      expect(choice.selected!.label, 'Dark');
    });

    test('a stepper stays inside its range and does not drift', () {
      final stepper = PaletteStepper(
        value: 0.9,
        min: 0.5,
        max: 1,
        step: 0.1,
        label: (value) => '$value',
        onChanged: (_) {},
      );
      expect(stepper.stepped(1), 1.0);
      expect(stepper.stepped(-1), 0.8);
      expect(stepper.canIncrease, isTrue);

      final atTop = PaletteStepper(
        value: 1,
        min: 0.5,
        max: 1,
        step: 0.1,
        label: (value) => '$value',
        onChanged: (_) {},
      );
      expect(atTop.canIncrease, isFalse);
      expect(atTop.stepped(1), 1.0);
    });
  });

  group('a conversation in the palette', () {
    late _ScriptedEngine engine;
    late PaletteAIConversation conversation;
    var ids = 0;

    setUp(() {
      engine = _ScriptedEngine();
      conversation = PaletteAIConversation(
        engine: () => engine,
        newConversationId: () => 'conversation-${ids++}',
        readPage: (id) async => 'The words on $id.',
        notifyInterval: Duration.zero,
      );
    });

    tearDown(() => conversation.dispose());

    test('streams an answer and remembers it for the next question', () async {
      await conversation.ask(
        'What is in the plan?',
        sources: const [PaletteAISource(id: 'plan', title: 'Plan')],
      );
      expect(conversation.isBusy, isTrue);
      final first = engine.requests.single;
      expect(first.question, 'What is in the plan?');
      expect(first.sources.single.excerpt, 'The words on plan.');
      expect(first.prompt, contains('## Plan'));
      expect(first.prompt, contains('The words on plan.'));

      engine.say('Three ');
      engine.say('things.');
      expect(conversation.turns.single.status, PaletteAITurnStatus.answering);
      engine.finish();
      expect(conversation.isBusy, isFalse);
      expect(conversation.turns.single.answer, 'Three things.');

      await conversation.ask('Which is first?');
      final second = engine.requests.last;
      expect(second.conversationId, first.conversationId);
      expect(second.history.single.question, 'What is in the plan?');
      expect(second.history.single.answer, 'Three things.');
      // No pages went with it, so the model reads only the question.
      expect(second.prompt, 'Which is first?');
    });

    test('stopping keeps what arrived and ignores anything late', () async {
      await conversation.ask('Tell me a story');
      engine.say('Once upon');
      await conversation.stop();
      expect(engine.stops, 1);
      engine.say(' a time');
      engine.finish();
      final turn = conversation.turns.single;
      expect(turn.status, PaletteAITurnStatus.stopped);
      expect(turn.answer, 'Once upon');
    });

    test('a failure says why, and trying again asks the same question',
        () async {
      await conversation.ask('Hello?');
      engine.fail('No model is set up.');
      expect(conversation.turns.single.status, PaletteAITurnStatus.failed);
      expect(conversation.turns.single.failure!.message, 'No model is set up.');

      await conversation.retry();
      expect(conversation.turns.length, 1);
      expect(conversation.turns.single.isActive, isTrue);
      expect(engine.requests.last.question, 'Hello?');
    });

    test('a new conversation forgets the old one', () async {
      await conversation.ask('First');
      engine
        ..say('One')
        ..finish();
      final before = conversation.conversationId;
      await conversation.clear();
      expect(conversation.isEmpty, isTrue);
      expect(conversation.conversationId, isNot(before));
    });

    test('a page that cannot be read is still named', () async {
      final failing = PaletteAIConversation(
        engine: () => engine,
        newConversationId: () => 'x',
        readPage: (_) async => throw StateError('gone'),
        notifyInterval: Duration.zero,
      );
      addTearDown(failing.dispose);
      await failing.ask(
        'Summarize',
        sources: const [PaletteAISource(id: 'a', title: 'Notes')],
      );
      expect(engine.requests.last.sources.single.title, 'Notes');
      expect(engine.requests.last.sources.single.excerpt, isEmpty);
    });
  });

  test('a long page is cut short before it reaches the model', () {
    final long = 'x' * (paletteAISourceExcerptLimit + 50);
    final source =
        const PaletteAISource(id: 'a', title: 'Long').withExcerpt(long);
    expect(source.excerpt.length, paletteAISourceExcerptLimit + 1);
    expect(source.excerpt.endsWith('…'), isTrue);
  });

  test('the conversation notifies listeners as an answer arrives', () async {
    final engine = _ScriptedEngine();
    final conversation = PaletteAIConversation(
      engine: () => engine,
      newConversationId: () => 'id',
      notifyInterval: Duration.zero,
    );
    addTearDown(conversation.dispose);
    var notified = 0;
    conversation.addListener(() => notified++);
    await conversation.ask('Hi');
    final afterAsk = notified;
    engine.say('Hello');
    engine.say(' there');
    await Future<void>.delayed(Duration.zero);
    engine.finish();
    expect(notified, greaterThan(afterAsk));
    expect(conversation.turns.single.status, PaletteAITurnStatus.done);
    // Every listener has seen the finished answer.
    final completer = Completer<void>();
    scheduleMicrotask(completer.complete);
    await completer.future;
    expect(conversation.turns.single.answer, 'Hello there');
  });
}
