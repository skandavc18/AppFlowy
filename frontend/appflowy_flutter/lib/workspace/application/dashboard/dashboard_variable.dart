import 'package:flutter/foundation.dart';

/// A choice a dashboard offers — an option in a selector, a value a variable
/// can hold, a segment in a radio group.
///
/// It is declared here rather than reused from the editor's interactive blocks
/// because the model layer must not depend on `lib/plugins/`.
@immutable
class DashboardOption {
  const DashboardOption({
    required this.id,
    required this.label,
    this.accent = '',
  });

  factory DashboardOption.fromJson(Map<String, Object?> json) =>
      DashboardOption(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        accent: json['color'] as String? ?? '',
      );

  final String id;
  final String label;

  /// The name of a [DashboardAccent]; empty means "follow the dashboard".
  final String accent;

  DashboardOption copyWith({String? id, String? label, String? accent}) =>
      DashboardOption(
        id: id ?? this.id,
        label: label ?? this.label,
        accent: accent ?? this.accent,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        if (accent.isNotEmpty) 'color': accent,
      };

  static List<DashboardOption> listFromJson(Object? value) => value is List
      ? [
          for (final entry in value)
            if (entry is Map)
              DashboardOption.fromJson(Map<String, Object?>.from(entry)),
        ]
      : const [];

  @override
  bool operator ==(Object other) =>
      other is DashboardOption &&
      other.id == id &&
      other.label == label &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(id, label, accent);
}

/// What kind of value a dashboard variable holds.
enum DashboardVariableKind {
  /// A single choice out of [DashboardVariable.options].
  option,

  /// Several choices at once; the value is a list of option ids.
  multiOption,

  /// Free text — a search box, a note.
  text,

  /// A number.
  number,

  /// A named period: today, this week, this month, this quarter, this year.
  period,

  /// A single moment.
  date,

  /// On or off.
  toggle,

  /// A page in the workspace; the value is a view id.
  page;

  static DashboardVariableKind fromValue(Object? value) =>
      DashboardVariableKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => DashboardVariableKind.option,
      );
}

/// The named periods a `period` variable can hold.
///
/// They are stored as ids rather than as dates so that a dashboard reopened
/// tomorrow reads "this week" as this week, not as last week.
enum DashboardPeriod {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisQuarter,
  thisYear,
  allTime;

  static DashboardPeriod fromValue(Object? value) =>
      DashboardPeriod.values.firstWhere(
        (period) => period.name == value,
        orElse: () => DashboardPeriod.thisWeek,
      );

  /// The half-open range this period covers, measured from [now].
  ///
  /// A null start or end means unbounded, which is what "all time" is.
  ({DateTime? start, DateTime? end}) rangeFrom(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    switch (this) {
      case DashboardPeriod.today:
        return (start: day, end: day.add(const Duration(days: 1)));
      case DashboardPeriod.yesterday:
        final start = day.subtract(const Duration(days: 1));
        return (start: start, end: day);
      case DashboardPeriod.thisWeek:
        final start = day.subtract(Duration(days: day.weekday - 1));
        return (start: start, end: start.add(const Duration(days: 7)));
      case DashboardPeriod.lastWeek:
        final thisWeek = day.subtract(Duration(days: day.weekday - 1));
        final start = thisWeek.subtract(const Duration(days: 7));
        return (start: start, end: thisWeek);
      case DashboardPeriod.thisMonth:
        final start = DateTime(now.year, now.month);
        return (start: start, end: DateTime(now.year, now.month + 1));
      case DashboardPeriod.lastMonth:
        final start = DateTime(now.year, now.month - 1);
        return (start: start, end: DateTime(now.year, now.month));
      case DashboardPeriod.thisQuarter:
        final firstMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return (
          start: DateTime(now.year, firstMonth),
          end: DateTime(now.year, firstMonth + 3),
        );
      case DashboardPeriod.thisYear:
        return (start: DateTime(now.year), end: DateTime(now.year + 1));
      case DashboardPeriod.allTime:
        return (start: null, end: null);
    }
  }
}

/// One piece of dashboard-level state.
///
/// This is what makes a dashboard behave like a small application rather than
/// a page: a selector writes a variable, and every widget bound to that
/// variable redraws.
@immutable
class DashboardVariable {
  const DashboardVariable({
    required this.key,
    required this.label,
    this.kind = DashboardVariableKind.option,
    this.options = const [],
    this.defaultValue,
    this.includeAll = true,
    this.allLabel = '',
  });

  factory DashboardVariable.fromJson(Map<String, Object?> json) =>
      DashboardVariable(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        kind: DashboardVariableKind.fromValue(json['kind']),
        options: DashboardOption.listFromJson(json['options']),
        defaultValue: json['default'],
        includeAll: json['all'] != false,
        allLabel: json['all_label'] as String? ?? '',
      );

  /// The name a widget binds to. Unique within one dashboard.
  final String key;
  final String label;
  final DashboardVariableKind kind;
  final List<DashboardOption> options;
  final Object? defaultValue;

  /// Whether an option variable offers an "everything" choice.
  final bool includeAll;
  final String allLabel;

  /// The value the dashboard starts with when nobody has chosen one.
  Object? get initialValue {
    if (defaultValue != null) {
      return defaultValue;
    }
    switch (kind) {
      case DashboardVariableKind.option:
        return includeAll || options.isEmpty ? null : options.first.id;
      case DashboardVariableKind.multiOption:
        return const <String>[];
      case DashboardVariableKind.text:
        return '';
      case DashboardVariableKind.number:
        return 0;
      case DashboardVariableKind.period:
        return DashboardPeriod.thisWeek.name;
      case DashboardVariableKind.toggle:
        return false;
      case DashboardVariableKind.date:
      case DashboardVariableKind.page:
        return null;
    }
  }

  DashboardVariable copyWith({
    String? key,
    String? label,
    DashboardVariableKind? kind,
    List<DashboardOption>? options,
    Object? defaultValue,
    bool clearDefault = false,
    bool? includeAll,
    String? allLabel,
  }) =>
      DashboardVariable(
        key: key ?? this.key,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        options: options ?? this.options,
        defaultValue: clearDefault ? null : (defaultValue ?? this.defaultValue),
        includeAll: includeAll ?? this.includeAll,
        allLabel: allLabel ?? this.allLabel,
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'kind': kind.name,
        if (options.isNotEmpty)
          'options': [for (final option in options) option.toJson()],
        if (defaultValue != null) 'default': defaultValue,
        if (!includeAll) 'all': false,
        if (allLabel.isNotEmpty) 'all_label': allLabel,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardVariable &&
      other.key == key &&
      other.label == label &&
      other.kind == kind &&
      listEquals(other.options, options) &&
      other.defaultValue == defaultValue &&
      other.includeAll == includeAll &&
      other.allLabel == allLabel;

  @override
  int get hashCode => Object.hash(
        key,
        label,
        kind,
        Object.hashAll(options),
        defaultValue,
        includeAll,
        allLabel,
      );
}

/// The values the dashboard's variables currently hold.
///
/// Immutable, so a widget can compare the state it was built with against the
/// state it is being rebuilt with and only do the work that changed.
@immutable
class DashboardStateValues {
  const DashboardStateValues([this._values = const {}]);

  factory DashboardStateValues.initial(List<DashboardVariable> variables) =>
      DashboardStateValues({
        for (final variable in variables)
          if (variable.initialValue != null)
            variable.key: variable.initialValue!,
      });

  final Map<String, Object?> _values;

  Map<String, Object?> get values => Map.unmodifiable(_values);

  bool get isEmpty => _values.isEmpty;

  Object? operator [](String key) => _values[key];

  String text(String key, {String fallback = ''}) {
    final value = _values[key];
    return value is String ? value : fallback;
  }

  double number(String key, {double fallback = 0}) {
    final value = _values[key];
    if (value is num) {
      return value.toDouble();
    }
    return value is String ? (double.tryParse(value) ?? fallback) : fallback;
  }

  bool flag(String key, {bool fallback = false}) {
    final value = _values[key];
    return value is bool ? value : fallback;
  }

  List<String> selection(String key) {
    final value = _values[key];
    if (value is List) {
      return [
        for (final entry in value)
          if (entry is String) entry,
      ];
    }
    return value is String && value.isNotEmpty ? [value] : const [];
  }

  DateTime? date(String key) {
    final value = _values[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  DashboardStateValues withValue(String key, Object? value) {
    final next = Map<String, Object?>.from(_values);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return DashboardStateValues(next);
  }

  DashboardStateValues merge(Map<String, Object?> values) =>
      DashboardStateValues({..._values, ...values});

  @override
  bool operator ==(Object other) =>
      other is DashboardStateValues && mapEquals(other._values, _values);

  @override
  int get hashCode => Object.hashAll([
        for (final entry in _values.entries)
          Object.hash(entry.key, entry.value),
      ]);
}
