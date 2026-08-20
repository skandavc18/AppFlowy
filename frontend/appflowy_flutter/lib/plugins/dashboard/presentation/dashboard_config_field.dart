import 'package:appflowy/shared/settings_schema/settings_schema.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// One row of a widget's configuration, described rather than drawn.
///
/// A widget says what it can be configured with; the panel decides how that
/// looks. That is what keeps every widget's settings consistent, and what lets
/// a new widget be added without writing a single form.
///
/// The generic rows below are the shared `SettingsField` vocabulary under their
/// dashboard names, so a block, an extension and a dashboard widget all
/// describe a text box the same way. Only the rows that genuinely need to know
/// about variables, data sources and views are declared here.
typedef DashboardConfigField = SettingsField;

/// A line or a paragraph of text.
typedef DashboardConfigText = SettingsTextField;

/// A number, with a stepper.
typedef DashboardConfigNumber = SettingsNumberField;

/// On or off.
typedef DashboardConfigToggle = SettingsToggleField;

/// One choice out of a few. Drawn as segments when there are three or fewer,
/// as a menu when there are more.
typedef DashboardConfigChoice = SettingsChoiceField;

typedef DashboardChoice = SettingsChoice;

/// A heading with its own rows underneath.
typedef DashboardConfigGroup = SettingsGroupField;

/// A single action the panel offers — "Reset", "Open the page".
typedef DashboardConfigButton = SettingsButtonField;

/// A sentence explaining something the panel cannot show.
typedef DashboardConfigNote = SettingsNoteField;

/// The widget's colour, drawn as a row of swatches.
class DashboardConfigAccent extends DashboardConfigField {
  const DashboardConfigAccent({
    required super.label,
    required this.value,
    required this.onChanged,
    super.hint,
  });

  final DashboardAccent value;
  final ValueChanged<DashboardAccent> onChanged;
}

/// Where the widget reads from.
class DashboardConfigSource extends DashboardConfigField {
  const DashboardConfigSource({
    required super.label,
    required this.value,
    required this.onChanged,
    required this.kinds,
    super.hint,
  });

  final DashboardDataSource value;
  final ValueChanged<DashboardDataSource> onChanged;

  /// The kinds this widget can actually read. A widget that reads nothing
  /// passes an empty set and no source row is drawn at all.
  final List<DashboardSourceKind> kinds;
}

/// A page, database or collection somewhere in the workspace.
class DashboardConfigView extends DashboardConfigField {
  const DashboardConfigView({
    required super.label,
    required this.viewId,
    required this.name,
    required this.onChanged,
    super.hint,
    this.filter,
  });

  final String viewId;
  final String name;

  /// Called with the chosen view's id and name; both empty means "cleared".
  final void Function(String viewId, String name) onChanged;
  final bool Function(ViewPB view)? filter;
}

/// A place on the map, chosen by searching for it.
///
/// The coordinates come back with the name, so nothing has to guess later.
class DashboardConfigPlace extends DashboardConfigField {
  const DashboardConfigPlace({
    required super.label,
    required this.place,
    required this.onChanged,
    super.hint,
  });

  final String place;

  /// An empty name clears the place.
  final void Function(String name, double? latitude, double? longitude)
      onChanged;
}

/// The list of choices a selector, a radio group or a variable offers.
class DashboardConfigOptions extends DashboardConfigField {
  const DashboardConfigOptions({
    required super.label,
    required this.options,
    required this.onChanged,
    super.hint,
  });

  final List<DashboardOption> options;
  final ValueChanged<List<DashboardOption>> onChanged;
}

/// What a control does when it is used.
class DashboardConfigAction extends DashboardConfigField {
  const DashboardConfigAction({
    required super.label,
    required this.action,
    required this.onChanged,
    super.hint,
  });

  final DashboardAction action;
  final ValueChanged<DashboardAction> onChanged;
}

/// Which dashboard variable a setting follows.
///
/// This is the row that turns a widget from a static card into part of an
/// application: bind a list's filter to the project selector and it follows it.
class DashboardConfigBinding extends DashboardConfigField {
  const DashboardConfigBinding({
    required super.label,
    required this.setting,
    required this.variableKey,
    required this.onChanged,
    super.hint,
    this.kinds = const [],
  });

  final String setting;
  final String variableKey;
  final ValueChanged<String> onChanged;

  /// Restrict the offer to variables of these kinds; empty means any.
  final List<DashboardVariableKind> kinds;
}
