import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:flutter/foundation.dart';

enum SlideSortDirection {
  ascending,
  descending;

  SlideSortDirection get flipped => this == SlideSortDirection.ascending
      ? SlideSortDirection.descending
      : SlideSortDirection.ascending;
}

/// What the reader has asked to see.
///
/// Searching, sorting and narrowing are all decided here rather than in the
/// deck, so the order the slides arrive in can be tested without drawing one.
@immutable
class SlideQuery {
  const SlideQuery({
    this.search = '',
    this.sortColumn = '',
    this.direction = SlideSortDirection.ascending,
    this.filterColumn = '',
    this.filterValue = '',
  });

  final String search;

  /// The column the deck is ordered by. Empty keeps the table's own order.
  final String sortColumn;
  final SlideSortDirection direction;

  /// The column the deck is narrowed by. Empty shows everything.
  final String filterColumn;

  /// The value that column must hold. Empty means "anything at all".
  final String filterValue;

  bool get isFiltering => filterColumn.isNotEmpty;
  bool get isSorting => sortColumn.isNotEmpty;
  bool get isSearching => search.trim().isNotEmpty;
  bool get isPlain => !isFiltering && !isSorting && !isSearching;

  SlideQuery copyWith({
    String? search,
    String? sortColumn,
    SlideSortDirection? direction,
    String? filterColumn,
    String? filterValue,
  }) =>
      SlideQuery(
        search: search ?? this.search,
        sortColumn: sortColumn ?? this.sortColumn,
        direction: direction ?? this.direction,
        filterColumn: filterColumn ?? this.filterColumn,
        filterValue: filterValue ?? this.filterValue,
      );

  @override
  bool operator ==(Object other) =>
      other is SlideQuery &&
      other.search == search &&
      other.sortColumn == sortColumn &&
      other.direction == direction &&
      other.filterColumn == filterColumn &&
      other.filterValue == filterValue;

  @override
  int get hashCode =>
      Object.hash(search, sortColumn, direction, filterColumn, filterValue);
}

/// The value a card holds in a column, or an empty string.
String slideValueOf(SlideCardData card, String fieldId) {
  for (final property in card.properties) {
    if (property.fieldId == fieldId) {
      return property.value;
    }
  }
  return '';
}

/// The slides that are left once the deck has been narrowed and ordered.
///
/// Searching never removes a slide — a deck that empties itself as you type
/// loses your place. Matches are reported separately so the deck can bring
/// them forward and quieten the rest.
List<SlideCardData> applySlideQuery(
  List<SlideCardData> cards,
  SlideQuery query,
) {
  var result = cards;

  if (query.isFiltering) {
    final wanted = query.filterValue.trim().toLowerCase();
    result = result.where((card) {
      final value = slideValueOf(card, query.filterColumn).trim();
      if (wanted.isEmpty) {
        return value.isNotEmpty;
      }
      return slidePartsOf(value).any((part) => part.toLowerCase() == wanted);
    }).toList();
  }

  if (query.isSorting) {
    final ascending = query.direction == SlideSortDirection.ascending;
    result = [...result]..sort((a, b) {
        final left = slideValueOf(a, query.sortColumn).trim();
        final right = slideValueOf(b, query.sortColumn).trim();
        // A cell with nothing in it has nothing to be ordered by, so it sits
        // at the end either way rather than leading a descending deck.
        if (left.isEmpty || right.isEmpty) {
          if (left.isEmpty && right.isEmpty) {
            return 0;
          }
          return left.isEmpty ? 1 : -1;
        }
        final compared = compareSlideValues(left, right);
        return ascending ? compared : -compared;
      });
  }

  return result;
}

/// Orders two cells the way a reader expects: numbers by size, words by
/// letter, and an empty cell after everything else.
int compareSlideValues(String left, String right) {
  if (left.isEmpty && right.isEmpty) {
    return 0;
  }
  if (left.isEmpty) {
    return 1;
  }
  if (right.isEmpty) {
    return -1;
  }
  final leftNumber = double.tryParse(left.replaceAll(',', ''));
  final rightNumber = double.tryParse(right.replaceAll(',', ''));
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  return left.toLowerCase().compareTo(right.toLowerCase());
}

/// The rows a search matched.
Set<String> slideMatchesOf(List<SlideCardData> cards, String search) {
  final needle = search.trim().toLowerCase();
  if (needle.isEmpty) {
    return const {};
  }
  return {
    for (final card in cards)
      if (slideCardMatches(card, needle)) card.rowId,
  };
}

/// Whether a slide holds the words being looked for, anywhere on it.
bool slideCardMatches(SlideCardData card, String needle) {
  if (card.title.toLowerCase().contains(needle) ||
      card.subtitle.toLowerCase().contains(needle)) {
    return true;
  }
  for (final property in card.properties) {
    if (property.value.toLowerCase().contains(needle)) {
      return true;
    }
  }
  return false;
}

/// The values a column actually holds, so a filter can offer them.
List<String> slideValuesOf(List<SlideCardData> cards, String fieldId) {
  final seen = <String>{};
  final values = <String>[];
  for (final card in cards) {
    for (final part in slidePartsOf(slideValueOf(card, fieldId))) {
      if (seen.add(part.toLowerCase())) {
        values.add(part);
      }
    }
  }
  values.sort(compareSlideValues);
  return values;
}
