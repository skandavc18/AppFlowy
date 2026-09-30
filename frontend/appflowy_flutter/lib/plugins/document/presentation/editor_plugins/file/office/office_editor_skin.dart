import 'dart:convert';

import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// AppFlowy's active palette, restated in ONLYOFFICE's interface-theme
/// vocabulary so the editor chrome paints with the same surfaces, ink and
/// accent as the page around it.
@immutable
class OfficeEditorSkin {
  const OfficeEditorSkin({
    required this.isDark,
    required this.desk,
    required this.raised,
    required this.muted,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.onAccent,
    required this.shadow,
    required this.scrim,
  });

  factory OfficeEditorSkin.fromPalette(
    PremiumThemeExtension palette, {
    required bool isDark,
  }) =>
      OfficeEditorSkin._normalized(
        isDark: isDark,
        desk: palette.surface,
        raised: palette.floatingSurface,
        muted: palette.mutedSurface,
        hover: palette.hover,
        pressed: palette.pressed,
        selected: palette.selected,
        border: palette.border,
        borderStrong: palette.borderStrong,
        textPrimary: palette.textPrimary,
        textSecondary: palette.textSecondary,
        textMuted: palette.textMuted,
        accent: palette.accent,
        accentHover: palette.accentHover,
        accentPressed: palette.accentPressed,
        onAccent: palette.onAccent,
        shadow: palette.shadow,
        scrim: palette.scrim,
      );

  factory OfficeEditorSkin.of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = PremiumThemeExtension.maybeOf(context);
    if (palette != null) {
      return OfficeEditorSkin.fromPalette(palette, isDark: isDark);
    }

    // Hosts outside the application theme still honour Paper's stationery.
    final scheme = theme.colorScheme;
    final paper = !isDark && PaperTheme.isEnabled(context);
    return OfficeEditorSkin._normalized(
      isDark: isDark,
      desk: paper
          ? PaperTheme.editorPreviewBackground
          : scheme.surfaceContainerLow,
      raised: paper ? PaperTheme.popupBackground : scheme.surface,
      muted: paper ? PaperTheme.controlBackground : scheme.surfaceContainer,
      hover: paper ? PaperTheme.controlHover : scheme.surfaceContainerHigh,
      pressed:
          paper ? PaperTheme.controlSelected : scheme.surfaceContainerHighest,
      selected:
          paper ? PaperTheme.controlSelectedHover : scheme.secondaryContainer,
      border: paper ? PaperTheme.codeBlockBorder : scheme.outlineVariant,
      borderStrong: paper ? PaperTheme.strongBorder : scheme.outline,
      textPrimary: paper ? PaperTheme.textPrimary : scheme.onSurface,
      textSecondary: paper ? PaperTheme.textSecondary : scheme.onSurfaceVariant,
      textMuted: paper
          ? PaperTheme.textMuted
          : scheme.onSurfaceVariant.withValues(alpha: 0.72),
      accent: paper ? PaperTheme.accent : scheme.primary,
      accentHover: paper ? PaperTheme.accentHover : scheme.primary,
      accentPressed: paper ? PaperTheme.accentPressed : scheme.primary,
      onAccent: paper ? PaperTheme.onAccent : scheme.onPrimary,
      shadow: paper ? PaperTheme.shadow : scheme.shadow,
      scrim: paper ? PaperTheme.scrim : scheme.scrim,
    );
  }

  /// Opaque surfaces and ink, so ONLYOFFICE's canvas renderer (which ignores
  /// alpha in some roles) sees exactly what the CSS paints.
  factory OfficeEditorSkin._normalized({
    required bool isDark,
    required Color desk,
    required Color raised,
    required Color muted,
    required Color hover,
    required Color pressed,
    required Color selected,
    required Color border,
    required Color borderStrong,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color accent,
    required Color accentHover,
    required Color accentPressed,
    required Color onAccent,
    required Color shadow,
    required Color scrim,
  }) {
    final base = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final opaqueDesk = _over(desk, base);
    final opaqueRaised = _over(raised, opaqueDesk);
    Color onRaised(Color color) => _over(color, opaqueRaised);
    return OfficeEditorSkin(
      isDark: isDark,
      desk: opaqueDesk,
      raised: opaqueRaised,
      muted: _over(muted, opaqueDesk),
      hover: onRaised(hover),
      pressed: onRaised(pressed),
      selected: onRaised(selected),
      border: border,
      borderStrong: borderStrong,
      textPrimary: onRaised(textPrimary),
      textSecondary: onRaised(textSecondary),
      textMuted: onRaised(textMuted),
      accent: onRaised(accent),
      accentHover: onRaised(accentHover),
      accentPressed: onRaised(accentPressed),
      onAccent: _over(onAccent, onRaised(accent)),
      shadow: shadow,
      scrim: scrim,
    );
  }

  final bool isDark;

  /// The sheet behind the editor: header band, side panes and the area
  /// around pages. Also the host page and card colour, so no seam shows.
  final Color desk;

  /// Floating chrome: the toolbar card, menus, inputs and the status bar.
  final Color raised;
  final Color muted;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color onAccent;
  final Color shadow;
  final Color scrim;

  /// ONLYOFFICE's own modern theme, kept for its layout, radii and icons.
  String get baseThemeId => officeUiTheme(isDark);

  @override
  bool operator ==(Object other) =>
      other is OfficeEditorSkin &&
      other.isDark == isDark &&
      other.desk == desk &&
      other.raised == raised &&
      other.muted == muted &&
      other.hover == hover &&
      other.pressed == pressed &&
      other.selected == selected &&
      other.border == border &&
      other.borderStrong == borderStrong &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.textMuted == textMuted &&
      other.accent == accent &&
      other.accentHover == accentHover &&
      other.accentPressed == accentPressed &&
      other.onAccent == onAccent &&
      other.shadow == shadow &&
      other.scrim == scrim;

  @override
  int get hashCode => Object.hash(
        isDark,
        desk,
        raised,
        muted,
        hover,
        pressed,
        selected,
        border,
        borderStrong,
        textPrimary,
        textSecondary,
        textMuted,
        accent,
        accentHover,
        accentPressed,
        onAccent,
        shadow,
        scrim,
      );
}

String officeUiTheme(bool isDark) => isDark ? 'theme-night' : 'theme-white';

/// Editor chrome AppFlowy already shows around the document: the file name
/// and product announcements.
const officeChromeCustomization = <String, Object>{
  'toolbarHideFileName': true,
  'suggestFeature': false,
  'features': {'featuresTips': false},
};

String officeCssColor(Color color) => _hex(color);

const _officeEditorKinds = [
  'document',
  'spreadsheet',
  'presentation',
  'pdf',
  'visio',
];

/// ONLYOFFICE interface-theme variables (without the leading `--`) that
/// repaint its modern White/Night theme with [skin].
Map<String, String> officeThemeTokens(OfficeEditorSkin skin) {
  final desk = skin.desk;
  final raised = skin.raised;
  final border = _over(skin.border, raised);
  final borderStrong = _over(skin.borderStrong, raised);
  final text = skin.textPrimary;
  final text2 = skin.textSecondary;
  final text3 = skin.textMuted;
  final accent = skin.accent;
  final thumb = _over(text3.withValues(alpha: 0.36), desk);
  final thumbHover = _over(text3.withValues(alpha: 0.5), desk);
  final thumbPressed = _over(text3.withValues(alpha: 0.64), desk);
  final shadowStrong = skin.isDark ? 0.34 : 0.12;
  final shadowSoft = skin.isDark ? 0.2 : 0.07;
  final shadow = _rgba(skin.shadow, shadowStrong);
  final shadowTight = _rgba(skin.shadow, shadowSoft);

  final colors = <String, Color>{
    for (final kind in _officeEditorKinds) ...{
      'toolbar-header-$kind': desk,
      'highlight-header-tab-underline-$kind': accent,
      'highlight-toolbar-tab-underline-$kind': accent,
    },
    'background-normal': raised,
    'background-toolbar': raised,
    'background-toolbar-tab': raised,
    'background-toolbar-additional': skin.muted,
    'background-pane': desk,
    'background-contrast-popover': raised,
    'border-contrast-popover': skin.isDark ? borderStrong : raised,
    'background-primary-dialog-button': accent,
    'background-accent-button': accent,
    'highlight-button-hover': skin.hover,
    'highlight-button-pressed': skin.pressed,
    'highlight-button-pressed-hover':
        _over(text.withValues(alpha: 0.06), skin.pressed),
    'highlight-primary-dialog-button-hover': skin.accentHover,
    'highlight-primary-dialog-button-pressed': skin.accentPressed,
    'highlight-header-button-hover': skin.hover,
    'highlight-header-button-pressed': skin.pressed,
    'highlight-text-select': accent,
    'highlight-comment-hover': skin.hover,
    'highlight-comment-pressed': skin.selected,
    'border-toolbar': borderStrong,
    'border-toolbar-active-panel-top': desk,
    'border-divider': border,
    'border-regular-control': borderStrong,
    'border-preview-hover': _over(accent.withValues(alpha: 0.45), raised),
    'border-preview-select': accent,
    'border-control-focus': accent,
    'border-button-pressed-focus': accent,
    'border-fill-input-focused': accent,
    'text-normal': text,
    'text-normal-pressed': text,
    'text-secondary': text2,
    'text-tertiary': text3,
    'text-link': accent,
    'text-link-visited': accent,
    'text-link-hover': skin.accentHover,
    'text-link-active': skin.accentHover,
    'text-inverse': skin.onAccent,
    'text-toolbar-header': text,
    'text-contrast-background': skin.onAccent,
    'icon-normal': text,
    'icon-normal-pressed': text,
    'icon-toolbar-header': text2,
    'icon-gray-primary': text,
    'icon-gray-secondary': text3,
    'icon-blue-primary': accent,
    'icon-blue-secondary': _over(accent.withValues(alpha: 0.18), raised),
    'canvas-background': desk,
    'canvas-page-border': _over(skin.borderStrong, desk),
    'canvas-ruler-background': raised,
    'canvas-ruler-border': borderStrong,
    'canvas-ruler-margins-background': skin.pressed,
    'canvas-ruler-mark': text2,
    'canvas-ruler-handle-border': text2,
    'canvas-ruler-handle-border-disabled': text3,
    'canvas-high-contrast': text,
    'canvas-high-contrast-disabled': text3,
    'canvas-cell-title-background': skin.muted,
    'canvas-cell-title-background-hover': skin.hover,
    'canvas-cell-title-background-selected': skin.pressed,
    'canvas-cell-title-border': _over(skin.borderStrong, skin.muted),
    'canvas-cell-title-border-hover': _over(skin.borderStrong, skin.hover),
    'canvas-cell-title-border-selected':
        _over(text3.withValues(alpha: 0.55), skin.pressed),
    'canvas-cell-title-text': text2,
    'canvas-select-all-icon': text3,
    'canvas-scroll-thumb': thumb,
    'canvas-scroll-thumb-border': thumb,
    'canvas-scroll-thumb-hover': thumbHover,
    'canvas-scroll-thumb-border-hover': thumbHover,
    'canvas-scroll-thumb-pressed': thumbPressed,
    'canvas-scroll-thumb-border-pressed': thumbPressed,
    'canvas-scroll-arrow': text3,
    'canvas-scroll-arrow-hover': text2,
    'canvas-scroll-arrow-pressed': text,
    'canvas-scroll-thumb-target': thumbPressed,
    'canvas-scroll-thumb-target-hover': text3,
    'canvas-scroll-thumb-target-pressed': text2,
    'canvas-anim-pane-background': raised,
    for (final control in ['chb', 'rb']) ...{
      '$control-background-normal-hover': skin.hover,
      '$control-background-checked-hover': skin.hover,
      '$control-border-normal': text3,
      '$control-border-checked': text3,
      '$control-border-normal-hover': text2,
      '$control-border-checked-hover': text2,
      '$control-border-normal-focus': accent,
      '$control-border-checked-focus': accent,
    },
    'slider-track-background-normal': skin.pressed,
    'slider-track-background-filled': accent,
    'slider-thumb-background-normal': accent,
    'slider-thumb-background-hover': skin.accentHover,
    'slider-thumb-background-active': skin.accentPressed,
    'slider-thumb-border-normal': raised,
  };

  return {
    for (final entry in colors.entries) entry.key: _hex(entry.value),
    'background-scrim': _rgba(skin.scrim, 0.2),
    'highlight-category-button-hover': _rgba(accent, 0.06),
    'highlight-category-button-pressed': _rgba(accent, 0.12),
    'shadow-toolbar': '0 1px 3px 0 $shadow, 0 1px 2px 0 $shadowTight',
    'shadow-toolbar-style-off': '0 1px 2px 0 $shadowTight',
    'shadow-side-panel': '0 4px 6px -1px $shadow, 0 2px 4px -1px $shadowTight',
  };
}

/// The loading placeholder ONLYOFFICE paints before its interface boots.
String officeSkeletonCss(OfficeEditorSkin skin) {
  final shadow = _rgba(skin.shadow, skin.isDark ? 0.34 : 0.12);
  final shadowTight = _rgba(skin.shadow, skin.isDark ? 0.2 : 0.07);
  final variables = {
    'sk-background-toolbar': _hex(skin.desk),
    'sk-background-toolbar-header-cell': _hex(skin.desk),
    'sk-canvas-background': _hex(skin.desk),
    'sk-background-toolbar-controls': _hex(skin.raised),
    'sk-background-toolbar-tab': _hex(skin.hover),
    'sk-background-toolbar-button': _hex(skin.hover),
    'sk-canvas-page-border': _hex(_over(skin.borderStrong, skin.desk)),
    'sk-shadow-toolbar':
        '0px 1px 3px 0px $shadow, 0px 1px 2px 0px $shadowTight',
  };
  final declarations = variables.entries
      .map((entry) => '--${entry.key}:${entry.value} !important;')
      .join();
  return '.loadmask{$declarations}';
}

/// The cached interface theme ONLYOFFICE applies before its first paint.
///
/// `!important` lets these values win over the stock `:root .theme-white`
/// rule while keeping everything that theme does not colour.
Map<String, Object?> officeStoredUiTheme(OfficeEditorSkin skin) => {
      'id': skin.baseThemeId,
      'type': skin.isDark ? 'dark' : 'light',
      'colors': {
        for (final entry in officeThemeTokens(skin).entries)
          entry.key: '${entry.value} !important',
      },
      'skeleton': {'css': officeSkeletonCss(skin)},
    };

String officeStoredUiThemeJson(OfficeEditorSkin skin) =>
    jsonEncode(officeStoredUiTheme(skin));

Color _over(Color top, Color bottom) =>
    Color.alphaBlend(top, bottom).withValues(alpha: 1);

int _channel(double value) => (value * 255).round().clamp(0, 255);

String _hex(Color color) {
  final rgb =
      (_channel(color.r) << 16) | (_channel(color.g) << 8) | _channel(color.b);
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String _rgba(Color color, double alpha) =>
    'rgba(${_channel(color.r)},${_channel(color.g)},${_channel(color.b)},'
    '${alpha.toStringAsFixed(2)})';
