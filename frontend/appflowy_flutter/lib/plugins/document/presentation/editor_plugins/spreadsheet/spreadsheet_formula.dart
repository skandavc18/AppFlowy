/// A lightweight formula engine: tokenizer, recursive-descent parser and an
/// evaluator with cycle detection, sized for note-taking arithmetic rather
/// than a full Excel implementation.
library;

import 'dart:math' as math;

import 'spreadsheet_model.dart';

/// The result of evaluating a cell.
sealed class SheetValue {
  const SheetValue();

  static const blank = BlankValue._();

  bool get isBlank => this is BlankValue;
  bool get isError => this is ErrorValue;

  /// The number this value coerces to, or null when it cannot.
  double? get asNumber => switch (this) {
        NumberValue(:final value) => value,
        BoolValue(:final value) => value ? 1 : 0,
        BlankValue() => 0,
        TextValue(:final value) => parseCellNumber(value),
        ErrorValue() => null,
      };

  String get asText => switch (this) {
        NumberValue(:final value) => formatPlainNumber(value),
        TextValue(:final value) => value,
        BoolValue(:final value) => value ? 'TRUE' : 'FALSE',
        BlankValue() => '',
        ErrorValue(:final code) => code,
      };
}

class NumberValue extends SheetValue {
  const NumberValue(this.value);
  final double value;

  @override
  bool operator ==(Object other) =>
      other is NumberValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NumberValue($value)';
}

class TextValue extends SheetValue {
  const TextValue(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is TextValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TextValue($value)';
}

class BoolValue extends SheetValue {
  const BoolValue(this.value);
  final bool value;

  @override
  bool operator ==(Object other) => other is BoolValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BoolValue($value)';
}

class BlankValue extends SheetValue {
  const BlankValue._();

  @override
  bool operator ==(Object other) => other is BlankValue;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'BlankValue()';
}

class ErrorValue extends SheetValue {
  const ErrorValue(this.code);

  static const divideByZero = ErrorValue('#DIV/0!');
  static const name = ErrorValue('#NAME?');
  static const value = ErrorValue('#VALUE!');
  static const reference = ErrorValue('#REF!');
  static const cycle = ErrorValue('#CYCLE!');
  static const parse = ErrorValue('#ERROR!');

  final String code;

  @override
  bool operator ==(Object other) => other is ErrorValue && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'ErrorValue($code)';
}

/// Parses `1,234.50`, `$1,200`, `45%`, `(12)` and plain numbers.
double? parseCellNumber(String input) {
  var text = input.trim();
  if (text.isEmpty) {
    return null;
  }
  var negative = false;
  if (text.startsWith('(') && text.endsWith(')')) {
    negative = true;
    text = text.substring(1, text.length - 1).trim();
  }
  var percent = false;
  if (text.endsWith('%')) {
    percent = true;
    text = text.substring(0, text.length - 1).trim();
  }
  // Strip a leading or trailing currency symbol.
  text = text.replaceAll(RegExp(r'^[\$€£¥₹]\s*'), '');
  text = text.replaceAll(RegExp(r'\s*[\$€£¥₹]$'), '');
  text = text.replaceAll(',', '');
  if (text.isEmpty) {
    return null;
  }
  final parsed = double.tryParse(text);
  if (parsed == null) {
    return null;
  }
  var result = parsed;
  if (percent) {
    result /= 100;
  }
  if (negative) {
    result = -result;
  }
  return result;
}

/// Renders a double without a trailing `.0` and without scientific notation
/// for the ranges a note-taking sheet actually reaches.
String formatPlainNumber(double value) {
  if (value.isNaN) {
    return '#VALUE!';
  }
  if (value.isInfinite) {
    return value.isNegative ? '-∞' : '∞';
  }
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(10);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

enum _TokenType {
  number,
  string,
  identifier,
  reference,
  operator,
  openParen,
  closeParen,
  comma,
  colon,
  end,
}

class _Token {
  const _Token(this.type, this.text, [this.number]);
  final _TokenType type;
  final String text;
  final double? number;
}

class _FormulaLexer {
  _FormulaLexer(this.source);

  final String source;
  int _index = 0;

  static const _operatorStarts = {
    '+',
    '-',
    '*',
    '/',
    '^',
    '&',
    '=',
    '<',
    '>',
    '%',
  };

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (true) {
      final token = _next();
      tokens.add(token);
      if (token.type == _TokenType.end) {
        return tokens;
      }
    }
  }

  _Token _next() {
    while (_index < source.length && _isSpace(source[_index])) {
      _index++;
    }
    if (_index >= source.length) {
      return const _Token(_TokenType.end, '');
    }
    final char = source[_index];

    if (char == '(') {
      _index++;
      return const _Token(_TokenType.openParen, '(');
    }
    if (char == ')') {
      _index++;
      return const _Token(_TokenType.closeParen, ')');
    }
    if (char == ',' || char == ';') {
      _index++;
      return const _Token(_TokenType.comma, ',');
    }
    if (char == ':') {
      _index++;
      return const _Token(_TokenType.colon, ':');
    }
    if (char == '"') {
      return _readString();
    }
    if (_isDigit(char) ||
        (char == '.' &&
            _index + 1 < source.length &&
            _isDigit(source[_index + 1]))) {
      return _readNumber();
    }
    if (_isLetter(char) || char == r'$' || char == '_') {
      return _readWord();
    }
    if (_operatorStarts.contains(char)) {
      return _readOperator();
    }
    throw const FormatException('unexpected character');
  }

  _Token _readString() {
    _index++; // opening quote
    final buffer = StringBuffer();
    while (_index < source.length) {
      final char = source[_index];
      if (char == '"') {
        if (_index + 1 < source.length && source[_index + 1] == '"') {
          buffer.write('"');
          _index += 2;
          continue;
        }
        _index++;
        return _Token(_TokenType.string, buffer.toString());
      }
      buffer.write(char);
      _index++;
    }
    throw const FormatException('unterminated string');
  }

  _Token _readNumber() {
    final start = _index;
    var seenDot = false;
    while (_index < source.length) {
      final char = source[_index];
      if (_isDigit(char)) {
        _index++;
      } else if (char == '.' && !seenDot) {
        seenDot = true;
        _index++;
      } else {
        break;
      }
    }
    final text = source.substring(start, _index);
    return _Token(_TokenType.number, text, double.parse(text));
  }

  _Token _readWord() {
    final start = _index;
    while (_index < source.length) {
      final char = source[_index];
      if (_isLetter(char) ||
          _isDigit(char) ||
          char == r'$' ||
          char == '_' ||
          char == '.') {
        _index++;
      } else {
        break;
      }
    }
    final text = source.substring(start, _index);
    if (CellRef.parseA1(text) != null) {
      return _Token(_TokenType.reference, text);
    }
    return _Token(_TokenType.identifier, text);
  }

  _Token _readOperator() {
    final char = source[_index];
    if (_index + 1 < source.length) {
      final pair = source.substring(_index, _index + 2);
      if (pair == '<=' || pair == '>=' || pair == '<>') {
        _index += 2;
        return _Token(_TokenType.operator, pair);
      }
    }
    _index++;
    return _Token(_TokenType.operator, char);
  }

  static bool _isSpace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

sealed class FormulaNode {
  const FormulaNode();
}

class LiteralNode extends FormulaNode {
  const LiteralNode(this.value);
  final SheetValue value;
}

class ReferenceNode extends FormulaNode {
  const ReferenceNode(this.ref);
  final CellRef ref;
}

class RangeNode extends FormulaNode {
  const RangeNode(this.range);
  final CellRange range;
}

class UnaryNode extends FormulaNode {
  const UnaryNode(this.operatorText, this.operand);
  final String operatorText;
  final FormulaNode operand;
}

class BinaryNode extends FormulaNode {
  const BinaryNode(this.operatorText, this.left, this.right);
  final String operatorText;
  final FormulaNode left;
  final FormulaNode right;
}

class CallNode extends FormulaNode {
  const CallNode(this.name, this.arguments);
  final String name;
  final List<FormulaNode> arguments;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class FormulaParser {
  FormulaParser(String source) : _tokens = _FormulaLexer(source).tokenize();

  final List<_Token> _tokens;
  int _index = 0;

  /// Parses the body of a formula (without the leading `=`).
  ///
  /// Returns null when the text is not valid.
  static FormulaNode? tryParse(String source) {
    try {
      final parser = FormulaParser(source);
      final node = parser._parseExpression();
      if (parser._peek.type != _TokenType.end) {
        return null;
      }
      return node;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  _Token get _peek => _tokens[_index];

  _Token _advance() => _tokens[_index++];

  bool _match(_TokenType type, [String? text]) {
    final token = _peek;
    if (token.type != type) {
      return false;
    }
    if (text != null && token.text.toUpperCase() != text) {
      return false;
    }
    _index++;
    return true;
  }

  void _expect(_TokenType type) {
    if (_peek.type != type) {
      throw const FormatException('unexpected token');
    }
    _index++;
  }

  FormulaNode _parseExpression() => _parseComparison();

  FormulaNode _parseComparison() {
    var left = _parseConcat();
    while (_peek.type == _TokenType.operator &&
        const {'=', '<>', '<', '>', '<=', '>='}.contains(_peek.text)) {
      final operatorText = _advance().text;
      final right = _parseConcat();
      left = BinaryNode(operatorText, left, right);
    }
    return left;
  }

  FormulaNode _parseConcat() {
    var left = _parseAdditive();
    while (_peek.type == _TokenType.operator && _peek.text == '&') {
      _advance();
      final right = _parseAdditive();
      left = BinaryNode('&', left, right);
    }
    return left;
  }

  FormulaNode _parseAdditive() {
    var left = _parseMultiplicative();
    while (_peek.type == _TokenType.operator &&
        (_peek.text == '+' || _peek.text == '-')) {
      final operatorText = _advance().text;
      final right = _parseMultiplicative();
      left = BinaryNode(operatorText, left, right);
    }
    return left;
  }

  FormulaNode _parseMultiplicative() {
    var left = _parseUnary();
    while (_peek.type == _TokenType.operator &&
        (_peek.text == '*' || _peek.text == '/')) {
      final operatorText = _advance().text;
      final right = _parseUnary();
      left = BinaryNode(operatorText, left, right);
    }
    return left;
  }

  FormulaNode _parseUnary() {
    if (_peek.type == _TokenType.operator &&
        (_peek.text == '-' || _peek.text == '+')) {
      final operatorText = _advance().text;
      return UnaryNode(operatorText, _parseUnary());
    }
    return _parsePower();
  }

  FormulaNode _parsePower() {
    final base = _parsePostfix();
    if (_peek.type == _TokenType.operator && _peek.text == '^') {
      _advance();
      // Right associative.
      return BinaryNode('^', base, _parseUnary());
    }
    return base;
  }

  FormulaNode _parsePostfix() {
    var node = _parsePrimary();
    while (_peek.type == _TokenType.operator && _peek.text == '%') {
      _advance();
      node = UnaryNode('%', node);
    }
    return node;
  }

  FormulaNode _parsePrimary() {
    final token = _peek;
    switch (token.type) {
      case _TokenType.number:
        _advance();
        return LiteralNode(NumberValue(token.number!));
      case _TokenType.string:
        _advance();
        return LiteralNode(TextValue(token.text));
      case _TokenType.openParen:
        _advance();
        final inner = _parseExpression();
        _expect(_TokenType.closeParen);
        return inner;
      case _TokenType.reference:
        _advance();
        final start = CellRef.parseA1(token.text)!;
        if (_peek.type == _TokenType.colon) {
          _advance();
          final endToken = _advance();
          final end = CellRef.parseA1(endToken.text);
          if (end == null) {
            throw const FormatException('bad range');
          }
          return RangeNode(CellRange(start, end));
        }
        return ReferenceNode(start);
      case _TokenType.identifier:
        _advance();
        final upper = token.text.toUpperCase();
        if (upper == 'TRUE') {
          return const LiteralNode(BoolValue(true));
        }
        if (upper == 'FALSE') {
          return const LiteralNode(BoolValue(false));
        }
        if (_match(_TokenType.openParen)) {
          final arguments = <FormulaNode>[];
          if (_peek.type != _TokenType.closeParen) {
            arguments.add(_parseExpression());
            while (_match(_TokenType.comma)) {
              arguments.add(_parseExpression());
            }
          }
          _expect(_TokenType.closeParen);
          return CallNode(upper, arguments);
        }
        throw const FormatException('unknown identifier');
      case _TokenType.operator:
      case _TokenType.comma:
      case _TokenType.colon:
      case _TokenType.closeParen:
      case _TokenType.end:
        throw const FormatException('unexpected token');
    }
  }
}

// ---------------------------------------------------------------------------
// Evaluator
// ---------------------------------------------------------------------------

/// Evaluates a sheet, caching results until [invalidate] is called.
class SpreadsheetEvaluator {
  SpreadsheetEvaluator(this.data);

  final SpreadsheetData data;
  final Map<CellRef, SheetValue> _cache = {};
  final Set<CellRef> _visiting = {};

  void invalidate() {
    _cache.clear();
    _visiting.clear();
  }

  /// The evaluated value of a cell, following formulas.
  SheetValue valueAt(CellRef ref) {
    final cached = _cache[ref];
    if (cached != null) {
      return cached;
    }
    if (ref.row < 0 ||
        ref.column < 0 ||
        ref.row >= data.rowCount ||
        ref.column >= data.columnCount) {
      return ErrorValue.reference;
    }
    if (!_visiting.add(ref)) {
      return ErrorValue.cycle;
    }
    try {
      final value = _evaluateCell(ref);
      _cache[ref] = value;
      return value;
    } finally {
      _visiting.remove(ref);
    }
  }

  SheetValue _evaluateCell(CellRef ref) {
    final cell = data.cellAt(ref);
    final raw = cell.raw;
    if (raw.isEmpty) {
      return SheetValue.blank;
    }
    if (cell.isFormula) {
      final node = FormulaParser.tryParse(raw.substring(1));
      if (node == null) {
        return ErrorValue.parse;
      }
      return evaluateNode(node);
    }
    if (cell.style.format == CellNumberFormat.text) {
      return TextValue(raw);
    }
    final number = parseCellNumber(raw);
    if (number != null) {
      return NumberValue(number);
    }
    final upper = raw.trim().toUpperCase();
    if (upper == 'TRUE') {
      return const BoolValue(true);
    }
    if (upper == 'FALSE') {
      return const BoolValue(false);
    }
    return TextValue(raw);
  }

  SheetValue evaluateNode(FormulaNode node) {
    switch (node) {
      case LiteralNode(:final value):
        return value;
      case ReferenceNode(:final ref):
        return valueAt(ref);
      case RangeNode():
        // A bare range outside a function collapses to an error.
        return ErrorValue.value;
      case UnaryNode(:final operatorText, :final operand):
        return _unary(operatorText, evaluateNode(operand));
      case BinaryNode(:final operatorText, :final left, :final right):
        return _binary(operatorText, evaluateNode(left), evaluateNode(right));
      case CallNode(:final name, :final arguments):
        return _call(name, arguments);
    }
  }

  SheetValue _unary(String operatorText, SheetValue operand) {
    if (operand is ErrorValue) {
      return operand;
    }
    final number = operand.asNumber;
    if (number == null) {
      return ErrorValue.value;
    }
    return switch (operatorText) {
      '-' => NumberValue(-number),
      '+' => NumberValue(number),
      '%' => NumberValue(number / 100),
      _ => ErrorValue.value,
    };
  }

  SheetValue _binary(String operatorText, SheetValue left, SheetValue right) {
    if (left is ErrorValue) {
      return left;
    }
    if (right is ErrorValue) {
      return right;
    }
    if (operatorText == '&') {
      return TextValue('${left.asText}${right.asText}');
    }
    if (const {'=', '<>', '<', '>', '<=', '>='}.contains(operatorText)) {
      return _compare(operatorText, left, right);
    }
    final a = left.asNumber;
    final b = right.asNumber;
    if (a == null || b == null) {
      return ErrorValue.value;
    }
    switch (operatorText) {
      case '+':
        return NumberValue(a + b);
      case '-':
        return NumberValue(a - b);
      case '*':
        return NumberValue(a * b);
      case '/':
        if (b == 0) {
          return ErrorValue.divideByZero;
        }
        return NumberValue(a / b);
      case '^':
        return NumberValue(math.pow(a, b).toDouble());
      default:
        return ErrorValue.value;
    }
  }

  SheetValue _compare(String operatorText, SheetValue left, SheetValue right) {
    final a = left.asNumber;
    final b = right.asNumber;
    int comparison;
    if (a != null && b != null && left is! TextValue && right is! TextValue) {
      comparison = a.compareTo(b);
    } else if (a != null && b != null) {
      comparison = a.compareTo(b);
    } else {
      comparison =
          left.asText.toLowerCase().compareTo(right.asText.toLowerCase());
    }
    return BoolValue(
      switch (operatorText) {
        '=' => comparison == 0,
        '<>' => comparison != 0,
        '<' => comparison < 0,
        '>' => comparison > 0,
        '<=' => comparison <= 0,
        '>=' => comparison >= 0,
        _ => false,
      },
    );
  }

  /// Flattens arguments, expanding ranges into their cell values.
  List<SheetValue> _flatten(List<FormulaNode> arguments) {
    final values = <SheetValue>[];
    for (final argument in arguments) {
      if (argument is RangeNode) {
        for (final ref in argument.range.cells) {
          values.add(valueAt(ref));
        }
      } else {
        values.add(evaluateNode(argument));
      }
    }
    return values;
  }

  List<double> _numbers(List<SheetValue> values) {
    final numbers = <double>[];
    for (final value in values) {
      if (value.isBlank) {
        continue;
      }
      if (value is TextValue && parseCellNumber(value.value) == null) {
        continue;
      }
      final number = value.asNumber;
      if (number != null) {
        numbers.add(number);
      }
    }
    return numbers;
  }

  SheetValue _call(String name, List<FormulaNode> arguments) {
    // IF short-circuits, so it must not evaluate both branches eagerly.
    if (name == 'IF') {
      if (arguments.length < 2 || arguments.length > 3) {
        return ErrorValue.value;
      }
      final condition = evaluateNode(arguments.first);
      if (condition is ErrorValue) {
        return condition;
      }
      final truthy = switch (condition) {
        BoolValue(:final value) => value,
        NumberValue(:final value) => value != 0,
        BlankValue() => false,
        TextValue(:final value) => value.toUpperCase() == 'TRUE',
        ErrorValue() => false,
      };
      if (truthy) {
        return evaluateNode(arguments[1]);
      }
      return arguments.length == 3
          ? evaluateNode(arguments[2])
          : const BoolValue(false);
    }

    final values = _flatten(arguments);
    for (final value in values) {
      if (value is ErrorValue) {
        return value;
      }
    }

    switch (name) {
      case 'SUM':
        return NumberValue(_numbers(values).fold(0.0, (a, b) => a + b));
      case 'PRODUCT':
        final numbers = _numbers(values);
        if (numbers.isEmpty) {
          return const NumberValue(0);
        }
        return NumberValue(numbers.fold(1.0, (a, b) => a * b));
      case 'AVERAGE':
        final numbers = _numbers(values);
        if (numbers.isEmpty) {
          return ErrorValue.divideByZero;
        }
        return NumberValue(
          numbers.fold(0.0, (a, b) => a + b) / numbers.length,
        );
      case 'COUNT':
        return NumberValue(_numbers(values).length.toDouble());
      case 'COUNTA':
        return NumberValue(
          values.where((value) => !value.isBlank).length.toDouble(),
        );
      case 'MIN':
        final numbers = _numbers(values);
        if (numbers.isEmpty) {
          return const NumberValue(0);
        }
        return NumberValue(numbers.reduce(math.min));
      case 'MAX':
        final numbers = _numbers(values);
        if (numbers.isEmpty) {
          return const NumberValue(0);
        }
        return NumberValue(numbers.reduce(math.max));
      case 'MEDIAN':
        final numbers = _numbers(values)..sort();
        if (numbers.isEmpty) {
          return ErrorValue.divideByZero;
        }
        final middle = numbers.length ~/ 2;
        return NumberValue(
          numbers.length.isOdd
              ? numbers[middle]
              : (numbers[middle - 1] + numbers[middle]) / 2,
        );
      case 'ROUND':
      case 'ROUNDUP':
      case 'ROUNDDOWN':
        if (values.isEmpty) {
          return ErrorValue.value;
        }
        final input = values.first.asNumber;
        if (input == null) {
          return ErrorValue.value;
        }
        final digits =
            values.length > 1 ? (values[1].asNumber ?? 0).toInt() : 0;
        final factor = math.pow(10, digits).toDouble();
        final scaled = input * factor;
        final rounded = switch (name) {
          'ROUNDUP' =>
            scaled.abs().ceilToDouble() * (scaled.isNegative ? -1 : 1),
          'ROUNDDOWN' =>
            scaled.abs().floorToDouble() * (scaled.isNegative ? -1 : 1),
          _ => scaled.roundToDouble(),
        };
        return NumberValue(rounded / factor);
      case 'ABS':
        final input = values.isEmpty ? null : values.first.asNumber;
        return input == null ? ErrorValue.value : NumberValue(input.abs());
      case 'SQRT':
        final input = values.isEmpty ? null : values.first.asNumber;
        if (input == null) {
          return ErrorValue.value;
        }
        if (input < 0) {
          return ErrorValue.value;
        }
        return NumberValue(math.sqrt(input));
      case 'POWER':
        if (values.length < 2) {
          return ErrorValue.value;
        }
        final base = values[0].asNumber;
        final exponent = values[1].asNumber;
        if (base == null || exponent == null) {
          return ErrorValue.value;
        }
        return NumberValue(math.pow(base, exponent).toDouble());
      case 'MOD':
        if (values.length < 2) {
          return ErrorValue.value;
        }
        final a = values[0].asNumber;
        final b = values[1].asNumber;
        if (a == null || b == null) {
          return ErrorValue.value;
        }
        if (b == 0) {
          return ErrorValue.divideByZero;
        }
        return NumberValue(a % b);
      case 'INT':
        final input = values.isEmpty ? null : values.first.asNumber;
        return input == null
            ? ErrorValue.value
            : NumberValue(input.floorToDouble());
      case 'AND':
        return BoolValue(values.every(_truthy));
      case 'OR':
        return BoolValue(values.any(_truthy));
      case 'NOT':
        if (values.isEmpty) {
          return ErrorValue.value;
        }
        return BoolValue(!_truthy(values.first));
      case 'LEN':
        return NumberValue(
          values.isEmpty ? 0 : values.first.asText.length.toDouble(),
        );
      case 'UPPER':
        return TextValue(
          values.isEmpty ? '' : values.first.asText.toUpperCase(),
        );
      case 'LOWER':
        return TextValue(
          values.isEmpty ? '' : values.first.asText.toLowerCase(),
        );
      case 'TRIM':
        return TextValue(values.isEmpty ? '' : values.first.asText.trim());
      case 'CONCAT':
      case 'CONCATENATE':
        return TextValue(values.map((value) => value.asText).join());
      default:
        return ErrorValue.name;
    }
  }

  static bool _truthy(SheetValue value) => switch (value) {
        BoolValue(:final value) => value,
        NumberValue(:final value) => value != 0,
        TextValue(:final value) => value.toUpperCase() == 'TRUE',
        BlankValue() => false,
        ErrorValue() => false,
      };
}

/// The functions offered by autocomplete, in the order they are shown.
const List<String> supportedFormulaNames = [
  'SUM',
  'AVERAGE',
  'COUNT',
  'COUNTA',
  'MIN',
  'MAX',
  'IF',
  'ROUND',
  'ABS',
  'MEDIAN',
  'PRODUCT',
  'ROUNDUP',
  'ROUNDDOWN',
  'SQRT',
  'POWER',
  'MOD',
  'INT',
  'AND',
  'OR',
  'NOT',
  'LEN',
  'UPPER',
  'LOWER',
  'TRIM',
  'CONCAT',
];
