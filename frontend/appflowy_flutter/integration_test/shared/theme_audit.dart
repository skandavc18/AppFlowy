import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

/// The three looks every surface has to hold up in. Paper's dark mode is the
/// workspace dark palette, so it is covered by [dark].
enum AuditMode {
  light(BuiltInTheme.defaultTheme, ThemeMode.light),
  dark(BuiltInTheme.defaultTheme, ThemeMode.dark),
  paper(BuiltInTheme.paper, ThemeMode.light);

  const AuditMode(this.theme, this.themeMode);

  final String theme;
  final ThemeMode themeMode;
}

/// One painted text or icon glyph whose ink does not read on what is behind
/// it, measured on the rendered frame.
class LegibilityFinding {
  const LegibilityFinding({
    required this.surface,
    required this.text,
    required this.ratio,
    required this.minimum,
    required this.ink,
    required this.background,
    required this.rect,
    required this.owner,
    required this.glyph,
  });

  final String surface;
  final String text;
  final double ratio;
  final double minimum;
  final Color ink;
  final Color background;
  final Rect rect;
  final String owner;
  final bool glyph;

  String get severity => ratio < 2
      ? 'INVISIBLE'
      : ratio < 3
          ? 'POOR'
          : 'BELOW-AA';

  Map<String, Object> toJson() => {
        'surface': surface,
        'severity': severity,
        'ratio': double.parse(ratio.toStringAsFixed(2)),
        'minimum': minimum,
        'text': text,
        'glyph': glyph,
        'ink': _hex(ink),
        'background': _hex(background),
        'rect': [rect.left, rect.top, rect.width, rect.height]
            .map((v) => v.round())
            .toList(),
        'owner': owner,
      };
}

String _hex(Color color) {
  String channel(double value) =>
      (value * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}'
      .toUpperCase();
}

/// Drives one audit run: switches the look, writes a screenshot of each
/// surface it is shown, and scans every painted paragraph for legibility.
class ThemeAudit {
  ThemeAudit(this.tester, this.root);

  final WidgetTester tester;
  final Directory root;
  final List<LegibilityFinding> findings = [];
  final List<String> notes = [];
  final List<String> glare = [];

  /// The surface captured last, so an error raised while the next one is
  /// being opened can be traced to where it happened.
  String _lastSurface = 'start';

  Future<void> settle({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        timeout,
      );
    } on FlutterError {
      // Spinners and carets never settle; a bounded wait is enough to paint.
    }
  }

  Future<void> pumpFor(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Sizes the real window and drops the test surface override, so a logical
  /// pixel is a captured pixel. With an override the binding letterboxes and
  /// scales the frame, and nothing measured on it lines up.
  Future<void> fitWindow(Size size) async {
    await windowManager.setSize(size);
    await pumpFor(const Duration(milliseconds: 500));
    await tester.binding.setSurfaceSize(null);
    await settle();
    final view = tester.view;
    note(
      'window ${view.physicalSize.width.round()}x'
      '${view.physicalSize.height.round()} at ${view.devicePixelRatio}x',
    );
  }

  Future<void> apply(AuditMode mode) async {
    final cubit = tester
        .element(find.byType(Overlay).first)
        .read<AppearanceSettingsCubit>();
    await cubit.setTheme(mode.theme);
    cubit.setThemeMode(mode.themeMode);
    await pumpFor(const Duration(milliseconds: 900));
    await settle();
  }

  /// Screenshots the frame and scans it. [within] restricts the scan to one
  /// subtree, such as a dialog, so text behind a scrim is not judged.
  Future<void> capture(
    AuditMode mode,
    String name, {
    Finder? within,
  }) async {
    await settle();
    final surface = '${mode.name}/$name';
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      view.paintBounds,
      pixelRatio: 1 / view.flutterView.devicePixelRatio,
    );
    final ByteData png;
    final ByteData pixels;
    final int width;
    final int height;
    try {
      png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      pixels = (await image.toByteData())!;
      width = image.width;
      height = image.height;
    } finally {
      image.dispose();
    }
    final file = File(p.join(root.path, mode.name, '$name.png'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);

    final frame = _Frame(pixels, width, height, width / view.size.width);
    final screen =
        Offset.zero & (Size(width.toDouble(), height.toDouble()) / frame.scale);
    Finder scoped(Finder matching) => within == null
        ? matching
        : find.descendant(of: within, matching: matching);

    for (final element in scoped(find.byType(RichText)).evaluate()) {
      final paragraph = element.renderObject;
      if (paragraph is RenderParagraph) {
        _record(_inspectText(paragraph, frame, screen, surface));
      }
    }
    for (final element in scoped(find.byType(FlowySvg)).evaluate()) {
      _record(_inspectSvg(element, frame, screen, surface));
    }
    if (within == null) {
      _glare(mode, frame, surface);
    }
    _lastSurface = surface;
  }

  void _record(LegibilityFinding? finding) {
    if (finding != null) {
      findings.add(finding);
    }
  }

  /// Where [box] is actually seen on screen and how opaque it is drawn, or
  /// null when it is clipped away, faded out or mostly off screen.
  static ({Rect visible, double opacity})? _visibility(
    RenderBox box,
    Rect screen,
  ) {
    if (!box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    var visible = bounds.intersect(screen);
    var opacity = 1.0;
    RenderObject child = box;
    RenderObject? parent = box.parent;
    while (parent != null) {
      if (parent is RenderOpacity) {
        opacity *= parent.opacity;
      } else if (parent is RenderAnimatedOpacity) {
        opacity *= parent.opacity.value;
      } else if (parent is RenderOffstage && parent.offstage) {
        return null;
      }
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      if (visible.width < 2 || visible.height < 2 || opacity < 0.05) {
        return null;
      }
      child = parent;
      parent = parent.parent;
    }
    if (visible.width * visible.height < bounds.width * bounds.height * 0.4) {
      return null;
    }
    return (visible: visible, opacity: opacity);
  }

  LegibilityFinding? _inspectText(
    RenderParagraph paragraph,
    _Frame frame,
    Rect screen,
    String surface,
  ) {
    final text = paragraph.text.toPlainText().trim();
    if (text.isEmpty) {
      return null;
    }
    final style = _dominantStyle(paragraph.text);
    final color = style?.color;
    if (style == null || color == null || style.foreground != null) {
      return null;
    }
    final seen = _visibility(paragraph, screen);
    if (seen == null) {
      return null;
    }
    final glyph = _isGlyph(text, style);
    final size = style.fontSize ?? 14;
    final bold = (style.fontWeight?.value ?? 400) >= 700;
    return _judge(
      surface: surface,
      text: text,
      color: color,
      seen: seen,
      frame: frame,
      minimum: glyph || size >= 24 || (bold && size >= 18.66)
          ? LegibleColor.glyph
          : LegibleColor.text,
      glyph: glyph,
      owner: paragraph,
    );
  }

  LegibilityFinding? _inspectSvg(
    Element element,
    _Frame frame,
    Rect screen,
    String surface,
  ) {
    final svg = element.widget as FlowySvg;
    final box = element.renderObject;
    // Only these blend modes repaint the artwork in [color]; the rest keep
    // the SVG's own colours, which this cannot know.
    const recolouring = {BlendMode.srcIn, BlendMode.srcATop, BlendMode.src};
    if (!recolouring.contains(svg.blendMode) || box is! RenderBox) {
      return null;
    }
    final color = svg.color ?? Theme.of(element).iconTheme.color;
    final seen = _visibility(box, screen);
    if (color == null || seen == null) {
      return null;
    }
    return _judge(
      surface: surface,
      text: 'svg ${svg.svg.path.split('/').last}',
      color: color.withValues(alpha: color.a * (svg.opacity ?? 1)),
      seen: seen,
      frame: frame,
      minimum: LegibleColor.glyph,
      glyph: true,
      owner: box,
    );
  }

  LegibilityFinding? _judge({
    required String surface,
    required String text,
    required Color color,
    required ({Rect visible, double opacity}) seen,
    required _Frame frame,
    required double minimum,
    required bool glyph,
    required RenderObject owner,
  }) {
    if (color.a * seen.opacity < 0.05) {
      // Painted transparent on purpose, like a placeholder awaiting focus.
      return null;
    }
    // A glyph can fill most of its own box, so what is behind it is read from
    // a ring just outside; a line of text is mostly the surface it sits on.
    final background = glyph
        ? frame.dominant(seen.visible.inflate(3), excluding: seen.visible)
        : frame.dominant(seen.visible);
    if (background == null) {
      return null;
    }
    final ink = Color.alphaBlend(
      color.withValues(alpha: color.a * seen.opacity),
      background,
    );
    final ratio = LegibleColor.contrast(ink, background);
    if (ratio >= minimum) {
      return null;
    }
    // Something painted over the ink (a menu, a scrim) leaves none of it in
    // the frame; only near-invisible ink cannot be told apart that way.
    if (ratio >= 1.6 && !frame.contains(seen.visible, ink)) {
      return null;
    }
    return LegibilityFinding(
      surface: surface,
      text: text.length > 60 ? '${text.substring(0, 57)}...' : text,
      ratio: ratio,
      minimum: minimum,
      ink: ink,
      background: background,
      rect: seen.visible,
      owner: _owner(owner),
      glyph: glyph,
    );
  }

  /// Large panels that ignore the theme: a sheet of near-white in dark mode,
  /// or of near-black in the light looks. Media legitimately does both, so
  /// these are leads to look at rather than verdicts.
  void _glare(AuditMode mode, _Frame frame, String surface) {
    const tile = 24;
    final dark = mode == AuditMode.dark;
    final columns = frame.width ~/ tile;
    final rows = frame.height ~/ tile;
    final hot = List.generate(rows, (_) => List.filled(columns, false));
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        hot[row][column] = frame.uniformlyExtreme(
          column * tile,
          row * tile,
          tile,
          light: dark,
        );
      }
    }
    final seen = List.generate(rows, (_) => List.filled(columns, false));
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        if (!hot[row][column] || seen[row][column]) {
          continue;
        }
        var count = 0;
        var left = column, right = column, top = row, bottom = row;
        final stack = [(row, column)];
        seen[row][column] = true;
        while (stack.isNotEmpty) {
          final (r, c) = stack.removeLast();
          count++;
          left = c < left ? c : left;
          right = c > right ? c : right;
          top = r < top ? r : top;
          bottom = r > bottom ? r : bottom;
          for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nr = r + dr, nc = c + dc;
            if (nr >= 0 &&
                nc >= 0 &&
                nr < rows &&
                nc < columns &&
                hot[nr][nc] &&
                !seen[nr][nc]) {
              seen[nr][nc] = true;
              stack.add((nr, nc));
            }
          }
        }
        if (count >= 12) {
          glare.add(
            '$surface: ${dark ? 'light' : 'dark'} panel '
            '${(right - left + 1) * tile}x${(bottom - top + 1) * tile} '
            'at ${left * tile},${top * tile}',
          );
        }
      }
    }
  }

  static TextStyle? _dominantStyle(InlineSpan root) {
    final weights = <TextStyle, int>{};
    void walk(InlineSpan span, TextStyle? inherited) {
      final style = inherited?.merge(span.style) ?? span.style;
      if (span is TextSpan) {
        final length = span.text?.trim().length ?? 0;
        if (length > 0 && style != null) {
          weights[style] = (weights[style] ?? 0) + length;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child, style);
        }
      }
    }

    walk(root, null);
    if (weights.isEmpty) {
      return null;
    }
    return weights.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static bool _isGlyph(String text, TextStyle style) {
    final family = style.fontFamily ?? '';
    if (family.contains('Icons') || family.contains('icon')) {
      return true;
    }
    final runes = text.runes.toList();
    return runes.length == 1 && runes.first >= 0xE000 && runes.first <= 0xF8FF;
  }

  static const _plumbing = {
    'Text',
    'RichText',
    'Padding',
    'Align',
    'Center',
    'Container',
    'Row',
    'Column',
    'Flex',
    'Expanded',
    'Flexible',
    'SizedBox',
    'ConstrainedBox',
    'DecoratedBox',
    'DefaultTextStyle',
    'AnimatedDefaultTextStyle',
    'Builder',
    'Semantics',
    'MergeSemantics',
    'ExcludeSemantics',
    'IconTheme',
    'Icon',
    'MouseRegion',
    'GestureDetector',
    'RawGestureDetector',
    'Listener',
    'Material',
    'InkWell',
    'InkResponse',
    'Ink',
    'AnimatedContainer',
    'Opacity',
    'FadeTransition',
    'AnimatedOpacity',
    'Stack',
    'Positioned',
    'Transform',
    'ClipRRect',
    'ClipRect',
    'ClipPath',
    'Tooltip',
    'Focus',
    'FocusScope',
    'Actions',
    'Shortcuts',
    'KeyedSubtree',
    'RepaintBoundary',
    'LayoutBuilder',
    'FittedBox',
    'LimitedBox',
    'IntrinsicWidth',
    'IntrinsicHeight',
    'UnconstrainedBox',
    'OverflowBox',
    'AnimatedSize',
    'AnimatedSwitcher',
    'AnimatedBuilder',
    'ValueListenableBuilder',
    'ListenableBuilder',
    'StreamBuilder',
    'FutureBuilder',
    'BlocBuilder',
    'BlocProvider',
    'Provider',
    'MultiBlocProvider',
    'IgnorePointer',
    'AbsorbPointer',
    'Visibility',
    'Offstage',
    'TickerMode',
    'Wrap',
    'ListView',
    'SliverList',
    'Scrollable',
    'Viewport',
    'NotificationListener',
    'ScrollConfiguration',
    'PrimaryScrollController',
    'SingleChildScrollView',
    'Scrollbar',
    'RawScrollbar',
    'CustomPaint',
    'Hero',
    'TextButton',
    'ElevatedButton',
    'OutlinedButton',
    'IconButton',
    'Card',
    'CompositedTransformTarget',
    'CompositedTransformFollower',
    'Overlay',
    'OverlayPortal',
    'Directionality',
    'MediaQuery',
    'Theme',
    'AnimatedTheme',
    'Localizations',
    'Title',
    'ButtonStyleButton',
    'InkFeatures',
    'PhysicalModel',
    'AnimatedPhysicalModel',
    'AnimatedPadding',
    'AnimatedAlign',
    'AnimatedPositioned',
    'SliverPadding',
    'SliverToBoxAdapter',
    'CustomScrollView',
    'NestedScrollView',
    'Flow',
  };

  static String _owner(RenderObject object) {
    final creator = object.debugCreator;
    if (creator is! DebugCreator) {
      return object.runtimeType.toString();
    }
    final chain = <String>[];
    void add(Element element) {
      final name = element.widget.runtimeType.toString().split('<').first;
      if (!_plumbing.contains(name) &&
          !name.startsWith('_') &&
          (chain.isEmpty || chain.last != name)) {
        chain.add(name);
      }
    }

    add(creator.element);
    creator.element.visitAncestorElements((element) {
      add(element);
      return chain.length < 5;
    });
    return chain.join(' < ');
  }

  void note(String message) => notes.add(message);

  /// Keeps a framework error as a note, with the widget that caused it, so a
  /// block that fails to lay out (and so shows nothing) can be found.
  void recordError(FlutterErrorDetails details) {
    final summary = details.exceptionAsString().split('\n').first;
    // These follow from an earlier layout error rather than cause one.
    if (summary.startsWith('RenderBox was not laid out') ||
        summary.startsWith('Updated layout information required')) {
      return;
    }
    final text = details.toString();
    final cause = RegExp(r'The relevant error-causing widget was:\s*\n\s*(.+)')
        .firstMatch(text)
        ?.group(1)
        ?.trim();
    // Debug builds track where each widget was created; keep the file and
    // line so an overflow below the fold can still be found.
    const header = 'The relevant error-causing widget was:';
    final at = text.indexOf(header);
    final where = at < 0
        ? null
        : RegExp(r'file://\S*?/lib/(\S+?:\d+):\d+')
            .firstMatch(
              text.substring(at, math.min(text.length, at + 480)),
            )
            ?.group(1);
    note(
      'error after $_lastSurface: $summary'
      '${cause == null ? '' : ' <- $cause'}'
      '${where == null ? '' : ' ($where)'}',
    );
  }

  Future<void> finish() async {
    final bySurface = <String, List<LegibilityFinding>>{};
    for (final finding in findings) {
      (bySurface[finding.surface] ??= []).add(finding);
    }
    final buffer = StringBuffer()
      ..writeln('# Legibility audit')
      ..writeln()
      ..writeln('${findings.length} finding(s) on ${bySurface.length} '
          'surface(s). INVISIBLE < 2:1, POOR < 3:1, BELOW-AA < 4.5:1 '
          '(3:1 for glyphs and large text).')
      ..writeln();
    for (final note in notes) {
      buffer.writeln('- note: $note');
    }
    if (glare.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Panels that ignore the theme (leads)')
        ..writeln();
      for (final lead in glare) {
        buffer.writeln('- $lead');
      }
    }
    for (final MapEntry(key: surface, value: list) in bySurface.entries) {
      list.sort((a, b) => a.ratio.compareTo(b.ratio));
      buffer
        ..writeln()
        ..writeln('## $surface')
        ..writeln()
        ..writeln('| severity | ratio | text | ink | background | owner |')
        ..writeln('|---|---|---|---|---|---|');
      for (final f in list) {
        final text = f.text.replaceAll('|', '/').replaceAll('\n', ' ');
        buffer.writeln(
          '| ${f.severity}${f.glyph ? ' (glyph)' : ''} | '
          '${f.ratio.toStringAsFixed(2)} | $text | ${_hex(f.ink)} | '
          '${_hex(f.background)} | ${f.owner} |',
        );
      }
    }
    await File(p.join(root.path, 'legibility-report.md'))
        .writeAsString(buffer.toString(), flush: true);
    await File(p.join(root.path, 'legibility-report.json')).writeAsString(
      const JsonEncoder.withIndent(' ')
          .convert([for (final f in findings) f.toJson()]),
      flush: true,
    );
  }
}

class _Frame {
  _Frame(ByteData pixels, this.width, this.height, this.scale)
      : _bytes = pixels.buffer.asUint8List(
          pixels.offsetInBytes,
          pixels.lengthInBytes,
        );

  final Uint8List _bytes;
  final int width;
  final int height;
  final double scale;

  (int, int, int, int) _box(Rect rect) => (
        (rect.left * scale).floor().clamp(0, width - 1),
        (rect.top * scale).floor().clamp(0, height - 1),
        (rect.right * scale).ceil().clamp(1, width),
        (rect.bottom * scale).ceil().clamp(1, height),
      );

  /// The most common colour inside [rect] — the surface behind the text —
  /// leaving out whatever falls inside [excluding].
  Color? dominant(Rect rect, {Rect? excluding}) {
    final (left, top, right, bottom) = _box(rect);
    final hole = excluding == null ? null : _box(excluding);
    final area = (right - left) * (bottom - top);
    if (area <= 0) {
      return null;
    }
    final stride = area > 60000 ? 3 : (area > 15000 ? 2 : 1);
    final counts = <int, int>{};
    final sums = <int, List<int>>{};
    for (var y = top; y < bottom; y += stride) {
      for (var x = left; x < right; x += stride) {
        if (hole != null &&
            x >= hole.$1 &&
            x < hole.$3 &&
            y >= hole.$2 &&
            y < hole.$4) {
          continue;
        }
        final i = (y * width + x) * 4;
        final r = _bytes[i], g = _bytes[i + 1], b = _bytes[i + 2];
        final key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3);
        counts[key] = (counts[key] ?? 0) + 1;
        final sum = sums[key] ??= [0, 0, 0];
        sum[0] += r;
        sum[1] += g;
        sum[2] += b;
      }
    }
    if (counts.isEmpty) {
      return null;
    }
    final key = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final n = counts[key]!;
    final sum = sums[key]!;
    return Color.fromARGB(255, sum[0] ~/ n, sum[1] ~/ n, sum[2] ~/ n);
  }

  /// Whether every sampled pixel of the [size] square at [left], [top] is
  /// near white ([light]) or near black — a flat panel, not text or media.
  bool uniformlyExtreme(int left, int top, int size, {required bool light}) {
    var extreme = 0;
    var total = 0;
    for (var y = top; y < top + size && y < height; y += 3) {
      for (var x = left; x < left + size && x < width; x += 3) {
        final i = (y * width + x) * 4;
        final r = _bytes[i], g = _bytes[i + 1], b = _bytes[i + 2];
        final luma = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 255;
        if (light ? luma > 0.86 : luma < 0.07) {
          extreme++;
        }
        total++;
      }
    }
    return total > 0 && extreme >= total * 0.95;
  }

  /// Whether any pixel inside [rect] is close to [color].
  bool contains(Rect rect, Color color) {
    final (left, top, right, bottom) = _box(rect);
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final i = (y * width + x) * 4;
        if ((_bytes[i] - r).abs() +
                (_bytes[i + 1] - g).abs() +
                (_bytes[i + 2] - b).abs() <
            36) {
          return true;
        }
      }
    }
    return false;
  }
}
