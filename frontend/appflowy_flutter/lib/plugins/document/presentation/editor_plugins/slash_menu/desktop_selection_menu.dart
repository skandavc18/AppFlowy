import 'dart:async';
import 'dart:math';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_menu_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
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
  bool _selectionUpdateByInner = false;
  Offset _offset = Offset.zero;
  Alignment _alignment = Alignment.topLeft;

  @override
  Offset get offset => _offset;

  @override
  Alignment get alignment => _alignment;

  @override
  Future<void> show() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _show();
      completer.complete();
    });
    return completer.future;
  }

  void _show() {
    dismiss();

    final selectionService = editorState.service.selectionService;
    final selectionRects = selectionService.selectionRects;
    if (selectionRects.isEmpty) {
      return;
    }

    _calculateSelectionMenuOffset(selectionRects.first);
    final (left, top, right, bottom) = getPosition();
    final editorSize = editorState.renderBox!.size;

    for (final item in selectionMenuItems) {
      item
        ..deleteSlash = deleteSlashByDefault
        ..deleteKeywords = deleteKeywordsByDefault
        ..onSelected = dismiss;
    }

    final menu = InheritedTheme.captureAll(
      context,
      AppFlowyDesktopSelectionMenuWidget(
        items: selectionMenuItems,
        editorState: editorState,
        menuService: this,
        onExit: dismiss,
        onSelectionUpdate: () => _selectionUpdateByInner = true,
        selectionMenuStyle: style,
        deleteSlashByDefault: deleteSlashByDefault,
      ),
    );

    _selectionMenuEntry = OverlayEntry(
      builder: (_) => SizedBox(
        width: editorSize.width,
        height: editorSize.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: dismiss,
          child: Stack(
            children: [
              Positioned(
                top: top,
                bottom: bottom,
                left: left,
                right: right,
                child: menu,
              ),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_selectionMenuEntry!);
    editorState.service.keyboardService?.disable(showCursor: true);
    editorState.service.scrollService?.disable();
    selectionService.currentSelection.addListener(_onSelectionChange);
  }

  @override
  void dismiss() {
    if (_selectionMenuEntry != null) {
      editorState.service.keyboardService?.enable();
      editorState.service.scrollService?.enable();
    }

    _selectionMenuEntry?.remove();
    _selectionMenuEntry = null;

    final selectionServiceState =
        editorState.service.selectionServiceKey.currentState;
    if (selectionServiceState != null) {
      final selectionService = editorState.service.selectionService;
      editorState.selection = editorState.selection;
      selectionService.currentSelection.removeListener(_onSelectionChange);
    }
  }

  void _onSelectionChange() {
    final selectionServiceState =
        editorState.service.selectionServiceKey.currentState;
    if (selectionServiceState != null &&
        editorState.service.selectionService.currentSelection.value == null) {
      return;
    }

    if (_selectionUpdateByInner) {
      _selectionUpdateByInner = false;
    } else {
      dismiss();
    }
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

  void _calculateSelectionMenuOffset(Rect rect) {
    const menuOffset = Offset(0, 10);
    const menuHeight = AppFlowyEditorMenuStyle.slashMenuMaxHeight;
    const menuWidth = AppFlowyEditorMenuStyle.menuWidth;
    final editorOffset =
        editorState.renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final editorSize = editorState.renderBox!.size;

    _alignment = Alignment.topLeft;
    var candidate = rect.bottomRight + menuOffset;
    _offset = candidate;

    if (candidate.dy + menuHeight >= editorOffset.dy + editorSize.height) {
      candidate = rect.topRight - menuOffset;
      _alignment = Alignment.bottomLeft;
      _offset = Offset(
        candidate.dx,
        editorSize.height + editorOffset.dy - candidate.dy,
      );
    }

    if (_offset.dx + menuWidth >= editorOffset.dx + editorSize.width &&
        candidate.dx - editorOffset.dx > menuWidth) {
      _alignment = _alignment == Alignment.topLeft
          ? Alignment.topRight
          : Alignment.bottomRight;
      _offset = Offset(
        editorSize.width - _offset.dx + editorOffset.dx,
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
  });

  final List<SelectionMenuItem> items;
  final EditorState editorState;
  final SelectionMenuService menuService;
  final VoidCallback onExit;
  final VoidCallback onSelectionUpdate;
  final SelectionMenuStyle selectionMenuStyle;
  final bool deleteSlashByDefault;

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
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    keepEditorFocusNotifier.decrease();
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
            iconWidget: item.icon(
              widget.editorState,
              isSelected,
              widget.selectionMenuStyle,
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
