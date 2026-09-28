import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter/material.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

typedef CsvFindCell = ({int row, int column});

/// Index the preview's already-parsed cells, not another interpretation of CSV.
Iterable<SurfaceFindEntry> csvFindEntries(List<List<String>> rows) sync* {
  for (var row = 0; row < rows.length; row++) {
    for (var column = 0; column < rows[row].length; column++) {
      yield SurfaceFindEntry((row: row, column: column), rows[row][column]);
    }
  }
}

/// The two local file readers deliberately offer no replacement transaction.
/// Access is checked at activation/navigation too, not only during indexing.
class LocalFileFindController extends SurfaceFindController {
  LocalFileFindController({required this.canRead, required super.search});

  final bool Function() canRead;

  @override
  List<SurfaceFindMatch> get matches => canRead() ? super.matches : const [];

  @override
  SurfaceFindMatch? get current => canRead() ? super.current : null;

  @override
  int get currentIndex => canRead() ? super.currentIndex : -1;

  @override
  void open({bool replace = false}) {
    if (!canRead()) {
      close();
      return;
    }
    super.open();
  }

  @override
  void refresh() {
    if (!canRead()) {
      close();
      return;
    }
    super.refresh();
  }

  @override
  void step(int direction) {
    if (!canRead()) {
      close();
      return;
    }
    super.step(direction);
  }
}

/// Variable-height native rows, with a cancellable, serialized Find reveal.
/// The estimate is only a first hop: scroll_to_index finishes at the real tag.
/// No second list, row replacement, or focus/selection mutation is involved.
class LocalFileFindScrollController extends SimpleAutoScrollController {
  LocalFileFindScrollController({required double suggestedRowHeight})
      : super(
          suggestedRowHeight: suggestedRowHeight,
          beginGetter: (rect) => rect.top,
          endGetter: (rect) => rect.bottom,
        );

  Future<void> _pending = Future.value();
  bool Function()? _canReveal;

  Future<void> reveal(int index, {required bool Function() isCurrent}) {
    final next = _pending.then((_) async {
      if (!isCurrent() || !hasClients) return;
      _canReveal = isCurrent;
      try {
        await scrollToIndex(index, preferPosition: AutoScrollPosition.middle);
      } finally {
        _canReveal = null;
      }
    });
    // Keep a failed reveal from poisoning subsequent requests; its caller
    // still receives the original error.
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    final canReveal = _canReveal;
    if (canReveal == null) {
      return super.animateTo(offset, duration: duration, curve: curve);
    }
    if (hasClients && canReveal()) {
      // Find is an immediate reveal, including under reduced motion. The
      // index scroller still waits for real layout after every jump.
      jumpTo(offset.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    return Future.value();
  }
}
