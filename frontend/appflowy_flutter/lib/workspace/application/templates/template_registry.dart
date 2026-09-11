import 'package:appflowy/workspace/application/templates/built_in/built_in_templates.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// Every template AppFlowy can start somebody from.
///
/// Templates are registered rather than listed so an extension can contribute
/// one — and so switching that extension off takes its templates away with it,
/// instead of leaving a card that makes a page full of missing widgets.
abstract final class TemplateRegistry {
  static final Map<String, WorkspaceTemplate> _templates = {};
  static final List<String> _order = [];
  static bool _initialized = false;

  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Bumped whenever the set of templates changes, so a gallery that is open
  /// picks up an extension being switched on without a restart.
  static Listenable get changes => _revision;

  static void register(WorkspaceTemplate template) {
    if (!_templates.containsKey(template.id)) {
      _order.add(template.id);
    }
    _templates[template.id] = template;
    _revision.value++;
  }

  /// Removes every template an extension added.
  static void unregisterAll(String extensionId) {
    if (extensionId.isEmpty) {
      return;
    }
    final doomed = [
      for (final entry in _templates.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    if (doomed.isEmpty) {
      return;
    }
    for (final id in doomed) {
      _templates.remove(id);
      _order.remove(id);
    }
    _revision.value++;
  }

  static List<WorkspaceTemplate> all() {
    _ensureInitialized();
    return [
      for (final id in _order)
        if (_templates[id] != null) _templates[id]!,
    ];
  }

  static WorkspaceTemplate? forId(String id) {
    _ensureInitialized();
    return _templates[id];
  }

  static List<WorkspaceTemplate> inCategory(TemplateCategory category) => [
        for (final template in all())
          if (template.category == category) template,
      ];

  /// Every template that could be laid over [view].
  static List<WorkspaceTemplate> applicableTo(ViewPB view) => [
        for (final template in all())
          if (template.appliesTo(view)) template,
      ];

  /// The templates matching [query], best first — the same ranking the widget
  /// registry and the workspace search use, so the three read as one thing.
  static List<WorkspaceTemplate> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return all();
    }
    final scored = <(int, WorkspaceTemplate)>[];
    for (final template in all()) {
      final name = template.label().toLowerCase();
      int? score;
      if (name == needle) {
        score = 0;
      } else if (name.startsWith(needle)) {
        score = 1;
      } else if (name.contains(needle)) {
        score = 2;
      } else if (template.description().toLowerCase().contains(needle)) {
        score = 3;
      } else if (template.keywords
          .any((keyword) => keyword.toLowerCase().startsWith(needle))) {
        score = 4;
      } else if (template.keywords
          .any((keyword) => keyword.toLowerCase().contains(needle))) {
        score = 5;
      }
      if (score != null) {
        scored.add((score, template));
      }
    }
    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      return byScore != 0
          ? byScore
          : a.$2.label().length.compareTo(b.$2.label().length);
    });
    return [for (final entry in scored) entry.$2];
  }

  @visibleForTesting
  static void reset() {
    _templates.clear();
    _order.clear();
    _initialized = false;
  }

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    // Set first: registration reaches back into the registry, and a second
    // pass would double every template.
    _initialized = true;
    registerBuiltInTemplates();
  }
}
