import 'dart:math' as math;

import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in ['light', 'dark', 'paper']) {
    final palette = _palette(mode);
    final dark = mode == 'dark';
    final brightness = dark ? Brightness.dark : Brightness.light;
    final surfaces = [
      palette.canvas,
      palette.surface,
      palette.floatingSurface,
      palette.mutedSurface,
      palette.sidebar,
    ];

    test('$mode: chrome and surfaces are warm with readable hover ink', () {
      expect(
        palette.sidebar,
        switch (mode) {
          'paper' => PaperTheme.chromeBackground,
          'dark' => PremiumTheme.darkChrome,
          _ => PremiumTheme.lightChrome,
        },
      );
      for (final surface in surfaces) {
        for (final color in [surface, palette.hoverOn(surface)]) {
          expect(color.a, 1);
          expect(color.r, greaterThan(color.g));
          expect(color.g, greaterThan(color.b));
          expect(
            color.computeLuminance(),
            dark ? lessThan(0.06) : greaterThan(0.70),
            reason: 'Dark gets warm charcoal, never a cream overlay surface.',
          );
          expect(
              _contrast(palette.textPrimary, color), greaterThanOrEqualTo(7));
          expect(_contrast(palette.textSecondary, color),
              greaterThanOrEqualTo(4.5));
          expect(_contrast(palette.accent, color), greaterThanOrEqualTo(3));
        }
      }
    });

    test('$mode: composited hover is quiet, not invisible or selected', () {
      for (final surface in surfaces) {
        final hover = palette.hoverOn(surface);
        final pressed = palette.pressedOn(surface);
        final selected = palette.selectedOn(surface);
        final delta = _difference(surface, hover);

        expect(delta, inExclusiveRange(0.003, 0.055));
        expect(_contrast(surface, hover), lessThan(1.30));
        expect(_difference(surface, pressed), greaterThan(delta * 1.5));
        expect(_difference(surface, selected), greaterThan(delta * 1.5));
        expect(_difference(selected, hover), greaterThan(0.015));
        expect(_contrast(palette.accent, selected), greaterThanOrEqualTo(3));
        expect(
          _difference(selected, palette.hoverOn(selected)),
          lessThan(0.055),
          reason: 'Hover adds a wash; it must not replace a selected surface.',
        );
      }
    });

    test('$mode: semantic hover layers blend over their own resting surface',
        () {
      final defaults = AppFlowyDefaultTheme();
      final theme = PremiumTheme.appFlowyTheme(
        base: dark ? defaults.dark() : defaults.light(),
        palette: palette,
        brightness: brightness,
      );
      final fill = theme.fillColorScheme;
      final surface = theme.surfaceColorScheme;
      for (final (rest, hover) in [
        (fill.primary, fill.primaryHover),
        (fill.secondary, fill.secondaryHover),
        (surface.primary, surface.primaryHover),
        (surface.layer01, surface.layer01Hover),
        (surface.layer02, surface.layer02Hover),
        (surface.layer03, surface.layer03Hover),
        (surface.layer04, surface.layer04Hover),
      ]) {
        expect(hover, palette.hoverOn(rest));
        expect(_difference(rest, hover), lessThan(0.055));
      }
      expect(fill.content, palette.subtleHover.withValues(alpha: 0));
      expect(fill.contentHover, palette.subtleHover);
      expect(fill.themeSelect, palette.selectedOverlay);
      expect(fill.contentVisible, palette.selectedOverlay);
      expect(fill.contentVisibleHover, palette.focusRing);
      expect(fill.errorThick, isNot(fill.contentHover));
      expect(
          theme.textColorScheme.error, isNot(theme.textColorScheme.tertiary));
    });

    test('$mode: native focus is opaque; hover does not change ink or fields',
        () {
      final app = mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((t) => t.themeName == BuiltInTheme.paper)
          : AppTheme.fallback;
      final theme = PremiumTheme.materialTheme(
        legacy: dark ? app.darkTheme : app.lightTheme,
        palette: palette,
        brightness: brightness,
        fontFamily: 'Ahem',
        textTheme: ThemeData(brightness: brightness).textTheme,
        isDesktop: true,
      );
      for (final style in [
        theme.textButtonTheme.style!,
        theme.iconButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
      ]) {
        final ring = style.side!.resolve({WidgetState.focused})!;
        expect(ring.color, palette.accent);
        expect(ring.color.a, 1);
        expect(_contrast(ring.color, palette.sidebar), greaterThanOrEqualTo(3));
        expect(
          style.foregroundColor!.resolve({WidgetState.hovered}),
          style.foregroundColor!.resolve({}),
        );
        expect(
          style.foregroundColor!.resolve({WidgetState.disabled}),
          isNot(style.foregroundColor!.resolve({})),
        );
        expect(
          style.backgroundColor!
              .resolve({WidgetState.disabled, WidgetState.hovered})!.a,
          0,
        );
        expect(style.animationDuration, const Duration(milliseconds: 140));
      }
      expect(theme.inputDecorationTheme.filled, isNot(true));
      expect(theme.inputDecorationTheme.focusedBorder, isNull);
      expect(theme.inputDecorationTheme.enabledBorder, isNull);
    });
  }

  test(
      'custom low-alpha washes retain alpha and composite the supplied surface',
      () {
    final original = _palette('paper');
    for (final alpha in [0.0, 1 / 255, 0.02, 0.5, 1.0]) {
      final palette = original.copyWith(
        hoverOverlay: const Color(0xFF8B6042).withValues(alpha: alpha),
      );
      final wash = palette.subtleHover;
      expect(wash.a, closeTo((alpha * 0.65).clamp(0.0, 0.07), 1e-9));
      expect(wash.withValues(alpha: 1), const Color(0xFF8B6042));
      for (final surface in [
        const Color(0xFF342922),
        const Color(0xFFF3E9D6)
      ]) {
        expect(palette.hoverOn(surface), Color.alphaBlend(wash, surface));
        expect(palette.hoverOn(surface).a, 1);
      }
      expect(palette.selected, original.selected);
      expect(palette.focusRing, original.focusRing);
    }
  });
}

PremiumThemeExtension _palette(String mode) {
  final app = mode == 'paper'
      ? AppTheme.builtins
          .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
      : AppTheme.fallback;
  final dark = mode == 'dark';
  return PremiumTheme.resolve(
    appTheme: app,
    legacy: dark ? app.darkTheme : app.lightTheme,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
}

double _difference(Color a, Color b) =>
    math.max((a.r - b.r).abs(), math.max((a.g - b.g).abs(), (a.b - b.b).abs()));

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}
