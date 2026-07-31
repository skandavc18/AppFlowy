import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_format.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything about how the book is set: surface, size, measure, page turn.
class BookReaderSettingsPanel extends StatelessWidget {
  const BookReaderSettingsPanel({
    super.key,
    required this.settings,
    required this.palette,
    required this.onChanged,
  });

  static const width = 306.0;

  final BookReaderSettings settings;
  final BookReaderPalette palette;
  final ValueChanged<BookReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.rule, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 26,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(LocaleKeys.collections_book_theme.tr()),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final theme in BookReaderTheme.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: theme == BookReaderTheme.values.last ? 0 : 7,
                    ),
                    child: _ThemeSwatch(
                      theme: theme,
                      palette: palette,
                      selected: settings.theme == theme,
                      onTap: () => onChanged(settings.copyWith(theme: theme)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label(LocaleKeys.collections_book_textSize.tr()),
          const SizedBox(height: 6),
          _TextSizeRow(
            settings: settings,
            palette: palette,
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
          _label(LocaleKeys.collections_book_measure.tr()),
          const SizedBox(height: 8),
          _Segments<BookReaderMeasure>(
            palette: palette,
            values: BookReaderMeasure.values,
            selected: settings.measure,
            labelOf: bookMeasureLabel,
            onChanged: (value) => onChanged(settings.copyWith(measure: value)),
          ),
          const SizedBox(height: 16),
          _label(LocaleKeys.collections_book_flow.tr()),
          const SizedBox(height: 8),
          _Segments<BookReaderFlow>(
            palette: palette,
            values: BookReaderFlow.values,
            selected: settings.flow,
            labelOf: bookFlowLabel,
            onChanged: (value) => onChanged(settings.copyWith(flow: value)),
          ),
          const SizedBox(height: 16),
          _label(LocaleKeys.collections_book_transition.tr()),
          const SizedBox(height: 8),
          _Segments<BookPageTransition>(
            palette: palette,
            values: BookPageTransition.values,
            selected: settings.transition,
            labelOf: bookTransitionLabel,
            onChanged: (value) =>
                onChanged(settings.copyWith(transition: value)),
          ),
          const SizedBox(height: 14),
          _Toggle(
            palette: palette,
            label: LocaleKeys.collections_book_autoAdvance.tr(),
            value: settings.autoAdvance,
            onChanged: (value) =>
                onChanged(settings.copyWith(autoAdvance: value)),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: palette.inkFaint,
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final BookReaderTheme theme;
  final BookReaderPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The workspace swatch has no fixed colours of its own — it shows the
    // surface the application is wearing right now.
    final swatch = theme == BookReaderTheme.workspace
        ? BookReaderPalette.of(context, BookReaderTheme.workspace)
        : BookReaderPalette.swatch(theme);
    return Tooltip(
      message: bookThemeLabel(theme),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: BookReaderMetrics.motion,
            curve: BookReaderMetrics.curve,
            height: 44,
            decoration: BoxDecoration(
              color: swatch.page,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? palette.accent : palette.rule,
                width: selected ? 1.6 : 0.8,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              theme == BookReaderTheme.workspace ? 'A' : 'Aa',
              style: TextStyle(
                color: swatch.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSizeRow extends StatelessWidget {
  const _TextSizeRow({
    required this.settings,
    required this.palette,
    required this.onChanged,
  });

  final BookReaderSettings settings;
  final BookReaderPalette palette;
  final ValueChanged<BookReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final scale = settings.fontScale;
    return Row(
      children: [
        _StepButton(
          palette: palette,
          icon: Icons.remove_rounded,
          enabled: scale > BookReaderSettings.minimumFontScale,
          onTap: () => onChanged(
            settings.copyWith(
              fontScale: scale - BookReaderSettings.fontScaleStep,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: palette.accent,
              inactiveTrackColor: palette.rule,
              thumbColor: palette.accent,
              overlayColor: palette.accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: scale,
              min: BookReaderSettings.minimumFontScale,
              max: BookReaderSettings.maximumFontScale,
              divisions: 9,
              onChanged: (value) =>
                  onChanged(settings.copyWith(fontScale: value)),
            ),
          ),
        ),
        _StepButton(
          palette: palette,
          icon: Icons.add_rounded,
          enabled: scale < BookReaderSettings.maximumFontScale,
          onTap: () => onChanged(
            settings.copyWith(
              fontScale: scale + BookReaderSettings.fontScaleStep,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(scale * 100).round()}%',
            textAlign: TextAlign.end,
            style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.palette,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final BookReaderPalette palette;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? palette.inkMuted : palette.inkFaint,
          ),
        ),
      ),
    );
  }
}

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.palette,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final BookReaderPalette palette;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.hover,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: BookReaderMetrics.motion,
                    curve: BookReaderMetrics.curve,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == selected
                          ? palette.chrome
                          : palette.chrome.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      labelOf(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            value == selected ? palette.ink : palette.inkMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final BookReaderPalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: palette.ink, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 10),
            Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: WidgetStatePropertyAll(palette.chrome),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? palette.accent
                    : palette.rule,
              ),
              trackOutlineColor: WidgetStatePropertyAll(palette.rule),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
