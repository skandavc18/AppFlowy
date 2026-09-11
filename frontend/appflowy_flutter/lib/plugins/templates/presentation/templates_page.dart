import 'dart:async';

import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/templates/presentation/template_card.dart';
import 'package:appflowy/plugins/templates/presentation/template_preview.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/templates/built_in/built_in_templates.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/template_service.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The shelf of everything somebody can start from.
///
/// It is a browser, not a wizard: pressing a card makes the thing and opens
/// it, and what it made is then an ordinary page nobody has to keep in step
/// with a template afterwards.
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  final TextEditingController _search = TextEditingController();

  /// null means the featured shelf.
  TemplateCategory? _category;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // An extension being switched on adds templates, and takes them away again.
    TemplateRegistry.changes.addListener(_refresh);
    DartExtensionHost.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    TemplateRegistry.changes.removeListener(_refresh);
    DartExtensionHost.instance.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  List<WorkspaceTemplate> get _shown {
    final query = _search.text.trim();
    if (query.isNotEmpty) {
      return TemplateRegistry.search(query);
    }
    final category = _category;
    if (category != null) {
      return TemplateRegistry.inCategory(category);
    }
    final featured = [
      for (final id in featuredTemplateIds)
        if (TemplateRegistry.forId(id) != null) TemplateRegistry.forId(id)!,
    ];
    final rest = [
      for (final template in TemplateRegistry.all())
        if (!featuredTemplateIds.contains(template.id)) template,
    ];
    return [...featured, ...rest];
  }

  /// Where a template lands: the space that is open, or the workspace itself.
  ///
  /// ⚠️ `SpaceBloc` is provided inside the SIDEBAR, not above the page stack,
  /// so it has to be read nullably here or every press throws.
  ({String id, ViewSectionPB? section})? _parent() {
    final workspace = context.read<UserWorkspaceBloc>().state;
    final space = context.read<SpaceBloc?>()?.state.currentSpace;
    final parentId = space?.id ?? workspace.currentWorkspace?.workspaceId;
    if (parentId == null || parentId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return null;
    }
    return (
      id: parentId,
      section: space == null
          ? workspace.isCollabWorkspaceOn
              ? ViewSectionPB.Private
              : ViewSectionPB.Public
          : null,
    );
  }

  Future<void> _use(WorkspaceTemplate template) async {
    if (_busy) {
      return;
    }
    final missing = missingExtensionsFor(template);
    if (missing.isNotEmpty) {
      // Making it now would be a page full of widgets nobody can draw — but
      // refusing without a word is indistinguishable from a dead button.
      showSnackBarMessage(
        context,
        missing.length == 1
            ? LocaleKeys.templates_needsExtension.tr(args: [missing.single])
            : LocaleKeys.templates_needsExtensions
                .tr(args: [missing.join(', ')]),
      );
      return;
    }
    final wanted = await showTemplatePreview(
      context,
      template,
      confirmLabel: LocaleKeys.templates_use.tr(),
    );
    if (!wanted || !mounted) {
      return;
    }

    final parent = _parent();
    if (parent == null) {
      return;
    }

    setState(() => _busy = true);
    TemplateOutcome? outcome;
    try {
      outcome = await TemplateService.create(
        parentViewId: parent.id,
        template: template,
        section: parent.section,
      );
    } on Object catch (error, stack) {
      // A template that fails silently is indistinguishable from a dead button.
      Log.error('[Template] ${template.id} could not be made', error, stack);
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    if (outcome == null) {
      showSnackBarMessage(context, LocaleKeys.templates_failed.tr());
      return;
    }
    showSnackBarMessage(
      context,
      LocaleKeys.templates_created.tr(args: [template.label()]),
    );
    context.read<TabsBloc>().openPlugin(outcome.primary);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final templates = _shown;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 26, 40, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(palette: palette, search: _search, onChanged: _refresh),
          const SizedBox(height: 22),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 178,
                  child: _Shelves(
                    palette: palette,
                    selected: _category,
                    searching: _search.text.trim().isNotEmpty,
                    onChosen: (category) => setState(() {
                      _category = category;
                      _search.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 26),
                Expanded(
                  child: templates.isEmpty
                      ? _Nothing(palette: palette)
                      : _Grid(
                          palette: palette,
                          templates: templates,
                          busy: _busy,
                          onChosen: (template) => unawaited(_use(template)),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.search,
    required this.onChanged,
  });

  final DashboardPalette palette;
  final TextEditingController search;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.templates_title.tr(),
                  style: DashboardType.title(palette),
                ),
                const SizedBox(height: 5),
                Text(
                  LocaleKeys.templates_body.tr(),
                  style: DashboardType.caption(palette).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 246,
            child: TemplateSearchField(
              palette: palette,
              controller: search,
              onChanged: onChanged,
            ),
          ),
        ],
      );
}

/// The one field on the page, so it carries the editing keys itself.
class TemplateSearchField extends StatelessWidget {
  const TemplateSearchField({
    super.key,
    required this.palette,
    required this.controller,
    required this.onChanged,
  });

  final DashboardPalette palette;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextEntryShortcuts(
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  style: DashboardType.body(palette).copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: LocaleKeys.templates_search.tr(),
                    hintStyle: DashboardType.caption(palette)
                        .copyWith(fontSize: 13),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    controller.clear();
                    onChanged();
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: palette.textMuted,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Shelves extends StatelessWidget {
  const _Shelves({
    required this.palette,
    required this.selected,
    required this.searching,
    required this.onChosen,
  });

  final DashboardPalette palette;
  final TemplateCategory? selected;
  final bool searching;
  final ValueChanged<TemplateCategory?> onChosen;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.zero,
        children: [
          _ShelfRow(
            palette: palette,
            icon: Icons.auto_awesome_rounded,
            label: LocaleKeys.templates_featured.tr(),
            selected: !searching && selected == null,
            onTap: () => onChosen(null),
          ),
          const SizedBox(height: 10),
          for (final category in TemplateCategory.values)
            _ShelfRow(
              palette: palette,
              icon: category.icon,
              label: category.label,
              selected: !searching && selected == category,
              onTap: () => onChosen(category),
            ),
        ],
      );
}

class _ShelfRow extends StatefulWidget {
  const _ShelfRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DashboardPalette palette;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<_ShelfRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final ink = widget.selected ? palette.accent : palette.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.accent.withValues(alpha: 0.12)
                : palette.hover.withValues(alpha: _hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.palette,
    required this.templates,
    required this.busy,
    required this.onChosen,
  });

  final DashboardPalette palette;
  final List<WorkspaceTemplate> templates;
  final bool busy;
  final ValueChanged<WorkspaceTemplate> onChosen;

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        absorbing: busy,
        child: AnimatedOpacity(
          duration: DashboardMetrics.hover,
          opacity: busy ? 0.6 : 1,
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 330,
              mainAxisExtent: 136,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: templates.length,
            itemBuilder: (_, index) => TemplateCard(
              template: templates[index],
              palette: palette,
              onChosen: () => onChosen(templates[index]),
            ),
          ),
        ),
      );
}

class _Nothing extends StatelessWidget {
  const _Nothing({required this.palette});

  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 26, color: palette.textMuted),
            const SizedBox(height: 12),
            Text(
              LocaleKeys.templates_noResults.tr(),
              style: DashboardType.cardTitle(
                palette,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              LocaleKeys.templates_noResultsHint.tr(),
              style: DashboardType.caption(palette).copyWith(fontSize: 12.5),
            ),
          ],
        ),
      );
}
