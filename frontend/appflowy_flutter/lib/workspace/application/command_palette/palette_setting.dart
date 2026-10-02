import 'dart:async';

import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart'
    show SettingsPage;
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

/// How many choices a setting may have and still show them all in its row.
/// Beyond this the row opens a list of its own.
const paletteInlineChoiceLimit = 3;

/// The heading a setting is listed under. The order is the order the
/// headings are offered in.
enum PaletteSettingSection {
  appearance,
  editor,
  language,
  ai,
  notifications,
  privacy,
  extensions,
}

/// One possible value of a setting that picks between several.
@immutable
class PaletteSettingOption {
  const PaletteSettingOption({
    required this.id,
    required this.label,
    this.description = '',
    this.icon,
    this.keywords = const <String>[],
  });

  final String id;
  final String label;
  final String description;
  final IconData? icon;

  /// Words the option answers to besides its label, such as the English name
  /// of a language.
  final List<String> keywords;
}

/// How a setting is changed straight from its row.
sealed class PaletteSettingControl {
  const PaletteSettingControl();
}

/// On or off.
final class PaletteToggle extends PaletteSettingControl {
  const PaletteToggle({required this.value, required this.onChanged});

  final bool value;
  final FutureOr<void> Function(bool value) onChanged;
}

/// One of several values.
final class PaletteChoice extends PaletteSettingControl {
  const PaletteChoice({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PaletteSettingOption> options;
  final String? selectedId;
  final FutureOr<void> Function(PaletteSettingOption option) onSelected;

  /// Whether every option fits in the row itself.
  bool get isInline => options.length <= paletteInlineChoiceLimit;

  PaletteSettingOption? get selected =>
      options.firstWhereOrNull((option) => option.id == selectedId);

  /// The option [offset] places after the selected one, wrapping round, or
  /// null when there is nothing else to choose.
  PaletteSettingOption? step(int offset) {
    if (options.length < 2) {
      return null;
    }
    final at = options.indexWhere((option) => option.id == selectedId);
    final from = at < 0 ? (offset > 0 ? -1 : 0) : at;
    return options[(from + offset) % options.length];
  }
}

/// A number moved up and down in steps.
final class PaletteStepper extends PaletteSettingControl {
  const PaletteStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double step;

  /// How [value] reads, such as "110%".
  final String Function(double value) label;
  final FutureOr<void> Function(double value) onChanged;

  static const _tolerance = 1e-6;

  bool get canDecrease => value - min > _tolerance;

  bool get canIncrease => max - value > _tolerance;

  /// The value one step in [direction], kept inside the range and rounded so
  /// repeated steps do not drift (0.1 + 0.2 is not 0.3 in binary).
  double stepped(int direction) {
    final next = (value + direction.sign * step).clamp(min, max);
    return double.parse(next.toStringAsFixed(4));
  }
}

/// Something done rather than a value set, such as locking encrypted pages.
final class PaletteAction extends PaletteSettingControl {
  const PaletteAction({required this.label, required this.run});

  final String label;
  final FutureOr<void> Function() run;
}

/// One setting the palette can find and change in place.
@immutable
class PaletteSetting {
  const PaletteSetting({
    required this.id,
    required this.title,
    required this.section,
    required this.icon,
    required this.control,
    this.description = '',
    this.keywords = const <String>[],
    this.settingsPage,
  });

  /// Stable identity, used as the widget key and by the tests.
  final String id;
  final String title;
  final String description;
  final PaletteSettingSection section;
  final IconData icon;
  final PaletteSettingControl control;

  /// Extra words the setting answers to, so "dark" finds "Appearance".
  final List<String> keywords;

  /// Where the whole of this setting lives in Settings, if anywhere.
  final SettingsPage? settingsPage;

  /// Everything a search may match besides the title and description:
  /// the keywords, and the names of the values it can take, so "lavender"
  /// finds the theme setting.
  Iterable<String> get searchTerms sync* {
    yield* keywords;
    final control = this.control;
    if (control is PaletteChoice) {
      for (final option in control.options) {
        yield option.label;
        yield* option.keywords;
      }
    }
  }
}

/// The settings matching [query], best first, judged the way commands are.
List<PaletteSetting> rankPaletteSettings(
  List<PaletteSetting> settings,
  String query, {
  int limit = 40,
}) =>
    rankPaletteMatches(
      settings,
      query,
      limit: limit,
      title: (setting) => setting.title,
      subtitle: (setting) => setting.description,
      keywords: (setting) => setting.searchTerms,
    );

/// The options of a long choice matching [query], best first.
List<PaletteSettingOption> rankPaletteOptions(
  List<PaletteSettingOption> options,
  String query,
) =>
    rankPaletteMatches(
      options,
      query,
      limit: options.length,
      title: (option) => option.label,
      subtitle: (option) => option.description,
      keywords: (option) => option.keywords,
    );
