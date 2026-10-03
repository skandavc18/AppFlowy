import 'dart:convert';

import 'package:appflowy/extensions/application/action_template.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:intl/intl.dart';

import 'workflow_model.dart';

/// Everything a step can read: `trigger`, each earlier step under its id,
/// `storage`, `workflow`, `run`, and the clock (`now`, `today`, `time`).
typedef WorkflowContext = Map<String, Object?>;

final RegExp workflowTemplatePattern = RegExp(r'\{\{([^{}]*)\}\}');
final RegExp _wholeTemplatePattern = RegExp(r'^\s*\{\{([^{}]*)\}\}\s*$');

/// Names a step id can never take, because the context already uses them.
const workflowReservedKeys = {
  'trigger',
  'storage',
  'workflow',
  'run',
  'now',
  'today',
  'time',
};

/// Text for a value dropped into a sentence. Structures become JSON rather
/// than Dart's `{a: 1}`, so a body forwarded into a request stays readable.
String workflowText(Object? value) => switch (value) {
      null => '',
      final String text => text,
      final num number => _numberText(number),
      final bool flag => '$flag',
      final DateTime date => date.toIso8601String(),
      final Map<Object?, Object?> map => jsonEncode(workflowJsonSafe(map)),
      final List<Object?> list => jsonEncode(workflowJsonSafe(list)),
      _ => '$value',
    };

String _numberText(num number) {
  if (number is double &&
      number == number.roundToDouble() &&
      number.abs() < 1e15) {
    return number.toInt().toString();
  }
  return '$number';
}

/// Fills every `{{ path }}` in [source] with text.
String renderWorkflowText(String source, WorkflowContext context) =>
    source.replaceAllMapped(
      workflowTemplatePattern,
      (match) => workflowText(resolveActionPath(context, match.group(1) ?? '')),
    );

/// Like [renderWorkflowText], but a value that is nothing BUT one template
/// keeps its own type — a number stays a number in a JSON body.
Object? renderWorkflowValue(String source, WorkflowContext context) {
  final whole = _wholeTemplatePattern.firstMatch(source);
  if (whole != null) {
    return resolveActionPath(context, whole.group(1) ?? '');
  }
  return renderWorkflowText(source, context);
}

/// The paths a template reads, for checking it before it runs.
Iterable<String> workflowTemplatePaths(String source) => workflowTemplatePattern
    .allMatches(source)
    .map((match) => (match.group(1) ?? '').trim())
    .where((path) => path.isNotEmpty);

/// Makes [value] something `jsonEncode` accepts, however it was built.
Object? workflowJsonSafe(Object? value, {int depth = 0}) {
  if (depth > 24) {
    return null;
  }
  return switch (value) {
    null => null,
    final String text => text,
    final bool flag => flag,
    final num number => number.isFinite ? number : null,
    final DateTime date => date.toIso8601String(),
    final Map<Object?, Object?> map => {
        for (final entry in map.entries)
          '${entry.key}': workflowJsonSafe(entry.value, depth: depth + 1),
      },
    final Iterable<Object?> list => [
        for (final entry in list) workflowJsonSafe(entry, depth: depth + 1),
      ],
    _ => '$value',
  };
}

/// A shortened copy of [value] for a run's history: long text is cut, long
/// lists keep their head, deep structures stop early.
Object? previewWorkflowValue(Object? value, {int depth = 0}) {
  if (depth > 5) {
    return '…';
  }
  return switch (value) {
    null => null,
    final String text =>
      text.length > 400 ? '${text.substring(0, 400)}…' : text,
    final bool flag => flag,
    final num number => number.isFinite ? number : null,
    final DateTime date => date.toIso8601String(),
    final Map<Object?, Object?> map => {
        for (final entry in map.entries.take(40))
          '${entry.key}': previewWorkflowValue(entry.value, depth: depth + 1),
        if (map.length > 40) '…': '${map.length - 40} more',
      },
    final Iterable<Object?> list => [
        for (final entry in list.take(20))
          previewWorkflowValue(entry, depth: depth + 1),
        if (list.length > 20) '… ${list.length - 20} more',
      ],
    _ => '$value',
  };
}

/// Every leaf path inside [value], for the data picker: `body.price`,
/// `items.0.title`. Lists offer their first entry only.
List<String> workflowFieldPaths(
  Object? value, {
  String prefix = '',
  int depth = 0,
}) {
  if (depth > 4) {
    return prefix.isEmpty ? const [] : [prefix];
  }
  if (value is Map && value.isNotEmpty) {
    return [
      for (final entry in value.entries.take(60))
        ...workflowFieldPaths(
          entry.value,
          prefix: prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}',
          depth: depth + 1,
        ),
    ];
  }
  if (value is List && value.isNotEmpty) {
    return [
      if (prefix.isNotEmpty) prefix,
      ...workflowFieldPaths(
        value.first,
        prefix: prefix.isEmpty ? '0' : '$prefix.0',
        depth: depth + 1,
      ),
    ];
  }
  return prefix.isEmpty ? const [] : [prefix];
}

bool _isEmptyValue(Object? value) => switch (value) {
      null => true,
      final String text => text.trim().isEmpty,
      final Iterable<Object?> list => list.isEmpty,
      final Map<Object?, Object?> map => map.isEmpty,
      _ => false,
    };

num? workflowNumber(Object? value) => switch (value) {
      final num number => number,
      final String text => num.tryParse(text.trim().replaceAll(',', '')),
      final bool flag => flag ? 1 : 0,
      _ => null,
    };

/// Reads a moment from ISO text, epoch seconds or milliseconds.
DateTime? workflowDate(Object? value) {
  if (value is DateTime) {
    return value;
  }
  final number = workflowNumber(value);
  if (number != null && value is! String) {
    return _fromEpoch(number);
  }
  final text = workflowText(value).trim();
  if (text.isEmpty) {
    return null;
  }
  if (text == 'now') {
    return DateTime.now();
  }
  final parsed = DateTime.tryParse(text);
  if (parsed != null) {
    return parsed.toLocal();
  }
  final epoch = num.tryParse(text);
  return epoch == null ? null : _fromEpoch(epoch);
}

DateTime _fromEpoch(num value) => value.abs() > 100000000000
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
    : DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());

/// Whether one filter line holds. Text comparisons ignore case; numbers and
/// dates are compared as such when both sides read as one.
bool evaluateWorkflowCondition(
  WorkflowCondition condition,
  WorkflowContext context,
) {
  final left = renderWorkflowValue(condition.left, context);
  switch (condition.operator) {
    case WorkflowOperator.isEmpty:
      return _isEmptyValue(left);
    case WorkflowOperator.isNotEmpty:
      return !_isEmptyValue(left);
    default:
      break;
  }
  final right = renderWorkflowValue(condition.right, context);
  final leftText = workflowText(left).trim().toLowerCase();
  final rightText = workflowText(right).trim().toLowerCase();

  switch (condition.operator) {
    case WorkflowOperator.equals:
      return _looselyEqual(left, right, leftText, rightText);
    case WorkflowOperator.notEquals:
      return !_looselyEqual(left, right, leftText, rightText);
    case WorkflowOperator.contains:
      if (left is List) {
        return left.any(
          (entry) => workflowText(entry).trim().toLowerCase() == rightText,
        );
      }
      return leftText.contains(rightText);
    case WorkflowOperator.notContains:
      if (left is List) {
        return !left.any(
          (entry) => workflowText(entry).trim().toLowerCase() == rightText,
        );
      }
      return !leftText.contains(rightText);
    case WorkflowOperator.startsWith:
      return leftText.startsWith(rightText);
    case WorkflowOperator.endsWith:
      return leftText.endsWith(rightText);
    case WorkflowOperator.greaterThan:
    case WorkflowOperator.lessThan:
      final order = _compare(left, right);
      if (order == null) {
        return false;
      }
      return condition.operator == WorkflowOperator.greaterThan
          ? order > 0
          : order < 0;
    case WorkflowOperator.isEmpty:
    case WorkflowOperator.isNotEmpty:
      return false;
  }
}

bool _looselyEqual(
  Object? left,
  Object? right,
  String leftText,
  String rightText,
) {
  final leftNumber = workflowNumber(left);
  final rightNumber = workflowNumber(right);
  if (leftNumber != null &&
      rightNumber != null &&
      left is! bool &&
      right is! bool) {
    return leftNumber == rightNumber;
  }
  return leftText == rightText;
}

int? _compare(Object? left, Object? right) {
  final leftNumber = workflowNumber(left);
  final rightNumber = workflowNumber(right);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  final leftDate = workflowDate(left);
  final rightDate = workflowDate(right);
  if (leftDate != null && rightDate != null) {
    return leftDate.compareTo(rightDate);
  }
  return null;
}

/// A formatter step's operations.
enum WorkflowFormatOperation {
  trim,
  uppercase,
  lowercase,
  titleCase,
  replace,
  truncate,
  split,
  extractNumber,
  extractEmail,
  extractUrl,
  stripHtml,
  urlEncode,
  wordCount,
  defaultValue,
  formatDate,
  addTime,
  math,
  round,
  parseJson;

  static WorkflowFormatOperation parse(Object? value) =>
      WorkflowFormatOperation.values.firstWhere(
        (operation) => operation.name == value,
        orElse: () => WorkflowFormatOperation.trim,
      );
}

final RegExp _numberPattern = RegExp(r'-?\d[\d,]*(?:\.\d+)?|-?\.\d+');
final RegExp _emailPattern =
    RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final RegExp _urlPattern = RegExp(r'''https?://[^\s<>"')\]]+''');
final RegExp _tagPattern = RegExp('<[^>]*>');

/// Thrown when a formatter cannot do what it was asked.
class WorkflowFormatException implements Exception {
  const WorkflowFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs one formatter step against [context].
Object? runWorkflowFormatter(WorkflowStep step, WorkflowContext context) {
  final operation = WorkflowFormatOperation.parse(step.config['operation']);
  final input = renderWorkflowValue(step.text('input'), context);
  final text = workflowText(input);
  String option(String key) => renderWorkflowText(step.text(key), context);

  switch (operation) {
    case WorkflowFormatOperation.trim:
      return text.trim();
    case WorkflowFormatOperation.uppercase:
      return text.toUpperCase();
    case WorkflowFormatOperation.lowercase:
      return text.toLowerCase();
    case WorkflowFormatOperation.titleCase:
      return text.replaceAllMapped(
        RegExp("[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ']*"),
        (match) {
          final word = match.group(0)!;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        },
      );
    case WorkflowFormatOperation.replace:
      final find = option('find');
      return find.isEmpty ? text : text.replaceAll(find, option('replaceWith'));
    case WorkflowFormatOperation.truncate:
      final length = int.tryParse(option('length').trim()) ?? 100;
      if (length < 1 || text.characters.length <= length) {
        return text;
      }
      return '${text.characters.take(length)}…';
    case WorkflowFormatOperation.split:
      final separator = option('separator');
      final parts = (separator.isEmpty
              ? text.split(RegExp(r'\s*,\s*'))
              : text.split(separator))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final which = option('index').trim().toLowerCase();
      if (which.isEmpty || which == 'all') {
        return parts;
      }
      if (parts.isEmpty) {
        return '';
      }
      if (which == 'first') {
        return parts.first;
      }
      if (which == 'last') {
        return parts.last;
      }
      final index = int.tryParse(which);
      return index == null || index < 0 || index >= parts.length
          ? ''
          : parts[index];
    case WorkflowFormatOperation.extractNumber:
      final match = _numberPattern.firstMatch(text);
      return match == null
          ? null
          : num.tryParse(match.group(0)!.replaceAll(',', ''));
    case WorkflowFormatOperation.extractEmail:
      return _emailPattern.firstMatch(text)?.group(0) ?? '';
    case WorkflowFormatOperation.extractUrl:
      return _urlPattern.firstMatch(text)?.group(0) ?? '';
    case WorkflowFormatOperation.stripHtml:
      return _decodeEntities(text.replaceAll(_tagPattern, ' '))
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\s*\n\s*'), '\n')
          .trim();
    case WorkflowFormatOperation.urlEncode:
      return Uri.encodeQueryComponent(text);
    case WorkflowFormatOperation.wordCount:
      final words = text.trim();
      return words.isEmpty ? 0 : words.split(RegExp(r'\s+')).length;
    case WorkflowFormatOperation.defaultValue:
      return _isEmptyValue(input) ? option('fallback') : input;
    case WorkflowFormatOperation.formatDate:
      final date = workflowDate(input);
      if (date == null) {
        throw WorkflowFormatException('"$text" is not a date.');
      }
      final pattern = option('pattern').trim();
      try {
        return DateFormat(pattern.isEmpty ? 'yyyy-MM-dd' : pattern)
            .format(date);
      } on Object {
        throw WorkflowFormatException('"$pattern" is not a date pattern.');
      }
    case WorkflowFormatOperation.addTime:
      final date = workflowDate(input);
      if (date == null) {
        throw WorkflowFormatException('"$text" is not a date.');
      }
      final amount = int.tryParse(option('amount').trim()) ?? 0;
      final moved = switch (step.text('unit')) {
        'minutes' => date.add(Duration(minutes: amount)),
        'hours' => date.add(Duration(hours: amount)),
        'weeks' => DateTime(
            date.year,
            date.month,
            date.day + amount * 7,
            date.hour,
            date.minute,
            date.second,
          ),
        'months' => DateTime(
            date.year,
            date.month + amount,
            date.day,
            date.hour,
            date.minute,
            date.second,
          ),
        _ => DateTime(
            date.year,
            date.month,
            date.day + amount,
            date.hour,
            date.minute,
            date.second,
          ),
      };
      return moved.toIso8601String();
    case WorkflowFormatOperation.math:
      final left = workflowNumber(input);
      final right = workflowNumber(option('operand'));
      if (left == null || right == null) {
        throw const WorkflowFormatException('Both sides must be numbers.');
      }
      return switch (step.text('operator')) {
        '-' => left - right,
        '*' => left * right,
        '/' => right == 0
            ? throw const WorkflowFormatException('Cannot divide by zero.')
            : left / right,
        _ => left + right,
      };
    case WorkflowFormatOperation.round:
      final value = workflowNumber(input);
      if (value == null) {
        throw WorkflowFormatException('"$text" is not a number.');
      }
      final places =
          (int.tryParse(option('decimals').trim()) ?? 0).clamp(0, 10);
      return places == 0
          ? value.round()
          : num.parse(value.toStringAsFixed(places));
    case WorkflowFormatOperation.parseJson:
      if (input is Map || input is List) {
        return input;
      }
      try {
        return jsonDecode(text);
      } on FormatException {
        throw const WorkflowFormatException('The text is not valid JSON.');
      }
  }
}

String _decodeEntities(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
