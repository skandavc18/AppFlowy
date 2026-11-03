import 'package:flutter/foundation.dart';
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

  /// How far document text is softened, in logical pixels, where the window
  /// is resampled to a fractional display scale.
  ///
  /// GTK 3 draws only at whole scales, so at 133 % GNOME shows the 2x frame
  /// through bilinear sampling, which lands each stroke differently and
  /// leaves body text grainy. Softening the glyphs slightly first lets that
  /// sampling come out smooth, close to macOS font smoothing. Chosen side by
  /// side on a 133 % display.
  static const documentTextSmoothing = 0.19;

  static const _smoothing =
      MaskFilter.blur(BlurStyle.normal, documentTextSmoothing);

  // One paint per colour, so rebuilding a paragraph doesn't repaint it.
  static final _smoothPaints = <Color, Paint>{};

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

  /// Whether this view's text reaches the screen through such a resample:
  /// on Linux, GTK draws at 2x or more for any display scale above 100 %.
  static bool smoothsDocumentText(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.linux &&
      (View.maybeOf(context)?.devicePixelRatio ?? 1) >= 2;

  /// [span] with every coloured run drawn through [documentTextSmoothing].
  ///
  /// The colour moves into a foreground paint, which keeps text colours,
  /// links and highlights as they were. Inline widgets and runs that already
  /// paint themselves are left alone.
  static InlineSpan smoothDocumentText(InlineSpan span) {
    if (span is! TextSpan) {
      return span;
    }
    final style = span.style;
    final smoothedStyle = style == null ? null : _smoothStyle(style);
    var changed = !identical(style, smoothedStyle);
    final children = span.children;
    List<InlineSpan>? smoothedChildren;
    if (children != null) {
      smoothedChildren = [
        for (final child in children) smoothDocumentText(child),
      ];
      for (var i = 0; i < children.length && !changed; i++) {
        changed = !identical(children[i], smoothedChildren[i]);
      }
    }
    if (!changed) {
      return span;
    }
    return TextSpan(
      text: span.text,
      children: smoothedChildren,
      style: smoothedStyle,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  static TextStyle _smoothStyle(TextStyle style) {
    final color = style.color;
    if (color == null || style.foreground != null) {
      return style;
    }
    if (_smoothPaints.length > 256) {
      _smoothPaints.clear();
    }
    final paint = _smoothPaints.putIfAbsent(
      color,
      () => Paint()
        ..color = color
        ..maskFilter = _smoothing,
    );
    return style.copyWith(
      foreground: paint,
      decorationColor: style.decorationColor ?? color,
    );
  }
}
