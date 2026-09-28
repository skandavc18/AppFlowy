import 'dart:async';

import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:flutter/material.dart';

/// Local defaults only. The preview uses the actual cover renderer, with no
/// synthetic view id, metadata writer, network request, or image mutation.
class CoverAppearanceSetting extends StatefulWidget {
  const CoverAppearanceSetting({super.key, this.store});
  final CoverAppearanceStore? store;
  @override
  State<CoverAppearanceSetting> createState() => _CoverAppearanceSettingState();
}

class _CoverAppearanceSettingState extends State<CoverAppearanceSetting> {
  late CoverAppearanceStore _store;
  bool _loading = true;
  double? _ratioDraft;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? CoverAppearanceStore.instance;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CoverAppearanceSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _store = widget.store ?? CoverAppearanceStore.instance;
      _loading = true;
      _ratioDraft = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final store = _store;
    await store.ensureLoaded();
    if (mounted && identical(store, _store)) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final value = _store.value;
          final preview = _ratioDraft == null
              ? value
              : value.copyWith(aspectRatio: _ratioDraft);
          final enabled = !_loading && _store.isLoaded && !_store.isSaving;
          final palette = WorkspacePalette.of(context);
          return Column(
            key: const ValueKey('cover-appearance-setting'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(coverLabel('title', 'Default page covers'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                coverLabel('description',
                    'Appearance on this device. Existing images, positions and page height overrides are kept.'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.secondaryText),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final width =
                    constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
                final height = PageCoverHeight.resolve(
                    width: width, appearance: preview, fallback: 144);
                return PageCoverPresentation(
                  appearance: preview,
                  alignment: preview.alignment,
                  child: SizedBox(
                    key: const ValueKey('cover-appearance-preview'),
                    height: height,
                    child: const WorkspacePageCover(
                      image: ViewCoverImage(
                        cover: PageStyleCover(
                            type: PageStyleCoverImageType.builtInImage,
                            value: 'n1'),
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              _choices<CoverCorners>(
                label: coverLabel('corners', 'Corners'),
                values: CoverCorners.values,
                selected: value.corners,
                name: (v) => coverLabel(
                    v.name, v == CoverCorners.rounded ? 'Rounded' : 'Square'),
                enabled: enabled,
                onChanged: (v) =>
                    _store.update((current) => current.copyWith(corners: v)),
              ),
              _choices<CoverImageFit>(
                label: coverLabel('imageFit', 'Image fitting'),
                values: CoverImageFit.values,
                selected: value.fit,
                name: (v) => coverLabel(
                    v.name,
                    switch (v) {
                      CoverImageFit.fit => 'Fit',
                      CoverImageFit.crop => 'Fill / crop',
                      CoverImageFit.stretch => 'Stretch',
                    }),
                enabled: enabled,
                onChanged: (v) =>
                    _store.update((current) => current.copyWith(fit: v)),
              ),
              _choices<CoverPosition>(
                label: coverLabel('position', 'Default position'),
                values: CoverPosition.values,
                selected: value.position,
                name: (v) => coverLabel(
                    v.name,
                    switch (v) {
                      CoverPosition.top => 'Top',
                      CoverPosition.center => 'Center',
                      CoverPosition.bottom => 'Bottom',
                    }),
                enabled: enabled,
                onChanged: (v) =>
                    _store.update((current) => current.copyWith(position: v)),
              ),
              SwitchListTile(
                key: const ValueKey('cover-appearance-ratio-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(coverLabel('aspectRatio', 'Use an aspect ratio')),
                subtitle: Text(coverLabel('ratioHint',
                    'Width ÷ height, bounded to keep the page usable. Resized pages retain their height.')),
                value: value.aspectRatio != null,
                onChanged: !enabled
                    ? null
                    : (useRatio) => unawaited(_store.update(
                          (current) => current.copyWith(
                              aspectRatio: 3, resetAspectRatio: !useRatio),
                        )),
              ),
              if (value.aspectRatio != null) ...[
                Text(
                    '${(_ratioDraft ?? value.aspectRatio!).toStringAsFixed(2)} : 1'),
                Slider(
                  key: const ValueKey('cover-appearance-ratio'),
                  min: 1,
                  max: 6,
                  value: _ratioDraft ?? value.aspectRatio!,
                  semanticFormatterCallback: (ratio) =>
                      '${ratio.toStringAsFixed(2)} : 1',
                  onChanged: !enabled
                      ? null
                      : (ratio) => setState(() => _ratioDraft = ratio),
                  onChangeEnd: !enabled
                      ? null
                      : (ratio) async {
                          final store = _store;
                          await store.update((current) =>
                              current.copyWith(aspectRatio: ratio));
                          if (mounted && identical(store, _store))
                            setState(() => _ratioDraft = null);
                        },
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('cover-appearance-reset'),
                  style: WorkspaceChrome.controlStyle(context),
                  onPressed: enabled ? () => unawaited(_store.reset()) : null,
                  child: Text(coverLabel('reset', 'Reset cover defaults')),
                ),
              ),
              if (_loading || _store.isSaving || _store.failure != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _loading
                        ? coverLabel('loading', 'Loading')
                        : _store.isSaving
                            ? coverLabel('saving', 'Saving')
                            : coverLabel('settingsFailed',
                                'Cover preferences could not be loaded or saved. Try again.'),
                    key: const ValueKey('cover-appearance-status'),
                    style: TextStyle(
                        color: _store.failure == null
                            ? palette.secondaryText
                            : palette.destructive),
                  ),
                ),
              if (!_loading && !_store.isLoaded)
                TextButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    unawaited(_load());
                  },
                  child: Text(coverLabel('retry', 'Retry')),
                ),
            ],
          );
        },
      );

  Widget _choices<T>({
    required String label,
    required List<T> values,
    required T selected,
    required String Function(T) name,
    required bool enabled,
    required Future<bool> Function(T) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in values)
                  ChoiceChip(
                    key: ValueKey('cover-appearance-$option'),
                    label: Text(name(option)),
                    selected: selected == option,
                    onSelected:
                        !enabled ? null : (_) => unawaited(onChanged(option)),
                  ),
              ],
            ),
          ],
        ),
      );
}
