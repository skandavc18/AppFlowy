import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';

/// The pieces every built-in template is assembled from.
///
/// Deliberately the same widgets the Add panel offers — a template has no
/// private parts, so anything it makes can be taken apart afterwards.

DashboardWidgetSpec widget(
  String type, {
  int x = 0,
  int y = 0,
  int w = 4,
  int h = 4,
  String title = '',
  DashboardAccent accent = DashboardAccent.neutral,
  Map<String, Object?> settings = const {},
  DashboardDataSource source = DashboardDataSource.none,
}) =>
    DashboardWidgetSpec(
      id: newDashboardId('w'),
      type: type,
      placement:
          DashboardPlacement(column: x, row: y, columnSpan: w, rowSpan: h),
      title: title,
      showTitle: title.isNotEmpty,
      accent: accent,
      settings: settings,
      source: source,
    );

DashboardSection section(
  List<DashboardWidgetSpec> widgets, {
  String title = '',
}) =>
    DashboardSection(
      id: newDashboardId('section'),
      title: title,
      widgets: widgets,
    );

DashboardDocument document(
  List<DashboardSection> sections, {
  List<DashboardVariable> variables = const [],
  DashboardSettings settings = const DashboardSettings(),
  String subtitle = '',
}) =>
    DashboardDocument(
      sections: sections,
      variables: variables,
      settings: settings,
      subtitle: subtitle,
    );

/// A widget reading a table the template made a moment ago.
///
/// [viewId] is empty when the table could not be created, and a widget with no
/// source simply offers to be pointed at one — never an error.
DashboardDataSource table(
  String? viewId, {
  String name = '',
  String field = '',
  String groupField = '',
}) =>
    viewId == null || viewId.isEmpty
        ? DashboardDataSource.none
        : DashboardDataSource(
            kind: DashboardSourceKind.database,
            viewId: viewId,
            name: name,
            field: field,
            groupField: groupField,
          );

/// A heading strip across the top of a section.
DashboardWidgetSpec heading(
  String text, {
  int y = 0,
  int w = 12,
  DashboardAccent accent = DashboardAccent.neutral,
}) =>
    widget(
      'heading',
      y: y,
      w: w,
      h: 1,
      accent: accent,
      settings: {'text': text},
    );

DashboardWidgetSpec note(
  String text, {
  int x = 0,
  int y = 0,
  int w = 4,
  int h = 4,
  DashboardAccent accent = DashboardAccent.neutral,
}) =>
    widget(
      'sticky_note',
      x: x,
      y: y,
      w: w,
      h: h,
      accent: accent,
      settings: {'text': text},
    );
