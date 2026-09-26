import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// An interactive collection widget living inside a document.
///
/// The frame is deliberately thin: it owns the surface, the sizing, the
/// controls and the menu, and hands everything else to the preview the
/// collection type registered. A type therefore never has to reimplement
/// hover, resize, fullscreen or the context menu.
class CollectionEmbed extends StatefulWidget {
  const CollectionEmbed({
    super.key,
    required this.collection,
    required this.settings,
    required this.onSettingsChanged,
    this.userProfile,
    this.width = CollectionEmbedMetrics.defaultWidth,
    this.height,
    this.alignment = Alignment.center,
    this.onResizeWidth,
    this.onResizeHeight,
    this.editable = true,
    this.onChangeCollection,
    this.onRemove,
    this.fullscreen = false,
    this.controller,
    this.onInteractionFocus,
    this.canEdit,
    this.onSessionSettingsChanged,
  });

  final ViewPB collection;
  final CollectionEmbedSettings settings;
  final ValueChanged<CollectionEmbedSettings> onSettingsChanged;
  final UserProfilePB? userProfile;
  final double width;

  /// An explicit height, set by dragging the bottom handle. `null` means the
  /// size preset decides.
  final double? height;

  /// Where the widget sits on the page.
  final Alignment alignment;
  final ValueChanged<double>? onResizeWidth;
  final ValueChanged<double>? onResizeHeight;
  final bool editable;
  final VoidCallback? onChangeCollection;
  final VoidCallback? onRemove;
  final bool fullscreen;

  /// A borrowed controller. Fullscreen passes the page's own so the widget
  /// and its expanded form never read the collection twice.
  final CollectionEmbedController? controller;

  /// Raised when something inside the widget takes focus.
  ///
  /// The host clears the editor's selection there: appflowy_editor's key
  /// handling sits *above* any embedded field, so without it Backspace inside
  /// the widget deletes the whole block.
  final VoidCallback? onInteractionFocus;

  /// Live owner guard for an expanded route; it cannot retain permission from
  /// an earlier editable snapshot after the embedding page is locked/removed.
  final bool Function()? canEdit;
  final ValueChanged<CollectionEmbedSettings>? onSessionSettingsChanged;

  @override
  State<CollectionEmbed> createState() => _CollectionEmbedState();
}

class _CollectionEmbedState extends State<CollectionEmbed> {
  late CollectionEmbedController controller;
  bool ownsController = false;
  bool hovered = false;
  bool menuOpen = false;
  CollectionEmbedSettings? _sessionSettings;

  CollectionEmbedSettings get _settings => _sessionSettings ?? widget.settings;
  bool get _canEdit =>
      mounted &&
      widget.editable &&
      !controller.collection.isLocked &&
      (widget.canEdit?.call() ?? true);

  @override
  void initState() {
    super.initState();
    _adoptController();
  }

  @override
  void didUpdateWidget(covariant CollectionEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) _sessionSettings = null;
    if (oldWidget.controller != widget.controller ||
        oldWidget.collection.id != widget.collection.id) {
      _sessionSettings = null;
      if (ownsController) {
        controller.dispose();
      }
      _adoptController();
    }
  }

  void _adoptController() {
    final borrowed = widget.controller;
    ownsController = borrowed == null;
    controller =
        borrowed ?? CollectionEmbedController(collection: widget.collection);
  }

  @override
  void dispose() {
    if (ownsController) {
      controller.dispose();
    }
    super.dispose();
  }

  CollectionKind? get kind => widget.collection.collection?.kind;

  @override
  Widget build(BuildContext context) {
    final theme = CollectionEmbedTheme.of(context, kind);
    final definition = CollectionEmbedRegistry.definitionFor(kind);

    Widget body = AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildSurface(context, theme, definition),
    );

    // The widget holds real scroll views and text fields; without this the
    // editor's own Backspace command would delete the block from under them.
    body = FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          widget.onInteractionFocus?.call();
        }
      },
      child: body,
    );

    if (widget.fullscreen) {
      // This also means "the dashboard owns the size", not just a dialog.
      return PreviewToolbarRegion(child: body);
    }

    return ResizableMedia(
      width: widget.width,
      minWidth: CollectionEmbedMetrics.minWidth,
      height: widget.height ?? definition.heightFor(_settings.size),
      minHeight: 96,
      alignment: widget.alignment,
      editable: _canEdit,
      onResize: widget.onResizeWidth ?? (_) {},
      onResizeHeight: widget.onResizeHeight,
      child: body,
    );
  }

  Widget _buildSurface(
    BuildContext context,
    CollectionEmbedTheme theme,
    CollectionEmbedDefinition definition,
  ) {
    final embed = _embedContext(context, theme, definition);
    final background = _settings.background;
    final flush = background == CollectionEmbedBackground.flush ||
        (definition.flush && background == CollectionEmbedBackground.surface);

    final preview = definition.builder(context, embed);
    final showHeading = definition.showsHeading && !flush;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
            child: _buildHeading(context, embed),
          ),
        Expanded(child: preview),
      ],
    );

    if (!showHeading) {
      // Flush previews and types with their own identity (book/album) still
      // need controls. Float them without adding a second heading.
      content = Stack(
        children: [
          Positioned.fill(child: preview),
          Positioned(
            top: 2,
            left: 2,
            right: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildControls(context, embed),
              ),
            ),
          ),
        ],
      );
    }

    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapDown: (details) =>
            unawaited(_showMenu(context, embed, details.globalPosition)),
        child: CollectionEmbedSurface(
          theme: theme,
          hovered: hovered && !widget.fullscreen,
          flush: flush,
          lift: !widget.fullscreen,
          color: background == CollectionEmbedBackground.tinted
              ? theme.accentWash
              : null,
          child: content,
        ),
      ),
    );
  }

  CollectionEmbedContext _embedContext(
    BuildContext context,
    CollectionEmbedTheme theme,
    CollectionEmbedDefinition definition,
  ) =>
      CollectionEmbedContext(
        collection: controller.collection,
        controller: controller,
        settings: _settings,
        theme: theme,
        definition: definition,
        userProfile: widget.userProfile,
        hovered: hovered || menuOpen,
        fullscreen: widget.fullscreen,
        editable: _canEdit,
        onSettingsChanged: _changeSettings,
        onOpenObject: _openObject,
        onOpenCollection: _openCollection,
        onFullscreen: _toggleFullscreen,
        onRefresh: () => unawaited(controller.refresh()),
        onShowMenu: (position) => unawaited(
          _showMenu(
            context,
            _embedContext(context, theme, definition),
            position,
          ),
        ),
      );

  Widget _buildHeading(BuildContext context, CollectionEmbedContext embed) {
    final theme = embed.theme;
    final count = controller.children.length;
    return CollectionEmbedHeading(
      theme: theme,
      title: controller.collection.name.isEmpty
          ? LocaleKeys.collections_untitled.tr()
          : controller.collection.name,
      dense: _settings.size.isCompact,
      onTap: _openCollection,
      subtitle: _settings.showMetadata
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (theme.typeLabel.isNotEmpty) ...[
                  Flexible(
                    child: Text(
                      theme.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  CollectionEmbedMetaDot(theme: theme),
                ],
                Text(
                  count == 1
                      ? LocaleKeys.collections_oneObject.tr()
                      : LocaleKeys.collections_objectCount.tr(args: ['$count']),
                ),
              ],
            )
          : null,
      trailing: _buildControls(context, embed),
    );
  }

  Widget _buildControls(BuildContext context, CollectionEmbedContext embed) {
    final theme = embed.theme;
    return PreviewToolbar(
      keepVisible: controller.error != null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CollectionEmbedButton(
            theme: theme,
            icon: widget.fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip: widget.fullscreen
                ? LocaleKeys.collections_embed_exitFullscreen.tr()
                : LocaleKeys.collections_embed_fullscreen.tr(),
            onPressed: _toggleFullscreen,
          ),
          CollectionEmbedButton(
            theme: theme,
            icon: Icons.open_in_new_rounded,
            tooltip: LocaleKeys.collections_embed_openCollection.tr(),
            onPressed: _openCollection,
          ),
          AppMenuIconButton(
            icon: Icons.more_horiz_rounded,
            iconColor: theme.textMuted,
            tooltip: LocaleKeys.collections_embed_blockOptions.tr(),
            onVisibilityChanged: (open) {
              if (mounted) setState(() => menuOpen = open);
            },
            entries: () => _menuEntries(embed),
          ),
        ],
      ),
    );
  }

  List<AppMenuEntry> _menuEntries(CollectionEmbedContext embed) =>
      collectionEmbedMenuEntries(
        embed: embed,
        onChangeCollection: widget.onChangeCollection,
        onRemove: widget.onRemove,
        onRename: _canEdit ? () => unawaited(_rename()) : null,
        onFavorite: () => unawaited(_favorite()),
        onDuplicate: _canEdit ? () => unawaited(_duplicate()) : null,
      );

  Future<void> _showMenu(
    BuildContext context,
    CollectionEmbedContext embed,
    Offset position,
  ) async {
    setState(() => menuOpen = true);
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: _menuEntries(embed),
    );
    if (mounted) {
      setState(() => menuOpen = false);
    }
  }

  void _openObject(ViewPB view) => context.read<TabsBloc>().openPlugin(view);

  void _openCollection() =>
      context.read<TabsBloc>().openPlugin(controller.collection);

  void _changeSettings(CollectionEmbedSettings next) {
    if (!mounted) return;
    setState(() => _sessionSettings = next);
    widget.onSessionSettingsChanged?.call(next);
    // Read-only browsing changes only this retained session, never the node or
    // collection. Recheck the live widget, not the menu's earlier snapshot.
    if (_canEdit) widget.onSettingsChanged(next);
  }

  void _toggleFullscreen() {
    if (widget.fullscreen) {
      Navigator.of(context).maybePop();
      return;
    }
    final owner = controller;
    final originalSize = _settings.size;
    unawaited(
      showCollectionEmbedFullscreen(
        context: context,
        collection: controller.collection,
        settings: _settings,
        onSettingsChanged: (next) {
          if (mounted && identical(controller, owner)) {
            _changeSettings(next.copyWith(size: originalSize));
          }
        },
        controller: controller,
        userProfile: widget.userProfile,
        editable: _canEdit,
        canEdit: () => mounted && identical(controller, owner) && _canEdit,
        onSessionSettingsChanged: (next) {
          if (mounted && identical(controller, owner)) {
            setState(
              () => _sessionSettings = next.copyWith(size: originalSize),
            );
          }
        },
      ),
    );
  }

  Future<void> _rename() async {
    if (!_canEdit) return;
    final view = controller.collection;
    final name = await showAFTextFieldDialog(
      context: context,
      title: LocaleKeys.collections_embed_rename.tr(),
      initialValue: view.name,
    );
    if (!_canEdit ||
        controller.collection.id != view.id ||
        name == null ||
        name.trim().isEmpty) {
      return;
    }
    await const WorkspaceItemService()
        .rename(viewId: view.id, name: name.trim());
  }

  Future<void> _favorite() async {
    await FavoriteService().toggleFavorite(controller.collection.id);
  }

  Future<void> _duplicate() async {
    if (!_canEdit) return;
    final view = controller.collection;
    final result = await const WorkspaceItemService().duplicate(
      view: view,
      parentViewId: view.parentViewId,
    );
    if (!mounted) {
      return;
    }
    result.fold(
      (_) {},
      (error) => showSnackBarMessage(context, error.msg),
    );
  }
}

/// Opens the widget at window size, keeping every setting it already has.
///
/// The transition grows the widget out of the page rather than fading a new
/// screen in, so it reads as the same object expanding.
Future<void> showCollectionEmbedFullscreen({
  required BuildContext context,
  required ViewPB collection,
  required CollectionEmbedSettings settings,
  required ValueChanged<CollectionEmbedSettings> onSettingsChanged,
  UserProfilePB? userProfile,
  bool editable = true,
  CollectionEmbedController? controller,
  bool Function()? canEdit,
  ValueChanged<CollectionEmbedSettings>? onSessionSettingsChanged,
}) async {
  final tabs = context.read<TabsBloc>();
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: LocaleKeys.collections_embed_fullscreen.tr(),
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context)
        ? Duration.zero
        : CollectionEmbedMetrics.reveal,
    pageBuilder: (dialogContext, animation, _) {
      final media = MediaQuery.sizeOf(dialogContext);
      return BlocProvider<TabsBloc>.value(
        value: tabs,
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(38),
              child: SizedBox(
                width: media.width,
                height: media.height,
                child: _FullscreenEmbed(
                  collection: collection,
                  settings: settings.copyWith(size: CollectionEmbedSize.large),
                  onSettingsChanged: onSettingsChanged,
                  userProfile: userProfile,
                  editable: editable,
                  controller: controller,
                  canEdit: canEdit,
                  onSessionSettingsChanged: onSessionSettingsChanged,
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FullscreenEmbed extends StatefulWidget {
  const _FullscreenEmbed({
    required this.collection,
    required this.settings,
    required this.onSettingsChanged,
    required this.userProfile,
    required this.editable,
    this.controller,
    this.canEdit,
    this.onSessionSettingsChanged,
  });

  final ViewPB collection;
  final CollectionEmbedSettings settings;
  final ValueChanged<CollectionEmbedSettings> onSettingsChanged;
  final UserProfilePB? userProfile;
  final bool editable;
  final CollectionEmbedController? controller;
  final bool Function()? canEdit;
  final ValueChanged<CollectionEmbedSettings>? onSessionSettingsChanged;

  @override
  State<_FullscreenEmbed> createState() => _FullscreenEmbedState();
}

class _FullscreenEmbedState extends State<_FullscreenEmbed> {
  late CollectionEmbedSettings settings = widget.settings;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(Navigator.of(context).maybePop()),
        },
        child: CollectionEmbed(
          collection: widget.collection,
          controller: widget.controller,
          canEdit: widget.canEdit,
          onSessionSettingsChanged: (next) {
            setState(() => settings = next);
            widget.onSessionSettingsChanged?.call(next);
          },
          settings: settings,
          fullscreen: true,
          editable: widget.editable,
          userProfile: widget.userProfile,
          onSettingsChanged: (next) {
            setState(() => settings = next);
            widget.onSettingsChanged(next);
          },
        ),
      );
}
