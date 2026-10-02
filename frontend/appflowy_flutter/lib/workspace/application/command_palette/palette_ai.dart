import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// How much of one page is shown to the assistant. Enough to answer from,
/// little enough that four pages still leave room for the question.
const paletteAISourceExcerptLimit = 2400;

/// How many pages one question may lean on.
const paletteAISourceLimit = 4;

/// How many earlier questions and answers go along with a new one.
const paletteAIHistoryLimit = 8;

/// A page the assistant is shown alongside a question.
@immutable
class PaletteAISource {
  const PaletteAISource({
    required this.id,
    required this.title,
    this.excerpt = '',
    this.isCurrentPage = false,
  });

  final String id;
  final String title;

  /// The page's own words, as much of them as [paletteAISourceExcerptLimit]
  /// allows. Empty until read.
  final String excerpt;

  /// Whether this is the page open behind the palette, rather than one the
  /// search found.
  final bool isCurrentPage;

  PaletteAISource withExcerpt(String text) => PaletteAISource(
        id: id,
        title: title,
        excerpt: text.length > paletteAISourceExcerptLimit
            ? '${text.substring(0, paletteAISourceExcerptLimit)}…'
            : text,
        isCurrentPage: isCurrentPage,
      );

  @override
  bool operator ==(Object other) =>
      other is PaletteAISource &&
      other.id == id &&
      other.title == title &&
      other.excerpt == excerpt &&
      other.isCurrentPage == isCurrentPage;

  @override
  int get hashCode => Object.hash(id, title, excerpt, isCurrentPage);
}

/// One earlier question and the answer it got.
@immutable
class PaletteAIExchange {
  const PaletteAIExchange(this.question, this.answer);

  final String question;
  final String answer;
}

/// Everything an engine is handed to answer one question.
@immutable
class PaletteAIRequest {
  const PaletteAIRequest({
    required this.conversationId,
    required this.question,
    this.history = const [],
    this.sources = const [],
  });

  /// Stays the same for the whole conversation. A UUID, because the AppFlowy
  /// backend silently never answers a completion for anything else.
  final String conversationId;
  final String question;
  final List<PaletteAIExchange> history;
  final List<PaletteAISource> sources;

  /// The question as the model reads it: what was asked, then the pages it
  /// may lean on.
  String get prompt => composePaletteAIPrompt(question, sources);
}

/// Why an answer did not arrive.
@immutable
class PaletteAIFailure {
  const PaletteAIFailure(this.message, {this.needsSetup = false});

  final String message;

  /// Whether the fix is in Settings ▸ AI — no model, no key, local AI off —
  /// rather than in trying again.
  final bool needsSetup;
}

/// Something that answers questions asked in the palette.
abstract class PaletteAIEngine {
  /// Shown beside the conversation, such as the model's name.
  String get label;

  /// Whether this engine keeps a transcript a chat page can carry on from.
  bool get canContinueInChat;

  /// Streams an answer to [request] through [onDelta].
  ///
  /// Exactly one of [onDone] and [onError] is called, unless [stop] is called
  /// first, in which case neither need be.
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  });

  /// Abandons whatever is in flight. What already arrived is kept.
  Future<void> stop();
}

enum PaletteAITurnStatus {
  /// Asked, nothing back yet.
  thinking,

  /// The answer is arriving.
  answering,
  done,
  failed,

  /// Stopped by the person before it finished.
  stopped;

  bool get isActive => this == thinking || this == answering;
}

/// One question and its answer, as the conversation goes.
class PaletteAITurn {
  PaletteAITurn._({
    required this.id,
    required this.question,
    required List<PaletteAISource> sources,
  }) : _sources = sources;

  final int id;
  final String question;

  List<PaletteAISource> _sources;
  final StringBuffer _answer = StringBuffer();
  final List<String> _notes = [];
  PaletteAITurnStatus _status = PaletteAITurnStatus.thinking;
  PaletteAIFailure? _failure;
  String _engineLabel = '';

  /// The pages that went with the question, as they were read then.
  List<PaletteAISource> get sources => List.unmodifiable(_sources);

  String get answer => _answer.toString();

  /// What the assistant did on the way, such as a tool it ran.
  List<String> get notes => List.unmodifiable(_notes);

  PaletteAITurnStatus get status => _status;

  PaletteAIFailure? get failure => _failure;

  /// Which model answered.
  String get engineLabel => _engineLabel;

  bool get isActive => _status.isActive;

  bool get hasAnswer => _answer.toString().trim().isNotEmpty;
}

/// A conversation held in the palette.
///
/// One lives for the whole session, so closing the palette and opening it
/// again finds the conversation where it was left. Answers stream in through
/// [notifyListeners], gathered into a frame or so at a time so a fast model
/// does not rebuild the panel for every token.
class PaletteAIConversation extends ChangeNotifier {
  PaletteAIConversation({
    required PaletteAIEngine Function() engine,
    required String Function() newConversationId,
    Future<String> Function(String pageId)? readPage,
    Duration notifyInterval = const Duration(milliseconds: 40),
  })  : _engineFor = engine,
        _newConversationId = newConversationId,
        _readPage = readPage,
        _notifyInterval = notifyInterval,
        _conversationId = newConversationId();

  final PaletteAIEngine Function() _engineFor;
  final String Function() _newConversationId;
  final Future<String> Function(String pageId)? _readPage;
  final Duration _notifyInterval;

  final List<PaletteAITurn> _turns = [];
  String _conversationId;
  PaletteAIEngine? _engine;
  PaletteAIEngine? _lastEngine;
  int _generation = 0;
  int _nextTurnId = 0;
  Timer? _notifyTimer;
  bool _disposed = false;

  List<PaletteAITurn> get turns => List.unmodifiable(_turns);

  bool get isEmpty => _turns.isEmpty;

  /// Whether an answer is being waited for or written.
  bool get isBusy => _turns.lastOrNull?.isActive ?? false;

  String get conversationId => _conversationId;

  /// The engine that answered last, or null before anything was asked.
  PaletteAIEngine? get lastEngine => _lastEngine;

  /// Asks [question], with [sources] read and shown to the model alongside.
  ///
  /// Anything still being answered is stopped first: one question at a time.
  Future<void> ask(
    String question, {
    List<PaletteAISource> sources = const [],
  }) async {
    final text = question.trim();
    if (text.isEmpty || _disposed) {
      return;
    }
    await _stopActive();
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    final turn = PaletteAITurn._(
      id: ++_nextTurnId,
      question: text,
      sources: sources.take(paletteAISourceLimit).toList(growable: false),
    );
    _turns.add(turn);
    _notifyNow();

    final read = await _readSources(turn._sources);
    if (generation != _generation || _disposed) {
      return;
    }
    turn._sources = read;
    await _answer(turn, generation);
  }

  /// Asks the last question again, replacing its answer.
  Future<void> retry() async {
    final last = _turns.lastOrNull;
    if (last == null || _disposed) {
      return;
    }
    await _stopActive();
    _turns.remove(last);
    await ask(last.question, sources: last.sources);
  }

  /// Stops the answer being written. What arrived stays on screen.
  Future<void> stop() => _stopActive();

  /// Forgets the conversation and starts a new one.
  Future<void> clear() async {
    await _stopActive();
    _turns.clear();
    _conversationId = _newConversationId();
    _notifyNow();
  }

  /// Every finished question and answer, oldest first, for handing the
  /// conversation on.
  List<PaletteAIExchange> get exchanges => [
        for (final turn in _turns)
          if (!turn.isActive && turn.hasAnswer)
            PaletteAIExchange(turn.question, turn.answer),
      ];

  Future<List<PaletteAISource>> _readSources(
    List<PaletteAISource> sources,
  ) async {
    final readPage = _readPage;
    if (readPage == null || sources.isEmpty) {
      return sources;
    }
    return Future.wait(
      sources.map((source) async {
        if (source.excerpt.isNotEmpty) {
          return source;
        }
        try {
          return source.withExcerpt((await readPage(source.id)).trim());
        } on Object {
          // A page that cannot be read is still worth naming; the model is
          // told only its title.
          return source;
        }
      }),
    );
  }

  Future<void> _answer(PaletteAITurn turn, int generation) async {
    final engine = _engineFor();
    _engine = engine;
    _lastEngine = engine;
    turn._engineLabel = engine.label;

    // Only finished turns count, so the question being answered is not in it.
    final history = exchanges;
    final request = PaletteAIRequest(
      conversationId: _conversationId,
      question: turn.question,
      history: history.length > paletteAIHistoryLimit
          ? history.sublist(history.length - paletteAIHistoryLimit)
          : history,
      sources: turn.sources,
    );

    bool current() => generation == _generation && !_disposed && turn.isActive;

    try {
      await engine.answer(
        request,
        onDelta: (delta) {
          if (!current() || delta.isEmpty) return;
          turn._answer.write(delta);
          if (turn._status == PaletteAITurnStatus.thinking) {
            turn._status = PaletteAITurnStatus.answering;
            _notifyNow();
          } else {
            _notifySoon();
          }
        },
        onNote: (note) {
          if (!current()) return;
          turn._notes.add(note);
          _notifySoon();
        },
        onDone: () {
          if (!current()) return;
          turn._status = PaletteAITurnStatus.done;
          _finish(engine);
        },
        onError: (failure) {
          if (!current()) return;
          turn
            .._status = PaletteAITurnStatus.failed
            .._failure = failure;
          _finish(engine);
        },
      );
    } on Object catch (error) {
      if (current()) {
        turn
          .._status = PaletteAITurnStatus.failed
          .._failure = PaletteAIFailure('$error');
        _finish(engine);
      }
    }
  }

  void _finish(PaletteAIEngine engine) {
    if (identical(_engine, engine)) {
      _engine = null;
    }
    _notifyNow();
  }

  Future<void> _stopActive() async {
    _generation++;
    final engine = _engine;
    _engine = null;
    final last = _turns.lastOrNull;
    if (last != null && last.isActive) {
      last._status = PaletteAITurnStatus.stopped;
      _notifyNow();
    }
    await engine?.stop();
  }

  void _notifySoon() {
    if (_disposed || _notifyTimer != null) {
      return;
    }
    _notifyTimer = Timer(_notifyInterval, () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _notifyTimer?.cancel();
    final engine = _engine;
    _engine = null;
    unawaited(engine?.stop());
    super.dispose();
  }
}

/// [question] as the model reads it: the question, then whatever the pages
/// in [sources] say, each under its title.
String composePaletteAIPrompt(
  String question,
  List<PaletteAISource> sources,
) {
  final readable = sources.where((source) => source.excerpt.trim().isNotEmpty);
  if (readable.isEmpty) {
    return question;
  }
  final buffer = StringBuffer()
    ..writeln(question)
    ..writeln()
    ..writeln('---')
    ..writeln(
      'Pages from my AppFlowy workspace that may help. Use them when they '
      'are relevant, and name the pages you relied on:',
    );
  for (final source in readable) {
    final title = source.title.trim().isEmpty ? 'Untitled' : source.title;
    buffer
      ..writeln()
      ..writeln(
        source.isCurrentPage ? '## $title (the page I have open)' : '## $title',
      )
      ..writeln(source.excerpt.trim());
  }
  return buffer.toString().trimRight();
}
