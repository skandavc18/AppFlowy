import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/find_replace/text_find.dart'
    show buildFindPattern, matchesOfPattern;
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flutter/widgets.dart';

/// Kind, model owner, plain-text field. No JSON path or configuration traversal.
typedef DashboardFindId = (String, String, String);

/// Native identities belong to an embed, never to a dashboard config field.
@immutable
class DashboardEmbedFindId {
  const DashboardEmbedFindId(this.widgetId, this.render, this.start);
  final String widgetId;
  final RenderBox render;
  final int start;

  @override
  bool operator ==(Object other) =>
      other is DashboardEmbedFindId &&
      other.widgetId == widgetId &&
      identical(other.render, render) &&
      other.start == start;
  @override
  int get hashCode => Object.hash(widgetId, render, start);
}

abstract class DashboardFindEmbedDelegate {
  String get widgetId;
  Iterable<SurfaceFindEntry> get entries;
  Rect? get currentRect;
  void reveal();
}

/// The renderer can reject a range that exists in a preview's string but was
/// ellipsized/clipped away. Both the index and native painter use this gate.
class DashboardEmbedFindEntry extends SurfaceFindEntry {
  const DashboardEmbedFindEntry(super.id, super.text, this.acceptsMatch);
  final bool Function(RegExpMatch) acceptsMatch;
}

const dashboardFindTitle = ('page', '', 'title');
const dashboardFindSubtitle = ('page', '', 'subtitle');

DashboardFindId dashboardFindSection(String id) => ('section', id, 'title');
DashboardFindId dashboardFindWidget(String id, String field) =>
    ('widget', id, field);

const _textFields = <String, List<String>>{
  'heading': ['text'],
  'text': ['text'],
  'quote': ['text', 'author'],
  'callout': ['text'],
  'sticky_note': ['text'],
  'button': ['label'],
  'toggle': ['label'],
};

/// Only words the dashboard owns and presents. Linked pages, remote sources,
/// action payloads, credentials, variables and arbitrary settings are not read.
Iterable<SurfaceFindEntry> dashboardFindEntries(
  DashboardController dashboard, {
  required String title,
}) sync* {
  final document = dashboard.document;
  final editable = dashboard.isEditable;
  if (document.settings.showHeader || editable) {
    // The view title has its own backend/rename contract, not dashboard undo.
    yield SurfaceFindEntry(dashboardFindTitle, title);
    yield SurfaceFindEntry(
      dashboardFindSubtitle,
      document.subtitle,
      replaceable: editable,
    );
  }
  for (final section in document.sections) {
    if (!editable &&
        !dashboardVisibilityHolds(section.visibleWhen, dashboard.state)) {
      continue;
    }
    yield SurfaceFindEntry(
      dashboardFindSection(section.id),
      section.title,
      replaceable: editable,
    );
    final widgets = [...section.widgets]..sort((a, b) {
        final row = a.placement.row.compareTo(b.placement.row);
        return row != 0
            ? row
            : a.placement.column.compareTo(b.placement.column);
      });
    for (final spec in widgets) {
      if (!editable &&
          (spec.hidden ||
              !dashboardVisibilityHolds(spec.visibleWhen, dashboard.state))) {
        continue;
      }
      if (spec.showTitle) {
        yield SurfaceFindEntry(
          dashboardFindWidget(spec.id, 'title'),
          spec.title,
          replaceable: editable,
        );
      }
      for (final field in _textFields[spec.type] ?? const <String>[]) {
        yield SurfaceFindEntry(
          dashboardFindWidget(spec.id, field),
          spec.setting(field),
          replaceable: editable,
        );
      }
    }
  }
}

/// The dashboard controller remains the only writer, so Replace All is one
/// undo step and access/identity checks happen against the current document.
void replaceDashboardFindText(
  DashboardController controller,
  List<SurfaceFindReplacement> edits,
) {
  if (!controller.isEditable || edits.isEmpty) return;
  controller.edit((document) {
    if (!controller.isEditable) return document;
    var next = document;
    for (final edit in edits) {
      final id = edit.id;
      if (id is! DashboardFindId) continue;
      if (id == dashboardFindSubtitle && next.subtitle == edit.before) {
        next = next.copyWith(subtitle: edit.after);
      } else if (id.$1 == 'section' && id.$3 == 'title') {
        final section = next.sectionById(id.$2);
        if (section != null && section.title == edit.before) {
          next = next.withSection(section.copyWith(title: edit.after));
        }
      } else if (id.$1 == 'widget') {
        final spec = next.widgetById(id.$2);
        if (spec == null) continue;
        if (id.$3 == 'title' && spec.title == edit.before) {
          next = next.withWidget(spec.copyWith(title: edit.after));
        } else if ((_textFields[spec.type]?.contains(id.$3) ?? false) &&
            spec.setting(id.$3) == edit.before) {
          next = next.withWidget(spec.withSettings({id.$3: edit.after}));
        }
      }
    }
    return next;
  });
}

class DashboardFindController extends SurfaceFindController {
  factory DashboardFindController(
    DashboardController dashboard, {
    required String Function() title,
    DocumentFindReadProvider? readProvider,
  }) =>
      DashboardFindController._(dashboard, title, {}, {}, readProvider);

  DashboardFindController._(
    this.dashboard,
    String Function() title,
    Map<Object, List<TextEditingController>> drafts,
    Map<Object, DashboardFindEmbedDelegate> embeds,
    this.readProvider,
  )   : _drafts = drafts,
        _embeds = embeds,
        super(
          search: (query, options) => [
            ...searchSurfaceEntries(
              dashboardFindEntries(dashboard, title: title()).map((entry) {
                final fields = drafts[entry.id];
                final text = fields?.lastOrNull?.text ?? entry.text;
                return SurfaceFindEntry(
                  entry.id,
                  text,
                  // Never overwrite a suspended/unacknowledged local draft.
                  replaceable: entry.replaceable &&
                      text == entry.text &&
                      (fields?.every((field) => field.text == entry.text) ??
                          true),
                );
              }),
              query,
              options,
            ),
            ..._searchEmbeds(embeds.values, query, options),
          ],
          canReplace: () => dashboard.isEditable,
          applyReplacements: (edits) => replaceDashboardFindText(
            dashboard,
            edits.where((edit) {
              final fields = drafts[edit.id];
              return fields == null ||
                  fields.every((field) => field.text == edit.before);
            }).toList(),
          ),
        ) {
    dashboard.addListener(refresh);
  }

  final DashboardController dashboard;
  final DocumentFindReadProvider? readProvider;
  final Map<Object, DashboardFindEmbedDelegate> _embeds;
  final Map<Object, List<TextEditingController>> _drafts;
  bool _closed = false;
  bool _refreshPending = false;
  DashboardDocument? _indexedDocument;
  final _widgetLocations = <String, (DashboardWidgetSpec, DashboardSection)>{};

  /// One membership traversal per immutable dashboard revision, not per card.
  (DashboardWidgetSpec, DashboardSection)? locationOf(String id) {
    final document = dashboard.document;
    if (!identical(document, _indexedDocument)) {
      _indexedDocument = document;
      _widgetLocations.clear();
      for (final section in document.sections) {
        for (final spec in section.widgets) {
          _widgetLocations.putIfAbsent(spec.id, () => (spec, section));
        }
      }
    }
    return _widgetLocations[id];
  }

  void revokeEmbed(String widgetId) {
    discardMatchesWhere((hit) =>
        hit.id is DashboardEmbedFindId &&
        (hit.id as DashboardEmbedFindId).widgetId == widgetId);
    _refreshLater();
  }

  /// Always honest: no invisible renderer is mounted for Find. Canvas-painted
  /// chart axes, remote/provider and unloaded text remain
  /// outside this scope, even when the dashboard itself is editable.
  String get coverageLabel => 'Dashboard + bounded loaded document/table text '
      'and visible preview body text; native chart labels only. '
      'Clipped preview text, covers, locked, unavailable, unloaded and provider '
      'content excluded.';

  static List<SurfaceFindMatch> _searchEmbeds(
    Iterable<DashboardFindEmbedDelegate> delegates,
    String query,
    FindOptions options,
  ) {
    final RegExp? pattern;
    try {
      pattern = buildFindPattern(query, options);
    } on FormatException {
      return const [];
    }
    if (pattern == null) return const [];
    final matches = <SurfaceFindMatch>[];
    for (final entry in _embedEntries(delegates)) {
      for (final range in matchesOfPattern(entry.text, pattern)) {
        if (entry is DashboardEmbedFindEntry && !entry.acceptsMatch(range))
          continue;
        if (matches.length == const DocumentFindLimits().maxEntries)
          return matches;
        matches.add(SurfaceFindMatch(entry, range));
      }
    }
    return matches;
  }

  static Iterable<SurfaceFindEntry> _embedEntries(
    Iterable<DashboardFindEmbedDelegate> delegates,
  ) sync* {
    var bytes = 0;
    var count = 0;
    final seen = <String>{};
    const limits = DocumentFindLimits();
    for (final delegate in delegates.toList().reversed) {
      final entries = delegate.entries.toList();
      if (entries.isEmpty || !seen.add(delegate.widgetId)) continue;
      if (seen.length > limits.maxViews) return;
      for (final entry in entries) {
        if (++count > limits.maxEntries ||
            (bytes += utf8.encode(entry.text).length) > limits.maxBytes) return;
        yield entry;
      }
    }
  }

  void registerEmbed(Object owner, DashboardFindEmbedDelegate delegate) {
    _embeds[owner] = delegate;
    _refreshLater();
  }

  void unregisterEmbed(Object owner) {
    _embeds.remove(owner);
    _refreshLater();
  }

  void embedChanged() => _refreshLater();

  bool allowsEmbed(Object owner) => _embeds.keys.take(24).contains(owner);

  DashboardFindEmbedDelegate? get _currentEmbed {
    final id = current?.id;
    if (id is! DashboardEmbedFindId) return null;
    return _embeds.values
        .toList()
        .reversed
        .where((delegate) =>
            delegate.widgetId == id.widgetId &&
            delegate.entries.any((entry) => entry.id == id))
        .firstOrNull;
  }

  @override
  Rect? get currentTargetRect => current?.id is DashboardEmbedFindId
      ? _currentEmbed?.currentRect
      : super.currentTargetRect;

  @override
  void revealCurrentTarget() {
    if (current?.id is DashboardEmbedFindId) {
      _currentEmbed?.reveal();
    } else {
      super.revealCurrentTarget();
    }
  }

  void watchDraft(Object id, TextEditingController draft) {
    final fields = _drafts[id] ??= [];
    if (fields.contains(draft)) return;
    fields.add(draft);
    draft.addListener(_refreshLater);
    _refreshLater();
  }

  void unwatchDraft(Object id, TextEditingController draft) {
    draft.removeListener(_refreshLater);
    _drafts[id]?.remove(draft);
    if (_drafts[id]?.isEmpty == true) _drafts.remove(id);
    _refreshLater();
  }

  void _refreshLater() {
    if (_closed || _refreshPending || !isOpen) return;
    _refreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPending = false;
      if (!_closed && isOpen) refresh();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _closed = true;
    dashboard.removeListener(refresh);
    for (final fields in _drafts.values) {
      for (final draft in fields) {
        draft.removeListener(_refreshLater);
      }
    }
    _drafts.clear();
    _embeds.clear();
    super.dispose();
  }
}

/// Search temporarily unfolds a matching band/card in presentation state;
/// it never writes a collapsed flag, even in a read-only dashboard.
bool dashboardFindRevealsWidget(BuildContext context, String id) {
  final target = SurfaceFindScope.maybeOf(context)?.current?.id;
  if (target is DashboardEmbedFindId) return target.widgetId == id;
  return target is DashboardFindId && target.$1 == 'widget' && target.$2 == id;
}

bool dashboardFindRevealsSection(
  BuildContext context,
  DashboardSection section,
) =>
    section.widgets.any((spec) => dashboardFindRevealsWidget(context, spec.id));
