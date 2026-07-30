import 'package:appflowy/shared/object_type_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emphasizeTableCellText', () {
    test('lifts ordinary body copy to the emphasis weight', () {
      const body = TextStyle(fontWeight: FontWeight.w500);

      final emphasized = ObjectTypeTypography.emphasizeTableCellText(body);

      expect(emphasized.fontWeight, ObjectTypeTypography.emphasisFontWeight);
    });

    test('never reaches the weight a hand-bolded span already uses', () {
      const body = TextStyle(fontWeight: FontWeight.w400);

      final emphasized = ObjectTypeTypography.emphasizeTableCellText(body);

      expect(emphasized.fontWeight!.value, lessThan(FontWeight.bold.value));
    });

    test('holds when the body is already at or above the emphasis weight', () {
      // Windows body copy is Segoe UI Semibold, so there is nowhere lighter to
      // go without erasing the difference from the rows beneath.
      for (final weight in [FontWeight.w600, FontWeight.w700]) {
        final emphasized = ObjectTypeTypography.emphasizeTableCellText(
          TextStyle(fontWeight: weight),
        );

        expect(emphasized.fontWeight, weight);
      }
    });

    test('moves the variable axis with the weight', () {
      const body = TextStyle(
        fontWeight: FontWeight.w500,
        fontVariations: [FontVariation.weight(550)],
      );

      final emphasized = ObjectTypeTypography.emphasizeTableCellText(body);

      // A variable face ignores fontWeight and reads the axis, so leaving the
      // axis behind renders the header at body weight.
      expect(
        emphasized.fontVariations,
        [FontVariation.weight(ObjectTypeTypography.emphasisFontWeight.value.toDouble())],
      );
    });

    test('leaves a heavier variable axis alone', () {
      const body = TextStyle(
        fontWeight: FontWeight.w500,
        fontVariations: [FontVariation.weight(680)],
      );

      final emphasized = ObjectTypeTypography.emphasizeTableCellText(body);

      expect(emphasized.fontVariations, [const FontVariation.weight(680)]);
    });

    test('keeps axes it does not own', () {
      const body = TextStyle(
        fontWeight: FontWeight.w400,
        fontVariations: [
          FontVariation('wdth', 90),
          FontVariation.weight(400),
        ],
      );

      final emphasized = ObjectTypeTypography.emphasizeTableCellText(body);

      expect(emphasized.fontVariations, [
        const FontVariation('wdth', 90),
        FontVariation.weight(
          ObjectTypeTypography.emphasisFontWeight.value.toDouble(),
        ),
      ]);
    });
  });
}
