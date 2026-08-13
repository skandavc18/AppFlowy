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
sealed class DashboardConfigField {
  const DashboardConfigField({required this.label, this.hint = ''});

  final String label;
  final String hint;
}

/// A line or a paragraph of text.
class DashboardConfigText extends DashboardConfigField {
  const DashboardConfigText({
    required super.label,
    required this.value,
    required this.onChanged,
    super.hint,
    this.multiline = false,
    this.placeholder = '',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool multiline;
  final String placeholder;
}

/// A number, with a stepper.
class DashboardConfigNumber extends DashboardConfigField {
  const DashboardConfigNumber({
    required super.label,
    required this.value,
    required this.onChanged,
    super.hint,
    this.minimum,
    this.maximum,
    this.step = 1,
    this.suffix = '',
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double? minimum;
  final double? maximum;
  final double step;
  final String suffix;
}

/// On or off.
class DashboardConfigToggle extends DashboardConfigField {
  const DashboardConfigToggle({
    required super.label,
    required this.value,
    required this.onChanged,
    super.hint,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
}

/// One choice out of a few. Drawn as segments when there are three or fewer,
/// as a menu when there are more.
class DashboardConfigChoice extends DashboardConfigField {
  const DashboardConfigChoice({
    required super.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    super.hint,
    this.iconsOnly = false,
  });

  final String value;
  final List<DashboardChoice> choices;
  final ValueChanged<String> onChanged;
  final bool iconsOnly;
}

@immutable
class DashboardChoice {
  const DashboardChoice({
    required this.value,
    required this.label,
    this.icon,
    this.description = '',
  });

  final String value;
  final String label;
  final IconData? icon;
  final String description;
}

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

/// A heading with its own rows underneath.
class DashboardConfigGroup extends DashboardConfigField {
  const DashboardConfigGroup({
    required super.label,
    required this.fields,
    this.initiallyOpen = true,
  }) : super();

  final List<DashboardConfigField> fields;
  final bool initiallyOpen;
}

/// A single action the panel offers — "Reset", "Open the page".
class DashboardConfigButton extends DashboardConfigField {
  const DashboardConfigButton({
    required super.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    super.hint,
  });

  final VoidCallback onPressed;
  final IconData? icon;
  final bool destructive;
}

/// A sentence explaining something the panel cannot show.
class DashboardConfigNote extends DashboardConfigField {
  const DashboardConfigNote({required super.label, this.icon});

  final IconData? icon;
}
