import 'dart:ui' as ui;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_chrome_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/background_color/theme_background_color.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_host.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/i18n/editor_i18n.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/text_field_aware_commands.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/document_spell_check.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_gestures.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/plugins/inline_actions/handlers/child_page.dart';
import 'package:appflowy/plugins/inline_actions/handlers/date_reference.dart';
import 'package:appflowy/plugins/inline_actions/handlers/inline_page_reference.dart';
import 'package:appflowy/plugins/inline_actions/handlers/reminder_reference.dart';
import 'package:appflowy/plugins/inline_actions/inline_actions_service.dart';
import 'package:appflowy/shared/editor_focus_node.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/shortcuts/settings_shortcuts_service.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/af_focus_manager.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide QuoteBlockKeys;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import 'editor_plugins/desktop_toolbar/desktop_floating_toolbar.dart';
import 'editor_plugins/toolbar_item/custom_format_toolbar_items.dart';
import 'editor_plugins/toolbar_item/custom_hightlight_color_toolbar_item.dart';
import 'editor_plugins/toolbar_item/custom_link_toolbar_item.dart';
import 'editor_plugins/toolbar_item/custom_placeholder_toolbar_item.dart';
import 'editor_plugins/toolbar_item/custom_text_align_toolbar_item.dart';
import 'editor_plugins/toolbar_item/custom_text_color_toolbar_item.dart';
import 'editor_plugins/toolbar_item/more_option_toolbar_item.dart';
import 'editor_plugins/toolbar_item/text_heading_toolbar_item.dart';
import 'editor_plugins/toolbar_item/text_suggestions_toolbar_item.dart';

/// Wrapper for the appflowy editor.
class AppFlowyEditorPage extends StatefulWidget {
  const AppFlowyEditorPage({
    super.key,
    required this.editorState,
    this.header,
    this.shrinkWrap = false,
    this.scrollController,
    this.autoFocus,
    required this.styleCustomizer,
    this.showParagraphPlaceholder,
    this.placeholderText,
    this.initialSelection,
    this.useViewInfoBloc = true,
    this.isSelected,
    this.findMetadataScope,
  });

  final Widget? header;
  final EditorState editorState;
  final ScrollController? scrollController;
  final bool shrinkWrap;
  final bool? autoFocus;
  final EditorStyleCustomizer styleCustomizer;
  final ShowPlaceholder? showParagraphPlaceholder;
  final String Function(Node)? placeholderText;

  /// Used to provide an initial selection on Page-load
  final Selection? initialSelection;

  final bool useViewInfoBloc;

  /// Optional live tab/pane ownership when multiple editors remain mounted.
  /// Find must not reopen an inactive editor from retained focus or hover.
  final bool Function()? isSelected;

  /// Row hosts supply actual document metadata separately from table access.
  /// The host observes this scope; native body editing and Find share its gate.
  final DocumentFindMetadataScope? findMetadataScope;

  @override
  State<AppFlowyEditorPage> createState() => _AppFlowyEditorPageState();
}

class _AppFlowyEditorPageState extends State<AppFlowyEditorPage>
    with WidgetsBindingObserver {
  late final ScrollController effectiveScrollController;

  late final InlineActionsService inlineActionsService = InlineActionsService(
    context: context,
    handlers: [
      if (FeatureFlag.inlineSubPageMention.isOn)
        InlineChildPageService(currentViewId: documentBloc.documentId),
      InlinePageReferenceService(currentViewId: documentBloc.documentId),
      DateReferenceService(context),
      ReminderReferenceService(context),
    ],
  );

  late final List<CommandShortcutEvent> commandShortcuts =
      standAsideForTextFields([
    ...commandShortcutEvents,
    ..._buildFindAndReplaceCommands(),
    _buildSpellCheckCommand(),
  ]);

  final EditorFocusNode _editorFocusNode =
      EditorFocusNode(debugLabel: 'document editor');

  final List<ToolbarItem> toolbarItems = [
    improveWritingItem,
    group0PaddingItem,
    aiWriterItem,
    customTextHeadingItem,
    buildPaddingPlaceholderItem(
      1,
      isActive: onlyShowInSingleTextTypeSelectionAndExcludeTable,
    ),
    ...customMarkdownFormatItems,
    group1PaddingItem,
    customTextColorItem,
    group1PaddingItem,
    customHighlightColorItem,
    customInlineCodeItem,
    suggestionsItem,
    customLinkItem,
    group4PaddingItem,
    customTextAlignItem,
    moreOptionItem,
  ];

  List<CharacterShortcutEvent> get characterShortcutEvents {
    return buildCharacterShortcutEvents(
      context,
      documentBloc,
      styleCustomizer,
      inlineActionsService,
      (editorState, node) => _customSlashMenuItems(
        editorState: editorState,
        node: node,
      ),
    );
  }

  EditorStyleCustomizer get styleCustomizer => widget.styleCustomizer;

  DocumentBloc get documentBloc => context.read<DocumentBloc>();

  late final EditorScrollController editorScrollController;

  late final ViewInfoBloc viewInfoBloc = context.read<ViewInfoBloc>();

  final editorKeyboardInterceptor = EditorKeyboardInterceptor();

  Future<bool> showSlashMenu(editorState) async => customSlashCommand(
        _customSlashMenuItems(),
        shouldInsertSlash: false,
        style: styleCustomizer.selectionMenuStyleBuilder(),
        supportSlashMenuNodeTypes: supportSlashMenuNodeTypes,
      ).handler(editorState);

  AFFocusManager? focusManager;
  BuildContext? _findOwnerContext;

  AppLifecycleState? lifecycleState = WidgetsBinding.instance.lifecycleState;
  List<Selection?> previousSelections = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.useViewInfoBloc) {
      viewInfoBloc.add(
        ViewInfoEvent.registerEditorState(editorState: widget.editorState),
      );
    }

    _initEditorL10n();
    _initializeShortcuts();

    AppFlowyRichTextKeys.partialSliced.addAll([
      MentionBlockKeys.mention,
      InlineMathEquationKeys.formula,
    ]);

    indentableBlockTypes.addAll([
      ToggleListBlockKeys.type,
      CalloutBlockKeys.type,
      QuoteBlockKeys.type,
    ]);
    convertibleBlockTypes.addAll([
      ToggleListBlockKeys.type,
      CalloutBlockKeys.type,
      QuoteBlockKeys.type,
    ]);

    editorLaunchUrl = (url) {
      if (url != null) {
        afLaunchUrlString(url, addingHttpSchemeWhenFailed: true);
      }

      return Future.value(true);
    };

    effectiveScrollController = widget.scrollController ?? ScrollController();
    // disable the color parse in the HTML decoder.
    DocumentHTMLDecoder.enableColorParse = false;

    DocumentSpellCheck.attach(
      editorState: widget.editorState,
      viewId: documentBloc.documentId,
    );

    editorScrollController = EditorScrollController(
      editorState: widget.editorState,
      shrinkWrap: widget.shrinkWrap,
      scrollController: effectiveScrollController,
    );

    toolbarItemWhiteList.addAll([
      ToggleListBlockKeys.type,
      CalloutBlockKeys.type,
      TableBlockKeys.type,
      SimpleTableBlockKeys.type,
      SimpleTableCellBlockKeys.type,
      SimpleTableRowBlockKeys.type,
    ]);
    AppFlowyRichTextKeys.supportSliced.add(AppFlowyRichTextKeys.fontFamily);

    // customize the dynamic theme color
    _customizeBlockComponentBackgroundColorDecorator();

    widget.editorState.selectionNotifier.addListener(onSelectionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      focusManager = AFFocusManager.maybeOf(context);
      focusManager?.loseFocusNotifier.addListener(_loseFocus);

      _scrollToSelectionIfNeeded();

      widget.editorState.service.keyboardService?.registerInterceptor(
        editorKeyboardInterceptor,
      );
    });
  }

  void _scrollToSelectionIfNeeded() {
    final initialSelection = widget.initialSelection;
    final path = initialSelection?.start.path;
    if (path == null) {
      return;
    }

    // on desktop, using jumpTo to scroll to the selection.
    // on mobile, using scrollTo to scroll to the selection, because using jumpTo will break the scroll notification metrics.
    if (UniversalPlatform.isDesktop) {
      editorScrollController.itemScrollController.jumpTo(
        index: path.first,
        alignment: 0.5,
      );
      widget.editorState.updateSelectionWithReason(
        initialSelection,
      );
    } else {
      const delayDuration = Duration(milliseconds: 250);
      const animationDuration = Duration(milliseconds: 400);
      Future.delayed(delayDuration, () {
        editorScrollController.itemScrollController.scrollTo(
          index: path.first,
          duration: animationDuration,
          curve: Curves.easeInOut,
        );
        widget.editorState.updateSelectionWithReason(
          initialSelection,
          extraInfo: {
            selectionExtraInfoDoNotAttachTextService: true,
            selectionExtraInfoDisableMobileToolbarKey: true,
          },
        );
      }).then((_) {
        Future.delayed(animationDuration, () {
          widget.editorState.selectionType = SelectionType.inline;
          widget.editorState.selectionExtraInfo = null;
        });
      });
    }
  }

  void onSelectionChanged() {
    if (widget.editorState.isDisposed) {
      return;
    }

    previousSelections.add(widget.editorState.selection);

    if (previousSelections.length > 2) {
      previousSelections.removeAt(0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    lifecycleState = state;

    if (widget.editorState.isDisposed) {
      return;
    }

    if (previousSelections.length == 2 &&
        state == AppLifecycleState.resumed &&
        widget.editorState.selection == null) {
      widget.editorState.selection = previousSelections.first;
    }
  }

  @override
  void didChangeDependencies() {
    final currFocusManager = AFFocusManager.maybeOf(context);
    if (focusManager != currFocusManager) {
      focusManager?.loseFocusNotifier.removeListener(_loseFocus);
      focusManager = currFocusManager;
      focusManager?.loseFocusNotifier.addListener(_loseFocus);
    }

    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant AppFlowyEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.editorState, widget.editorState) ||
        !identical(oldWidget.findMetadataScope, widget.findMetadataScope)) {
      DocumentFindMenu.dismiss(editorState: oldWidget.editorState);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DocumentFindMenu.dismiss(editorState: widget.editorState);
    _findOwnerContext = null;
    widget.editorState.selectionNotifier.removeListener(onSelectionChanged);
    widget.editorState.service.keyboardService?.unregisterInterceptor(
      editorKeyboardInterceptor,
    );
    focusManager?.loseFocusNotifier.removeListener(_loseFocus);
    DocumentSpellCheck.detach(widget.editorState);

    if (widget.useViewInfoBloc && !viewInfoBloc.isClosed) {
      viewInfoBloc.add(const ViewInfoEvent.unregisterEditorState());
    }

    SystemChannels.textInput.invokeMethod('TextInput.hide');

    if (widget.scrollController == null) {
      effectiveScrollController.dispose();
    }
    inlineActionsService.dispose();
    editorScrollController.dispose();
    _editorFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bool autoFocus, Selection? selection) =
        _computeAutoFocusParameters();

    final isRTL =
        context.read<AppearanceSettingsCubit>().state.layoutDirection ==
            LayoutDirection.rtlLayout;
    final textDirection = isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr;

    _setRTLToolbarItems(
      context.read<AppearanceSettingsCubit>().state.enableRtlToolbarItems,
    );

    final isViewDeleted = context.watch<DocumentBloc>().state.isDeleted;
    final access = context.watch<PageAccessLevelBloc?>()?.state;
    final isEditable =
        _ownsDocumentFind(widget.editorState) && _isDocumentEditable(access);

    final editorContent = Directionality(
      textDirection: textDirection,
      child: EditorContextMenuRegion(
        editorState: widget.editorState,
        enabled: UniversalPlatform.isDesktopOrWeb,
        child: SpellCheckGestureRegion(
          editorState: widget.editorState,
          enabled: UniversalPlatform.isDesktopOrWeb,
          child: AppFlowyEditor(
            editorState: widget.editorState,
            focusNode: _editorFocusNode,
            editable: !isViewDeleted && isEditable,
            disableSelectionService: UniversalPlatform.isMobile && !isEditable,
            disableKeyboardService: UniversalPlatform.isMobile && !isEditable,
            editorScrollController: editorScrollController,
            // setup the auto focus parameters
            autoFocus: widget.autoFocus ?? autoFocus,
            focusedSelection: selection,
            // setup the theme
            editorStyle: styleCustomizer.style(),
            // customize the block builders
            blockComponentBuilders: buildBlockComponentBuilders(
              slashMenuItemsBuilder: (editorState, node) =>
                  _customSlashMenuItems(
                editorState: editorState,
                node: node,
              ),
              context: context,
              editorState: widget.editorState,
              styleCustomizer: widget.styleCustomizer,
              showParagraphPlaceholder: widget.showParagraphPlaceholder,
              placeholderText: widget.placeholderText,
            ),
            // customize the shortcuts
            characterShortcutEvents: characterShortcutEvents,
            commandShortcutEvents: commandShortcuts,
            // The app-owned menu matches the rest of AppFlowy's menu surfaces.
            contextMenuItems: const [],
            // customize the header and footer.
            header: widget.header,
            autoScrollEdgeOffset: UniversalPlatform.isDesktopOrWeb
                ? 250
                : appFlowyEditorAutoScrollEdgeOffset,
            footer: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: isEditable ? _focusOnLastEmptyParagraph : null,
              child: SizedBox(
                width: double.infinity,
                height: UniversalPlatform.isDesktopOrWeb ? 600 : 400,
              ),
            ),
            dropTargetStyle: AppFlowyDropTargetStyle(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
              margin: const EdgeInsets.only(left: 44),
            ),
          ),
        ),
      ),
    );

    final findEditor = widget.editorState;
    final editor = ValueListenableBuilder<EditorState?>(
      valueListenable: DocumentFindMenu.activeEditorListenable,
      builder: (context, activeEditor, child) => ContextualFindRegion(
        enabled: UniversalPlatform.isDesktopOrWeb &&
            !isViewDeleted &&
            !findEditor.isDisposed,
        isActive: () => _ownsDocumentFind(findEditor),
        // The page title belongs to page-wide Find too. More specific native
        // source/cell regions retain priority through the contextual router.
        findInEditable: true,
        onFind: () => _showDocumentFind(findEditor),
        onReplace: isEditable && !isViewDeleted
            ? () => _showDocumentFind(findEditor, replace: true)
            : null,
        onDismiss: () => DocumentFindMenu.dismiss(editorState: findEditor),
        findOpen: identical(activeEditor, findEditor),
        findFocusNode: identical(activeEditor, findEditor)
            ? DocumentFindMenu.findFocusNode
            : null,
        isSelected: () => _ownsDocumentFind(findEditor),
        debugLabel: 'document',
        child: child!,
      ),
      // Keep the content subtree stable when just the overlay owner changes.
      child: Builder(
        builder: (context) {
          _findOwnerContext = context;
          return editorContent;
        },
      ),
    );

    if (isViewDeleted) {
      return editor;
    }

    final editorState = widget.editorState;

    if (UniversalPlatform.isMobile) {
      return AppFlowyMobileToolbar(
        toolbarHeight: 42.0,
        editorState: editorState,
        toolbarItemsBuilder: (sel) => buildMobileToolbarItems(editorState, sel),
        child: MobileFloatingToolbar(
          editorState: editorState,
          editorScrollController: editorScrollController,
          toolbarBuilder: (_, anchor, closeToolbar) =>
              CustomMobileFloatingToolbar(
            editorState: editorState,
            anchor: anchor,
            closeToolbar: closeToolbar,
          ),
          floatingToolbarHeight: 32,
          child: editor,
        ),
      );
    }
    final appTheme = AppFlowyTheme.of(context);
    return Center(
      child: BlocProvider.value(
        value: context.read<DocumentBloc>(),
        child: FloatingToolbar(
          floatingToolbarHeight: 40,
          padding: EdgeInsets.symmetric(horizontal: 6),
          style: FloatingToolbarStyle(
            backgroundColor: Theme.of(context).cardColor,
            toolbarActiveColor: Color(0xffe0f8fd),
            toolbarIconColor: EditorChromeStyle.iconColor(context),
          ),
          items: toolbarItems,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(appTheme.borderRadius.l),
            color: appTheme.surfaceColorScheme.primary,
            boxShadow: appTheme.shadow.small,
          ),
          toolbarBuilder: (_, child, onDismiss, isMetricsChanged) =>
              BlocProvider.value(
            value: context.read<DocumentBloc>(),
            child: DesktopFloatingToolbar(
              editorState: editorState,
              onDismiss: onDismiss,
              enableAnimation: !isMetricsChanged,
              child: child,
            ),
          ),
          placeHolderBuilder: (_) => customPlaceholderItem,
          editorState: editorState,
          editorScrollController: editorScrollController,
          textDirection: textDirection,
          tooltipBuilder: (context, id, message, child) =>
              widget.styleCustomizer.buildToolbarItemTooltip(
            context,
            id,
            message,
            child,
          ),
          child: editor,
        ),
      ),
    );
  }

  List<SelectionMenuItem> _customSlashMenuItems({
    EditorState? editorState,
    Node? node,
  }) {
    final documentBloc = context.read<DocumentBloc>();
    final isLocalMode = documentBloc.isLocalMode;
    final view = context.read<ViewBloc>().state.view;
    return slashMenuItemsBuilder(
      editorState: editorState,
      node: node,
      isLocalMode: isLocalMode,
      documentBloc: documentBloc,
      view: view,
    );
  }

  (bool, Selection?) _computeAutoFocusParameters() {
    if (widget.editorState.document.isEmpty) {
      return (true, Selection.collapsed(Position(path: [0])));
    }
    return const (false, null);
  }

  Future<void> _initializeShortcuts() async {
    defaultCommandShortcutEvents;
    final settingsShortcutService = SettingsShortcutService();
    final customizeShortcuts =
        await settingsShortcutService.getCustomizeShortcuts();
    await settingsShortcutService.updateCommandShortcuts(
      commandShortcuts,
      customizeShortcuts,
    );
  }

  void _setRTLToolbarItems(bool enableRtlToolbarItems) {
    final textDirectionItemIds = textDirectionItems.map((e) => e.id);
    // clear all the text direction items
    toolbarItems.removeWhere((item) => textDirectionItemIds.contains(item.id));
    // only show the rtl item when the layout direction is ltr.
    if (enableRtlToolbarItems) {
      toolbarItems.addAll(textDirectionItems);
    }
  }

  List<CommandShortcutEvent> _buildFindAndReplaceCommands() {
    // The editor package's own commands are not used: its menu service bails
    // out unless a selection rectangle is on screen, so Ctrl+F did nothing on
    // a page that had not been clicked into. The keys are kept so a
    // customized shortcut still resolves.
    return [
      CommandShortcutEvent(
        key: 'show the find dialog',
        getDescription: () => AppFlowyEditorL10n.current.cmdOpenFind,
        command: 'ctrl+f',
        macOSCommand: 'cmd+f',
        handler: _openFindMenu,
      ),
      CommandShortcutEvent(
        key: 'show the find and replace dialog',
        getDescription: () => AppFlowyEditorL10n.current.cmdOpenFindAndReplace,
        command: 'ctrl+h',
        macOSCommand: 'cmd+h',
        handler: (editorState) => _openFindMenu(editorState, replace: true),
      ),
    ];
  }

  KeyEventResult _openFindMenu(
    EditorState editorState, {
    bool replace = false,
  }) {
    if (UniversalPlatform.isMobile ||
        !mounted ||
        editorState.isDisposed ||
        !identical(editorState, widget.editorState)) {
      return KeyEventResult.ignored;
    }
    return ContextualFindRegion.dispatch(
      _findOwnerContext ?? context,
      replace: replace,
    )
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  bool _ownsDocumentFind(EditorState editorState) {
    if (!mounted ||
        editorState.isDisposed ||
        !identical(editorState, widget.editorState) ||
        !(widget.isSelected?.call() ?? true)) {
      return false;
    }
    final document = documentBloc;
    final scope = widget.findMetadataScope;
    return !document.isClosing &&
        !document.isClosed &&
        !document.state.isDeleted &&
        !document.state.forceClose &&
        (scope == null ||
            (scope.documentId == document.documentId && scope.isActive)) &&
        (document.state.editorState == null ||
            identical(document.state.editorState, editorState));
  }

  bool _isDocumentEditable(PageAccessLevelState? access) {
    final scope = widget.findMetadataScope;
    if (scope != null) {
      if (scope.documentId != documentBloc.documentId || !scope.canReplace) {
        return false;
      }
      // Popup routes need not inherit a bloc. The row scope owns native table
      // authority; an unrelated ancestor's bloc must never grant it access.
      if (access?.view.id != scope.tableViewId) return true;
      return !access!.isLoadingLockStatus &&
          !access.isReadOnly &&
          access.isEditable;
    }
    return access == null || (!access.isLoadingLockStatus && access.isEditable);
  }

  /// Region callbacks open directly; only the customized command dispatches.
  void _showDocumentFind(EditorState editorState, {bool replace = false}) {
    if (!_ownsDocumentFind(editorState)) {
      return;
    }
    final boundDocument = documentBloc;
    final boundScope = widget.findMetadataScope;
    final boundView = boundScope == null ? context.read<ViewBloc?>() : null;
    bool ownsBinding() =>
        _ownsDocumentFind(editorState) &&
        identical(documentBloc, boundDocument) &&
        identical(widget.findMetadataScope, boundScope) &&
        (boundScope != null || identical(context.read<ViewBloc?>(), boundView));
    ViewPB? currentView() {
      if (!ownsBinding() ||
          boundView?.isClosed == true ||
          boundView?.state.isDeleted == true) {
        return null;
      }
      final view =
          boundScope == null ? boundView?.state.view : boundScope.currentView;
      // In a full-page row ViewBloc belongs to the TABLE. Do not hand its ID
      // (or name) to a session attached to the row's DocumentBloc.
      return view?.id == boundDocument.documentId ? view : null;
    }

    DocumentFindMenu.show(
      _findOwnerContext ?? context,
      editorState,
      documentId: boundDocument.documentId,
      currentView: currentView,
      viewChanges: boundScope?.viewChanges ??
          boundView?.stream.map((state) => state.view),
      replace: replace,
      isSelected: ownsBinding,
      canReplace: () =>
          ownsBinding() &&
          currentView() != null &&
          _isDocumentEditable(context.read<PageAccessLevelBloc?>()?.state),
    );
  }

  /// Reaching the suggestions from the keyboard, for anybody who does not
  /// want to leave the caret to use a pointer.
  CommandShortcutEvent _buildSpellCheckCommand() => CommandShortcutEvent(
        key: 'show spelling suggestions',
        getDescription: () =>
            LocaleKeys.document_spellCheck_showSuggestions.tr(),
        command: 'ctrl+period',
        macOSCommand: 'cmd+period',
        handler: (editorState) {
          if (UniversalPlatform.isMobile || !mounted) {
            return KeyEventResult.ignored;
          }
          return showSpellSuggestionsForCaret(context, editorState);
        },
      );

  void _customizeBlockComponentBackgroundColorDecorator() {
    blockComponentBackgroundColorDecorator = (Node node, String colorString) {
      if (mounted && context.mounted) {
        return buildEditorCustomizedColor(context, node, colorString);
      }
      return null;
    };
  }

  void _initEditorL10n() => AppFlowyEditorL10n.current = EditorI18n();

  Future<void> _focusOnLastEmptyParagraph() async {
    // A retained footer callback can run before a revoked permission or closed
    // document reaches the next build. Match the live gate used by Replace.
    if (!_ownsDocumentFind(widget.editorState) ||
        !_isDocumentEditable(context.read<PageAccessLevelBloc?>()?.state)) {
      return;
    }
    final editorState = widget.editorState;
    final root = editorState.document.root;
    final lastNode = root.children.lastOrNull;
    final transaction = editorState.transaction;
    if (lastNode == null ||
        lastNode.delta?.isEmpty == false ||
        lastNode.type != ParagraphBlockKeys.type) {
      transaction.insertNode([root.children.length], paragraphNode());
      transaction.afterSelection = Selection.collapsed(
        Position(path: [root.children.length]),
      );
    } else {
      transaction.afterSelection = Selection.collapsed(
        Position(path: lastNode.path),
      );
    }

    transaction.customSelectionType = SelectionType.inline;
    transaction.reason = SelectionUpdateReason.uiEvent;

    await editorState.apply(transaction);
  }

  void _loseFocus() {
    if (!widget.editorState.isDisposed) {
      widget.editorState.selection = null;
    }
  }
}

Color? buildEditorCustomizedColor(
  BuildContext context,
  Node node,
  String colorString,
) {
  if (!context.mounted) {
    return null;
  }

  // the color string is from FlowyTint.
  final tintColor = FlowyTint.values.firstWhereOrNull(
    (e) => e.id == colorString,
  );
  if (tintColor != null) {
    return tintColor.color(context);
  }

  final themeColor = themeBackgroundColors[colorString];
  if (themeColor != null) {
    return themeColor.color(context);
  }

  if (colorString == optionActionColorDefaultColor) {
    final defaultColor = node.type == CalloutBlockKeys.type
        ? AFThemeExtension.of(context).calloutBGColor
        : Colors.transparent;
    return defaultColor;
  }

  if (colorString == tableCellDefaultColor) {
    return AFThemeExtension.of(context).tableCellBGColor;
  }

  try {
    return colorString.tryToColor();
  } catch (e) {
    return null;
  }
}

bool showInAnyTextType(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return false;
  }

  final nodes = editorState.getNodesInSelection(selection);
  return nodes.any((node) => toolbarItemWhiteList.contains(node.type));
}
