import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/deferred_code_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scrolling displays full code without starting a parse',
      (tester) async {
    final h = _Harness(scrolling: true);
    try {
      await tester.pumpWidget(h.app('final scrollingCode = compute(42);'));
      final element = h.editorKey.currentContext;
      await tester.pump(const Duration(seconds: 1));
      expect(h.requests, isEmpty);
      expect(h.span!.toPlainText(), 'final scrollingCode = compute(42);');
      h.scrolling.value = false;
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.requests, hasLength(1));
      h.requests.single.complete();
      await tester.pumpAndSettle();
      expect(h.span!.style!.color, Colors.purple);
      expect(h.editorKey.currentContext, same(element));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    }
  });

  testWidgets('a newer edit rejects the old answer and keeps its text',
      (tester) async {
    final h = _Harness();
    try {
      await tester.pumpWidget(h.app('final oldCode = compute(1);'));
      await tester.pump(const Duration(milliseconds: 100));
      final old = h.requests.single;
      await tester.pumpWidget(h.app('final newCode = compute(2);'));
      expect(old.isCancelled(), isTrue);
      old.complete();
      await tester.pump();
      expect(h.span!.toPlainText(), 'final newCode = compute(2);');
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.requests, hasLength(2));
      h.requests.last.complete();
      await tester.pumpAndSettle();
      expect(h.span!.toPlainText(), 'final newCode = compute(2);');
      expect(h.span!.style!.color, Colors.purple);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    }
  });

  testWidgets('resuming scroll cancels work and retries only when idle',
      (tester) async {
    final h = _Harness();
    try {
      await tester.pumpWidget(h.app('final interruptedCode = compute(3);'));
      await tester.pump(const Duration(milliseconds: 100));
      h.scrolling.value = true;
      expect(h.requests.single.isCancelled(), isTrue);
      h.requests.single.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(h.requests, hasLength(1));
      expect(h.span!.style!.color, isNot(Colors.purple));
      h.scrolling.value = false;
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.requests, hasLength(2));
      h.requests.last.complete();
      await tester.pumpAndSettle();
      expect(h.span!.style!.color, Colors.purple);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    }
  });

  testWidgets('unmount cancels delayed and in-flight decoration',
      (tester) async {
    final h = _Harness();
    try {
      await tester.pumpWidget(h.app('final unmountedCode = compute(4);'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.requests, isEmpty);
      await tester.pumpWidget(h.app('final anotherCode = compute(5);'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(h.requests.single.isCancelled(), isTrue);
      h.requests.single.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    }
  });
}

class _Harness {
  _Harness({bool scrolling = false}) : scrolling = ValueNotifier(scrolling);
  final ValueNotifier<bool> scrolling;
  final requests = <_Request>[];
  final editorKey = GlobalKey();
  TextSpan? span;

  Future<TextSpan?> highlight({
    required String code,
    required String language,
    required Brightness brightness,
    TextStyle? style,
    bool isPaper = false,
    bool Function()? isCancelled,
  }) {
    final request = _Request(code, isCancelled!);
    requests.add(request);
    return request.result.future;
  }

  Widget app(String code) => MaterialApp(
        home: DeferredCodeHighlight(
          code: code,
          language: 'dart',
          brightness: Brightness.light,
          style: const TextStyle(fontSize: 14),
          scrolling: scrolling,
          highlighter: highlight,
          builder: (_, value) {
            span = value;
            return RichText(key: editorKey, text: value);
          },
        ),
      );

  void dispose() => scrolling.dispose();
}

class _Request {
  _Request(this.code, this.isCancelled);
  final String code;
  final bool Function() isCancelled;
  final result = Completer<TextSpan?>();
  void complete() => result.complete(
        TextSpan(text: code, style: const TextStyle(color: Colors.purple)),
      );
}
