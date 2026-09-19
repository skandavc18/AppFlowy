import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Best-effort expiry of the current sensitive text. This cannot erase copies
/// already taken by another app or by the operating system's clipboard history.
class SensitiveClipboard {
  SensitiveClipboard({
    this.lifetime = const Duration(seconds: 30),
    Future<void> Function(String)? write,
    Future<String?> Function()? read,
  })  : _write = write ?? _writeText,
        _read = read ?? _readText;

  static final instance = SensitiveClipboard();

  final Duration lifetime;
  final Future<void> Function(String) _write;
  final Future<String?> Function() _read;
  Timer? _timer;
  String? _copied;
  int _generation = 0;
  Future<void>? _tail;

  Future<void> copy(String text, {required bool sensitive}) async {
    final generation = ++_generation;
    _timer?.cancel();
    _copied = sensitive ? text : null;
    await _enqueue(() => _write(text));
    if (generation != _generation || !sensitive) return;
    _copied = text;
    _timer = Timer(lifetime, () => unawaited(clear()));
  }

  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    final text = _copied;
    if (text == null) return;
    final generation = ++_generation;
    _copied = null;
    try {
      await _enqueue(() async {
        if (await _read() == text && generation == _generation) {
          await _write('');
        }
      });
    } on Object {
      // Clipboard access can be refused by the OS. Do not log its contents.
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result =
        _tail?.then((_) => operation()) ?? Future<void>.sync(operation);
    late final Future<void> tail;
    void finished() {
      if (identical(_tail, tail)) _tail = null;
    }

    tail = result.then((_) => finished(),
        onError: (Object _, StackTrace __) => finished());
    _tail = tail;
    return result;
  }

  /// A test ends its fake clock between cases. Never carry that clock's timer
  /// or pending platform-channel future into a different widget test.
  @visibleForTesting
  void resetForTest() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _copied = null;
    _tail = null;
  }

  static Future<void> _writeText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  static Future<String?> _readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
