import 'package:flutter/foundation.dart';

/// What pressing something on a dashboard does.
///
/// Actions are DATA, not code: a button stores one of these and the canvas
/// runs it. That is what lets a template ship a working button, and what lets
/// a new action be added without every widget learning about it.
enum DashboardActionKind {
  none,

  /// Open a page, database, collection or another dashboard in the workspace.
  openPage,

  /// Open a web address in the browser.
  openUrl,

  /// Create a page under a chosen parent and open it.
  createPage,

  /// Add a row to a database.
  createRow,

  /// Write a value into dashboard state — this is how one control drives
  /// another without either knowing about the other.
  setVariable,

  /// Flip a boolean variable.
  toggleVariable,

  /// Show or hide a section.
  toggleSection,

  /// Put text on the clipboard.
  copyText,

  /// Ask for a reminder.
  setReminder,

  /// Re-read every widget that has a source.
  refresh,

  /// Open a widget on its own, over the dashboard.
  openModal;

  static DashboardActionKind fromValue(Object? value) =>
      DashboardActionKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => DashboardActionKind.none,
      );

  /// Whether this action's target is a view in the workspace.
  bool get needsView => const {
        DashboardActionKind.openPage,
        DashboardActionKind.createPage,
        DashboardActionKind.createRow,
      }.contains(this);
}

/// One thing a control does when it is used.
@immutable
class DashboardAction {
  const DashboardAction({
    this.kind = DashboardActionKind.none,
    this.target = '',
    this.targetName = '',
    this.value,
    this.variableKey = '',
    this.label = '',
  });

  factory DashboardAction.fromJson(Map<String, Object?> json) =>
      DashboardAction(
        kind: DashboardActionKind.fromValue(json['kind']),
        target: json['target'] as String? ?? '',
        targetName: json['target_name'] as String? ?? '',
        value: json['value'],
        variableKey: json['variable'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );

  static const DashboardAction none = DashboardAction();

  final DashboardActionKind kind;

  /// A view id, a url or a widget id, depending on [kind].
  final String target;

  /// Remembered so a button can name where it goes without a round trip.
  final String targetName;
  final Object? value;
  final String variableKey;
  final String label;

  bool get isSet => kind != DashboardActionKind.none;

  DashboardAction copyWith({
    DashboardActionKind? kind,
    String? target,
    String? targetName,
    Object? value,
    bool clearValue = false,
    String? variableKey,
    String? label,
  }) =>
      DashboardAction(
        kind: kind ?? this.kind,
        target: target ?? this.target,
        targetName: targetName ?? this.targetName,
        value: clearValue ? null : (value ?? this.value),
        variableKey: variableKey ?? this.variableKey,
        label: label ?? this.label,
      );

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (target.isNotEmpty) 'target': target,
        if (targetName.isNotEmpty) 'target_name': targetName,
        if (value != null) 'value': value,
        if (variableKey.isNotEmpty) 'variable': variableKey,
        if (label.isNotEmpty) 'label': label,
      };

  static List<DashboardAction> listFromJson(Object? value) => value is List
      ? [
          for (final entry in value)
            if (entry is Map)
              DashboardAction.fromJson(Map<String, Object?>.from(entry)),
        ]
      : const [];

  @override
  bool operator ==(Object other) =>
      other is DashboardAction &&
      other.kind == kind &&
      other.target == target &&
      other.targetName == targetName &&
      other.value == value &&
      other.variableKey == variableKey &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(kind, target, targetName, value, variableKey, label);
}
