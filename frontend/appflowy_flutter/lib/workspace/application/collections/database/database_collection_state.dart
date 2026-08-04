import 'package:flutter/foundation.dart';

/// What the workbench remembers between visits.
@immutable
class DatabaseCollectionState {
  const DatabaseCollectionState({
    this.activeTableId,
    this.showRail = true,
    this.showSchema = false,
    this.chartSpecs = const {},
  });

  static const empty = DatabaseCollectionState();

  /// The table that was last open.
  final String? activeTableId;

  /// Whether the list of tables is docked beside the stage.
  final bool showRail;

  /// Whether the stage shows the table's columns instead of its rows.
  final bool showSchema;

  /// How each table is charted, kept by view id.
  final Map<String, Map<String, dynamic>> chartSpecs;

  DatabaseCollectionState copyWith({
    String? activeTableId,
    bool? showRail,
    bool? showSchema,
    Map<String, Map<String, dynamic>>? chartSpecs,
    bool clearActiveTable = false,
  }) =>
      DatabaseCollectionState(
        activeTableId:
            clearActiveTable ? null : (activeTableId ?? this.activeTableId),
        showRail: showRail ?? this.showRail,
        showSchema: showSchema ?? this.showSchema,
        chartSpecs: chartSpecs ?? this.chartSpecs,
      );

  Map<String, Object?> toJson() => {
        if (activeTableId != null) 'active_table': activeTableId,
        'show_rail': showRail,
        'show_schema': showSchema,
        if (chartSpecs.isNotEmpty) 'chart_specs': chartSpecs,
      };

  static DatabaseCollectionState fromJson(Map<String, dynamic> json) {
    final active = json['active_table'];
    return DatabaseCollectionState(
      activeTableId: active is String && active.isNotEmpty ? active : null,
      showRail: json['show_rail'] != false,
      showSchema: json['show_schema'] == true,
      chartSpecs: _nested(json['chart_specs']),
    );
  }

  static Map<String, Map<String, dynamic>> _nested(Object? value) =>
      value is Map
          ? {
              for (final entry in value.entries)
                if (entry.key is String && entry.value is Map)
                  entry.key as String:
                      Map<String, dynamic>.from(entry.value as Map),
            }
          : const {};
}
