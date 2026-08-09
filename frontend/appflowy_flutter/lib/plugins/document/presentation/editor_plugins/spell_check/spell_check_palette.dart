import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:flutter/material.dart';

/// The colours the two kinds of mistake are drawn in.
///
/// They are tuned separately for every appearance: a red that reads on paper
/// is too soft on a dark canvas, and one that reads on a dark canvas shouts on
/// ivory. Nothing is filled and nothing is coloured except the underline.
@immutable
class SpellCheckPalette {
  const SpellCheckPalette({
    required this.spelling,
    required this.grammar,
    required this.thickness,
  });

  final Color spelling;
  final Color grammar;
  final double thickness;

  static const _light = SpellCheckPalette(
    spelling: Color(0xFFC5372F),
    grammar: Color(0xFF5B5BD6),
    thickness: 1.1,
  );

  static const _dark = SpellCheckPalette(
    spelling: Color(0xFFF07A70),
    grammar: Color(0xFF9B98F5),
    thickness: 1.2,
  );

  /// Paper is deliberately the quietest of the three — the whole point of the
  /// mode is a page that looks printed.
  static const _paper = SpellCheckPalette(
    spelling: Color(0xFFA8443A),
    grammar: Color(0xFF60598F),
    thickness: 1.0,
  );

  static SpellCheckPalette of(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return _dark;
    }
    return PaperTheme.isEnabled(context) ? _paper : _light;
  }

  Color colorFor(SpellIssueKind kind) =>
      kind.isSpelling ? spelling : grammar;

  TextStyle styleFor(SpellIssueKind kind) => TextStyle(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.wavy,
        decorationColor: colorFor(kind),
        decorationThickness: thickness,
      );
}
