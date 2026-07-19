import 'package:flutter/material.dart';

abstract final class AppTextRendering {
  static const fontFeatures = <FontFeature>[
    FontFeature.enable('kern'),
    FontFeature.enable('liga'),
  ];

  // A zero-offset underprint reinforces antialiased edges without ghosting.
  static const lightTextUnderprint = <Shadow>[
    Shadow(color: Color(0x0C000000)),
  ];

  static TextStyle rootStyleFor(Brightness brightness) => TextStyle(
        fontFeatures: fontFeatures,
        leadingDistribution: TextLeadingDistribution.even,
        shadows:
            brightness == Brightness.light ? lightTextUnderprint : const [],
      );

  static TextStyle polish(TextStyle style) => style.copyWith(
        fontFeatures: style.fontFeatures ?? fontFeatures,
        leadingDistribution:
            style.leadingDistribution ?? TextLeadingDistribution.even,
      );
}
