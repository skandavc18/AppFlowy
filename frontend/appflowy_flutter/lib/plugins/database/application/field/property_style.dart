import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How a column is presented, on top of the type the backend stores it as.
///
/// A new [FieldType] would fork the stored data format, which lives in a
/// pinned crate. So a richer column is an ordinary column — text, a link, an
/// attachment — wearing a note that says how to draw it and how to edit it.
/// Everything that already reads that type (sorting, filtering, CSV export,
/// the board, the calendar) keeps working untouched.
enum PropertyStyleKind {
  /// No note: the column is drawn the way its own type is drawn.
  plain,

  /// A number against a maximum, drawn as a track.
  progress,

  /// A number with a minus and a plus beside it.
  counter,

  /// A compact button that does something with the row.
  button,

  /// A moment, with a bell and the ability to snooze or complete it.
  reminder,

  /// A link drawn as a bookmark rather than as underlined text.
  link,

  /// An attachment column narrowed to one kind of file.
  media;

  static PropertyStyleKind fromValue(Object? value) =>
      PropertyStyleKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => PropertyStyleKind.plain,
      );
}

/// What a button column does when its cell is pressed.
///
/// A button is the clearest case for a per-cell setting: one row's button
/// opens one page, the next row's opens another.
enum PropertyButtonAction {
  openRow,
  openView,
  openUrl,
  setValue,
  copyValue;

  static PropertyButtonAction fromValue(Object? value) =>
      PropertyButtonAction.values.firstWhere(
        (action) => action.name == value,
        orElse: () => PropertyButtonAction.openRow,
      );
}

/// What a button column's action is called, wherever it is offered.
String propertyButtonActionLabel(PropertyButtonAction action) =>
    switch (action) {
      PropertyButtonAction.openRow =>
        LocaleKeys.interactive_button_actionNone.tr(),
      PropertyButtonAction.openView =>
        LocaleKeys.interactive_button_actionOpenView.tr(),
      PropertyButtonAction.openUrl =>
        LocaleKeys.interactive_button_actionOpenUrl.tr(),
      PropertyButtonAction.setValue =>
        LocaleKeys.interactive_property_setValue.tr(),
      PropertyButtonAction.copyValue =>
        LocaleKeys.interactive_button_actionCopy.tr(),
    };

/// Which kind of attachment a media column is meant to hold.
///
/// The backend stores every attachment the same way; this only decides what
/// the column is called, which glyph it wears and what the picker offers.
enum PropertyMediaKind {
  files,
  photo,
  video,
  audio,
  pdf;

  static PropertyMediaKind fromValue(Object? value) =>
      PropertyMediaKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => PropertyMediaKind.files,
      );
}

/// Where a cell's contents sit in the column.
///
/// It applies to every column type, not only the styled ones, which is why it
/// is a setting rather than a kind.
enum PropertyAlign {
  left,
  center,
  right;

  static PropertyAlign? fromValue(Object? value) {
    for (final align in PropertyAlign.values) {
      if (align.name == value) {
        return align;
      }
    }
    return null;
  }

  Alignment get alignment => switch (this) {
        PropertyAlign.left => Alignment.centerLeft,
        PropertyAlign.center => Alignment.center,
        PropertyAlign.right => Alignment.centerRight,
      };

  TextAlign get textAlign => switch (this) {
        PropertyAlign.left => TextAlign.left,
        PropertyAlign.center => TextAlign.center,
        PropertyAlign.right => TextAlign.right,
      };

  MainAxisAlignment get rowAlignment => switch (this) {
        PropertyAlign.left => MainAxisAlignment.start,
        PropertyAlign.center => MainAxisAlignment.center,
        PropertyAlign.right => MainAxisAlignment.end,
      };

  WrapAlignment get wrapAlignment => switch (this) {
        PropertyAlign.left => WrapAlignment.start,
        PropertyAlign.center => WrapAlignment.center,
        PropertyAlign.right => WrapAlignment.end,
      };
}

/// How large an attachment preview is drawn.
enum PropertyThumbnailSize {
  small(28),
  medium(48),
  large(84);

  const PropertyThumbnailSize(this.extent);

  final double extent;

  static PropertyThumbnailSize fromValue(Object? value) =>
      PropertyThumbnailSize.values.firstWhere(
        (size) => size.name == value,
        orElse: () => PropertyThumbnailSize.medium,
      );
}

/// One column's presentation.
@immutable
class PropertyStyle {
  const PropertyStyle({
    required this.kind,
    this.settings = const <String, Object?>{},
  });

  factory PropertyStyle.fromJson(Map<String, Object?> json) => PropertyStyle(
        kind: PropertyStyleKind.fromValue(json['kind']),
        settings: Map<String, Object?>.from(json)..remove('kind'),
      );

  final PropertyStyleKind kind;

  /// Whatever the presentation needs — a maximum, a step, a label, an action.
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => {'kind': kind.name, ...settings};

  PropertyStyle withSetting(String key, Object? value) {
    final next = Map<String, Object?>.from(settings);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return PropertyStyle(kind: kind, settings: next);
  }

  /// The same column, as one cell asked for it.
  PropertyStyle withOverride(Map<String, Object?> override) =>
      override.isEmpty
          ? this
          : PropertyStyle(kind: kind, settings: {...settings, ...override});

  double doubleSetting(String key, {required double fallback}) {
    final value = settings[key];
    return value is num ? value.toDouble() : fallback;
  }

  bool boolSetting(String key, {bool fallback = false}) {
    final value = settings[key];
    return value is bool ? value : fallback;
  }

  String stringSetting(String key, {String fallback = ''}) {
    final value = settings[key];
    return value is String ? value : fallback;
  }

  // Progress ---------------------------------------------------------------

  double get maximum {
    final stored = doubleSetting('maximum', fallback: 100);
    return stored <= 0 ? 100 : stored;
  }

  bool get showPercent => boolSetting('show_percent', fallback: true);

  // Counter ----------------------------------------------------------------

  double get step {
    final stored = doubleSetting('step', fallback: 1);
    return stored == 0 ? 1 : stored;
  }

  double? get minimum {
    final value = settings['minimum'];
    return value is num ? value.toDouble() : null;
  }

  double? get counterMaximum {
    final value = settings['maximum'];
    return value is num ? value.toDouble() : null;
  }

  // Button -----------------------------------------------------------------

  String get buttonLabel => stringSetting('label');

  PropertyButtonAction get buttonAction =>
      PropertyButtonAction.fromValue(settings['action']);

  String get buttonTarget => stringSetting('target');

  /// What the target is called, so a button can say where it goes.
  String get buttonTargetName => stringSetting('target_name');

  // Link -------------------------------------------------------------------

  bool get showThumbnail => boolSetting('thumbnail', fallback: true);

  // Media ------------------------------------------------------------------

  PropertyMediaKind get mediaKind =>
      PropertyMediaKind.fromValue(settings['media']);

  PropertyThumbnailSize get thumbnailSize =>
      PropertyThumbnailSize.fromValue(settings['thumbnail_size']);

  // Every column -----------------------------------------------------------

  /// Null means nobody has chosen, which is not the same as left.
  PropertyAlign? get align => PropertyAlign.fromValue(settings['align']);

  /// The accent used for the cell, named from the interactive palette.
  String get accent => stringSetting('accent', fallback: 'neutral');

  @override
  bool operator ==(Object other) =>
      other is PropertyStyle &&
      other.kind == kind &&
      mapEquals(other.settings, settings);

  @override
  int get hashCode => Object.hash(kind, jsonEncode(settings));
}

/// One column's settings as a single cell asked for them.
typedef PropertyCellOverrides = Map<String, Map<String, Object?>>;

/// Every column style a view carries, stored in the view's own `extra`.
///
/// It rides beside the chart, map and slide marks that already live there, so
/// no schema anywhere has to learn about it.
@immutable
class PropertyStyles {
  const PropertyStyles({
    this.byField = const <String, PropertyStyle>{},
    this.byCell = const <String, PropertyCellOverrides>{},
  });

  factory PropertyStyles.fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return const PropertyStyles();
    }
    final byField = <String, PropertyStyle>{};
    final fields = envelope['fields'];
    if (fields is Map) {
      for (final entry in fields.entries) {
        final value = entry.value;
        if (value is Map) {
          byField[entry.key.toString()] = PropertyStyle.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }

    final byCell = <String, PropertyCellOverrides>{};
    final cells = envelope['cells'];
    if (cells is Map) {
      for (final field in cells.entries) {
        final rows = field.value;
        if (rows is! Map) {
          continue;
        }
        final overrides = <String, Map<String, Object?>>{};
        for (final row in rows.entries) {
          final value = row.value;
          if (value is Map && value.isNotEmpty) {
            overrides[row.key.toString()] =
                value.map((key, value) => MapEntry(key.toString(), value));
          }
        }
        if (overrides.isNotEmpty) {
          byCell[field.key.toString()] = overrides;
        }
      }
    }

    return PropertyStyles(byField: byField, byCell: byCell);
  }

  static const String envelopeKey = 'appflowy_property_styles';
  static const int currentVersion = 1;

  final Map<String, PropertyStyle> byField;

  /// Field id → row id → the settings that row overrides.
  final Map<String, PropertyCellOverrides> byCell;

  PropertyStyle? operator [](String fieldId) => byField[fieldId];

  /// What one cell overrides of its column, which is usually nothing.
  Map<String, Object?> cellOverride(String fieldId, String rowId) =>
      byCell[fieldId]?[rowId] ?? const <String, Object?>{};

  /// The column as this row asked for it.
  PropertyStyle? cellStyle(String fieldId, String rowId) {
    final style = byField[fieldId];
    if (style == null) {
      return null;
    }
    return style.withOverride(cellOverride(fieldId, rowId));
  }

  PropertyStyles withField(String fieldId, PropertyStyle? style) {
    final next = Map<String, PropertyStyle>.from(byField);
    // A plain column still earns an entry when it carries settings of its own
    // — an alignment belongs to any column, styled or not.
    if (style == null ||
        (style.kind == PropertyStyleKind.plain && style.settings.isEmpty)) {
      next.remove(fieldId);
    } else {
      next[fieldId] = style;
    }

    // A cell overrode settings that belonged to the old kind, so they mean
    // nothing once the column becomes something else.
    final cells = Map<String, PropertyCellOverrides>.from(byCell);
    if (byField[fieldId]?.kind != style?.kind) {
      cells.remove(fieldId);
    }
    return PropertyStyles(byField: next, byCell: cells);
  }

  PropertyStyles withCell(
    String fieldId,
    String rowId,
    Map<String, Object?>? override,
  ) {
    final cells = Map<String, PropertyCellOverrides>.from(byCell);
    final rows = Map<String, Map<String, Object?>>.from(
      cells[fieldId] ?? const <String, Map<String, Object?>>{},
    );
    if (override == null || override.isEmpty) {
      rows.remove(rowId);
    } else {
      rows[rowId] = override;
    }
    if (rows.isEmpty) {
      cells.remove(fieldId);
    } else {
      cells[fieldId] = rows;
    }
    return PropertyStyles(byField: byField, byCell: cells);
  }

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    if (byField.isEmpty && byCell.isEmpty) {
      values.remove(envelopeKey);
    } else {
      values[envelopeKey] = {
        'version': currentVersion,
        if (byField.isNotEmpty)
          'fields': byField.map((key, value) => MapEntry(key, value.toJson())),
        if (byCell.isNotEmpty) 'cells': byCell,
      };
    }
    return values.isEmpty ? '' : jsonEncode(values);
  }
}

/// Whether two views hold the same cell overrides.
bool _sameCells(
  Map<String, PropertyCellOverrides> a,
  Map<String, PropertyCellOverrides> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (final field in a.entries) {
    final other = b[field.key];
    if (other == null || other.length != field.value.length) {
      return false;
    }
    for (final row in field.value.entries) {
      if (!mapEquals(other[row.key], row.value)) {
        return false;
      }
    }
  }
  return true;
}

/// Remembers how each column of each database is drawn.
///
/// The type picker, the field panel and every cell need the same answer and
/// have to agree the moment any of them changes it, so it is fetched once and
/// shared, exactly as the location mark is.
class PropertyStyleRegistry {
  PropertyStyleRegistry._();

  static final PropertyStyleRegistry instance = PropertyStyleRegistry._();

  final Map<String, ValueNotifier<PropertyStyles>> _views = {};
  final Set<String> _loading = {};

  /// Which view's `extra` actually holds a view's styles.
  ///
  /// A column belongs to the DATABASE, so a grid, a board and a calendar of
  /// the same table must read one answer. They all read the database's first
  /// view, which for a table nobody has re-arranged is the grid itself.
  final Map<String, String> _hosts = {};
  final Map<String, Future<String>> _resolving = {};

  /// Bumped whenever any view's styles change, for surfaces that are not the
  /// view the column was marked in.
  final ValueNotifier<int> revision = ValueNotifier(0);

  ValueNotifier<PropertyStyles> listenable(String viewId) {
    final notifier = _views.putIfAbsent(
      viewId,
      () => ValueNotifier(const PropertyStyles()),
    );
    unawaited(refresh(viewId));
    return notifier;
  }

  PropertyStyle? styleFor(String viewId, String fieldId) =>
      _views[viewId]?.value[fieldId];

  /// The column as one row asked for it, which is what a cell draws.
  PropertyStyle? cellStyleFor(String viewId, String fieldId, String rowId) =>
      _views[viewId]?.value.cellStyle(fieldId, rowId);

  Map<String, Object?> cellOverrideFor(
    String viewId,
    String fieldId,
    String rowId,
  ) =>
      _views[viewId]?.value.cellOverride(fieldId, rowId) ??
      const <String, Object?>{};

  /// Changes one setting, keeping whatever kind the column already had.
  Future<void> setSetting({
    required String viewId,
    required String fieldId,
    required String key,
    required Object? value,
  }) {
    final current = styleFor(viewId, fieldId) ??
        const PropertyStyle(kind: PropertyStyleKind.plain);
    return setStyle(
      viewId: viewId,
      fieldId: fieldId,
      style: current.withSetting(key, value),
    );
  }

  /// Changes several of a column's settings in one write.
  Future<void> setSettings({
    required String viewId,
    required String fieldId,
    required Map<String, Object?> values,
  }) =>
      _write(viewId, (styles) {
        var style = styles[fieldId] ??
            const PropertyStyle(kind: PropertyStyleKind.plain);
        for (final entry in values.entries) {
          style = style.withSetting(entry.key, entry.value);
        }
        return styles.withField(fieldId, style);
      });

  /// Changes one setting for ONE cell, leaving the rest of the column alone.
  Future<void> setCellSetting({
    required String viewId,
    required String fieldId,
    required String rowId,
    required String key,
    required Object? value,
  }) =>
      setCellSettings(
        viewId: viewId,
        fieldId: fieldId,
        rowId: rowId,
        values: {key: value},
      );

  /// Changes several of a cell's settings in one write.
  Future<void> setCellSettings({
    required String viewId,
    required String fieldId,
    required String rowId,
    required Map<String, Object?> values,
  }) =>
      _write(viewId, (styles) {
        final override = Map<String, Object?>.from(
          styles.cellOverride(fieldId, rowId),
        );
        for (final entry in values.entries) {
          if (entry.value == null) {
            override.remove(entry.key);
          } else {
            override[entry.key] = entry.value;
          }
        }
        return styles.withCell(fieldId, rowId, override);
      });

  /// Gives a cell back whatever its column says.
  Future<void> clearCell({
    required String viewId,
    required String fieldId,
    required String rowId,
  }) =>
      _write(viewId, (styles) => styles.withCell(fieldId, rowId, null));

  Future<void> refresh(String viewId) async {
    if (!_loading.add(viewId)) {
      return;
    }
    try {
      final host = await _hostFor(viewId);
      var styles = await _read(host);
      if (styles == null) {
        return;
      }
      // Styles used to be written on whichever view marked the column. A
      // table that was marked from a board still has them there.
      if (host != viewId && styles.byField.isEmpty && styles.byCell.isEmpty) {
        final own = await _read(viewId);
        if (own != null && own.byField.isNotEmpty) {
          styles = own;
        }
      }
      _adopt(host, styles);
    } finally {
      _loading.remove(viewId);
    }
  }

  Future<PropertyStyles?> _read(String viewId) async {
    final result = await ViewBackendService.getView(viewId);
    return result.fold(
      (view) => PropertyStyles.fromExtra(view.extra),
      (error) {
        Log.warn('Could not read the column styles of $viewId: $error');
        return null;
      },
    );
  }

  /// Hands one answer to every view of the same database at once.
  void _adopt(String host, PropertyStyles styles) {
    var changed = false;
    for (final entry in _views.entries) {
      if (entry.key != host && _hosts[entry.key] != host) {
        continue;
      }
      final notifier = entry.value;
      if (mapEquals(notifier.value.byField, styles.byField) &&
          _sameCells(notifier.value.byCell, styles.byCell)) {
        continue;
      }
      notifier.value = styles;
      changed = true;
    }
    if (changed) {
      revision.value++;
    }
  }

  /// Which view's `extra` holds this view's styles.
  Future<String> _hostFor(String viewId) async {
    final known = _hosts[viewId];
    if (known != null) {
      return known;
    }
    final pending = _resolving[viewId];
    if (pending != null) {
      return pending;
    }
    final future = _resolveHost(viewId);
    _resolving[viewId] = future;
    final host = await future;
    _hosts[viewId] = host;
    _resolving.removeWhere((key, _) => key == viewId);
    return host;
  }

  Future<String> _resolveHost(String viewId) async {
    final databaseId = await DatabaseViewBackendService(viewId: viewId)
        .getDatabaseId()
        .fold((id) => id, (_) => null);
    if (databaseId == null) {
      return viewId;
    }
    final host = await DatabaseEventGetDatabases().send().fold(
          (databases) => databases.items
              .firstWhereOrNull((meta) => meta.databaseId == databaseId)
              ?.viewId,
          (_) => null,
        );
    return host == null || host.isEmpty ? viewId : host;
  }

  /// Writes one column's style. A null [style] clears it.
  Future<void> setStyle({
    required String viewId,
    required String fieldId,
    required PropertyStyle? style,
  }) =>
      _write(viewId, (styles) => styles.withField(fieldId, style));

  Future<void> _write(
    String viewId,
    PropertyStyles Function(PropertyStyles styles) change,
  ) async {
    final host = await _hostFor(viewId);
    // Re-read the view first: the extra carries other marks, and a stale copy
    // would write them away.
    final current = await ViewBackendService.getView(host);
    final view = current.fold((view) => view, (_) => null);
    if (view == null) {
      return;
    }

    final next = change(PropertyStyles.fromExtra(view.extra));
    _adopt(host, next);
    revision.value++;

    await ViewBackendService.updateView(
      viewId: host,
      extra: next.mergeIntoExtra(view.extra),
    );
    _loading.remove(viewId);
    await refresh(viewId);
  }
}
