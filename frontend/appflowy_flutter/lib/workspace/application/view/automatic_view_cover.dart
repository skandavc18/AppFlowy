import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which pictures a cover is invented from.
enum ViewCoverSet {
  nature('nature'),
  abstract('abstract');

  const ViewCoverSet(this.id);

  final String id;

  List<String> get coverValues =>
      this == ViewCoverSet.nature ? natureCoverValues : abstractCoverValues;

  static ViewCoverSet fromId(String? id) {
    for (final set in ViewCoverSet.values) {
      if (set.id == id) {
        return set;
      }
    }
    return ViewCoverSet.nature;
  }
}

@immutable
class AutomaticViewCoverSettings {
  const AutomaticViewCoverSettings({
    required this.enabled,
    required this.theme,
    this.set = ViewCoverSet.nature,
  });

  static const defaultTheme = 'calm editorial';

  final bool enabled;
  final String theme;
  final ViewCoverSet set;

  AutomaticViewCoverSettings copyWith({
    bool? enabled,
    String? theme,
    ViewCoverSet? set,
  }) =>
      AutomaticViewCoverSettings(
        enabled: enabled ?? this.enabled,
        theme: theme ?? this.theme,
        set: set ?? this.set,
      );
}

abstract final class AutomaticViewCoverPreferences {
  static const _enabledKey =
      'io.appflowy.appflowy_flutter.automatic_view_cover_enabled';
  static const _themeKey =
      'io.appflowy.appflowy_flutter.automatic_view_cover_theme';
  static const _setKey =
      'io.appflowy.appflowy_flutter.automatic_view_cover_set';

  static AutomaticViewCoverSettings? _cached;

  static Future<AutomaticViewCoverSettings> load() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }

    final preferences = await SharedPreferences.getInstance();
    final settings = AutomaticViewCoverSettings(
      // A new page arrives with a picture unless somebody says otherwise.
      enabled: preferences.getBool(_enabledKey) ?? true,
      theme: _normalizeTheme(preferences.getString(_themeKey)),
      set: ViewCoverSet.fromId(preferences.getString(_setKey)),
    );
    _cached = settings;
    return settings;
  }

  static Future<void> save(AutomaticViewCoverSettings settings) async {
    final normalized =
        settings.copyWith(theme: _normalizeTheme(settings.theme));
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool(_enabledKey, normalized.enabled),
      preferences.setString(_themeKey, normalized.theme),
      preferences.setString(_setKey, normalized.set.id),
    ]);
    _cached = normalized;
  }

  @visibleForTesting
  static void resetCache() => _cached = null;

  static String _normalizeTheme(String? theme) {
    final normalized = theme?.trim() ?? '';
    return normalized.isEmpty
        ? AutomaticViewCoverSettings.defaultTheme
        : normalized;
  }
}

abstract final class AutomaticViewCover {
  static PageStyleCover forWorkspace({required String name}) => forNewView(
        theme: AutomaticViewCoverSettings.defaultTheme,
        name: name,
        layout: ViewLayoutPB.Document,
      );

  static bool supports({
    required ViewLayoutPB layout,
    required String extra,
    required Map<String, String> creationMetadata,
  }) {
    if (creationMetadata.containsKey('database_id')) {
      return false;
    }
    if (WorkspaceItemMetadata.fromExtra(extra)?.isFile == true) {
      return false;
    }
    // A table is data, not a document — a picture invented for it is chrome
    // above the rows rather than something the reader chose. Grid, board,
    // calendar and every marked reading built on them are left bare, and a
    // cover can still be added by hand.
    return layout == ViewLayoutPB.Document;
  }

  static PageStyleCover forNewView({
    required String theme,
    required String name,
    required ViewLayoutPB layout,
    ViewCoverSet set = ViewCoverSet.nature,
  }) {
    final seed = '${theme.trim().toLowerCase()}|'
        '${name.trim().toLowerCase()}|${layout.value}';
    final values = set.coverValues;
    return PageStyleCover(
      type: PageStyleCoverImageType.builtInImage,
      value: values[_stableHash(seed) % values.length],
    );
  }

  static List<AutomaticViewCoverUpdate> updatesForExistingViews({
    required Iterable<ViewPB> views,
    required String theme,
    ViewCoverSet set = ViewCoverSet.nature,
  }) {
    final updates = <AutomaticViewCoverUpdate>[];
    for (final view in views) {
      if (!_supportsExistingView(view)) {
        continue;
      }

      final currentCover = ViewCoverCodec.decodeCover(view.extra);
      if (currentCover != null && !currentCover.isNone) {
        continue;
      }

      updates.add(
        AutomaticViewCoverUpdate(
          viewId: view.id,
          extra: ViewCoverCodec.mergeCover(
            view.extra,
            forNewView(
              theme: theme,
              name: view.name,
              layout: view.layout,
              set: set,
            ),
          ),
        ),
      );
    }
    return updates;
  }

  static bool _supportsExistingView(ViewPB view) {
    if (view.parentViewId.isEmpty) {
      return false;
    }
    final metadata = ViewCoverCodec.decodeExtra(view.extra);
    if (metadata['is_space'] == true) {
      return false;
    }
    return supports(
      layout: view.layout,
      extra: view.extra,
      creationMetadata: const {},
    );
  }

  /// Whether a table's cover was chosen by hand rather than invented for it.
  ///
  /// Tables stopped being given a cover, but the ones stamped before that keep
  /// theirs, and the picture depends on a theme somebody typed — so a stamped
  /// cover cannot be recognised after the fact. The rule is therefore the
  /// other way round: a table shows a cover only once somebody has actually
  /// set one, which is recorded the moment they do.
  static const chosenByHandKey = 'cover_chosen';

  static bool showsCover(ViewPB view) {
    final cover = ViewCoverCodec.decodeCover(view.extra);
    if (cover == null || cover.isNone) {
      return false;
    }
    if (supports(
      layout: view.layout,
      extra: view.extra,
      creationMetadata: const {},
    )) {
      return true;
    }
    return ViewCoverCodec.decodeExtra(view.extra)[chosenByHandKey] == true;
  }

  /// The view's `extra` with that record added, for the moment a cover is set.
  static String markCoverChosenByHand(String extra) {
    final decoded = Map<String, dynamic>.from(ViewCoverCodec.decodeExtra(extra))
      ..[chosenByHandKey] = true;
    return jsonEncode(decoded);
  }

  static int _stableHash(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}

@immutable
class AutomaticViewCoverUpdate {
  const AutomaticViewCoverUpdate({
    required this.viewId,
    required this.extra,
  });

  final String viewId;
  final String extra;
}
