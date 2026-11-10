import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final paperTheme = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );
  final palettes = <String, PremiumThemeExtension>{
    'light': PremiumTheme.resolve(
      appTheme: AppTheme.fallback,
      legacy: AppTheme.fallback.lightTheme,
      brightness: Brightness.light,
    ),
    'dark': PremiumTheme.resolve(
      appTheme: AppTheme.fallback,
      legacy: AppTheme.fallback.darkTheme,
      brightness: Brightness.dark,
    ),
    'paper': PremiumTheme.resolve(
      appTheme: paperTheme,
      legacy: paperTheme.lightTheme,
      brightness: Brightness.light,
    ),
  };
  final dark = palettes['dark']!;
  final light = palettes['light']!;

  test('contrast follows WCAG', () {
    expect(LegibleColor.contrast(Colors.black, Colors.white), closeTo(21, .01));
    expect(LegibleColor.contrast(Colors.white, Colors.black), closeTo(21, .01));
    expect(LegibleColor.contrast(dark.surface, dark.surface), 1);
  });

  test('a colour that already reads is returned untouched', () {
    const github = Color(0xFF24292F);
    expect(LegibleColor.on(light.surface, github), github);
    expect(LegibleColor.on(dark.surface, dark.textPrimary), dark.textPrimary);
  });

  test('every provider accent reads on its tint in light, dark and paper', () {
    final accents = <String, Color>{
      for (final family in ProviderAccountFamily.values)
        'family ${family.name}': family.accent,
      for (final info in ProviderServices.all)
        'service ${info.service.name}': info.accent,
    };
    for (final MapEntry(key: mode, value: palette) in palettes.entries) {
      for (final MapEntry(key: name, value: accent) in accents.entries) {
        for (final wash in const [0.08, 0.14]) {
          final ink = LegibleColor.onWash(palette.surface, accent, wash: wash);
          final fill = Color.alphaBlend(
            ink.withValues(alpha: wash),
            palette.surface,
          );
          expect(
            LegibleColor.contrast(ink, fill),
            greaterThanOrEqualTo(LegibleColor.text),
            reason: '$name on a $wash wash in $mode',
          );
        }
      }
    }
  });

  test('ink becomes chalk on a dark surface instead of a disabled grey', () {
    final github = LegibleColor.on(
      dark.surface,
      ProviderAccountFamily.github.accent,
    );
    expect(github.computeLuminance(), greaterThan(.5));
    expect(
      LegibleColor.contrast(github, dark.surface),
      greaterThanOrEqualTo(LegibleColor.text),
    );
  });

  test('a hue is kept and only lightness moves', () {
    for (final (background, accent) in [
      (dark.surface, ProviderAccountFamily.microsoft.accent),
      (dark.surface, ProviderAccountFamily.immich.accent),
      (palettes['paper']!.surface, ProviderAccountFamily.gitlab.accent),
    ]) {
      final before = HSLColor.fromColor(accent);
      final after = HSLColor.fromColor(LegibleColor.on(background, accent));
      expect(after.hue, closeTo(before.hue, 1.5));
      expect(after.saturation, closeTo(before.saturation, .03));
      expect(after.lightness, isNot(closeTo(before.lightness, .01)));
    }
  });

  test('alpha is kept as given', () {
    final muted = ProviderAccountFamily.github.accent.withValues(alpha: .7);
    expect(LegibleColor.on(dark.surface, muted).a, closeTo(.7, .001));
  });
}
