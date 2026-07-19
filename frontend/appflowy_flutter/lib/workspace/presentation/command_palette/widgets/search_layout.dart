import 'dart:math' as math;

const commandPalettePreviewBreakpoint = 720.0;
const commandPaletteListMaxWidth = 470.0;
const commandPaletteListWidthFactor = 0.54;

double commandPaletteListWidth(double availableWidth) => math.min(
      commandPaletteListMaxWidth,
      availableWidth * commandPaletteListWidthFactor,
    );
