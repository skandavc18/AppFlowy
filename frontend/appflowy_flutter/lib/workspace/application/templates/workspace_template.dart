import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// What a template has already made, by part key.
///
/// A part is built in order, so a dashboard listed after a table can read the
/// table's view id out of this and bind a chart to it.
typedef TemplateContext = Map<String, String>;

/// One artifact a template creates.
sealed class TemplateBlueprint {
  const TemplateBlueprint();
}

/// A dashboard: an arrangement of the same widgets the Add panel offers.
class TemplateDashboard extends TemplateBlueprint {
  const TemplateDashboard(this.build);

  final DashboardDocument Function(TemplateContext created) build;
}

/// A page, written as markdown and parsed into the editor's own blocks.
class TemplatePage extends TemplateBlueprint {
  const TemplatePage(this.markdown);

  final String Function(TemplateContext created) markdown;
}

/// An infinite canvas.
class TemplateCanvas extends TemplateBlueprint {
  const TemplateCanvas(this.build);

  final CanvasDocument Function(TemplateContext created) build;
}

/// A database, with its columns typed and a few rows to show the shape.
class TemplateDatabase extends TemplateBlueprint {
  const TemplateDatabase(this.build, {this.layout = ViewLayoutPB.Grid});

  final TemplateTable Function(TemplateContext created) build;
  final ViewLayoutPB layout;
}

/// A folder, so a template made of several things has somewhere to put them.
class TemplateFolder extends TemplateBlueprint {
  const TemplateFolder();
}

// ------------------------------------------------------------------ databases

/// A column a template asks for.
@immutable
class TemplateColumn {
  const TemplateColumn(
    this.name,
    this.type, {
    this.options = const [],
  });

  const TemplateColumn.text(String name) : this(name, FieldType.RichText);
  const TemplateColumn.number(String name) : this(name, FieldType.Number);
  const TemplateColumn.date(String name) : this(name, FieldType.DateTime);
  const TemplateColumn.checkbox(String name) : this(name, FieldType.Checkbox);
  const TemplateColumn.url(String name) : this(name, FieldType.URL);

  const TemplateColumn.select(String name, List<String> options)
      : this(name, FieldType.SingleSelect, options: options);

  const TemplateColumn.multiSelect(String name, List<String> options)
      : this(name, FieldType.MultiSelect, options: options);

  final String name;
  final FieldType type;

  /// The choices offered by a select column, in the order they should read.
  final List<String> options;
}

/// The shape of a database, plus a few rows so it opens as an example rather
/// than as an empty grid nobody can tell the purpose of.
@immutable
class TemplateTable {
  const TemplateTable({
    required this.columns,
    this.rows = const [],
  });

  final List<TemplateColumn> columns;

  /// Cell values, positionally matching [columns]. An empty string is left
  /// blank; a date is written as `yyyy-mm-dd`; a checkbox as `yes`/`no`.
  final List<List<String>> rows;
}

// ------------------------------------------------------------------ templates

/// One thing a template makes.
@immutable
class TemplatePart {
  const TemplatePart({
    required this.key,
    required this.name,
    required this.blueprint,
    this.icon = '',
  });

  /// How later parts refer to this one.
  final String key;
  final String Function() name;
  final TemplateBlueprint blueprint;

  /// An emoji, written onto the created view.
  final String icon;
}

/// Which shelf a template sits on.
enum TemplateCategory {
  everyday,
  work,
  finance,
  knowledge,
  publishing;
}

/// What a template mostly produces, shown on its card so somebody knows what
/// they are about to get before they press it.
enum TemplateKind {
  dashboard,
  page,
  database,
  canvas,
  bundle;
}

/// Something somebody can start from.
///
/// A template is only a starting point — everything it makes is an ordinary
/// page, dashboard or table afterwards, with nothing special about it.
class WorkspaceTemplate {
  WorkspaceTemplate({
    required this.id,
    required this.category,
    required this.label,
    required this.description,
    required this.icon,
    required this.build,
    this.accent = DashboardAccent.neutral,
    this.keywords = const [],
    this.requires = const {},
    this.extensionId = '',
  });

  final String id;
  final TemplateCategory category;
  final String Function() label;
  final String Function() description;
  final IconData icon;
  final DashboardAccent accent;
  final List<String> keywords;

  /// Dart extensions this template's widgets come from. A template whose
  /// extension is switched off would be a grid of "unknown widget" placards,
  /// so the gallery offers to turn it on rather than making one.
  final Set<String> requires;

  /// Set when an extension contributed the template, so switching the
  /// extension off takes its templates with it.
  final String extensionId;

  final List<TemplatePart> Function() build;

  /// The parts, worked out once. A gallery reads [kind] and the part count for
  /// every card on every frame, and rebuilding the closures each time is waste.
  late final List<TemplatePart> parts = build();

  /// More than one part means the template needs a folder to hold them.
  bool get makesSeveralThings => parts.length > 1;

  TemplateKind get kind {
    if (parts.length > 1) {
      return TemplateKind.bundle;
    }
    return switch (parts.single.blueprint) {
      TemplateDashboard() => TemplateKind.dashboard,
      TemplatePage() => TemplateKind.page,
      TemplateDatabase() => TemplateKind.database,
      TemplateCanvas() => TemplateKind.canvas,
      TemplateFolder() => TemplateKind.bundle,
    };
  }

  /// Whether this template can be laid over an existing view, rather than
  /// making a new one. Only a single-part template can.
  bool appliesTo(ViewPB view) {
    if (parts.length != 1) {
      return false;
    }
    final isDocument = view.layout == ViewLayoutPB.Document;
    return switch (parts.single.blueprint) {
      TemplateDashboard() => isDocument && view.isDashboard,
      TemplateCanvas() => isDocument && view.isCanvas,
      TemplatePage() => isDocument &&
          !view.isDashboard &&
          !view.isCanvas &&
          !view.isWorkspaceItem,
      TemplateDatabase() => false,
      TemplateFolder() => false,
    };
  }
}
