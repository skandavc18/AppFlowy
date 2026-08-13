import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_add_menu.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_panel.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_home.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_template_gallery.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_variables_bar.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A dashboard, open.
///
/// The page owns the controller and nothing else: the header switches modes,
/// the canvas arranges the widgets and the panel configures one of them. Every
/// one of those reads the same controller, so a change made anywhere reaches
/// everywhere without a bus in the middle.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.view,
    this.immersive = false,
    this.controller,
  });

  final ViewPB view;

  /// Fullscreen or presentation: no page chrome, larger measure.
  final bool immersive;

  /// A borrowed controller, so a fullscreen dashboard is the SAME dashboard —
  /// same state, same selection, same unsaved changes.
  final DashboardController? controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late DashboardController _controller;
  bool _ownsController = false;
  ViewListener? _listener;
  String _name = '';
  bool _renaming = false;
  bool _editingSubtitle = false;

  /// Where the sections are, so a widget can be dragged from one to another.
  final DashboardSectionRegistry _sections = DashboardSectionRegistry();

  @override
  void initState() {
    super.initState();
    _name = widget.view.name;
    final borrowed = widget.controller;
    if (borrowed != null) {
      _controller = borrowed;
    } else {
      _ownsController = true;
      _controller = DashboardController(
        viewId: widget.view.id,
        document: widget.view.dashboard?.document ?? DashboardDocument.blank(),
      );
      _listener = ViewListener(viewId: widget.view.id)
        ..start(
          onViewUpdated: (view) {
            if (mounted) {
              setState(() => _name = view.name);
              _controller.adoptFromView(view);
            }
          },
        );
    }
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    unawaited(_listener?.stop());
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final document = _controller.document;
    final immersive = widget.immersive || _controller.mode.isImmersive;

    final body = document.isEmpty && _controller.isEditable
        ? DashboardTemplateGallery(
            palette: palette,
            onChosen: (template) => _controller.replace(template.build()),
          )
        : _buildBoard(palette, document);

    Widget page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (document.settings.showHeader || _controller.isEditable)
          _buildHeader(palette, immersive),
        Expanded(child: body),
      ],
    );

    if (_controller.configuringWidgetId != null && _controller.isEditable) {
      final spec = document.widgetById(_controller.configuringWidgetId!);
      if (spec != null) {
        // The panel floats over the board rather than taking width from it:
        // reflowing the canvas would change the column count and move the
        // card out from under the pointer.
        page = Stack(
          children: [
            Positioned.fill(child: page),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: DashboardConfigPanel(
                controller: _controller,
                palette: palette,
                spec: spec,
              ),
            ),
          ],
        );
      }
    }

    final modalId = _controller.modalWidgetId;
    if (modalId != null) {
      page = Stack(
        children: [
          page,
          Positioned.fill(
            child: _ModalWidget(
              controller: _controller,
              palette: palette,
              widgetId: modalId,
            ),
          ),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_controller.modalWidgetId != null) {
            _controller.openModal(null);
          } else if (_controller.configuringWidgetId != null) {
            _controller.closeSettings();
          } else if (_controller.selectedWidgetId != null) {
            _controller.select(null);
          } else if (widget.immersive) {
            Navigator.of(context).maybePop();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _controller.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _controller.redo,
      },
      child: Focus(
        autofocus: widget.immersive,
        child: ColoredBox(
          color: _controller.mode == DashboardMode.presentation
              ? palette.canvas
              : Colors.transparent,
          child: page,
        ),
      ),
    );
  }

  Widget _buildBoard(DashboardPalette palette, DashboardDocument document) {
    final maxWidth = document.settings.maxWidth;
    final presenting = _controller.mode == DashboardMode.presentation;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (document.settings.showControlBar)
          DashboardVariablesBar(controller: _controller, palette: palette),
        for (final section in document.sections)
          DashboardSectionView(
            key: ValueKey(section.id),
            controller: _controller,
            section: section,
            palette: palette,
          ),
        if (_controller.isEditable) _buildAddSection(palette),
        SizedBox(height: presenting ? 40 : 80),
      ],
    );

    return _paintBackdrop(
      palette,
      document.settings,
      SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          presenting ? 48 : 28,
          8,
          presenting ? 48 : 28,
          0,
        ),
        child: MediaQuery(
          // A dashboard on a wall is read from further away.
          data: MediaQuery.of(context).copyWith(
            textScaler: presenting
                ? const TextScaler.linear(1.18)
                : MediaQuery.textScalerOf(context),
          ),
          child: DashboardBoard(
            registry: _sections,
            child: maxWidth > 0
                ? Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: content,
                    ),
                  )
                : content,
          ),
        ),
      ),
    );
  }

  /// The board's own surface. It sits behind the scroll view so a tint covers
  /// the whole board rather than only as far as the widgets reach.
  Widget _paintBackdrop(
    DashboardPalette palette,
    DashboardSettings settings,
    Widget child,
  ) =>
      switch (settings.background) {
        DashboardBackground.canvas => child,
        DashboardBackground.tinted => ColoredBox(
            color: palette.sunken.withValues(alpha: palette.isDark ? 0.5 : 0.7),
            child: child,
          ),
        DashboardBackground.grid => DashboardGridBackdrop(
            palette: palette,
            step: settings.density.rowHeight + settings.density.gap,
            child: child,
          ),
      };

  Widget _buildAddSection(DashboardPalette palette) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: DashboardButton(
            label: LocaleKeys.dashboard_section_add.tr(),
            icon: Icons.add_rounded,
            palette: palette,
            onPressed: () => _controller.edit(
              (document) => document.copyWith(
                sections: [
                  ...document.sections,
                  DashboardSection(id: newDashboardId('section')),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildHeader(DashboardPalette palette, bool immersive) {
    final document = _controller.document;
    final presenting = _controller.mode == DashboardMode.presentation;
    return Padding(
      padding: EdgeInsets.fromLTRB(presenting ? 48 : 28, 18, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                WorkspaceInlineEditableText(
                  text: _name.isEmpty
                      ? LocaleKeys.dashboard_untitled.tr()
                      : _name,
                  editingValue: _name,
                  editing: _renaming,
                  style: DashboardType.title(
                    palette,
                    size: presenting ? 28 : 22,
                  ),
                  onTap: presenting ? null : _beginRename,
                  onSubmitted: _rename,
                  onCancelled: () => setState(() => _renaming = false),
                ),
                if (document.subtitle.isNotEmpty || _controller.isEditable)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: WorkspaceInlineEditableText(
                      text: document.subtitle.isEmpty
                          ? LocaleKeys.dashboard_addDescription.tr()
                          : document.subtitle,
                      editingValue: document.subtitle,
                      editing: _editingSubtitle,
                      style: DashboardType.caption(palette).copyWith(
                        color: document.subtitle.isEmpty
                            ? palette.textMuted.withValues(alpha: 0.7)
                            : palette.textMuted,
                      ),
                      onTap: presenting
                          ? null
                          : () => setState(() => _editingSubtitle = true),
                      onSubmitted: (value) async {
                        setState(() => _editingSubtitle = false);
                        _controller.edit(
                          (document) =>
                              document.copyWith(subtitle: value.trim()),
                        );
                        return true;
                      },
                      onCancelled: () =>
                          setState(() => _editingSubtitle = false),
                    ),
                  ),
              ],
            ),
          ),
          if (!presenting) ...[
            DashboardIconButton(
              icon: Icons.undo_rounded,
              palette: palette,
              tooltip: LocaleKeys.toolbar_undo.tr(),
              onPressed: _controller.canUndo ? _controller.undo : null,
            ),
            DashboardIconButton(
              icon: Icons.redo_rounded,
              palette: palette,
              tooltip: LocaleKeys.toolbar_redo.tr(),
              onPressed: _controller.canRedo ? _controller.redo : null,
            ),
            DashboardIconButton(
              icon: Icons.refresh_rounded,
              palette: palette,
              tooltip: LocaleKeys.dashboard_action_refresh.tr(),
              onPressed: _controller.refresh,
            ),
            const SizedBox(width: 4),
            DashboardButton(
              label: LocaleKeys.dashboard_add_widget.tr(),
              icon: Icons.add_rounded,
              palette: palette,
              primary: true,
              onPressed: _addWidget,
            ),
            const SizedBox(width: 6),
            DashboardIconButton(
              icon: Icons.open_in_full_rounded,
              palette: palette,
              tooltip: LocaleKeys.dashboard_mode_focus.tr(),
              onPressed: _toggleFullscreen,
            ),
            // The menu is anchored to the button, so it needs the button's own
            // context rather than the page's.
            Builder(
              builder: (anchor) => DashboardIconButton(
                icon: Icons.more_horiz_rounded,
                palette: palette,
                tooltip: LocaleKeys.dashboard_options.tr(),
                onPressed: () => _showOptions(anchor, palette),
              ),
            ),
          ] else
            DashboardIconButton(
              icon: Icons.close_fullscreen_rounded,
              palette: palette,
              tooltip: LocaleKeys.button_close.tr(),
              onPressed: () => _controller.setMode(DashboardMode.edit),
            ),
        ],
      ),
    );
  }

  Future<void> _addWidget() async {
    final definition = await showDashboardWidgetPicker(
      context: context,
      palette: DashboardPalette.of(context),
    );
    if (definition == null) {
      return;
    }
    _controller.edit((document) => document.addWidget(definition.create()));
  }

  void _showOptions(BuildContext anchor, DashboardPalette palette) {
    final document = _controller.document;
    showAppMenuForWidget<void>(
      context: anchor,
      entries: [
        AppMenuItem(
          label: LocaleKeys.dashboard_mode_presentation.tr(),
          icon: Icons.slideshow_rounded,
          onSelected: () => _openImmersive(DashboardMode.presentation),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_density.tr(),
          icon: Icons.density_medium_rounded,
          submenu: [
            for (final density in DashboardDensity.values)
              AppMenuItem(
                label: switch (density) {
                  DashboardDensity.compact =>
                    LocaleKeys.dashboard_density_compact.tr(),
                  DashboardDensity.comfortable =>
                    LocaleKeys.dashboard_density_comfortable.tr(),
                  DashboardDensity.spacious =>
                    LocaleKeys.dashboard_density_spacious.tr(),
                },
                selected: document.settings.density == density,
                onSelected: () => _controller.edit(
                  (document) => document.copyWith(
                    settings: document.settings.copyWith(density: density),
                  ),
                ),
              ),
          ],
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_background.tr(),
          icon: Icons.grid_4x4_rounded,
          submenu: [
            for (final background in DashboardBackground.values)
              AppMenuItem(
                label: switch (background) {
                  DashboardBackground.canvas =>
                    LocaleKeys.dashboard_background_plain.tr(),
                  DashboardBackground.tinted =>
                    LocaleKeys.dashboard_background_tinted.tr(),
                  DashboardBackground.grid =>
                    LocaleKeys.dashboard_background_grid.tr(),
                },
                selected: document.settings.background == background,
                onSelected: () => _controller.edit(
                  (document) => document.copyWith(
                    settings:
                        document.settings.copyWith(background: background),
                  ),
                ),
              ),
          ],
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_layout.tr(),
          icon: Icons.dashboard_customize_rounded,
          submenu: [
            for (final layout in DashboardSectionLayout.values)
              AppMenuItem(
                label: dashboardSectionLayoutLabel(layout),
                icon: dashboardSectionLayoutIcon(layout),
                selected: document.sections.isNotEmpty &&
                    document.sections
                        .every((section) => section.layout == layout),
                onSelected: () => _applyLayout(layout),
              ),
          ],
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_columns.tr(),
          icon: Icons.view_column_rounded,
          submenu: [
            AppMenuItem(
              label: LocaleKeys.dashboard_columns_auto.tr(),
              selected: document.settings.columns == 0,
              onSelected: () => _setColumns(0),
            ),
            for (final count in const [2, 3, 4, 6, 8, 12])
              AppMenuItem(
                label: '$count',
                selected: document.settings.columns == count,
                onSelected: () => _setColumns(count),
              ),
          ],
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_stillness.tr(),
          icon: Icons.motion_photos_off_rounded,
          selected: document.settings.reduceMotion,
          onSelected: () => _controller.edit(
            (document) => document.copyWith(
              settings: document.settings.copyWith(
                reduceMotion: !document.settings.reduceMotion,
              ),
            ),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_narrow.tr(),
          icon: Icons.format_align_center_rounded,
          selected: document.settings.maxWidth > 0,
          onSelected: () => _controller.edit(
            (document) => document.copyWith(
              settings: document.settings.copyWith(
                maxWidth: document.settings.maxWidth > 0 ? 0 : 1200,
              ),
            ),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_setHome.tr(),
          icon: Icons.home_rounded,
          selected: DashboardHome.instance.viewId == widget.view.id,
          onSelected: () => unawaited(
            DashboardHome.instance.toggle(widget.view.id),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_startOver.tr(),
          icon: Icons.restart_alt_rounded,
          onSelected: () => _controller.replace(DashboardDocument.blank()),
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_option_turnBack.tr(),
          icon: Icons.description_rounded,
          onSelected: () => unawaited(_turnBackIntoPage()),
        ),
      ],
    );
  }

  /// Give every section the same arrangement, so a whole dashboard can be
  /// tidied without visiting each band's own menu.
  void _applyLayout(DashboardSectionLayout layout) => _controller.edit(
        (document) => document.copyWith(
          sections: [
            for (final section in document.sections)
              section.copyWith(
                layout: layout,
                widgets: applySectionLayout(section.widgets, layout),
              ),
          ],
        ),
      );

  void _setColumns(int columns) => _controller.edit(
        (document) => document.copyWith(
          settings: document.settings.copyWith(columns: columns),
        ),
      );

  /// Give the page back its ordinary reading. The body was never touched, so
  /// whatever was written on it before is still there.
  Future<void> _turnBackIntoPage() async {
    await _controller.flush();
    final current = await ViewBackendService.getView(widget.view.id);
    final view = current.fold<ViewPB?>((view) => view, (_) => null);
    if (view != null) {
      await DashboardService.revert(view);
    }
  }

  void _beginRename() {
    if (_controller.mode == DashboardMode.presentation) {
      return;
    }
    setState(() => _renaming = true);
  }

  Future<bool> _rename(String name) async {
    setState(() {
      _renaming = false;
      _name = name.trim();
    });
    final result = await ViewBackendService.updateView(
      viewId: widget.view.id,
      name: name.trim(),
    );
    return result.fold((_) => true, (_) => false);
  }

  void _toggleFullscreen() {
    if (widget.immersive) {
      Navigator.of(context).maybePop();
    } else {
      _openImmersive(DashboardMode.focus);
    }
  }

  Future<void> _openImmersive(DashboardMode mode) async {
    final previous = _controller.mode;
    _controller.setMode(mode);
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: DashboardMetrics.settle,
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: DashboardPalette.of(context).canvas,
          body: DashboardPage(
            view: widget.view,
            immersive: true,
            controller: _controller,
          ),
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (mounted) {
      _controller.setMode(
        previous.isImmersive ? DashboardMode.edit : previous,
      );
    }
  }
}

/// One widget, shown on its own over the dashboard.
class _ModalWidget extends StatelessWidget {
  const _ModalWidget({
    required this.controller,
    required this.palette,
    required this.widgetId,
  });

  final DashboardController controller;
  final DashboardPalette palette;
  final String widgetId;

  @override
  Widget build(BuildContext context) {
    final spec = controller.document.widgetById(widgetId);
    final definition =
        spec == null ? null : DashboardWidgetRegistry.definitionFor(spec.type);
    if (spec == null || definition == null) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () => controller.openModal(null),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: palette.isDark ? 0.55 : 0.3),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 900,
              height: 620,
              margin: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: palette.toneFor(spec.accent).surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: palette.cardShadow(raised: true),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 10, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            spec.title.isEmpty
                                ? definition.label()
                                : spec.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardType.title(palette, size: 16),
                          ),
                        ),
                        DashboardIconButton(
                          icon: Icons.close_rounded,
                          palette: palette,
                          tooltip: LocaleKeys.button_close.tr(),
                          onPressed: () => controller.openModal(null),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: definition.builder(
                        DashboardWidgetContext(
                          context: context,
                          controller: controller,
                          spec: spec,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
