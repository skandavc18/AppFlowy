import 'package:appflowy/ai/service/ai_entities.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:appflowy/plugins/ai_chat/presentation/animated_chat_list.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_find.dart';
import 'package:appflowy/plugins/ai_chat/presentation/message/ai_markdown_text.dart';
import 'package:appflowy/plugins/ai_chat/presentation/message/user_text_message.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show AppFlowyEditor;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'surface_find_test_support.dart';

const _composerKey = ValueKey('chat-find-composer');

TextMessage _message(String id, String text,
        {bool answer = false, Map<String, dynamic>? metadata}) =>
    TextMessage(
      id: id,
      text: text,
      author: User(id: answer ? aiResponseUserId : 'user'),
      createdAt: DateTime(2026),
      metadata: metadata,
    );

Widget _messageBody(TextMessage message) {
  final stream = message.metadata?['$AnswerStream'];
  if (stream is AnswerStream) {
    return ValueListenableBuilder<String>(
      valueListenable: stream.textListenable,
      builder: (_, text, __) => AIMarkdownText(
        markdown: text,
        findMessageId: message.id,
        withAnimation: true,
      ),
    );
  }
  if (message.author.id == aiResponseUserId) {
    return AIMarkdownText(markdown: message.text, findMessageId: message.id);
  }
  return SurfaceFindTarget(
      id: (message.id, ''), child: TextMessageText(text: message.text));
}

Widget _conversation(
        {required ChatController chat,
        required ScrollController scroll,
        required TextEditingController draft,
        required FocusNode focus,
        required VoidCallback loadPrevious}) =>
    MultiProvider(
      providers: [
        Provider<ChatController>.value(value: chat),
        Provider<User>.value(value: const User(id: 'user')),
        Provider<Builders>.value(
            value: Builders(
          scrollToBottomBuilder: (_, __, ___) => const SizedBox.shrink(),
        )),
      ],
      child: ChatFindHost(
          chatController: chat,
          child: Column(children: [
            Expanded(
                child: ChatAnimatedList(
              scrollController: scroll,
              onLoadPreviousMessages: loadPrevious,
              itemBuilder: (context, animation, message, {isRemoved}) =>
                  Padding(
                key: ValueKey('message-${message.id}'),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 80),
                child: _messageBody(message as TextMessage),
              ),
            )),
            TextField(key: _composerKey, controller: draft, focusNode: focus),
          ])),
    );

void main() {
  surfaceFindTestEnvironment();

  for (final appearance in WorkspaceDesignAppearance.values) {
    testWidgets(
        '${appearance.name}: chat Ctrl+F jumps the real loaded-message list',
        (tester) async {
      final messages = [
        for (var i = 0; i < 60; i++)
          _message('m$i',
              i == 0 || i == 30 ? 'needle message $i' : 'Loaded message $i')
      ];
      final chat = InMemoryChatController(messages: [...messages]);
      final scroll = ScrollController();
      final draft = TextEditingController(text: 'Draft not in conversation');
      final focus = FocusNode();
      var historyReads = 0;
      try {
        await tester.pumpWidget(surfaceFindTestApp(
            _conversation(
              chat: chat,
              scroll: scroll,
              draft: draft,
              focus: focus,
              loadPrevious: () => historyReads++,
            ),
            appearance: appearance));
        await pumpSurfaceFind(tester);
        final fieldState = tester.state(find.byKey(_composerKey));
        expect(find.text('needle message 0'), findsNothing);
        await openSurfaceFind(tester);
        final bar = tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));
        expect(bar.hintText, 'Find in loaded messages');
        expect(bar.replaceController, isNull);
        await tester.enterText(
            find.byKey(const ValueKey('findTextField')), 'needle');
        await pumpSurfaceFind(tester);
        final session = tester
            .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
            .controller;
        expect(session.matches, hasLength(2));
        final viewport = tester.getRect(find.byType(ChatAnimatedList));
        final firstMatch = session.currentTargetRect!;
        expect(viewport.contains(firstMatch.topLeft), isTrue);
        expect(viewport.contains(firstMatch.bottomRight), isTrue);
        expect(surfaceFindPaint(tester, ('m0', '')).matchRects, hasLength(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.f3,
            physicalKey: PhysicalKeyboardKey.f3);
        await pumpSurfaceFind(tester);
        final nextMatch = session.currentTargetRect!;
        expect(viewport.contains(nextMatch.topLeft), isTrue);
        expect(viewport.contains(nextMatch.bottomRight), isTrue);
        expect(surfaceFindPaint(tester, ('m30', '')).currentRect, isNotNull);
        expect(historyReads, 0,
            reason: 'Find must not page in unloaded history.');
        expect(tester.state(find.byKey(_composerKey)), same(fieldState));
        expect(draft.text, 'Draft not in conversation');
        expect(chat.messages, messages);
        await tester.enterText(
            find.byKey(const ValueKey('findTextField')), 'Draft not');
        await pumpSurfaceFind(tester);
        expect(session.matches, isEmpty,
            reason: 'The composer is not a message.');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        chat.dispose();
        scroll.dispose();
        draft.dispose();
        focus.dispose();
      }
    });
  }

  testWidgets(
      'composer Ctrl+F preserves its draft/focus and Escape does not stop streaming',
      (tester) async {
    final message = _message('message', 'needle');
    final chat = InMemoryChatController(messages: [message]);
    final scroll = ScrollController();
    final draft = TextEditingController();
    final focus = FocusNode();
    var stopRequests = 0;
    try {
      await tester.pumpWidget(surfaceFindTestApp(FocusScope(
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            stopRequests++;
          }
          return KeyEventResult.ignored;
        },
        child: _conversation(
            chat: chat,
            scroll: scroll,
            draft: draft,
            focus: focus,
            loadPrevious: () {}),
      )));
      await pumpSurfaceFind(tester);
      await tester.enterText(
          find.byKey(_composerKey), 'A draft that must remain');
      draft.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
      final value = draft.value;
      final state = tester.state(find.byKey(_composerKey));
      // Exercises the workspace's active-page ContextualFindScope fallback.
      await openSurfaceFind(tester);
      expect(find.byType(FindReplaceBar), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('findTextField')), 'needle');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
      await pumpSurfaceFind(tester);
      expect(stopRequests, 0);
      expect(focus.hasFocus, isTrue);
      expect(draft.value, value);
      expect(tester.state(find.byKey(_composerKey)), same(state));
      expect(chat.messages.single, same(message));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chat.dispose();
      scroll.dispose();
      draft.dispose();
      focus.dispose();
    }
  });

  testWidgets(
      'AI rendered words highlight without transcript writes or editor reparenting',
      (tester) async {
    final message =
        _message('answer', '**needle** and another needle', answer: true);
    final chat = InMemoryChatController(messages: [message]);
    final scroll = ScrollController();
    final draft = TextEditingController(text: 'Keep this draft');
    final focus = FocusNode();
    try {
      await tester.pumpWidget(surfaceFindTestApp(_conversation(
        chat: chat,
        scroll: scroll,
        draft: draft,
        focus: focus,
        loadPrevious: () {},
      )));
      await pumpSurfaceFind(tester);
      final editorElement = tester.element(find.byType(AppFlowyEditor));
      final originalEditor = tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .editorState;
      expect(
          tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editable,
          isFalse);
      await openSurfaceFind(tester);
      await tester.enterText(
          find.byKey(const ValueKey('findTextField')), 'needle');
      await pumpSurfaceFind(tester);
      final session = tester
          .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
          .controller;
      expect(session.matches, hasLength(2));
      expect(surfaceFindPaint(tester, session.current!.id).matchRects,
          hasLength(2));
      expect(tester.element(find.byType(AppFlowyEditor)), same(editorElement));
      expect(
          tester
              .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
              .editorState,
          same(originalEditor));
      await openSurfaceFind(tester, replace: true);
      expect(
          tester
              .widget<FindReplaceBar>(find.byType(FindReplaceBar))
              .replaceController,
          isNull);
      expect(chat.messages.single, same(message));
      expect(draft.text, 'Keep this draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
      await pumpSurfaceFind(tester);
      expect(tester.element(find.byType(AppFlowyEditor)), same(editorElement));
      expect(chat.messages.single, same(message));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chat.dispose();
      scroll.dispose();
      draft.dispose();
      focus.dispose();
    }
  });

  testWidgets(
      'streaming/new text refreshes loaded hits and cancels cleanly on disposal',
      (tester) async {
    final stream = AnswerStream();
    final rendererNotifications = <String>[];
    stream.listen(onData: rendererNotifications.add);
    final message = _message('stream', '',
        answer: true, metadata: {'$AnswerStream': stream});
    final chat = InMemoryChatController(messages: [message]);
    final scroll = ScrollController();
    final draft = TextEditingController(text: 'stream-safe draft');
    final focus = FocusNode();
    final baseline = ContextualFindRegion.debugRegisteredRegionCount;
    try {
      await tester.pumpWidget(surfaceFindTestApp(_conversation(
        chat: chat,
        scroll: scroll,
        draft: draft,
        focus: focus,
        loadPrevious: () {},
      )));
      await openSurfaceFind(tester);
      await tester.enterText(
          find.byKey(const ValueKey('findTextField')), 'needle');
      stream.addEvent('${AIStreamEventPrefix.data}needle');
      await pumpSurfaceFind(tester);
      final session = tester
          .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
          .controller;
      expect(session.matches, hasLength(1));
      expect(
          surfaceFindPaint(tester, session.current!.id).currentRect, isNotNull);
      stream.addEvent('${AIStreamEventPrefix.data} and **needle**');
      await pumpSurfaceFind(tester);
      expect(session.matches, hasLength(2));
      expect(rendererNotifications.last, 'needle and **needle**');
      expect(surfaceFindPaint(tester, session.current!.id).matchRects,
          hasLength(2));
      expect(chat.messages.single, same(message));
      expect(draft.text, 'stream-safe draft');
      await chat.insert(_message('new', 'needle newly loaded'));
      await pumpSurfaceFind(tester);
      expect(session.matches, hasLength(3));
      await tester.pumpWidget(const SizedBox.shrink());
      stream.addEvent('${AIStreamEventPrefix.data} after close');
      await pumpSurfaceFind(tester);
      expect(ContextualFindRegion.debugRegisteredRegionCount, baseline);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chat.dispose();
      scroll.dispose();
      draft.dispose();
      focus.dispose();
      await _closeAnswerStream(tester, stream);
    }
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets(
      'query after streamed mixed markdown paints every native occurrence',
      (tester) async {
    final stream = AnswerStream();
    final message = _message('late-query', '',
        answer: true, metadata: {'$AnswerStream': stream});
    final chat = InMemoryChatController(messages: [message]);
    final scroll = ScrollController();
    final draft = TextEditingController(text: 'untouched composer');
    final focus = FocusNode();
    try {
      await tester.pumpWidget(surfaceFindTestApp(_conversation(
        chat: chat,
        scroll: scroll,
        draft: draft,
        focus: focus,
        loadPrevious: () {},
      )));
      stream.addEvent(
          '${AIStreamEventPrefix.data}**needle** *needle* `needle`\n\n- needle\n\nlast needle');
      await pumpSurfaceFind(tester);
      final editor = tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .editorState;
      await openSurfaceFind(tester);
      await tester.enterText(
          find.byKey(const ValueKey('findTextField')), 'needle');
      await pumpSurfaceFind(tester);
      final controller = tester
          .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
          .controller;
      expect(controller.matches, hasLength(5));
      for (var occurrence = 0; occurrence < 5; occurrence++) {
        final paint = surfaceFindPaint(tester, controller.current!.id);
        final native = <Rect>[];
        for (final run in paint.textRuns) {
          for (final match in RegExp('needle').allMatches(run.text)) {
            native.addAll(run.boxes(match.start, match.end).map((box) =>
                MatrixUtils.transformRect(
                    run.render.getTransformTo(paint), box.toRect())));
          }
        }
        expect(native, isNotEmpty);
        expect(paint.matchRects, native);
        final viewport = tester.getRect(find.byType(ChatAnimatedList));
        expect(viewport.contains(controller.currentTargetRect!.center), isTrue);
        controller.step(1);
        await pumpSurfaceFind(tester);
      }
      expect(
          tester
              .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
              .editorState,
          same(editor));
      stream.addEvent('${AIStreamEventPrefix.data} and **needle**');
      await pumpSurfaceFind(tester);
      expect(controller.matches, hasLength(6));
      final last = controller.matches.last;
      expect(surfaceFindPaint(tester, last.id).matchRects, isNotEmpty);
      expect(chat.messages.single, same(message));
      expect(draft.text, 'untouched composer');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chat.dispose();
      scroll.dispose();
      draft.dispose();
      focus.dispose();
      await _closeAnswerStream(tester, stream);
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}

Future<void> _closeAnswerStream(
    WidgetTester tester, AnswerStream stream) async {
  var closed = false;
  final closing = stream.dispose().then((_) => closed = true);
  // Stream cancellation may use a cached Future from the real zone. Drive both
  // zones before awaiting completion so the widget-test barrier can finish too.
  for (var turn = 0; turn < 8 && !closed; turn++) {
    await tester.runAsync(() async {});
    await tester.pump();
  }
  expect(closed, isTrue, reason: 'The answer stream must finish disposal.');
  await closing;
}
