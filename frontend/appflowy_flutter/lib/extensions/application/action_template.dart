import 'package:flutter/foundation.dart';

/// The values a step can read: the action's arguments, the extension's data,
/// and whatever earlier steps produced, each under its own step id.
typedef ActionContext = Map<String, Object?>;

final RegExp _templatePattern = RegExp(r'\{\{([^{}]*)\}\}');
final RegExp _wholeTemplatePattern = RegExp(r'^\s*\{\{([^{}]*)\}\}\s*$');

/// Reads `a.b.0.c` out of nested maps and lists.
///
/// Returns null for anything missing rather than throwing: a recipe that names
/// a field a service stopped sending should report an empty value, not take
/// the whole run down.
Object? resolveActionPath(ActionContext context, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  Object? current = context;
  for (final segment in trimmed.split('.')) {
    final key = segment.trim();
    if (key.isEmpty) {
      return null;
    }
    if (current is Map) {
      current = current[key];
      continue;
    }
    if (current is List) {
      final index = int.tryParse(key);
      if (index == null || index < 0 || index >= current.length) {
        return null;
      }
      current = current[index];
      continue;
    }
    return null;
  }
  return current;
}

String _asText(Object? value) => switch (value) {
      null => '',
      final String text => text,
      _ => '$value',
    };

/// Fills `{{ }}` in [source].
String renderActionTemplate(String source, ActionContext context) =>
    source.replaceAllMapped(
      _templatePattern,
      (match) => _asText(resolveActionPath(context, match.group(1) ?? '')),
    );

/// Fills templates anywhere inside [value], keeping the shape.
///
/// ⚠️ A string that is nothing BUT one template keeps the resolved value's own
/// type. `"{{ fetch.body.price }}"` has to stay a number, or every value
/// written to the data store would arrive as text and every comparison after
/// it would be a string comparison.
Object? renderActionValue(Object? value, ActionContext context) {
  if (value is String) {
    final whole = _wholeTemplatePattern.firstMatch(value);
    if (whole != null) {
      return resolveActionPath(context, whole.group(1) ?? '');
    }
    return renderActionTemplate(value, context);
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': renderActionValue(entry.value, context),
    };
  }
  if (value is List) {
    return [for (final entry in value) renderActionValue(entry, context)];
  }
  return value;
}

/// How two rendered values are compared in a `when:`.
enum ActionComparison {
  equal('=='),
  notEqual('!='),
  greater('>'),
  greaterOrEqual('>='),
  less('<'),
  lessOrEqual('<='),
  contains('contains');

  const ActionComparison(this.token);

  final String token;
}

/// A `when:` condition.
///
/// ⚠️ Deliberately one flat comparison. No boolean operators, no arithmetic,
/// no nesting. Every configuration format that grew an expression language
/// became a bad programming language; anything more than this belongs in a
/// script step or an MCP tool.
@immutable
class ActionCondition {
  const ActionCondition({
    required this.left,
    this.comparison,
    this.right = '',
  });

  final String left;
  final ActionComparison? comparison;
  final String right;

  static ActionCondition parse(String source) {
    final trimmed = source.trim();
    // Longest token first, so `>=` is not read as `>`.
    const ordered = [
      ActionComparison.greaterOrEqual,
      ActionComparison.lessOrEqual,
      ActionComparison.notEqual,
      ActionComparison.equal,
      ActionComparison.contains,
      ActionComparison.greater,
      ActionComparison.less,
    ];
    for (final comparison in ordered) {
      final token = comparison == ActionComparison.contains
          ? ' ${comparison.token} '
          : comparison.token;
      final at = trimmed.indexOf(token);
      if (at > 0) {
        return ActionCondition(
          left: trimmed.substring(0, at).trim(),
          comparison: comparison,
          right: trimmed.substring(at + token.length).trim(),
        );
      }
    }
    return ActionCondition(left: trimmed);
  }

  bool evaluate(ActionContext context) {
    final leftValue = _resolve(left, context);
    final operation = comparison;
    if (operation == null) {
      return _isTruthy(leftValue);
    }
    final rightValue = _resolve(right, context);

    if (operation == ActionComparison.contains) {
      if (leftValue is List) {
        return leftValue.any((entry) => _looselyEqual(entry, rightValue));
      }
      return _asText(leftValue).contains(_asText(rightValue));
    }

    if (operation == ActionComparison.equal) {
      return _looselyEqual(leftValue, rightValue);
    }
    if (operation == ActionComparison.notEqual) {
      return !_looselyEqual(leftValue, rightValue);
    }

    final leftNumber = _asNumber(leftValue);
    final rightNumber = _asNumber(rightValue);
    if (leftNumber == null || rightNumber == null) {
      return false;
    }
    return switch (operation) {
      ActionComparison.greater => leftNumber > rightNumber,
      ActionComparison.greaterOrEqual => leftNumber >= rightNumber,
      ActionComparison.less => leftNumber < rightNumber,
      ActionComparison.lessOrEqual => leftNumber <= rightNumber,
      _ => false,
    };
  }

  /// A side of a comparison is either a template, a quoted word, or a literal.
  static Object? _resolve(String source, ActionContext context) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    if (_templatePattern.hasMatch(trimmed)) {
      return renderActionValue(trimmed, context);
    }
    return num.tryParse(trimmed) ??
        switch (trimmed) {
          'true' => true,
          'false' => false,
          'null' => null,
          _ => trimmed,
        };
  }

  static num? _asNumber(Object? value) => switch (value) {
        final num number => number,
        final String text => num.tryParse(text.trim()),
        final bool flag => flag ? 1 : 0,
        _ => null,
      };

  static bool _isTruthy(Object? value) => switch (value) {
        null => false,
        final bool flag => flag,
        final num number => number != 0,
        final String text => text.isNotEmpty && text != 'false',
        final Iterable<Object?> items => items.isNotEmpty,
        final Map<Object?, Object?> map => map.isNotEmpty,
        _ => true,
      };

  /// `200` and `"200"` mean the same thing here — a header, a JSON field and a
  /// hand-typed literal all arrive differently typed for the same value.
  static bool _looselyEqual(Object? left, Object? right) {
    if (left == null || right == null) {
      return left == right;
    }
    if (left == right) {
      return true;
    }
    final leftNumber = _asNumber(left);
    final rightNumber = _asNumber(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber == rightNumber;
    }
    return _asText(left) == _asText(right);
  }
}
