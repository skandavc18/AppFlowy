import 'dart:async';
import 'dart:math';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_menu_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'slash_menu_metadata.dart';

class AppFlowyDesktopSelectionMenu implements SelectionMenuService {
  AppFlowyDesktopSelectionMenu({
    required this.context,
    required this.editorState,
    required this.selectionMenuItems,
    this.deleteSlashByDefault = true,
    this.deleteKeywordsByDefault = false,
    this.style = SelectionMenuStyle.light,
  });

  final BuildContext context;
  final EditorState editorState;
  final List<SelectionMenuItem> selectionMenuItems;
  final bool deleteSlashByDefault;
  final bool deleteKeywordsByDefault;

  @override
  final SelectionMenuStyle style;

  OverlayEntry? _selectionMenuEntry;
  VoidCallback? _releaseServices;
  int _showRequest = 0;
  int? _pendingShow;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;

  @override
  Offset get offset => _offset;

  @override
  Alignment get alignment => _alignment;

  @override
  Future<void> show() {
    dismiss();
    final request = ++_showRequest;
    _pendingShow = request;
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (request == _pendingShow) {
          _pendingShow = null;
          if (context.mounted && !editorState.isDisposed) {
            _show();
          }
        }
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _show() {
    final selectionState = editorState.service.selectionServiceKey.currentState;
    final editorBox = editorState.renderBox;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (selectionState == null ||
        editorBox == null ||
        !editorBox.attached ||
        !editorBox.hasSize ||
        overlayBox is! RenderBox ||
        !overlayBox.hasSize) {
      return;
    }

    final routes = <ModalRoute<dynamic>>{};
    var route = ModalRoute.of(context);
    while (route != null && routes.add(route)) {
      final navigator = route.navigator;
      route = navigator == null ? null : ModalRoute.of(navigator.context);
    }
    bool ownerIsActive() =>
        context.mounted &&
        !editorState.isDisposed &&
        overlay!.mounted &&
        identical(
          editorState.service.selectionServiceKey.currentState,
          selectionState,
        ) &&
        routes.every((route) => route.isCurrent);
    if (!ownerIsActive()) {
      return;
    }

    final selectionService = editorState.service.selectionService;
    final selectionRects = selectionService.selectionRects;
    if (selectionRects.isEmpty) {
      return;
    }

    _calculateSelectionMenuOffset(selectionRects.first, editorBox, overlayBox);
    final (left, top, right, bottom) = getPosition();
    final selection = selectionService.currentSelection;
    final keyboard = editorState.service.keyboardService;
    final scroll = editorState.service.scrollService;
    final keyboardContext =
        editorState.service.keyboardServiceKey.currentContext;
    final editorFocusScope =
        keyboardContext == null ? null : FocusScope.of(keyboardContext);
    final menuKey = GlobalKey<_AppFlowyDesktopSelectionMenuWidgetState>();
    var servicesDisabled = false;
    var selectionUpdateByInner = false;
    late final OverlayEntry entry;
    bool isCurrentSession() => identical(_selectionMenuEntry, entry);
    void close() {
      if (isCurrentSession()) {
        dismiss();
      }
    }

    void onSelectionChange() {
      if (!isCurrentSession() || selection.value == null) {
        return;
      }
      if (selectionUpdateByInner) {
        selectionUpdateByInner = false;
      } else {
        close();
      }
    }

    for (final item in selectionMenuItems) {
      item
        ..deleteSlash = deleteSlashByDefault
        ..deleteKeywords = deleteKeywordsByDefault
        ..onSelected = close;
    }

    final menu = InheritedTheme.captureAll(
      context,
      AppFlowyDesktopSelectionMenuWidget(
        key: menuKey,
        items: selectionMenuItems,
        editorState: editorState,
        menuService: this,
        onExit: close,
        isActive: () => isCurrentSession() && ownerIsActive(),
        onSelectionUpdate: () {
          if (isCurrentSession()) {
            selectionUpdateByInner = true;
          }
        },
        selectionMenuStyle: style,
        deleteSlashByDefault: deleteSlashByDefault,
      ),
    );

    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                onSecondaryTap: close,
                onTertiaryTapUp: (_) => close(),
              ),
            ),
            Positioned(
              top: top,
              bottom: bottom,
              left: left,
              right: right,
              child: Listener(
                // Padding and headings belong to the menu, not the barrier.
                behavior: HitTestBehavior.opaque,
                child: menu,
              ),
            ),
          ],
        ),
      ),
    );

    _selectionMenuEntry = entry;
    _releaseServices = () {
      final closedAt = _showRequest;
      final menuFocus = menuKey.currentState?._focusNode;
      selection.removeListener(onSelectionChange);
      editorState.onDispose.removeListener(close);
      if (!servicesDisabled) {
        return;
      }
      if (identical(editorState.service.scrollService, scroll)) {
        scroll?.enable();
      }
      // Let a newer native field/route receive its pending focus first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (closedAt != _showRequest ||
            !ownerIsActive() ||
            !identical(editorState.service.keyboardService, keyboard)) {
          return;
        }
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null ||
            focus is FocusScopeNode ||
            identical(focus, menuFocus) ||
            (editorFocusScope?.descendants.contains(focus) ?? false)) {
          keyboard?.enable();
        }
      });
    };
    selection.addListener(onSelectionChange);
    editorState.onDispose.addListener(close);
    overlay!.insert(entry);

    void checkOwner(Duration _) {
      if (!isCurrentSession()) {
        return;
      }
      if (!ownerIsActive()) {
        close();
        return;
      }
      // Observe owner teardown on existing frames; never schedule a frame.
      WidgetsBinding.instance.addPostFrameCallback(checkOwner);
    }

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (!isCurrentSession() || !ownerIsActive()) {
        close();
        return;
      }
      // The menu has now acquired its keep-editor-focus hold in initState.
      // Unfocusing earlier can clear the document selection before it mounts.
      servicesDisabled = true;
      keyboard?.disable(showCursor: true);
      scroll?.disable();
      checkOwner(timeStamp);
    });
  }

  @override
  void dismiss() {
    _pendingShow = null;
    final entry = _selectionMenuEntry;
    final releaseServices = _releaseServices;
    _selectionMenuEntry = null;
    _releaseServices = null;
    entry?.remove();
    entry?.dispose();
    releaseServices?.call();
  }

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() {
    double? left, top, right, bottom;
    switch (alignment) {
      case Alignment.topLeft:
        left = offset.dx;
        top = offset.dy;
      case Alignment.bottomLeft:
        left = offset.dx;
        bottom = offset.dy;
      case Alignment.topRight:
        right = offset.dx;
        top = offset.dy;
      case Alignment.bottomRight:
        right = offset.dx;
        bottom = offset.dy;
      default:
        left = offset.dx;
        top = offset.dy;
    }
    return (left, top, right, bottom);
  }

  void _calculateSelectionMenuOffset(
    Rect rect,
    RenderBox editorBox,
    RenderBox overlayBox,
  ) {
    const menuOffset = Offset(0, 10);
    const menuHeight = AppFlowyEditorMenuStyle.slashMenuMaxHeight;
    const menuWidth = AppFlowyEditorMenuStyle.menuWidth;
    final editorBounds = Rect.fromPoints(
      overlayBox.globalToLocal(editorBox.localToGlobal(Offset.zero)),
      overlayBox.globalToLocal(
        editorBox.localToGlobal(editorBox.size.bottomRight(Offset.zero)),
      ),
    );
    rect = Rect.fromPoints(
      overlayBox.globalToLocal(rect.topLeft),
      overlayBox.globalToLocal(rect.bottomRight),
    );

    _alignment = Alignment.topLeft;
    var candidate = rect.bottomRight + menuOffset;
    _offset = candidate;

    if (candidate.dy + menuHeight >= editorBounds.bottom) {
      candidate = rect.topRight - menuOffset;
      _alignment = Alignment.bottomLeft;
      _offset = Offset(
        candidate.dx,
        overlayBox.size.height - candidate.dy,
      );
    }

    if (candidate.dx + menuWidth >= editorBounds.right &&
        candidate.dx - editorBounds.left > menuWidth) {
      _alignment = _alignment == Alignment.topLeft
          ? Alignment.topRight
          : Alignment.bottomRight;
      _offset = Offset(
        overlayBox.size.width - candidate.dx,
        _offset.dy,
      );
    }
  }
}

class AppFlowyDesktopSelectionMenuWidget extends StatefulWidget {
  const AppFlowyDesktopSelectionMenuWidget({
    super.key,
    required this.items,
    required this.editorState,
    required this.menuService,
    required this.onExit,
    required this.onSelectionUpdate,
    required this.selectionMenuStyle,
    required this.deleteSlashByDefault,
    this.isActive,
  });

  final List<SelectionMenuItem> items;
  final EditorState editorState;
  final SelectionMenuService menuService;
  final VoidCallback onExit;
  final VoidCallback onSelectionUpdate;
  final SelectionMenuStyle selectionMenuStyle;
  final bool deleteSlashByDefault;
  final bool Function()? isActive;

  @override
  State<AppFlowyDesktopSelectionMenuWidget> createState() =>
      _AppFlowyDesktopSelectionMenuWidgetState();
}

class _AppFlowyDesktopSelectionMenuWidgetState
    extends State<AppFlowyDesktopSelectionMenuWidget> {
  final _focusNode = FocusNode(debugLabel: 'appflowy_slash_menu');
  final _scrollController = ScrollController();
  final _itemKeys = <SelectionMenuItem, GlobalKey>{};

  late List<SelectionMenuItem> _showingItems = widget.items;
  int _selectedIndex = 0;
  int _searchCounter = 0;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    keepEditorFocusNotifier.increase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !widget.editorState.isDisposed &&
          (widget.isActive?.call() ?? true)) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    final focus = FocusManager.instance.primaryFocus;
    final preserveFocus = focus != null &&
        focus != _focusNode &&
        !_focusNode.descendants.contains(focus);
    _focusNode.dispose();
    _scrollController.dispose();
    keepEditorFocusNotifier.decrease();
    // Releasing the editor's hold requests editor focus synchronously. Do not
    // override a native field or a newer dialog that already owns focus.
    if (preserveFocus && focus.context?.mounted == true) {
      focus.requestFocus();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: AppMenuSurface(
        width: AppFlowyEditorMenuStyle.menuWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AppFlowyEditorMenuStyle.slashMenuContentMaxHeight,
          ),
          child: _showingItems.isEmpty
              ? _buildNoResults(context)
              : ListView(
                  controller: _scrollController,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: _buildMenuChildren(context),
                ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuChildren(BuildContext context) {
    final children = <Widget>[];
    SlashMenuSection? previousSection;

    for (final (index, item) in _showingItems.indexed) {
      final metadata = slashMenuMetadataFor(item) ??
          const SlashMenuItemMetadata(section: SlashMenuSection.advanced);
      if (metadata.section != previousSection) {
        children.add(_buildSectionTitle(context, metadata.section));
        previousSection = metadata.section;
      }

      final isSelected = index == _selectedIndex;
      children.add(
        KeyedSubtree(
          key: _itemKeys.putIfAbsent(item, GlobalKey.new),
          child: AppMenuRow(
            label: item.name,
            subtitle: metadata.description,
            highlighted: isSelected,
            // Some entries (outline and extension items) return Icon/FlowySvg
            // directly instead of going through the selectable helpers.
            iconWidget: WorkspaceGlyph.adapt(
              item.icon(
                widget.editorState,
                isSelected,
                widget.selectionMenuStyle,
              ),
            ),
            trailing: _buildTrailing(context, metadata),
            onHover: (_) {
              if (_selectedIndex != index) {
                setState(() => _selectedIndex = index);
              }
            },
            onTap: () => item.handler(
              widget.editorState,
              widget.menuService,
              context,
            ),
          ),
        ),
      );
    }

    return children;
  }

  Widget _buildSectionTitle(
    BuildContext context,
    SlashMenuSection section,
  ) {
    return AppMenuSectionLabel(
      label: switch (section) {
        SlashMenuSection.suggestions =>
          LocaleKeys.document_toolbar_suggestions.tr(),
        SlashMenuSection.basicBlocks => 'Basic blocks',
        SlashMenuSection.interactive => LocaleKeys.interactive_sectionName.tr(),
        SlashMenuSection.canvas => LocaleKeys.canvas_sectionName.tr(),
        SlashMenuSection.dashboards => LocaleKeys.dashboard_sectionName.tr(),
        SlashMenuSection.media =>
          LocaleKeys.document_slashMenu_name_fileAndMedia.tr(),
        SlashMenuSection.collections => LocaleKeys.collections_plural.tr(),
        SlashMenuSection.database => LocaleKeys.importPanel_database.tr(),
        SlashMenuSection.diagrams => LocaleKeys.diagrams_sectionName.tr(),
        SlashMenuSection.advanced =>
          LocaleKeys.document_slashMenu_name_advanced.tr(),
      },
    );
  }

  Widget? _buildTrailing(
    BuildContext context,
    SlashMenuItemMetadata metadata,
  ) {
    final style = AppMenuStyle.of(context);
    if (metadata.isNew) {
      final appTheme = AppFlowyTheme.of(context);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: appTheme.fillColorScheme.featuredLight,
          borderRadius: BorderRadius.circular(appTheme.borderRadius.xl),
        ),
        child: Text(
          'New',
          style: AppFlowyEditorMenuStyle.badgeTextStyle(context),
        ),
      );
    }

    final shortcut = metadata.shortcut;
    return shortcut == null ? null : Text(shortcut, style: style.shortcutStyle);
  }

  Widget _buildNoResults(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        LocaleKeys.inlineActions_noResults.tr(),
        textAlign: TextAlign.center,
        style: AppMenuStyle.of(context).labelStyle,
      ),
    );
  }

  void _updateKeyword(String value) {
    _keyword = value;
    var maxKeywordLength = 0;
    final items = widget.items.where((item) {
      return item.allKeywords.any((keyword) {
        final matches = keyword.contains(value.toLowerCase());
        if (matches) {
          maxKeywordLength = max(maxKeywordLength, keyword.length);
        }
        return matches;
      });
    }).toList(growable: false);

    if (_keyword.length >= maxKeywordLength + 2 &&
        !(widget.deleteSlashByDefault && _searchCounter < 2)) {
      widget.onExit();
      return;
    }

    setState(() {
      _showingItems = items;
      _selectedIndex = 0;
    });
    _searchCounter = items.isEmpty ? _searchCounter + 1 : 0;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent) {
      return KeyEventResult.skipRemainingHandlers;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_showingItems.isNotEmpty) {
        _showingItems[_selectedIndex].handler(
          widget.editorState,
          widget.menuService,
          context,
        );
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_searchCounter > 0) {
        _searchCounter--;
      }
      if (_keyword.isEmpty) {
        widget.onExit();
        if (widget.deleteSlashByDefault) {
          _deleteLastCharacter();
        }
      } else {
        _updateKeyword(_keyword.substring(0, _keyword.length - 1));
        _deleteLastCharacter();
      }
      return KeyEventResult.handled;
    }

    final isPrevious = event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final isNext = event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.tab;
    if ((isPrevious || isNext) && _showingItems.isNotEmpty) {
      setState(() {
        _selectedIndex = isPrevious
            ? (_selectedIndex - 1) % _showingItems.length
            : (_selectedIndex + 1) % _showingItems.length;
      });
      _scrollToSelectedItem();
      return KeyEventResult.handled;
    }

    if (event.character != null && event.logicalKey != LogicalKeyboardKey.tab) {
      _updateKeyword(_keyword + event.character!);
      _insertText(event.character!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToSelectedItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showingItems.isEmpty) {
        return;
      }
      final itemContext =
          _itemKeys[_showingItems[_selectedIndex]]?.currentContext;
      if (itemContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            itemContext,
            alignment: 0.5,
            duration: const Duration(milliseconds: 100),
          ),
        );
      }
    });
  }

  void _deleteLastCharacter() {
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = widget.editorState.getNodeAtPath(selection.end.path);
    if (node == null || node.delta == null) {
      return;
    }

    widget.onSelectionUpdate();
    final transaction = widget.editorState.transaction
      ..deleteText(node, selection.start.offset - 1, 1);
    widget.editorState.apply(transaction);
  }

  void _insertText(String text) {
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isSingle) {
      return;
    }
    final node = widget.editorState.getNodeAtPath(selection.end.path);
    if (node == null) {
      return;
    }

    widget.onSelectionUpdate();
    final transaction = widget.editorState.transaction
      ..insertText(node, selection.end.offset, text);
    widget.editorState.apply(transaction);
  }
}
