import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_views.dart';
import 'package:appflowy/plugins/collection/views/collection_contents_view.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/cover_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_tree.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../util/native_find_test_input.dart';
import '../util/workspace_explorer_permission_fakes.dart';
import 'document_find_host_test_support.dart';
import 'file_controls_test_support.dart';

const _navigationKey = ValueKey('active-find-sidebar');
const _documentTitleKey = ValueKey('active-find-document-title');
const _folderSearchKey = ValueKey('folder-explorer-search-field');
const _collectionSearchKey = ValueKey('collection-search');
const _queryKey = ValueKey('findTextField');

void main() => runActivePageFindHostRegressions();

/// Registers eight real-host tests, including their isolated fixture setup.
/// A Windows integration entry point can initialize its binding, then call this
/// instead of [main]. Physical key codes are explicit for Release reuse.
///
/// PageStack, AppFlowyEditorPage/CoverTitle, FolderExplorer, CollectionPage and
/// their search UIs are production widgets. Only page-manager output, backend
/// blocs/repositories, shortcut storage and asset setup use test boundaries.
/// No synthetic Find region, direct dispatch, app startup or FFI boot is used.
void runActivePageFindHostRegressions() {
  fileControlTestSetup();
  setUpFindHostTests();

  for (final mode in fileControlAppearances) {
    _documentTest(mode: mode, hover: false);
  }
  _documentTest(mode: 'paper', hover: true);

  for (final nestedRoute in [false, true]) {
    _browserTest(
      collection: false,
      nestedRoute: nestedRoute,
      mode: nestedRoute ? 'dark' : 'light',
    );
    _browserTest(
      collection: true,
      nestedRoute: nestedRoute,
      mode: nestedRoute ? 'dark' : 'paper',
    );
  }
}

void _documentTest({required String mode, required bool hover}) {
  testWidgets(
    '$mode document: ${hover ? 'page hover with' : 'no-hover'} sidebar focus opens real Find across the content Navigator',
    (tester) => withFindHostStorage(() async {
      final page = _DocumentPage();
      final shell = _ScopedShell(page.widget, nestedRoute: true);
      final semantics = tester.ensureSemantics();
      final registrations = ContextualFindRegion.debugRegisteredRegionCount;
      TestGesture? mouse;
      try {
        await shell.mount(tester, mode: mode);
        shell.expectRoutingBoundary(tester, find.byType(AppFlowyEditorPage));
        expect(find.byType(AppFlowyEditor), findsOneWidget);
        final native =
            tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
        expect(native.editorState, same(page.editor));
        expect(native.autoFocus, isFalse);
        expect(native.editable, isTrue);
        expect(
          find.descendant(
            of: find.byType(AppFlowyEditor),
            matching: find.text('needle first paragraph', findRichText: true),
          ),
          findsOneWidget,
        );
        final editorElement = tester.element(find.byType(AppFlowyEditor));
        final title = find.descendant(
          of: find.byKey(_documentTitleKey, skipOffstage: false),
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        );
        final titleElement = tester.element(title);
        final titleField = tester.widget<EditableText>(title);
        expect(titleField.controller, isA<DocumentFindTitleController>());
        expect(titleField.focusNode, same(page.shared.coverTitleFocusNode));
        expect(DocumentFindTitle.of(page.editor).text, page.view.view.name);
        final titleValue = titleField.controller.value;
        var titleNotifications = 0;
        titleField.controller.addListener(() => titleNotifications++);
        final before = page.editor.document.toJson();

        // Never click the editor, set a selection, or enable its keyboard
        // service to make this pass. Sidebar focus must be sufficient.
        await shell.focusNavigation(tester);
        shell.expectUntouchedContent();
        expect(page.editor.selection, isNull);
        expect(page.shared.coverTitleFocusNode.hasFocus, isFalse);
        expect(DocumentFindMenu.isOpen, isFalse);
        expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
        if (hover) {
          mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(
            location: tester.getCenter(find.byKey(_navigationKey)),
          );
          await mouse.moveTo(
            tester.getBottomLeft(find.byType(AppFlowyEditor)) +
                const Offset(32, -32),
          );
          await tester.pump();
          expect(shell.manager.pointerEnters, greaterThan(0));
          expect(shell.manager.pointerDowns, 0);
          expect(shell.navigation.hasPrimaryFocus, isTrue);
          expect(page.editor.selection, isNull);
          expect(titleField.controller.value, titleValue);
        }

        await _find(tester);
        expect(DocumentFindMenu.isOpen, isTrue);
        expect(DocumentFindMenu.activeEditor, same(page.editor));
        expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
        expect(findHostMenu(tester).documentId, page.view.view.id);
        expect(findHostMenu(tester).currentView!()!.id, page.view.view.id);
        expect(findHostMenu(tester).isOwnerActive!(), isTrue);
        expect(findHostBar(tester).matchCount, 0);
        expect(findHostBar(tester).showReplace, isFalse);
        expect(page.editor.selection, isNull);
        final query = find.byKey(_queryKey);
        final field = _expectFocusedSearch(tester, query);
        final queryElement = tester.element(query);
        final menuState = tester.state(find.byType(FindAndReplaceMenuWidget));
        expect(shell.navigation.hasFocus, isFalse);
        expect(
          PaperTheme.isEnabled(tester.element(query)),
          mode == 'paper',
        );
        if (mode == 'paper') {
          expect(
            FindBarPalette.of(tester.element(query)).surface,
            PaperTheme.popupBackground,
          );
        }

        await findHostQuery(tester, 'needle');
        await settleFileControls(tester);
        expect(findHostBar(tester).matchCount, 3);
        expect(findHostBar(tester).currentMatch, 1);
        expect(find.text('Read-only match · Title'), findsOneWidget);
        expect(page.editor.selection, isNull);
        _expectFocusedSearch(tester, query);

        // Submit through the real native query field, not a session callback.
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settleFileControls(tester);
        expect(findHostBar(tester).currentMatch, 2);
        expect(
          page.editor.selection,
          Selection.single(path: [0], startOffset: 0, endOffset: 6),
        );
        expect(find.text('Read-only match · Title'), findsNothing);
        final queryDraft = field.controller!.text;
        await shell.focusNavigation(tester);
        await _find(tester);
        expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
        expect(
          tester.state(find.byType(FindAndReplaceMenuWidget)),
          same(menuState),
        );
        expect(tester.element(query), same(queryElement));
        final reopened = _expectFocusedSearch(tester, query);
        expect(reopened.controller, same(field.controller));
        expect(reopened.focusNode, same(field.focusNode));
        // Desktop EditableText selects all on keyboard focus reactivation.
        // Retain the draft and owner, not the fixture's collapsed selection.
        expect(reopened.controller!.text, queryDraft);
        expect(reopened.controller!.selection.isValid, isTrue);
        expect(DocumentFindMenu.activeEditor, same(page.editor));
        expect(findHostMenu(tester).isOwnerActive!(), isTrue);
        expect(findHostBar(tester).matchCount, 3);
        expect(findHostBar(tester).currentMatch, 2);

        await _escape(tester);
        expect(DocumentFindMenu.isOpen, isFalse);
        expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
        expect(
          tester.element(find.byType(AppFlowyEditor)),
          same(editorElement),
        );
        expect(tester.element(title), same(titleElement));
        expect(
          tester.widget<EditableText>(title).controller,
          same(titleField.controller),
        );
        expect(titleField.controller.value, titleValue);
        expect(titleNotifications, 0);
        expect(page.view.events, isEmpty);
        expect(page.info.events, isEmpty);
        expect(page.bodyWrites, 0);
        expect(page.editor.document.toJson(), before);
        expect(tester.takeException(), isNull);
      } finally {
        if (mouse != null) await mouse.removePointer();
        try {
          await page.dispose(tester);
          expect(
            page.bodyWrites,
            0,
            reason: 'Find teardown must not write either',
          );
          expect(page.view.events, isEmpty);
          expect(page.info.events, isEmpty);
        } finally {
          semantics.dispose();
          shell.dispose();
        }
        expect(ContextualFindRegion.debugRegisteredRegionCount, registrations);
        expect(tester.takeException(), isNull);
      }
    }),
    variant: findTestPlatformVariant,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

void _browserTest({
  required bool collection,
  required bool nestedRoute,
  required String mode,
}) {
  testWidgets(
    '$mode ${collection ? 'CollectionPage' : 'FolderExplorer'}: no-hover sidebar Find on ${nestedRoute ? 'nested' : 'root'} route filters without replacing the listing',
    (tester) async {
      final repository = _BrowserRepository(collection: collection);
      final persistence = _CollectionPersistence();
      final controller = WorkspaceExplorerController(
        root: repository.root,
        repository: repository,
        listenForUpdates: false,
        // Do not make zero-write assertions vacuous by making the host read-only.
        canWrite: () => true,
      );
      final opened = <ViewPB>[];
      final shell = _ScopedShell(
        collection
            ? CollectionPage(
                view: repository.root,
                controller: controller,
                shellOwnsBreadcrumbs: true,
                service: persistence,
                onOpen: opened.add,
              )
            : FolderExplorer(
                rootView: repository.root,
                controller: controller,
                initialViewMode: FileBrowserViewMode.tree,
                onOpen: opened.add,
              ),
        nestedRoute: nestedRoute,
      );
      final semantics = tester.ensureSemantics();
      final registrations = ContextualFindRegion.debugRegisteredRegionCount;
      final before = repository.snapshot();
      final clipboard = controller.clipboard.data;
      try {
        await controller.initialize();
        controller.selection.selectOnly('first');
        await shell.mount(tester, mode: mode);
        final host = find.byType(collection ? CollectionPage : FolderExplorer);
        shell.expectRoutingBoundary(tester, host);
        final hostElement = tester.element(host);
        final folderElement = tester.element(find.byType(FolderExplorer));
        final treeState = tester.state(find.byType(ExplorerTree));
        final collectionScroll = collection
            ? tester.state<ScrollableState>(
                find.descendant(
                  of: find.byType(FileBrowserScrollView),
                  matching: find.byType(Scrollable),
                ),
              )
            : null;
        final listingPosition = collectionScroll?.position;
        if (collection) expect(find.byType(NestedScrollView), findsNothing);
        final title = find.byKey(
          ValueKey(collection ? 'collection-title' : 'folder-gallery-title'),
        );
        final titleElement = tester.element(title);
        final listing = controller.rows;
        final ids = listing.map((row) => row.item.id).toList();
        expect(ids, ['folder', 'first', 'second', ...repository.tailIds]);
        expect(controller.canWrite, isTrue);
        expect(
          tester.widget<ExplorerTree>(find.byType(ExplorerTree)).controller,
          same(controller),
        );
        expect(
          find.text('Needle notes.bin', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.text('Other notes.bin', findRichText: true),
          findsOneWidget,
        );
        expect(find.byType(ContextualFindRegion), findsOneWidget);
        final region = tester
            .widget<ContextualFindRegion>(find.byType(ContextualFindRegion));
        expect(
          region.debugLabel,
          collection ? 'Collection search' : 'Folder explorer',
        );

        Element? collapsedField;
        TextField? originalField;
        if (collection) {
          expect(find.byType(CollectionContentsView), findsOneWidget);
          expect(
            tester
                .widget<FolderExplorer>(find.byType(FolderExplorer))
                .showControls,
            isFalse,
          );
          expect(
            find.byKey(_folderSearchKey, skipOffstage: false),
            findsNothing,
          );
          expect(find.byKey(_collectionSearchKey), findsNothing);
        } else {
          final hidden = find.byKey(_folderSearchKey, skipOffstage: false);
          collapsedField = tester.element(hidden);
          originalField = tester.widget<TextField>(hidden);
          expect(hidden.hitTestable(), findsNothing);
        }

        await shell.focusNavigation(tester);
        shell.expectUntouchedContent();
        expect(controller.query, isEmpty);
        expect(controller.selection.ids, {'first'});
        expect(repository.indexReads, 0);
        await _find(tester);
        final search =
            collection ? _collectionSearch() : find.byKey(_folderSearchKey);
        final field = _expectFocusedSearch(tester, search);
        final fieldElement = tester.element(search);
        if (collectionScroll != null) {
          _expectCollectionSearchVisible(tester, search, collectionScroll);
          expect(
            collectionScroll.position.pixels,
            0,
            reason: 'Opening an already-visible field must not scroll it',
          );
        }
        if (!collection) {
          expect(fieldElement, same(collapsedField));
          expect(field.controller, same(originalField!.controller));
          expect(field.focusNode, same(originalField.focusNode));
          expect(
            tester
                .widget<FolderGalleryHeader>(find.byType(FolderGalleryHeader))
                .searchFocusNode,
            same(field.focusNode),
          );
        }
        expect(controller.rows, same(listing));
        expect(controller.selection.ids, {'first'});
        expect(
          repository.indexReads,
          0,
          reason: 'Opening alone must not search or reload',
        );

        await tester.enterText(search, 'needle');
        await settleFileControls(tester);
        expect(controller.query, 'needle');
        expect(controller.isSearching, isFalse);
        expect(controller.rows.map((row) => row.item.id),
            ['first', ...repository.tailIds]);
        expect(
          find.text('Needle notes.bin', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Other notes.bin', findRichText: true), findsNothing);
        expect(controller.selection.ids, {'first'});
        expect(repository.indexReads, 1);
        final filtered = controller.rows;
        final queryDraft = field.controller!.text;
        await shell.focusNavigation(tester);
        shell.expectUntouchedContent();
        if (collectionScroll != null) {
          // Make the existing header genuinely offscreen without hovering or
          // focusing content. Only the next real Ctrl+F may reveal it again.
          final header = find.byKey(
            const ValueKey('collection-page-identity'),
            skipOffstage: false,
          );
          final distance = tester.getBottomLeft(header).dy -
              tester.getTopLeft(find.byType(CustomScrollView)).dy +
              40;
          expect(
              collectionScroll.position.maxScrollExtent, greaterThan(distance));
          collectionScroll.position.jumpTo(distance);
          await settleFileControls(tester);
          final hiddenSearch = _collectionSearch(skipOffstage: false);
          expect(find.byKey(_collectionSearchKey), findsNothing);
          expect(hiddenSearch.hitTestable(), findsNothing);
          expect(tester.element(hiddenSearch), same(fieldElement));
          expect(fieldElement.mounted, isTrue);
          expect(tester.renderObject(hiddenSearch).attached, isTrue);
          expect(field.controller!.text, queryDraft);
          expect(shell.navigation.hasPrimaryFocus, isTrue);
          shell.expectUntouchedContent();
        }
        await _find(tester);
        final reopened = _expectFocusedSearch(tester, search);
        if (collectionScroll != null) {
          _expectCollectionSearchVisible(tester, search, collectionScroll);
          expect(
            collectionScroll.position,
            same(listingPosition),
          );
          expect(
            tester
                .widget<CollectionViewSwitcher>(
                  find.byType(CollectionViewSwitcher),
                )
                .activeViewId,
            CollectionViewIds.list,
          );
        }
        expect(tester.element(search), same(fieldElement));
        expect(reopened.controller, same(field.controller));
        expect(reopened.focusNode, same(field.focusNode));
        // A native select-all on refocus must not look like a lost draft.
        expect(reopened.controller!.text, queryDraft);
        expect(reopened.controller!.selection.isValid, isTrue);
        expect(controller.query, queryDraft);
        expect(controller.rows, same(filtered));
        expect(repository.indexReads, 1);

        // Clearing uses the real field's debounced onChanged -> controller path.
        await tester.enterText(search, '');
        await settleFileControls(tester);
        _expectFocusedSearch(tester, search);
        if (collectionScroll != null) {
          _expectCollectionSearchVisible(tester, search, collectionScroll);
        }
        expect(controller.query, isEmpty);
        expect(controller.rows, same(listing));
        expect(controller.rows.map((row) => row.item.id), ids);
        expect(
          find.text('Other notes.bin', findRichText: true),
          findsOneWidget,
        );
        expect(
          controller.childrenOf(repository.root.id).map((view) => view.id),
          ids,
        );
        expect(controller.selection.ids, {'first'});
        expect(controller.currentFolder.id, repository.root.id);
        expect(
          controller.breadcrumbs.map((item) => item.id),
          [repository.root.id],
        );
        expect(tester.element(host), same(hostElement));
        expect(
          tester.element(find.byType(FolderExplorer)),
          same(folderElement),
        );
        expect(tester.state(find.byType(ExplorerTree)), same(treeState));
        expect(tester.element(title), same(titleElement));
        expect(controller.editingId, isNull);
        expect(controller.draft, isNull);
        expect(controller.errorMessage, isNull);
        expect(repository.childrenReads, [repository.root.id]);
        expect(repository.indexReads, 1);
        expect(repository.writes, isEmpty);
        expect(persistence.writes, isEmpty);
        expect(repository.snapshot(), before);
        expect(
          controller.viewForId(repository.root.id)!.writeToBuffer(),
          before[repository.root.id],
        );
        expect(controller.clipboard.data, same(clipboard));
        expect(opened, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await unmountFileControls(tester);
          expect(repository.writes, isEmpty);
          expect(persistence.writes, isEmpty);
          expect(repository.snapshot(), before);
          expect(
            controller.viewForId(repository.root.id),
            isNotNull,
            reason: 'The page borrows, rather than disposes, the graph',
          );
        } finally {
          semantics.dispose();
          shell.dispose();
          controller.dispose();
        }
        expect(ContextualFindRegion.debugRegisteredRegionCount, registrations);
        expect(tester.takeException(), isNull);
      }
    },
    variant: findTestPlatformVariant,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

TextField _expectFocusedSearch(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  final field = tester.widget<TextField>(finder);
  expect(field.readOnly, isFalse);
  expect(field.focusNode!.hasPrimaryFocus, isTrue);
  final editableFinder =
      find.descendant(of: finder, matching: find.byType(EditableText));
  expect(editableFinder, findsOneWidget);
  final editable = tester.widget<EditableText>(editableFinder);
  final render = tester.state<EditableTextState>(editableFinder).renderEditable;
  final native = find.descendant(
    of: editableFinder,
    matching: find.byElementPredicate(
      (element) =>
          element is RenderObjectElement &&
          identical(element.renderObject, render),
    ),
  );
  expect(editable.focusNode, same(field.focusNode));
  expect(editable.controller, same(field.controller));
  // getSemantics uses RenderObject.debugSemantics, always null in Release.
  // Inspect the actual attached tree in both builds, not a debug-only cache
  // or the bar's separate live-region node. There must be one focused field.
  expect(native, findsOneWidget);
  final root = render.owner?.semanticsOwner?.rootSemanticsNode;
  expect(root, isNotNull);
  final focusedFields = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasFlag(ui.SemanticsFlag.isTextField) &&
        data.hasFlag(ui.SemanticsFlag.isFocused)) {
      focusedFields.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root!);
  expect(focusedFields, hasLength(1));
  final node = focusedFields.single;
  expect(node.attached, isTrue);
  final data = node.getSemanticsData();
  expect(data.hasFlag(ui.SemanticsFlag.isTextField), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
  expect(data.hasAction(ui.SemanticsAction.setText), isTrue);
  expect(data.value, field.controller!.text);
  return field;
}

Finder _collectionSearch({bool skipOffstage = true}) => find.descendant(
      of: find.byKey(_collectionSearchKey, skipOffstage: skipOffstage),
      matching: find.byType(TextField, skipOffstage: skipOffstage),
      skipOffstage: skipOffstage,
    );

void _expectCollectionSearchVisible(
  WidgetTester tester,
  Finder search,
  ScrollableState originalScroll,
) {
  final scroll = find.byType(CustomScrollView);
  expect(scroll, findsOneWidget);
  expect(Scrollable.of(tester.element(search)), same(originalScroll));
  final viewport = tester.getRect(scroll);
  final field = tester.getRect(search);
  expect(field.left, greaterThanOrEqualTo(viewport.left));
  expect(field.top, greaterThanOrEqualTo(viewport.top));
  expect(field.right, lessThanOrEqualTo(viewport.right));
  expect(field.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(
    originalScroll.position.isScrollingNotifier.value,
    isFalse,
    reason: 'Reveal must not leave a corrective caret scroll in flight',
  );
}

Future<void> _find(WidgetTester tester) async {
  await sendFindTestShortcut(tester);
  await settleFileControls(tester);
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(
    LogicalKeyboardKey.escape,
    physicalKey: PhysicalKeyboardKey.escape,
  );
  await settleFileControls(tester);
}

class _ScopedShell {
  _ScopedShell(Widget child, {required this.nestedRoute})
      : manager = _BorrowedPageManager(child, nestedRoute: nestedRoute);

  final bool nestedRoute;
  final _BorrowedPageManager manager;
  final navigation = FocusNode(debugLabel: 'Regression sidebar navigation');

  Future<void> mount(WidgetTester tester, {required String mode}) =>
      mountFileControls(
        tester,
        Row(
          children: [
            SizedBox(
              width: 140,
              child: Align(
                alignment: Alignment.topCenter,
                child: TextButton(
                  key: _navigationKey,
                  focusNode: navigation,
                  onPressed: () {},
                  child: const Text('Sidebar'),
                ),
              ),
            ),
            Expanded(
              // Do not add a test-owned ContextualFindScope: removing the
              // production PageStack scope must break the no-hover tests.
              child: PageStack(
                pageManager: manager,
                delegate: _UnusedStackDelegate(),
                userProfile: UserProfilePB(),
              ),
            ),
          ],
        ),
        mode: mode,
        width: 1060,
        height: 840,
        reduced: true,
        accessible: true,
      );

  Future<void> focusNavigation(WidgetTester tester) async {
    navigation.requestFocus();
    await settleFileControls(tester);
    expect(navigation.hasPrimaryFocus, isTrue);
  }

  void expectUntouchedContent() {
    expect(manager.pointerEnters, 0, reason: 'No prior content hover');
    expect(manager.pointerDowns, 0, reason: 'No prior content click');
  }

  void expectRoutingBoundary(WidgetTester tester, Finder host) {
    expect(find.byType(PageStack), findsOneWidget);
    expect(find.byType(ContextualFindScope), findsOneWidget);
    expect(
      find.ancestor(of: host, matching: find.byType(ContextualFindScope)),
      findsOneWidget,
    );
    final shellRoute = ModalRoute.of(navigation.context!);
    final contentRoute = ModalRoute.of(tester.element(host));
    expect(shellRoute, isNotNull);
    expect(contentRoute, isNotNull);
    expect(contentRoute!.isCurrent, isTrue);
    if (nestedRoute) {
      expect(contentRoute, isNot(same(shellRoute)));
      expect(ModalRoute.of(contentRoute.navigator!.context), same(shellRoute));
    } else {
      expect(contentRoute, same(shellRoute));
    }
  }

  void dispose() => navigation.dispose();
}

/// Replace only PageManager's plugin/FFI loading. PageStack still installs the
/// real scope, traversal group and surface; the returned content stays native.
class _BorrowedPageManager extends Fake implements PageManager {
  _BorrowedPageManager(this.child, {required this.nestedRoute});
  final Widget child;
  final bool nestedRoute;
  int pointerEnters = 0;
  int pointerDowns = 0;

  @override
  Widget stackWidget({
    required UserProfilePB userProfile,
    required Function(ViewPB, int?) onDeleted,
  }) {
    final content = MouseRegion(
      opaque: false,
      onEnter: (_) => pointerEnters++,
      child: Listener(
        onPointerDown: (_) => pointerDowns++,
        child: child,
      ),
    );
    return nestedRoute
        ? Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Material(child: content),
            ),
          )
        : content;
  }
}

class _UnusedStackDelegate extends Fake implements HomeStackDelegate {}

class _DocumentPage {
  _DocumentPage() {
    document = FindHostDocument(view.view.id, editor);
    transactions = editor.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after && event.$2.operations.isNotEmpty) {
        bodyWrites++;
      }
    });
  }

  final editor = EditorState(
    document: Document(
      root: pageNode(
        children: [
          paragraphNode(text: 'needle first paragraph'),
          paragraphNode(text: 'A second needle paragraph'),
        ],
      ),
    ),
  )..disableSealTimer = true;
  final view = FindHostView(
    ViewPB(id: 'active-document', name: 'Visible needle page title'),
  );
  final info = FindHostViewInfo();
  final shared = SharedEditorContext();
  final appearance = DocumentAppearanceCubit();
  late final FindHostDocument document;
  late final StreamSubscription<EditorTransactionValue> transactions;
  int bodyWrites = 0;

  Widget get widget => MultiProvider(
        providers: [
          Provider<AppearanceSettingsCubit>.value(value: FindHostAppearance()),
          Provider<SharedEditorContext>.value(value: shared),
          Provider<EditorState>.value(value: editor),
          Provider<ViewInfoBloc>.value(value: info),
          BlocProvider<DocumentAppearanceCubit>.value(value: appearance),
          BlocProvider<DocumentBloc>.value(value: document),
          BlocProvider<ViewBloc>.value(value: view),
        ],
        child: Builder(
          builder: (context) => AppFlowyEditorPage(
            editorState: editor,
            autoFocus: false,
            useViewInfoBloc: false,
            styleCustomizer: _FindStyle(context),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
              child: _BorrowedCoverTitle(
                key: _documentTitleKey,
                view: view.view,
                bloc: view,
              ),
            ),
          ),
        ),
      );

  Future<void> dispose(WidgetTester tester) async {
    DocumentFindMenu.dismiss(editorState: editor);
    // Drain highlight removal and the native list's deferred position report
    // before removing its renderer, as in RowFindHarness's existing cleanup.
    await tester.pump();
    await tester.pump();
    await unmountFileControls(tester);
    unawaited(transactions.cancel());
    unawaited(document.close());
    unawaited(view.close());
    unawaited(appearance.close());
    shared.dispose();
    editor.dispose();
    editor.editableNotifier.dispose();
    await tester.pump();
  }
}

/// Same narrow boundary as cover_title_find_host_test: preserve CoverTitle's
/// private native field, controller, focus handling and rename listener.
class _BorrowedCoverTitle extends CoverTitle {
  const _BorrowedCoverTitle({
    super.key,
    required super.view,
    required this.bloc,
  });
  final FindHostView bloc;

  @override
  Widget build(BuildContext context) {
    final native = super.build(context) as BlocProvider<ViewBloc>;
    return BlocProvider<ViewBloc>.value(value: bloc, child: native.child);
  }
}

class _FindStyle extends EditorStyleCustomizer {
  _FindStyle(BuildContext context)
      : super(context: context, padding: const EdgeInsets.all(24));

  @override
  EditorStyle style() => EditorStyle.desktop(
        padding: padding,
        textSpanDecorator: (context, node, start, text, before, after) =>
            decorateWithSearchHighlight(context, node, start, after),
      );
}

class _BrowserRepository extends ExplorerPermissionRepository {
  _BrowserRepository({required bool collection}) {
    root.name = collection ? 'Reference library' : 'Project files';
    if (collection) {
      // Use a registered production contents view, not a replacement builder.
      root.extra = const CollectionMetadata(
        kind: CollectionKind.book,
        activeViewId: CollectionViewIds.list,
      ).mergeIntoExtra(root.extra);
    }
    views[root.id] = ViewPB.fromBuffer(root.writeToBuffer());
    views['first']!.name = 'Needle notes.bin';
    views['second']!.name = 'Other notes.bin';
    if (collection) {
      for (var index = 0; index < 40; index++) {
        final id = 'tail-$index';
        tailIds.add(id);
        views[id] = permissionFile(
            id, root.id, 'Tail needle ${index.toString().padLeft(2, '0')}.bin');
      }
    }
  }

  final tailIds = <String>[];
  final childrenReads = <String>[];
  int indexReads = 0;

  Map<String, List<int>> snapshot() => {
        for (final entry in views.entries)
          entry.key: entry.value.writeToBuffer().toList(),
      };

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) {
    childrenReads.add(id);
    return super.getChildren(id);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() {
    indexReads++;
    return super.getAllViews();
  }
}

class _CollectionPersistence extends CollectionService {
  final writes = <CollectionMetadata>[];

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required CollectionMetadata metadata,
  }) async {
    writes.add(metadata);
    return FlowyResult.success(ViewPB.fromBuffer(view.writeToBuffer()));
  }
}
