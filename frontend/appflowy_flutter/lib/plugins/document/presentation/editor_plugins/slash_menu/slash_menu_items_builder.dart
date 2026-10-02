import 'package:appflowy/extensions/presentation/island_slash_items.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/operations/ai_writer_node_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide QuoteBlockKeys;
import 'package:universal_platform/universal_platform.dart';

import 'slash_menu_items/mobile_items.dart';
import 'slash_menu_items/slash_menu_items.dart';
import 'slash_menu_metadata.dart';

/// Build slash menu items
///
List<SelectionMenuItem> slashMenuItemsBuilder({
  bool isLocalMode = false,
  DocumentBloc? documentBloc,
  EditorState? editorState,
  Node? node,
  ViewPB? view,
}) {
  final isInTable = node != null && node.parentTableCellNode != null;
  final isMobile = UniversalPlatform.isMobile;
  bool isEmpty = false;
  if (editorState == null || editorState.isEmptyForContinueWriting()) {
    if (view == null || view.name.isEmpty) {
      isEmpty = true;
    }
  }
  if (isMobile) {
    if (isInTable) {
      return mobileItemsInTale;
    } else {
      return mobileItems;
    }
  } else {
    if (isInTable) {
      return _simpleTableSlashMenuItems();
    } else {
      return _defaultSlashMenuItems(
        isLocalMode: isLocalMode,
        documentBloc: documentBloc,
        isEmpty: isEmpty,
      );
    }
  }
}

/// The default slash menu items are used in the text-based block.
///
/// Except for the simple table block, the slash menu items in the table block are
/// built by the `tableSlashMenuItem` function.
/// If in local mode, disable the ai writer feature
///
/// The linked database relies on the documentBloc, so it's required to pass in
/// the documentBloc when building the slash menu items. If the documentBloc is
/// not provided, the linked database items will be disabled.
///
///
List<SelectionMenuItem> _defaultSlashMenuItems({
  bool isLocalMode = false,
  DocumentBloc? documentBloc,
  bool isEmpty = false,
}) {
  final linkedViews = linkedTableViewSlashMenuItems();
  final linkedCollections = linkedCollectionSlashMenuItems();
  final databaseItems = <SelectionMenuItem>[
    tableSlashMenuItem,
    spreadsheetSlashMenuItem,
    linkToPageSlashMenuItem,
    pagePreviewSlashMenuItem,
    if (documentBloc != null) gridSlashMenuItem(documentBloc),
    referencedGridSlashMenuItem,
    if (documentBloc != null) kanbanSlashMenuItem(documentBloc),
    referencedKanbanSlashMenuItem,
    if (documentBloc != null) calendarSlashMenuItem(documentBloc),
    referencedCalendarSlashMenuItem,
    ...linkedViews,
  ];

  return registerSlashMenuSections([
    SlashMenuSectionItems(
      section: SlashMenuSection.suggestions,
      items: [
        if (!isEmpty) continueWritingSlashMenuItem,
        aiWriterSlashMenuItem,
      ],
      newItems: {
        if (!isEmpty) continueWritingSlashMenuItem,
      },
      wholeSectionPageOnly: true,
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.basicBlocks,
      items: [
        paragraphSlashMenuItem,
        heading1SlashMenuItem,
        heading2SlashMenuItem,
        heading3SlashMenuItem,
        bulletedListSlashMenuItem,
        numberedListSlashMenuItem,
        todoListSlashMenuItem,
        toggleListSlashMenuItem,
        reminderSlashMenuItem,
      ],
      shortcuts: {
        heading1SlashMenuItem: '#',
        heading2SlashMenuItem: '##',
        heading3SlashMenuItem: '###',
        bulletedListSlashMenuItem: '-',
        numberedListSlashMenuItem: '1.',
        todoListSlashMenuItem: '-[]',
        toggleListSlashMenuItem: '>',
      },
      wholeSectionPageOnly: true,
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.interactive,
      items: interactiveSlashMenuItems(),
      descriptions: interactiveSlashMenuDescriptions(),
      blockTypes: {
        stickyNoteSlashMenuItem: StickyNoteBlockKeys.type,
        buttonSlashMenuItem: ButtonBlockKeys.type,
        progressSlashMenuItem: ProgressBlockKeys.type,
        counterSlashMenuItem: CounterBlockKeys.type,
        memorySlashMenuItem: MemoryBlockKeys.type,
        inputSlashMenuItem: InputBlockKeys.type,
        searchSlashMenuItem: SearchBlockKeys.type,
        selectorSlashMenuItem: SelectorBlockKeys.type,
        radioGroupSlashMenuItem: RadioGroupBlockKeys.type,
        multiSelectSlashMenuItem: MultiSelectBlockKeys.type,
        reminderBlockSlashMenuItem: ReminderBlockKeys.type,
      },
    ),
    _islandSection(),
    if (documentBloc != null) _canvasSection(documentBloc),
    if (documentBloc != null) _dashboardSection(documentBloc),
    _widgetSection(),
    SlashMenuSectionItems(
      section: SlashMenuSection.diagrams,
      items: diagramSlashMenuItems(),
      descriptions: diagramSlashMenuDescriptions(),
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.media,
      items: [
        imageSlashMenuItem,
        photoGallerySlashMenuItem,
        audioSlashMenuItem,
        videoSlashMenuItem,
        folderLinkSlashMenuItem,
        folderExplorerSlashMenuItem,
        bookmarkSlashMenuItem,
        chartSlashMenuItem,
        mapSlashMenuItem,
        fileSlashMenuItem,
        pdfSlashMenuItem,
        wordSlashMenuItem,
        excelSlashMenuItem,
        powerpointSlashMenuItem,
        htmlSlashMenuItem,
        markdownSlashMenuItem,
        zipSlashMenuItem,
        csvSlashMenuItem,
        jsonSlashMenuItem,
        codeFileSlashMenuItem,
        textFileSlashMenuItem,
        notebookSlashMenuItem,
      ],
      blockTypes: {
        imageSlashMenuItem: ImageBlockKeys.type,
        folderLinkSlashMenuItem: FolderExplorerBlockKeys.type,
        folderExplorerSlashMenuItem: FolderExplorerBlockKeys.type,
        bookmarkSlashMenuItem: BookmarkBlockKeys.type,
        chartSlashMenuItem: ChartBlockKeys.type,
        for (final item in [
          fileSlashMenuItem,
          pdfSlashMenuItem,
          wordSlashMenuItem,
          excelSlashMenuItem,
          powerpointSlashMenuItem,
          htmlSlashMenuItem,
          markdownSlashMenuItem,
          zipSlashMenuItem,
          csvSlashMenuItem,
          jsonSlashMenuItem,
          codeFileSlashMenuItem,
          textFileSlashMenuItem,
          notebookSlashMenuItem,
        ])
          item: FileBlockKeys.type,
      },
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.collections,
      items: [
        if (documentBloc != null) ...collectionSlashMenuItems(documentBloc),
        ...linkedCollections,
        // A page can also pull one object out of a connected service, which
        // reads as `/Google Drive`, `/OneDrive`, `/Box`, `/Google Photos`.
        ...externalEmbedSlashMenuItems(),
      ],
      blockTypes: {
        for (final item in linkedCollections)
          item: FolderExplorerBlockKeys.type,
      },
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.database,
      items: databaseItems,
      blockTypes: {
        pagePreviewSlashMenuItem: PagePreviewBlockKeys.type,
      },
      // Links and linked views belong to the page they are written in: they
      // create views beneath it, or point into its own text.
      pageOnly: {
        linkToPageSlashMenuItem,
        referencedGridSlashMenuItem,
        referencedKanbanSlashMenuItem,
        referencedCalendarSlashMenuItem,
        ...linkedViews,
      },
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.advanced,
      items: [
        dividerSlashMenuItem,
        quoteSlashMenuItem,
        twoColumnsSlashMenuItem,
        threeColumnsSlashMenuItem,
        fourColumnsSlashMenuItem,
        calloutSlashMenuItem,
        outlineSlashMenuItem,
        codeBlockSlashMenuItem,
        toggleHeading1SlashMenuItem,
        toggleHeading2SlashMenuItem,
        toggleHeading3SlashMenuItem,
        emojiSlashMenuItem,
        dateOrReminderSlashMenuItem,
        subPageSlashMenuItem,
      ],
      blockTypes: {
        dividerSlashMenuItem: DividerBlockKeys.type,
        quoteSlashMenuItem: QuoteBlockKeys.type,
        calloutSlashMenuItem: CalloutBlockKeys.type,
      },
      // Layout, headings, inline marks and the page's own outline and
      // sub-pages only mean something inside a page's flow of text.
      pageOnly: {
        twoColumnsSlashMenuItem,
        threeColumnsSlashMenuItem,
        fourColumnsSlashMenuItem,
        outlineSlashMenuItem,
        toggleHeading1SlashMenuItem,
        toggleHeading2SlashMenuItem,
        toggleHeading3SlashMenuItem,
        emojiSlashMenuItem,
        dateOrReminderSlashMenuItem,
        subPageSlashMenuItem,
      },
    ),
  ]);
}

/// One entry per island every enabled extension declares.
///
/// The list is read when the menu is built, so an island added to a folder is
/// offered at once — the same loop that makes an action need no rebuild.
SlashMenuSectionItems _islandSection() {
  final items = islandSlashMenuItems();
  return SlashMenuSectionItems(
    section: SlashMenuSection.interactive,
    items: items,
    descriptions: islandSlashMenuDescriptions(items),
  );
}

/// `/canvas`, `/embed canvas`, and one entry per template.
///
/// Like the dashboard section it needs the document's own id, because a new
/// canvas is created underneath the page that asked for it.
SlashMenuSectionItems _canvasSection(DocumentBloc documentBloc) {
  final items = canvasSlashMenuItems(documentBloc);
  return SlashMenuSectionItems(
    section: SlashMenuSection.canvas,
    items: items,
    descriptions: canvasSlashMenuDescriptions(items),
  );
}

/// `/dashboard`, and one entry per template.
///
/// It needs the document's own id to create the dashboard underneath it, so
/// it is only offered where that is known.
SlashMenuSectionItems _dashboardSection(DocumentBloc documentBloc) {
  final items = dashboardSlashMenuItems(documentBloc);
  return SlashMenuSectionItems(
    section: SlashMenuSection.dashboards,
    items: items,
    descriptions: dashboardSlashMenuDescriptions(items),
  );
}

/// Every dashboard widget a page has no block of its own for, read from the
/// widget registry as the menu opens.
SlashMenuSectionItems _widgetSection() {
  final items = dashboardWidgetSlashMenuItems();
  return SlashMenuSectionItems(
    section: SlashMenuSection.widgets,
    items: items,
    descriptions: dashboardWidgetSlashMenuDescriptions(items),
    blockTypes: {
      for (final item in items) item: DashboardWidgetBlockKeys.type,
    },
  );
}

/// The slash menu items in the simple table block.
///
/// There're some blocks should be excluded in the slash menu items.
///
/// - Database Items
/// - Image Gallery
List<SelectionMenuItem> _simpleTableSlashMenuItems() {
  return registerSlashMenuSections([
    SlashMenuSectionItems(
      section: SlashMenuSection.basicBlocks,
      items: [
        paragraphSlashMenuItem,
        heading1SlashMenuItem,
        heading2SlashMenuItem,
        heading3SlashMenuItem,
        bulletedListSlashMenuItem,
        numberedListSlashMenuItem,
        todoListSlashMenuItem,
        toggleListSlashMenuItem,
        reminderSlashMenuItem,
      ],
      shortcuts: {
        heading1SlashMenuItem: '#',
        heading2SlashMenuItem: '##',
        heading3SlashMenuItem: '###',
        bulletedListSlashMenuItem: '-',
        numberedListSlashMenuItem: '1.',
        todoListSlashMenuItem: '-[]',
        toggleListSlashMenuItem: '>',
      },
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.diagrams,
      items: diagramSlashMenuItems(),
      descriptions: diagramSlashMenuDescriptions(),
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.media,
      items: [
        imageSlashMenuItem,
        audioSlashMenuItem,
        videoSlashMenuItem,
        fileSlashMenuItem,
        pdfSlashMenuItem,
        wordSlashMenuItem,
        excelSlashMenuItem,
        powerpointSlashMenuItem,
        htmlSlashMenuItem,
        markdownSlashMenuItem,
        zipSlashMenuItem,
        csvSlashMenuItem,
        jsonSlashMenuItem,
        codeFileSlashMenuItem,
        textFileSlashMenuItem,
        notebookSlashMenuItem,
      ],
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.database,
      items: [linkToPageSlashMenuItem],
    ),
    SlashMenuSectionItems(
      section: SlashMenuSection.advanced,
      items: [
        dividerSlashMenuItem,
        quoteSlashMenuItem,
        calloutSlashMenuItem,
        codeBlockSlashMenuItem,
        toggleHeading1SlashMenuItem,
        toggleHeading2SlashMenuItem,
        toggleHeading3SlashMenuItem,
        emojiSlashMenuItem,
        dateOrReminderSlashMenuItem,
        subPageSlashMenuItem,
      ],
    ),
  ]);
}
