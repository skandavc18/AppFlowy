import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/page_block_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy/plugins/document/presentation/embedded_blocks/page_block_catalog.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show EditorState;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The words for one of the groups the "Add" panel is arranged in.
String dashboardGroupLabel(DashboardWidgetGroup group) => switch (group) {
      DashboardWidgetGroup.text => LocaleKeys.dashboard_group_text.tr(),
      DashboardWidgetGroup.content => LocaleKeys.dashboard_group_content.tr(),
      DashboardWidgetGroup.collections =>
        LocaleKeys.dashboard_group_collections.tr(),
      DashboardWidgetGroup.data => LocaleKeys.dashboard_group_data.tr(),
      DashboardWidgetGroup.money => LocaleKeys.dashboard_group_money.tr(),
      DashboardWidgetGroup.time => LocaleKeys.dashboard_group_time.tr(),
      DashboardWidgetGroup.controls => LocaleKeys.dashboard_group_controls.tr(),
      DashboardWidgetGroup.info => LocaleKeys.dashboard_group_info.tr(),
    };

/// Choose something to put on the dashboard.
///
/// A searchable panel rather than a nested menu: there are thirty widgets and
/// growing, and the fastest way to the one somebody wants is to type its name.
///
/// Everything a page's `/` menu can insert is offered here too, under "From
/// pages": choosing one runs that entry and returns the page-block widget
/// carrying what it inserted.
Future<DashboardWidgetDefinition?> showDashboardWidgetPicker({
  required BuildContext context,
  required DashboardPalette palette,
}) =>
    showDialog<DashboardWidgetDefinition>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: palette.isDark ? 0.5 : 0.22),
      builder: (_) => _DashboardWidgetPicker(palette: palette),
    );

/// The page-block widget carrying what [entry] inserts. None when it inserted
/// nothing that can stand on its own, or when what it asked was [dismissed].
Future<({DashboardWidgetDefinition? definition, bool dismissed})>
    dashboardDefinitionForPageBlock(
  PageBlockEntry entry,
  BuildContext context,
) async {
  final carrier = DashboardWidgetRegistry.definitionFor(dashboardPageBlockType);
  if (carrier == null) return (definition: null, dismissed: false);
  final run = await runPageBlockEntry(entry, context);
  final document = run.document;
  if (document == null) return (definition: null, dismissed: run.dismissed);
  return (
    definition: carrier.prefilled(
      settings: {
        dashboardPageBlockDocumentKey: document,
        dashboardPageBlockNameKey: entry.name,
      },
      label: () => entry.name,
      title: () => entry.name,
    ),
    dismissed: false,
  );
}

/// One thing the panel offers: a widget, or a block from a page.
sealed class _Choice {
  const _Choice();
}

class _WidgetChoice extends _Choice {
  const _WidgetChoice(this.definition);

  final DashboardWidgetDefinition definition;
}

class _BlockChoice extends _Choice {
  const _BlockChoice(this.entry);

  final PageBlockEntry entry;
}

class _DashboardWidgetPicker extends StatefulWidget {
  const _DashboardWidgetPicker({required this.palette});

  final DashboardPalette palette;

  @override
  State<_DashboardWidgetPicker> createState() => _DashboardWidgetPickerState();
}

class _DashboardWidgetPickerState extends State<_DashboardWidgetPicker> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  DashboardWidgetGroup? _group;

  /// The "From pages" chip is selected.
  bool _blocks = false;
  int _highlighted = 0;

  /// Read once per opening: the `/` entries as they are right now.
  late final List<PageBlockEntry> _catalog = pageBlockCatalog();

  /// `/` icons are drawn by builders that are handed an editor.
  final EditorState _iconEditor = EditorState.blank();

  /// A block is being inserted; another choice waits.
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _iconEditor.dispose();
    super.dispose();
  }

  List<_Choice> get _results {
    final text = _query.text.trim();
    if (text.isNotEmpty) {
      return [
        for (final definition in DashboardWidgetRegistry.search(text))
          _WidgetChoice(definition),
        for (final entry in _catalog)
          if (entry.matches(text)) _BlockChoice(entry),
      ];
    }
    if (_blocks) {
      return [for (final entry in _catalog) _BlockChoice(entry)];
    }
    final group = _group;
    return group == null
        ? [
            for (final definition in DashboardWidgetRegistry.offered())
              _WidgetChoice(definition),
            for (final entry in _catalog) _BlockChoice(entry),
          ]
        : [
            for (final definition in DashboardWidgetRegistry.inGroup(group))
              _WidgetChoice(definition),
          ];
  }

  Future<void> _choose(_Choice choice) async {
    if (_busy) return;
    switch (choice) {
      case _WidgetChoice(:final definition):
        Navigator.of(context).pop(definition);
      case _BlockChoice(:final entry):
        setState(() => _busy = true);
        final (:definition, :dismissed) =
            await dashboardDefinitionForPageBlock(entry, context);
        if (!mounted) return;
        setState(() => _busy = false);
        if (definition == null) {
          // A picker somebody closed is an answer, not a failure.
          if (!dismissed) {
            showToastNotification(
              message: LocaleKeys.dashboard_add_blockFailed.tr(),
              type: ToastificationType.error,
            );
          }
          return;
        }
        Navigator.of(context).pop(definition);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final results = _results;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        width: 660,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(20),
          boxShadow: palette.cardShadow(raised: true),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearch(palette),
            _buildGroups(palette),
            Flexible(
              child: results.isEmpty
                  ? DashboardPlaceholder(
                      palette: palette,
                      icon: Icons.search_off_rounded,
                      message: LocaleKeys.dashboard_add_noResults.tr(),
                    )
                  : _buildGrid(palette, results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(DashboardPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.sunken,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 17, color: palette.textMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        _MoveIntent(1),
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        _MoveIntent(-1),
                  },
                  child: Actions(
                    actions: {
                      _MoveIntent: CallbackAction<_MoveIntent>(
                        onInvoke: (intent) {
                          final results = _results;
                          if (results.isEmpty) {
                            return null;
                          }
                          setState(
                            () => _highlighted = (_highlighted + intent.delta)
                                .clamp(0, results.length - 1),
                          );
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      style: DashboardType.body(palette),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: LocaleKeys.dashboard_add_search.tr(),
                        hintStyle: DashboardType.body(
                          palette,
                          color: palette.textMuted,
                        ),
                      ),
                      onChanged: (_) => setState(() => _highlighted = 0),
                      onSubmitted: (_) {
                        final results = _results;
                        if (results.isNotEmpty) {
                          unawaited(
                            _choose(
                              results[
                                  _highlighted.clamp(0, results.length - 1)],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildGroups(DashboardPalette palette) => SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _GroupChip(
              label: LocaleKeys.dashboard_group_all.tr(),
              palette: palette,
              selected: _group == null && !_blocks,
              onTap: () => setState(() {
                _group = null;
                _blocks = false;
              }),
            ),
            // Second, not last: past the panel's edge it would go unseen.
            if (_catalog.isNotEmpty)
              _GroupChip(
                key: const ValueKey('dashboard-add-group-blocks'),
                label: LocaleKeys.dashboard_group_blocks.tr(),
                palette: palette,
                selected: _blocks,
                onTap: () => setState(() {
                  _group = null;
                  _blocks = true;
                }),
              ),
            for (final group in DashboardWidgetGroup.values)
              _GroupChip(
                label: dashboardGroupLabel(group),
                palette: palette,
                selected: _group == group && !_blocks,
                onTap: () => setState(() {
                  _group = group;
                  _blocks = false;
                }),
              ),
          ],
        ),
      );

  Widget _buildGrid(
    DashboardPalette palette,
    List<_Choice> results,
  ) =>
      GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          mainAxisExtent: 62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: results.length,
        itemBuilder: (context, index) => switch (results[index]) {
          _WidgetChoice(:final definition) => _WidgetTile(
              definition: definition,
              palette: palette,
              highlighted: index == _highlighted,
              onTap: () => unawaited(_choose(results[index])),
            ),
          _BlockChoice(:final entry) => _BlockTile(
              key: ValueKey('dashboard-add-block-${entry.name}'),
              entry: entry,
              editorState: _iconEditor,
              palette: palette,
              highlighted: index == _highlighted,
              busy: _busy,
              onTap: () => unawaited(_choose(results[index])),
            ),
        },
      );
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    super.key,
    required this.label,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DashboardPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? palette.accent.withValues(alpha: 0.14)
                    : palette.sunken,
                borderRadius:
                    BorderRadius.circular(DashboardMetrics.chipRadius),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: DashboardType.cardTitle(
                    palette,
                    color: selected ? palette.accent : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _WidgetTile extends StatefulWidget {
  const _WidgetTile({
    required this.definition,
    required this.palette,
    required this.highlighted,
    required this.onTap,
  });

  final DashboardWidgetDefinition definition;
  final DashboardPalette palette;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_WidgetTile> createState() => _WidgetTileState();
}

class _WidgetTileState extends State<_WidgetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final definition = widget.definition;
    final active = _hovered || widget.highlighted;
    // Each kind of widget is recognisable by its own colour before it is
    // even placed: the same colour it wears on the board.
    final accent = definition.identity != DashboardAccent.neutral
        ? definition.identity
        : definition.defaultAccent;
    final strong = accent == DashboardAccent.neutral
        ? palette.accent
        : palette.strongFor(accent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AnimatedScale(
                duration: DashboardMetrics.hover,
                curve: DashboardMetrics.curve,
                scale: active ? 1.06 : 1,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: strong.withValues(
                      alpha: palette.isDark ? 0.2 : 0.13,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(definition.icon, size: 16, color: strong),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      definition.label(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        palette,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (definition.description != null)
                      Text(
                        definition.description!(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.caption(palette),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The colour a `/` entry wears outside the page, by where `/` files it, so
/// blocks read as families the way widgets do.
DashboardAccent pageBlockAccent(PageBlockEntry entry) =>
    switch (entry.section) {
      SlashMenuSection.diagrams => DashboardAccent.purple,
      SlashMenuSection.media => DashboardAccent.blue,
      SlashMenuSection.interactive => DashboardAccent.orange,
      SlashMenuSection.collections => DashboardAccent.teal,
      SlashMenuSection.database => DashboardAccent.green,
      SlashMenuSection.canvas => DashboardAccent.pink,
      SlashMenuSection.dashboards => DashboardAccent.amber,
      _ => DashboardAccent.amber,
    };

/// One of a page's `/` entries, offered on the dashboard.
class _BlockTile extends StatefulWidget {
  const _BlockTile({
    super.key,
    required this.entry,
    required this.editorState,
    required this.palette,
    required this.highlighted,
    required this.busy,
    required this.onTap,
  });

  final PageBlockEntry entry;
  final EditorState editorState;
  final DashboardPalette palette;
  final bool highlighted;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_BlockTile> createState() => _BlockTileState();
}

class _BlockTileState extends State<_BlockTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final entry = widget.entry;
    final active = (_hovered || widget.highlighted) && !widget.busy;
    final strong = palette.strongFor(pageBlockAccent(entry));
    final description = entry.description;
    return MouseRegion(
      cursor: widget.busy ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AnimatedScale(
                duration: DashboardMetrics.hover,
                curve: DashboardMetrics.curve,
                scale: active ? 1.06 : 1,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: strong.withValues(
                      alpha: palette.isDark ? 0.2 : 0.13,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SizedBox.square(
                    dimension: 18,
                    child: FittedBox(
                      child: entry.icon(widget.editorState, strong),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        palette,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      description == null || description.isEmpty
                          ? LocaleKeys.dashboard_group_blocks.tr()
                          : description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.caption(palette),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
