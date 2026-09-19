import 'dart:async';

import 'package:appflowy/shared/encryption/sensitive_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a sensitive copy expires without trimming', (tester) async {
    String? text;
    final clipboard = SensitiveClipboard(
        write: (value) async => text = value, read: () async => text);
    await clipboard.copy('  secret\n', sensitive: true);
    expect(text, '  secret\n');
    await tester.pump(const Duration(seconds: 29));
    expect(text, '  secret\n');
    await tester.pump(const Duration(seconds: 1));
    expect(text, '');
  });

  testWidgets('expiry does not erase text copied by another application',
      (tester) async {
    String? text;
    final clipboard = SensitiveClipboard(
        write: (value) async => text = value, read: () async => text);
    await clipboard.copy('secret', sensitive: true);
    text = 'Other application';
    await tester.pump(const Duration(seconds: 30));
    expect(text, 'Other application');
  });

  testWidgets('an ordinary copy cancels an earlier secret expiry',
      (tester) async {
    String? text;
    final clipboard = SensitiveClipboard(
        write: (value) async => text = value, read: () async => text);
    await clipboard.copy('secret', sensitive: true);
    await clipboard.copy('ordinary', sensitive: false);
    await tester.pump(const Duration(minutes: 1));
    expect(text, 'ordinary');
  });

  testWidgets('locking during a pending copy still clears it afterwards',
      (tester) async {
    String? text;
    final pending = Completer<void>();
    final clipboard = SensitiveClipboard(
      write: (value) async {
        if (value.isNotEmpty) await pending.future;
        text = value;
      },
      read: () async => text,
    );
    final copying = clipboard.copy('secret', sensitive: true);
    final clearing = clipboard.clear();
    pending.complete();
    await copying;
    await clearing;
    expect(text, '');
    await tester.pump(const Duration(minutes: 1));
    expect(text, '');
  });

  testWidgets('a refused OS clipboard does not leave a timer', (tester) async {
    final clipboard = SensitiveClipboard(
        write: (_) async => throw StateError('denied'), read: () async => null);
    await expectLater(
        clipboard.copy('secret', sensitive: true), throwsStateError);
    await clipboard.clear();
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('multiple lock listeners cannot cancel the first cleanup',
      (tester) async {
    String? text;
    final clipboard = SensitiveClipboard(
        write: (value) async => text = value, read: () async => text);
    await clipboard.copy('secret', sensitive: true);
    await Future.wait([clipboard.clear(), clipboard.clear()]);
    expect(text, '');
  });
}
