import 'package:flutter/foundation.dart';

/// Where a widget reads from.
///
/// Every one of these is OPTIONAL. A dashboard of buttons, notes, counters and
/// links has no data source at all and is a perfectly good dashboard — which
/// is the whole point of not building this on top of a database.
enum DashboardSourceKind {
  /// Nothing external; the widget's own settings are its content.
  none,

  /// A database view — grid, board, calendar or any of the readings of one.
  database,

  /// A collection: a book, an album, a repository, a bookmark library…
  collection,

  /// A single page.
  page,

  /// A folder of workspace files.
  folder,

  /// A file: a picture, a PDF, a video.
  file,

  /// The calendar layer, whatever it is fed by.
  calendar,

  /// Reminders and tasks.
  reminders,

  /// A web address.
  url,

  /// A service reached through a connected account.
  external;

  static DashboardSourceKind fromValue(Object? value) =>
      DashboardSourceKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => DashboardSourceKind.none,
      );

  /// Whether choosing this source means choosing a view in the workspace.
  bool get needsView => const {
        DashboardSourceKind.database,
        DashboardSourceKind.collection,
        DashboardSourceKind.page,
        DashboardSourceKind.folder,
        DashboardSourceKind.file,
      }.contains(this);
}

/// How a widget narrows what it reads.
@immutable
class DashboardFilter {
  const DashboardFilter({
    required this.field,
    required this.operator,
    this.value,
    this.variableKey = '',
  });

  factory DashboardFilter.fromJson(Map<String, Object?> json) =>
      DashboardFilter(
        field: json['field'] as String? ?? '',
        operator: json['op'] as String? ?? 'is',
        value: json['value'],
        variableKey: json['variable'] as String? ?? '',
      );

  final String field;

  /// `is` | `isNot` | `contains` | `before` | `after` | `between` | `isEmpty`.
  final String operator;
  final Object? value;

  /// When set, the value comes from dashboard state rather than from [value].
  final String variableKey;

  bool get isBound => variableKey.isNotEmpty;

  DashboardFilter copyWith({
    String? field,
    String? operator,
    Object? value,
    String? variableKey,
  }) =>
      DashboardFilter(
        field: field ?? this.field,
        operator: operator ?? this.operator,
        value: value ?? this.value,
        variableKey: variableKey ?? this.variableKey,
      );

  Map<String, Object?> toJson() => {
        'field': field,
        'op': operator,
        if (value != null) 'value': value,
        if (variableKey.isNotEmpty) 'variable': variableKey,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardFilter &&
      other.field == field &&
      other.operator == operator &&
      other.value == value &&
      other.variableKey == variableKey;

  @override
  int get hashCode => Object.hash(field, operator, value, variableKey);
}

/// What a widget reads, if anything.
@immutable
class DashboardDataSource {
  const DashboardDataSource({
    this.kind = DashboardSourceKind.none,
    this.viewId = '',
    this.name = '',
    this.url = '',
    this.field = '',
    this.groupField = '',
    this.filters = const [],
    this.sortField = '',
    this.sortDescending = false,
    this.limit = 0,
    this.refreshSeconds = 0,
    this.options = const {},
  });

  factory DashboardDataSource.fromJson(Map<String, Object?> json) =>
      DashboardDataSource(
        kind: DashboardSourceKind.fromValue(json['kind']),
        viewId: json['view'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        field: json['field'] as String? ?? '',
        groupField: json['group'] as String? ?? '',
        filters: [
          for (final entry in (json['filters'] as List? ?? const []))
            if (entry is Map)
              DashboardFilter.fromJson(Map<String, Object?>.from(entry)),
        ],
        sortField: json['sort'] as String? ?? '',
        sortDescending: json['desc'] == true,
        limit: (json['limit'] as num?)?.round() ?? 0,
        refreshSeconds: (json['refresh'] as num?)?.round() ?? 0,
        options: json['options'] is Map
            ? Map<String, Object?>.from(json['options']! as Map)
            : const {},
      );

  static const DashboardDataSource none = DashboardDataSource();

  final DashboardSourceKind kind;
  final String viewId;

  /// Remembered so a widget can name its source before the view is read.
  final String name;
  final String url;

  /// The column a metric, chart or progress bar measures.
  final String field;

  /// The column a chart or a board groups by.
  final String groupField;
  final List<DashboardFilter> filters;
  final String sortField;
  final bool sortDescending;

  /// 0 means "everything".
  final int limit;

  /// 0 means "only when something changes".
  final int refreshSeconds;
  final Map<String, Object?> options;

  bool get isBound =>
      kind != DashboardSourceKind.none &&
      (!kind.needsView || viewId.isNotEmpty);

  DashboardDataSource copyWith({
    DashboardSourceKind? kind,
    String? viewId,
    String? name,
    String? url,
    String? field,
    String? groupField,
    List<DashboardFilter>? filters,
    String? sortField,
    bool? sortDescending,
    int? limit,
    int? refreshSeconds,
    Map<String, Object?>? options,
  }) =>
      DashboardDataSource(
        kind: kind ?? this.kind,
        viewId: viewId ?? this.viewId,
        name: name ?? this.name,
        url: url ?? this.url,
        field: field ?? this.field,
        groupField: groupField ?? this.groupField,
        filters: filters ?? this.filters,
        sortField: sortField ?? this.sortField,
        sortDescending: sortDescending ?? this.sortDescending,
        limit: limit ?? this.limit,
        refreshSeconds: refreshSeconds ?? this.refreshSeconds,
        options: options ?? this.options,
      );

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (viewId.isNotEmpty) 'view': viewId,
        if (name.isNotEmpty) 'name': name,
        if (url.isNotEmpty) 'url': url,
        if (field.isNotEmpty) 'field': field,
        if (groupField.isNotEmpty) 'group': groupField,
        if (filters.isNotEmpty)
          'filters': [for (final filter in filters) filter.toJson()],
        if (sortField.isNotEmpty) 'sort': sortField,
        if (sortDescending) 'desc': true,
        if (limit > 0) 'limit': limit,
        if (refreshSeconds > 0) 'refresh': refreshSeconds,
        if (options.isNotEmpty) 'options': options,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardDataSource &&
      other.kind == kind &&
      other.viewId == viewId &&
      other.name == name &&
      other.url == url &&
      other.field == field &&
      other.groupField == groupField &&
      listEquals(other.filters, filters) &&
      other.sortField == sortField &&
      other.sortDescending == sortDescending &&
      other.limit == limit &&
      other.refreshSeconds == refreshSeconds &&
      mapEquals(other.options, options);

  @override
  int get hashCode => Object.hash(
        kind,
        viewId,
        name,
        url,
        field,
        groupField,
        Object.hashAll(filters),
        sortField,
        sortDescending,
        limit,
        refreshSeconds,
      );
}
