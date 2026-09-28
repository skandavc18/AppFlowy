import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_add_menu.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_panel.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_home.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_template_gallery.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_variables_bar.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    this.userProfile,
  });

  final ViewPB view;
  final UserProfilePB? userProfile;

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
  late DashboardFindController _find;
  bool _ownsController = false;
  ViewListener? _listener;
  String _name = '';
  late ViewPB _view;
  bool _renaming = false;
  bool _editingSubtitle = false;

  /// Where the sections are, so a widget can be dragged from one to another.
  final DashboardSectionRegistry _sections = DashboardSectionRegistry();

  @override
  void initState() {
    super.initState();
    _view = widget.view;
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
    }
    _find = DashboardFindController(_controller, title: () => _name);
    if (_ownsController) {
      _listener = ViewListener(viewId: widget.view.id)
        ..start(
          onViewUpdated: (view) {
            if (mounted && view.id == _view.id) {
              setState(() {
                _view = view;
                _name = view.name;
              });
              _controller.adoptFromView(view);
              _find.refresh();
            }
          },
        );
    }
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      _view = widget.view;
      _name = widget.view.name;
    }
    final borrowed = widget.controller;
    if (borrowed != null && borrowed != _controller) {
      final previousController = _controller;
      final previousFind = _find;
      final owned = _ownsController;
      previousController.removeListener(_onChanged);
      unawaited(_listener?.stop());
      _listener = null;
      _controller = borrowed;
      _ownsController = false;
      _find = DashboardFindController(_controller, title: () => _name);
      _controller.addListener(_onChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousFind.dispose();
        if (owned) previousController.dispose();
      });
    }
    final access = context.read<PageAccessLevelBloc?>();
    _controller.setReadOnly(
      _view.isLocked || (access != null && !access.state.isEditable),
      notify: false,
    );
    final find = _find;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(find, _find)) find.refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.watch<PageAccessLevelBloc?>();
    final editable =
        !_view.isLocked && (access == null || access.state.isEditable);
    _controller.setReadOnly(!editable, notify: false);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _find.dispose();
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

    // Identity and content belong to one page scroll. A fixed editor toolbar
    // above a separately scrolling board made Home feel like an application
    // module rather than a workspace, and stole room from every widget.
    Widget page = _buildBoard(palette, document, immersive);

    Widget? configuration;
    if (_controller.configuringWidgetId != null && _controller.isEditable) {
      final spec = document.widgetById(_controller.configuringWidgetId!);
      if (spec != null) {
        // The panel floats over the board rather than taking width from it:
        // reflowing the canvas would change the column count and move the
        // card out from under the pointer.
        configuration = Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          child: DashboardConfigPanel(
            controller: _controller,
            palette: palette,
            spec: spec,
          ),
        );
      }
    }

    final modalId = _controller.modalWidgetId;
    // Keep the board at one tree depth when a settings/modal layer appears.
    // Reparenting it here would discard widget drafts and native preview state.
    page = Stack(
      children: [
        Positioned.fill(child: page),
        if (configuration != null) configuration,
        if (modalId != null)
          Positioned.fill(
            child: _ModalWidget(
              controller: _controller,
              palette: palette,
              widgetId: modalId,
            ),
          ),
      ],
    );
    // The modal and configuration fields need the same live access check as
    // cards, including while an outgoing borrowed page is being disposed.
    page = DashboardEditingScope(controller: _controller, child: page);
    page = SurfaceFindHost(
      controller: _find,
      debugLabel: 'Dashboard find',
      hintText: 'Find dashboard and loaded embeds',
      coverageText: _find.coverageLabel,
      child: page,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_find.isOpen) {
            _find.close();
          } else if (_controller.modalWidgetId != null) {
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

  Widget _buildBoard(
    DashboardPalette palette,
    DashboardDocument document,
    bool immersive,
  ) {
    final maxWidth = document.settings.maxWidth;
    final presenting = _controller.mode == DashboardMode.presentation;

    final content = document.isEmpty && _controller.isEditable
        ? DashboardTemplateGallery(
            palette: palette,
            embedded: true,
            onChosen: (template) => _controller.replace(template.build()),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (document.settings.showControlBar)
                DashboardVariablesBar(
                  controller: _controller,
                  palette: palette,
                ),
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
      LayoutBuilder(
        builder: (context, constraints) {
          final inset = WorkspaceTokens.pageInset(constraints.maxWidth);
          return SingleChildScrollView(
            key: const PageStorageKey('dashboard-workspace-scroll'),
            child: MediaQuery(
              // A dashboard on a wall is read from further away.
              data: MediaQuery.of(context).copyWith(
                textScaler: presenting
                    ? const TextScaler.linear(1.18)
                    : MediaQuery.textScalerOf(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (document.settings.showHeader || _controller.isEditable)
                    _buildHeader(palette, immersive, inset),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxWidth > 0 ? maxWidth : double.infinity,
                        ),
                        child: DashboardBoard(
                          registry: _sections,
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    DashboardPalette palette,
    bool immersive,
    double inset,
  ) {
    final document = _controller.document;
    final presenting = _controller.mode == DashboardMode.presentation;
    final editable = !presenting && _controller.isEditable;
    final cover = _view.cover;
    final icon = _view.icon.toEmojiIconData();
    final glyph = icon.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: icon,
            emojiSize: WorkspaceTokens.pageIconSize,
            opticalRole: IconOpticalRole.header,
          )
        : WorkspaceGlyph.named(
            DashboardHome.instance.viewId == _view.id ? 'house' : 'layout',
            size: WorkspaceTokens.pageIconSize,
            color: palette.accent,
          );
    return PreviewToolbarRegion(
      child: ViewDecorationActions(
        view: _view,
        userProfile: widget.userProfile,
        visible: _renaming || _editingSubtitle || immersive,
        showIconAction: editable,
        showCoverAction: editable,
        showDownloadAction: !immersive,
        onViewChanged: _adoptDecoration,
        layoutBuilder: (iconActions, coverActions, pageActions) =>
            WorkspacePageHeader(
          maxWidth: document.settings.maxWidth > 0
              ? document.settings.maxWidth + inset * 2
              : double.infinity,
          contentInset: inset,
          cover: !immersive && cover != null && !cover.isNone
              ? ViewCoverImage(
                  cover: cover,
                  userProfile: widget.userProfile,
                  width: double.infinity,
                )
              : null,
          coverActions: coverActions,
          coverView: _view,
          coverBinding: _controller,
          coverEditable: editable && !immersive,
          canResizeCover: () =>
              mounted &&
              !widget.immersive &&
              _controller.isEditable &&
              !_controller.mode.isImmersive,
          isSameCoverTarget: (fresh) => fresh.dashboard != null,
          onCoverHeightChanged: (height) =>
              _adoptDecoration(PageCoverHeight.applyTo(_view, height)),
          identity: WorkspacePageIdentity(
            icon: ResizablePageIcon(
              view: _view,
              binding: _controller,
              editable: editable,
              canResize: () =>
                  mounted &&
                  _controller.isEditable &&
                  _controller.mode != DashboardMode.presentation,
              isSameTarget: (fresh) => fresh.dashboard != null,
              defaultSize: icon.isNotEmpty
                  ? IconOpticalSize.resolve(
                      role: IconOpticalRole.header,
                      baseSize: WorkspaceTokens.pageIconSize,
                    ).slotSize
                  : WorkspaceTokens.pageIconSize,
              onSizeChanged: (size) =>
                  _adoptDecoration(IconSize.applyTo(_view, size)),
              builder: (size, _) => editable
                  ? ViewIconPicker(
                      view: _view,
                      onViewChanged: _adoptDecoration,
                      child: PageIconArtwork(size: size, child: glyph),
                    )
                  : PageIconArtwork(size: size, child: glyph),
            ),
            iconActions: iconActions,
            title: SurfaceFindTarget(
              id: dashboardFindTitle,
              child: ExcludeFocus(
                excluding: !editable,
                child: IgnorePointer(
                  ignoring: !editable,
                  child: WorkspaceInlineEditableText(
                    key: const ValueKey('dashboard-page-title'),
                    text: _name.isEmpty
                        ? LocaleKeys.dashboard_untitled.tr()
                        : _name,
                    editingValue: _name,
                    editing: _renaming,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.pageTitle,
                    ),
                    onTap: editable ? _beginRename : null,
                    onSubmitted: _rename,
                    onCancelled: () => setState(() => _renaming = false),
                  ),
                ),
              ),
            ),
            description: document.subtitle.isNotEmpty || _editingSubtitle
                ? SurfaceFindTarget(
                    id: dashboardFindSubtitle,
                    child: ExcludeFocus(
                      excluding: !editable,
                      child: IgnorePointer(
                        ignoring: !editable,
                        child: WorkspaceInlineEditableText(
                          text: document.subtitle.isEmpty
                              ? LocaleKeys.dashboard_addDescription.tr()
                              : document.subtitle,
                          editingValue: document.subtitle,
                          editing: _editingSubtitle,
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.body,
                            color: palette.textSecondary,
                          ),
                          onTap: editable
                              ? () => setState(() => _editingSubtitle = true)
                              : null,
                          onSubmitted: (value) async {
                            if (!_controller.isEditable) return false;
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
                    ),
                  )
                : null,
            actions: pageActions,
          ),
        ),
        children: [
          if (editable) ...[
            DashboardButton(
              key: const ValueKey('dashboard-add-widget'),
              label: LocaleKeys.dashboard_add_widget.tr(),
              icon: Icons.add_rounded,
              palette: palette,
              onPressed: _addWidget,
            ),
            Builder(
              key: const ValueKey('dashboard-options'),
              builder: (anchor) => DashboardIconButton(
                icon: Icons.more_horiz_rounded,
                palette: palette,
                tooltip: LocaleKeys.dashboard_options.tr(),
                onPressed: () => _showOptions(anchor, palette),
              ),
            ),
          ],
          if (immersive)
            DashboardIconButton(
              key: const ValueKey('dashboard-exit-immersive'),
              icon: Icons.close_fullscreen_rounded,
              palette: palette,
              tooltip: LocaleKeys.button_close.tr(),
              onPressed: _toggleFullscreen,
            ),
        ],
      ),
    );
  }

  void _adoptDecoration(ViewPB view) {
    if (mounted && view.id == _view.id) {
      setState(() => _view = view);
    }
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

  Future<void> _addWidget() async {
    if (!_controller.isEditable) return;
    final definition = await showDashboardWidgetPicker(
      context: context,
      palette: DashboardPalette.of(context),
    );
    if (!mounted || definition == null || !_controller.isEditable) {
      return;
    }
    _controller.edit((document) => document.addWidget(definition.create()));
  }

  void _showOptions(BuildContext anchor, DashboardPalette palette) {
    if (!_controller.isEditable) return;
    final document = _controller.document;
    showAppMenuForWidget<void>(
      context: anchor,
      entries: [
        AppMenuItem(
          label: LocaleKeys.toolbar_undo.tr(),
          icon: Icons.undo_rounded,
          enabled: _controller.canUndo,
          onSelected: _controller.undo,
        ),
        AppMenuItem(
          label: LocaleKeys.toolbar_redo.tr(),
          icon: Icons.redo_rounded,
          enabled: _controller.canRedo,
          onSelected: _controller.redo,
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_action_refresh.tr(),
          icon: Icons.refresh_rounded,
          onSelected: _controller.refresh,
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_addDescription.tr(),
          icon: Icons.notes_rounded,
          onSelected: () => setState(() => _editingSubtitle = true),
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_mode_focus.tr(),
          icon: Icons.open_in_full_rounded,
          onSelected: _toggleFullscreen,
        ),
        const AppMenuSeparator(),
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
    if (!_controller.isEditable) return;
    await _controller.flush();
    final current = await ViewBackendService.getView(widget.view.id);
    final view = current.fold<ViewPB?>((view) => view, (_) => null);
    if (view != null && mounted && _controller.isEditable) {
      await DashboardService.revert(view);
    }
  }

  void _beginRename() {
    if (!_controller.isEditable) {
      return;
    }
    setState(() => _renaming = true);
  }

  Future<bool> _rename(String name) async {
    if (!_controller.isEditable) return false;
    setState(() {
      _renaming = false;
      _name = name.trim();
    });
    _find.refresh();
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
    final access = context.read<PageAccessLevelBloc?>();
    _controller.setMode(mode);
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.transitionDuration),
        reverseTransitionDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.exitDuration),
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: DashboardPalette.of(context).canvas,
          body: Builder(
            builder: (_) {
              final page = DashboardPage(
                view: _view,
                immersive: true,
                controller: _controller,
                userProfile: widget.userProfile,
              );
              final scoped =
                  ContextualFindScope(findInControls: true, child: page);
              return access == null
                  ? scoped
                  : BlocProvider<PageAccessLevelBloc>.value(
                      value: access,
                      child: scoped,
                    );
            },
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
    final widgetContext = DashboardWidgetContext(
      context: context,
      controller: controller,
      spec: spec,
      palette: palette,
    );
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
                        if (definition.headerTrailing != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 240),
                                child:
                                    definition.headerTrailing!(widgetContext),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
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
                      child: definition.builder(widgetContext),
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
