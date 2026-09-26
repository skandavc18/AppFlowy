import 'dart:async';

import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const _copy = 'settings.workspacePage.defaultIconStyle';

/// Device appearance, not a bulk edit of page or workspace icons.
class DefaultIconStyleSetting extends StatefulWidget {
  const DefaultIconStyleSetting({super.key, this.store});

  final DefaultIconStyleStore? store;

  @override
  State<DefaultIconStyleSetting> createState() =>
      _DefaultIconStyleSettingState();
}

class _DefaultIconStyleSettingState extends State<DefaultIconStyleSetting> {
  late DefaultIconStyleStore _store;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? DefaultIconStyleStore.instance;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(DefaultIconStyleSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _store = widget.store ?? DefaultIconStyleStore.instance;
      _loading = true;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final store = _store;
    await store.ensureLoaded();
    if (mounted && identical(store, _store)) {
      setState(() => _loading = false);
    }
  }

  void _choose(DefaultIconStyle? style) {
    if (style == null || _store.isSaving || !_store.isLoaded) return;
    // The store exposes failure feedback and only publishes acknowledged
    // values. Closing Settings during a save does not cancel the device save.
    unawaited(_store.setStyle(style));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final disabled = _loading || !_store.isLoaded || _store.isSaving;
          final failure = _store.failure;
          final status = _store.isSaving
              ? '$_copy.saving'.tr()
              : _loading
                  ? '$_copy.loading'.tr()
                  : failure == DefaultIconStyleFailure.save
                      ? '$_copy.saveFailed'.tr()
                      : failure != null
                          ? '$_copy.loadFailed'.tr()
                          : '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('$_copy.title'.tr(), style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '$_copy.description'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: workspaceGlyphInk(context),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final style in DefaultIconStyle.values) ...[
                    if (style != DefaultIconStyle.monochrome)
                      const SizedBox(width: 12),
                    Expanded(
                      child: _StyleChoice(
                        style: style,
                        selected: _store.isLoaded ? _store.value : null,
                        onChanged: disabled ? null : _choose,
                      ),
                    ),
                  ],
                ],
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    key: const ValueKey('default-icon-style-status'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: failure != null && !_store.isSaving && !_loading
                          ? theme.colorScheme.error
                          : workspaceGlyphInk(context),
                    ),
                  ),
                ),
              ],
              if (!_loading && !_store.isLoaded)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _store.isSaving
                        ? null
                        : () {
                            setState(() => _loading = true);
                            unawaited(_load());
                          },
                    child: Text('button.retry'.tr()),
                  ),
                ),
            ],
          );
        },
      );
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    required this.style,
    required this.selected,
    required this.onChanged,
  });

  final DefaultIconStyle style;
  final DefaultIconStyle? selected;
  final ValueChanged<DefaultIconStyle?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    return Material(
      color: EditorSurfaceStyle.previewBackgroundFor(
        theme.brightness,
        premium?.surface ?? theme.colorScheme.surface,
        isPaper: PaperTheme.isEnabled(context),
      ),
      borderRadius: BorderRadius.circular(10),
      child: RadioListTile<DefaultIconStyle>(
        key: ValueKey('default-icon-style-${style.name}'),
        value: style,
        groupValue: selected,
        onChanged: onChanged,
        selected: style == selected,
        activeColor: workspaceGlyphAccent(context),
        hoverColor: premium?.hover ?? theme.hoverColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        title: Text(
          '$_copy.${style.name}'.tr(),
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Real glyphs, not painted/fake toolbars or extra buttons. These
              // examples are decorative; the native radio owns semantics,
              // focus, keyboard activation and the selected state.
              ExcludeSemantics(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in [
                      'file-text',
                      'folder',
                      'book-open',
                      'calendar-blank',
                      'gear',
                    ])
                      WorkspaceGlyph.named(name, size: 24, style: style),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_copy.${style.name}Description'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: workspaceGlyphInk(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
