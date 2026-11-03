import 'dart:ui';

/// The weight AppFlowy sets ordinary interface and document text at.
const flowyRegularFontWeight = FontWeight.w500;

/// Where each [FontWeight], from w100 to w900, lands on the `wght` axis.
///
/// The bundled Inter ships as static faces cut at exactly these values (see
/// `tool/fonts/build_inter_static.py`), so a [FontWeight] alone selects the
/// right one; variable faces reach the same weights through
/// [flowyFontVariationsForWeight]. Regular sits just under Medium, and each
/// heavier step is held back, so emphasis stays clear without the dense,
/// harsh look semibold and bold take on at small sizes.
const flowyFontWeightAxisValues = <double>[
  200,
  270,
  350,
  440,
  480,
  560,
  640,
  720,
  800,
];

const flowyRegularFontWeightValue = 480.0;
const flowyRegularFontVariations = <FontVariation>[
  FontVariation.weight(flowyRegularFontWeightValue),
];

double flowyFontWeightAxis(FontWeight fontWeight) =>
    flowyFontWeightAxisValues[(fontWeight.value ~/ 100 - 1).clamp(0, 8)];

List<FontVariation> flowyFontVariationsForWeight(FontWeight fontWeight) =>
    <FontVariation>[FontVariation.weight(flowyFontWeightAxis(fontWeight))];

/// The [FontWeight] a hand-written `wght` axis value was meant as.
///
/// A face cut into static weights ignores the axis, so styles that only set
/// one need this to keep their emphasis.
FontWeight flowyFontWeightForAxis(double axis) {
  if (axis < 350) return FontWeight.w300;
  if (axis < 500) return FontWeight.w400;
  if (axis <= 575) return FontWeight.w500;
  if (axis <= 650) return FontWeight.w600;
  if (axis <= 750) return FontWeight.w700;
  return FontWeight.w800;
}
