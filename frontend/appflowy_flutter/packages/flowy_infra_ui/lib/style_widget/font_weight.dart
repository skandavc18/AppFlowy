import 'dart:ui';

const flowyRegularFontWeight = FontWeight.w500;
const flowyRegularFontWeightValue = 550.0;
const flowyRegularFontVariations = <FontVariation>[
  FontVariation.weight(flowyRegularFontWeightValue),
];

List<FontVariation> flowyFontVariationsForWeight(FontWeight fontWeight) {
  final value = fontWeight == flowyRegularFontWeight
      ? flowyRegularFontWeightValue
      : fontWeight.value.toDouble();
  return <FontVariation>[FontVariation.weight(value)];
}
