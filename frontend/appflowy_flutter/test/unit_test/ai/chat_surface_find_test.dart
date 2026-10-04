import 'package:appflowy/ai/service/ai_entities.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_find.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

TextMessage _message(
  String id,
  String text, {
  bool answer = false,
  Map<String, dynamic>? metadata,
}) =>
    TextMessage(
      id: id,
      text: text,
      author: User(id: answer ? aiResponseUserId : 'user'),
      createdAt: DateTime(2026),
      metadata: metadata,
    );

void main() {
  test('loaded messages index rendered words, not metadata or markdown URLs',
      () {
    final messages = [
      _message('question', 'needle needle'),
      _message(
        'answer',
        '**needle** and [label](https://hidden_secret.test)',
        answer: true,
        metadata: {'token': 'hidden_secret'},
      ),
      _message(
        'related',
        'needle',
        metadata: {
          onetimeShotType: OnetimeShotType.relatedQuestion,
        },
      ),
    ];
    final chat = InMemoryChatController(messages: [...messages]);
    final find = ChatFindController(chat);
    addTearDown(chat.dispose);
    addTearDown(find.dispose);
    find.open(replace: true);
    find.setQuery('needle');
    expect(find.matches, hasLength(3));
    expect(find.supportsReplace, isFalse);
    expect(find.matches.every((hit) => !hit.entry.replaceable), isTrue);
    find.replacementController.text = 'never written';
    find.replaceAll();
    expect(chat.messages, messages);
    find.setQuery('hidden_secret');
    expect(find.matches, isEmpty);
  });

  test('insert, update, removal and clear refresh the same loaded index',
      () async {
    final first = _message('one', 'needle');
    final chat = InMemoryChatController(messages: [first]);
    final find = ChatFindController(chat);
    addTearDown(chat.dispose);
    addTearDown(find.dispose);
    find.open();
    find.setQuery('needle');
    await chat.insert(_message('two', 'needle needle'));
    await Future<void>.delayed(Duration.zero);
    expect(find.matches, hasLength(3));
    final changed = _message('one', 'no match');
    await chat.update(first, changed);
    await Future<void>.delayed(Duration.zero);
    expect(find.matches, hasLength(2));
    await chat.set([]);
    await Future<void>.delayed(Duration.zero);
    expect(find.matches, isEmpty);
  });

  test('stream observation does not replace the renderer callback', () async {
    final stream = AnswerStream();
    final seenByRenderer = <String>[];
    stream.listen(onData: seenByRenderer.add);
    final chat = InMemoryChatController(
      messages: [
        _message(
          'stream',
          '',
          answer: true,
          metadata: {'$AnswerStream': stream},
        ),
      ],
    );
    final find = ChatFindController(chat);
    find.open();
    find.setQuery('needle');
    stream.addEvent('${AIStreamEventPrefix.data}needle');
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(seenByRenderer, ['needle']);
    expect(find.matches, hasLength(1));
    stream.addEvent('${AIStreamEventPrefix.data} needle');
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(seenByRenderer.last, 'needle needle');
    expect(find.matches, hasLength(2));
    find.dispose();
    stream.addEvent('${AIStreamEventPrefix.data} after disposal');
    await Future<void>.delayed(Duration.zero);
    expect(seenByRenderer.last, 'needle needle after disposal');
    chat.dispose();
    await stream.dispose();
  });
}
