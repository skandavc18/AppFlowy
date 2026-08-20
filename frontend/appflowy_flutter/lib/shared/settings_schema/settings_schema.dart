import 'package:flutter/material.dart';

/// One row of configuration, described rather than drawn.
///
/// A thing says what it can be configured with; the panel decides how that
/// looks. That is what lets a new block, widget or extension be added without
/// anybody writing a form.
///
/// ⚠️ Deliberately NOT sealed. The dashboard adds field types of its own
/// (bindings, data sources, view pickers) and an extension may too, and a
/// sealed class can only be extended inside its own library. Every renderer
/// therefore needs a fallback arm for a field it does not know.
@immutable
abstract class SettingsField {
  const SettingsField({required this.label, this.hint = ''});

  final String label;
  final String hint;
}

/// A line or a paragraph of words.
class SettingsTextField extends SettingsField {
  const SettingsTextField({
    required super.label,
    required this.value,
    required this.onChanged,
    super.hint,
    this.placeholder = '',
    this.multiline = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final bool multiline;
}

/// A number, with a stepper.
class SettingsNumberField extends SettingsField {
  const SettingsNumberField({
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
class SettingsToggleField extends SettingsField {
  const SettingsToggleField({
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
class SettingsChoiceField extends SettingsField {
  const SettingsChoiceField({
    required super.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    super.hint,
    this.iconsOnly = false,
  });

  final String value;
  final List<SettingsChoice> choices;
  final ValueChanged<String> onChanged;
  final bool iconsOnly;
}

@immutable
class SettingsChoice {
  const SettingsChoice({
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

/// Something to press.
class SettingsButtonField extends SettingsField {
  const SettingsButtonField({
    required super.label,
    required this.onPressed,
    super.hint,
    this.icon,
    this.destructive = false,
  });

  final VoidCallback onPressed;
  final IconData? icon;
  final bool destructive;
}

/// A sentence, for something that has to be explained rather than set.
class SettingsNoteField extends SettingsField {
  const SettingsNoteField({
    required super.label,
    super.hint,
    this.warning = false,
    this.icon,
  });

  final bool warning;
  final IconData? icon;
}

/// A heading over the fields that follow.
class SettingsGroupField extends SettingsField {
  const SettingsGroupField({
    required super.label,
    super.hint,
    this.fields = const [],
    this.initiallyOpen = true,
  });

  final List<SettingsField> fields;
  final bool initiallyOpen;
}
