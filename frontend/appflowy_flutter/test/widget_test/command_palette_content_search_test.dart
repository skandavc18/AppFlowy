import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/floating_modal.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/search_service.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/content_search_widgets.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_inspection_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_preview.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_ask_ai_entrance.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_result_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart'
    show TrashPB;
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../unit_test/search/workspace_content_search_test_support.dart';
import 'test_material_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var ownsMenuState = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Keep the existing bundle loader; preferences and read I/O are isolated.
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    if (!getIt.isRegistered<MenuSharedState>()) {
      ownsMenuState = true;
      getIt.registerSingleton<MenuSharedState>(MenuSharedState());
    }
  });
  tearDownAll(() async {
    if (ownsMenuState) await getIt.unregister<MenuSharedState>();
  });

  testWidgets(
      'optional input callback owns typing and clear without backend dispatch',
      (tester) async {
    final palette = _PaletteBloc(CommandPaletteState.initial());
    final inputs = <String>[];
    Widget field(String seed) => BlocProvider<CommandPaletteBloc>.value(
          value: palette,
          child: SearchField(query: seed, onChanged: inputs.add),
        );
    await _mountSurface(tester, field('Initial draft'));
    await tester.enterText(find.byType(EditableText), 'Current [.*] draft');
    await tester.pump();
    await _mountSurface(tester, field('Delayed backend query'));
    expect(_draft(tester), 'Current [.*] draft');
    expect(inputs, ['Current [.*] draft']);
    expect(palette.events, isEmpty);
    await tester
        .tap(find.byKey(const ValueKey('command-palette-clear-search')));
    await tester.pump();
    expect(_draft(tester), isEmpty);
    expect(inputs.last, isEmpty);
    expect(palette.events, isEmpty);
    await _unmount(tester, palette: palette);
  });

  testWidgets(
      'native palette typing survives delayed source events and queued timeout without refocus',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('native', '', name: 'native documentation')
      ..page('long', '', name: 'abcdefghijklmnopqrstuvwxyzabcdef');
    final held = Completer<void>();
    reads.scheduler.schedule(Object(), () => true, () => held.future);
    final harness = _ModalHarness(reads);
    try {
      await harness.mount(tester, routed: true);
      final finder = find.byType(EditableText);
      final element = tester.element(finder);
      final state = tester.state<EditableTextState>(finder);
      for (final query in [
        'native documentation',
        'abcdefghijklmnopqrstuvwxyzabcdef',
      ]) {
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            selection: TextSelection.collapsed(offset: 0),
          ),
        );
        for (var i = 1; i <= query.length; i++) {
          expect(state.widget.focusNode.hasPrimaryFocus, isTrue);
          expect(tester.testTextInput.hasAnyClients, isTrue);
          expect(
            state.widget.controller.selection,
            TextSelection.collapsed(offset: i - 1),
          );
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: query.substring(0, i),
              selection: TextSelection.collapsed(offset: i),
            ),
          );
          if (i == 10) reads.changes.add('native');
          await tester.pump(const Duration(milliseconds: 20));
          await tester.pump();
          expect(tester.element(finder), same(element));
          expect(tester.state(finder), same(state));
          expect(state.widget.controller.text, query.substring(0, i));
          expect(
            state.widget.controller.selection,
            TextSelection.collapsed(offset: i),
          );
        }
      }
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.byKey(const ValueKey('command-palette-title-timeout')),
        findsOneWidget,
      );
      expect(find.byType(NoSearchResultsHint), findsNothing);
      held.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(SearchResultCell), findsOneWidget);
      expect(
        tester.widget<SearchResultCell>(find.byType(SearchResultCell)).item.id,
        'long',
      );
      expect(tester.element(finder), same(element));
      expect(state.widget.focusNode.hasPrimaryFocus, isTrue);
      expect(_draft(tester), 'abcdefghijklmnopqrstuvwxyzabcdef');
    } finally {
      if (!held.isCompleted) held.complete();
      await harness.dispose(tester);
    }
  });

  testWidgets(
      'filter toggles are mutually exclusive and preserve other choices',
      (tester) async {
    final filter = ValueNotifier(
      const CommandPaletteFilter(
        titleOnly: true,
        createdByMe: true,
        spaceId: 'space',
      ),
    );
    await _mountSurface(
      tester,
      ValueListenableBuilder<CommandPaletteFilter>(
        valueListenable: filter,
        builder: (_, value, __) => SearchFilterBar(
          filter: value,
          spaces: [ViewPB(id: 'space', name: 'Research')],
          onChanged: (value) => filter.value = value,
        ),
      ),
    );
    await tester
        .tap(find.byKey(const ValueKey('command-palette-content-filter')));
    await tester.pump();
    expect(filter.value.pageContents, isTrue);
    expect(filter.value.titleOnly, isFalse);
    expect(filter.value.createdByMe, isTrue);
    expect(filter.value.spaceId, 'space');
    expect(find.text('Page contents'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('command-palette-title-filter')));
    await tester.pump();
    expect(filter.value.pageContents, isFalse);
    expect(filter.value.titleOnly, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    filter.dispose();
    await tester.pump();
  });

  testWidgets(
      'body hit renders selected highlighted context using input, not delayed backend query',
      (tester) async {
    final reads = WorkspaceSearchReads();
    final view = reads.page(
      'body-hit',
      'The NeEdLe appears only in these page contents.',
      name: 'Planning ${'long page name ' * 30}',
    )..icon = ViewIconPB(ty: ViewIconTypePB.Emoji, value: '🧭');
    final harness = _ModalHarness(reads);
    await harness.mount(tester);
    expect(reads.calls, isEmpty);
    await _enableContents(tester);
    await tester.enterText(find.byType(EditableText), 'needle');
    await tester.pump(const Duration(milliseconds: 299));
    expect(reads.calls, isEmpty);
    expect(find.byType(NoSearchResultsHint), findsNothing);
    expect(find.text('Scanning for matching page contents…'), findsOneWidget);
    await _results(tester);

    expect(harness.palette.state.query, _oldQuery);
    expect(harness.palette.events, isEmpty);
    expect(find.byType(SearchAskAiEntrance), findsNothing);
    final panel =
        tester.widget<PageInspectionPanel>(find.byType(PageInspectionPanel));
    expect(panel.view.id, view.id);
    expect(panel.query, 'needle');
    expect(
      panel.matchingSnippet,
      'The NeEdLe appears only in these page contents.',
    );
    final preview = tester.widget<PagePreview>(find.byType(PagePreview));
    expect(preview.query, 'needle');
    expect(preview.matchingSnippet, panel.matchingSnippet);
    expect(preview.contentSearch, isTrue);
    final excerpt = tester.widget<Text>(
      find.byKey(const ValueKey('command-palette-match-excerpt')),
    );
    expect(excerpt.textSpan!.toPlainText(), panel.matchingSnippet);
    expect(_highlightedText(excerpt.textSpan!), ['NeEdLe']);
    expect(
      find.descendant(
        of: find.byType(SearchResultCell),
        matching: find.byType(RawEmojiIconWidget),
      ),
      findsOneWidget,
    );
    expect(
      reads.counts['document:body-hit'],
      1,
      reason: 'Preview must not read the page again',
    );
    expect(find.byType(AppFlowyEditor), findsNothing);
    expect(find.byType(DatabaseTabBarView), findsNothing);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
      'editing the query removes old preview context before the debounce',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('first', 'First Needle context')
      ..page('second', 'Literal [.*] context');
    final harness = _ModalHarness(reads);
    await harness.mount(tester);
    await _enableContents(tester);
    await tester.enterText(find.byType(EditableText), 'needle');
    await _results(tester);
    expect(
      tester
          .widget<PageInspectionPanel>(find.byType(PageInspectionPanel))
          .view
          .id,
      'first',
    );
    await tester.enterText(find.byType(EditableText), '[.*]');
    await tester.pump();
    expect(find.byType(SearchMatchContext), findsNothing);
    expect(find.text('First Needle context', findRichText: true), findsNothing);
    await _results(tester);
    final panel =
        tester.widget<PageInspectionPanel>(find.byType(PageInspectionPanel));
    expect(panel.view.id, 'second');
    expect(panel.query, '[.*]');
    expect(
      _highlightedText(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('command-palette-match-excerpt')),
            )
            .textSpan!,
      ),
      ['[.*]'],
    );
    expect(_draft(tester), '[.*]');
    await harness.dispose(tester);
  });

  testWidgets('revocation clears the preview and blocks a pre-frame stale open',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('page', 'Needle private context');
    final harness = _ModalHarness(reads);
    await harness.mount(tester);
    await _enableContents(tester);
    await tester.enterText(find.byType(EditableText), 'needle');
    await _results(tester);
    final oldPanel =
        tester.widget<PageInspectionPanel>(find.byType(PageInspectionPanel));
    reads.allowed = false;
    reads.access.value++;
    oldPanel.onOpen(oldPanel.view);
    await tester.pump();
    expect(find.byType(SearchMatchContext), findsNothing);
    expect(find.byType(CommandPaletteModal), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(
      find.text('No matches in the scanned content. Coverage is partial.'),
      findsOneWidget,
    );
    expect(reads.counts['document:page'], 1);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
      'command mode works inside contents mode and returning restores metadata dispatch',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final harness = _ModalHarness(reads);
    await harness.mount(tester);
    await _enableContents(tester);
    await tester.enterText(find.byType(EditableText), '> sidebar');
    await tester.pump();
    final commands =
        tester.widget<CommandPalettePanel>(find.byType(CommandPalettePanel));
    expect(
      commands.commands.map((command) => command.id),
      contains('toggle_sidebar'),
    );
    expect(reads.calls, isEmpty);
    expect(harness.palette.events, isEmpty);
    final before = collapseMenuNotifier.value;
    await tester.sendKeyEvent(
      LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
    );
    await tester.pump();
    expect(collapseMenuNotifier.value, before + 1);
    collapseMenuNotifier.value = before;
    await tester.enterText(find.byType(EditableText), 'needle');
    await _results(tester);
    await tester
        .tap(find.byKey(const ValueKey('command-palette-content-filter')));
    await tester.pump();
    expect(_draft(tester), 'needle');
    expect(harness.palette.contentMode, isFalse);
    expect(
      harness.palette.events,
      contains(const CommandPaletteEvent.searchChanged(search: 'needle')),
    );
    expect(find.byType(SearchMatchContext), findsNothing);
    await harness.dispose(tester);
  });

  testWidgets('popping the modal cancels scanning before route disposal',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('page', 'Needle')
      ..page('later', 'Needle');
    final gate = reads.hold('document:page');
    final harness = _ModalHarness(reads);
    await harness.mount(tester, routed: true);
    await _enableContents(tester);
    await tester.enterText(find.byType(EditableText), 'needle');
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads.inFlight, 1);
    final context = tester.element(find.byType(CommandPaletteModal));
    final oldFilter =
        tester.widget<SearchFilterBar>(find.byType(SearchFilterBar));
    final oldField = tester.widget<SearchField>(find.byType(SearchField));
    Navigator.of(context).pop();
    // Retained widgets can outlive pop through the closing animation.
    oldFilter.onChanged(oldFilter.filter);
    oldField.onChanged!('late draft');
    expect(harness.palette.contentMode, isFalse);
    expect(reads.scheduler.pendingCount, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteModal), findsNothing);
    expect(reads.counts['document:later'], isNull);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
      'workspace changes clear old previews and never relabel old content',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('old', 'Old Needle');
    final harness = _ModalHarness(reads);
    await harness.mount(tester);
    await _enableContents(tester);
    await tester.enterText(find.byType(EditableText), 'needle');
    await _results(tester);
    harness.workspace.publish(
      harness.workspace.state.copyWith(
        currentWorkspace:
            UserWorkspacePB(workspaceId: 'other', name: 'Other workspace'),
      ),
    );
    await tester.pump();
    expect(find.byType(SearchMatchContext), findsNothing);
    reads.page('new', 'New Needle', parent: 'other');
    harness.palette.publish(
      harness.palette.state.copyWith(cachedViews: Map.of(reads.views)),
    );
    await _results(tester);
    final panel =
        tester.widget<PageInspectionPanel>(find.byType(PageInspectionPanel));
    expect(panel.view.id, 'new');
    expect(panel.matchingSnippet, 'New Needle');
    expect(reads.counts['document:old'], 1);
    await harness.dispose(tester);
  });

  testWidgets(
      'narrow contents results open highlighted in-pane context and return to the list',
      (tester) async {
    final view = ViewPB(
      id: 'page',
      name: 'Long ${'name ' * 80}',
      layout: ViewLayoutPB.Document,
    );
    await _mountSurface(
      tester,
      Center(
        child: SizedBox(
          width: 360,
          height: 580,
          child: SearchResultList(
            cachedViews: {view.id: view},
            resultItems: [
              SearchResultItem(
                id: view.id,
                icon: ResultIconPB(),
                content: 'Original Needle context.',
                displayName: view.name,
              ),
            ],
            resultSummaries: const [],
            query: 'needle',
            contentSearch: true,
          ),
        ),
      ),
      textScale: 2,
    );
    expect(find.byType(SearchMatchContext), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(SearchResultCell));
    await tester.pump();
    expect(find.byType(SearchMatchContext), findsOneWidget);
    expect(
      _highlightedText(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('command-palette-match-excerpt')),
            )
            .textSpan!,
      ),
      ['Needle'],
    );
    await tester.tap(
      find.byKey(const ValueKey('command-palette-content-preview-back')),
    );
    await tester.pump();
    expect(find.byType(SearchResultCell), findsOneWidget);
    expect(find.byType(SearchMatchContext), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
        'actual excerpt text uses subtle theme-aware highlights in $mode',
        (tester) async {
      const snippet = 'Original NeEdLe sentence.';
      await _mountSurface(
        tester,
        const SizedBox(
          width: 360,
          height: 260,
          child: SearchMatchContext(query: 'needle', snippet: snippet),
        ),
        mode: mode,
      );
      final finder =
          find.byKey(const ValueKey('command-palette-match-excerpt'));
      final widget = tester.widget<Text>(finder);
      final context = tester.element(finder);
      final runs = _highlightedSpans(widget.textSpan!).toList();
      expect(runs.single.text, 'NeEdLe');
      expect(
        runs.single.style!.backgroundColor,
        workspaceGlyphAccent(context)
            .withValues(alpha: mode == 'dark' ? 0.20 : 0.12),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)),
      );
      expect(paragraph.text.toPlainText(), snippet);
      expect(
        paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 9, extentOffset: 15),
        ),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  test('navigation show remains idempotent while Ctrl+P toggle still closes',
      () {
    final notifier = ValueNotifier(CommandPaletteNotifierValue());
    final palette =
        CommandPalette(notifier: notifier, child: const SizedBox.shrink());
    palette.show();
    expect(notifier.value.isOpen, isTrue);
    palette.show();
    expect(notifier.value.isOpen, isTrue);
    palette.toggle();
    expect(notifier.value.isOpen, isFalse);
    notifier.dispose();
  });

  testWidgets(
      'title input uses cached native names before metadata arrives and filters live',
      (tester) async {
    final reads = WorkspaceSearchReads();
    reads.folder('space');
    reads.page(
      'cached',
      '',
      name: 'Quarterly Roadmap',
      parent: 'space',
      creator: Int64(7),
    );
    reads.page('other', '', name: 'Roadmap archive', creator: Int64(9));
    reads.page('denied', '', name: 'Roadmap denied');
    reads.denied.add('denied');
    reads.page('remote', '', name: 'Roadmap remote', parent: 'other-workspace');
    reads.page('protected', '', name: 'Roadmap protected').extra =
        '{"appflowy_encryption":{"version":1}}';
    reads.page('trashed', '', name: 'Roadmap trash');
    final harness = _ModalHarness(reads);
    harness.palette.publish(
      harness.palette.state.copyWith(
        trash: [TrashPB(id: 'trashed')],
      ),
    );
    await harness.mount(tester);
    await tester.enterText(find.byType(EditableText), '  QUARTERLY   roadmap ');
    await tester.pump();
    await tester.pump();
    expect(harness.palette.state.query, _oldQuery);
    expect(find.byType(SearchResultCell), findsOneWidget);
    expect(
      tester.widget<SearchResultCell>(find.byType(SearchResultCell)).item.id,
      'cached',
    );
    expect(find.text('Quarterly Roadmap', findRichText: true), findsWidgets);
    expect(reads.calls.where((call) => call.startsWith('document:')), isEmpty);
    final input = tester.widget<EditableText>(find.byType(EditableText));
    final focus = input.focusNode;
    await tester
        .tap(find.byKey(const ValueKey('command-palette-title-filter')));
    await tester.pump();
    expect(find.byType(SearchResultCell), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'roadmap');
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widgetList<SearchResultCell>(find.byType(SearchResultCell))
          .map((cell) => cell.item.id),
      ['other', 'cached'],
    );
    final bar = tester.widget<SearchFilterBar>(find.byType(SearchFilterBar));
    bar.onChanged(bar.filter.copyWith(createdByMe: true, spaceId: 'space'));
    await tester.pump();
    expect(
      tester.widget<SearchResultCell>(find.byType(SearchResultCell)).item.id,
      'cached',
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode,
      same(focus),
    );
    final stalePanel =
        tester.widget<PageInspectionPanel>(find.byType(PageInspectionPanel));
    reads.allowed = false;
    reads.access.value++;
    stalePanel.onOpen(stalePanel.view);
    await tester.pump();
    expect(find.byType(SearchResultCell), findsNothing);
    expect(find.byType(CommandPaletteModal), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
      'title index ranks all cached views before capping and never reads bodies',
      (tester) async {
    final reads = WorkspaceSearchReads();
    for (var i = 0; i < 4200; i++) {
      reads.page('page-$i', '', name: 'Unrelated $i');
    }
    final wanted = reads.page('last', '', name: 'Exact title');
    final title = WorkspaceTitleSearchController(
      provider: reads.provider(),
      isWorkspaceCurrent: (id) => id == 'workspace',
    );
    title.updateSource(
      workspaceId: 'workspace',
      cachedViews: reads.views,
      excludedViewIds: const [],
      ready: true,
    );
    title.search(
        ' exact   TITLE ', const CommandPaletteFilter(titleOnly: true), [
      SearchResultItem(
        id: wanted.id,
        icon: ResultIconPB(),
        content: '',
        displayName: '',
      ),
    ]);
    await tester.pump();
    expect(title.results.single.id, wanted.id);
    expect(title.results.single.displayName, wanted.name);
    expect(reads.calls, ['view:last', 'preflight:last']);
    title
        .search('exttl', const CommandPaletteFilter(titleOnly: true), const []);
    await tester.pump();
    expect(title.results.single.id, wanted.id);
    expect(
      reads.calls,
      hasLength(2),
      reason: 'No repeated I/O on typing/paint',
    );
    title.dispose();
    reads.dispose();
    await tester.pump();
  });

  testWidgets(
      'late metadata generations with reused IDs cannot replace current results',
      (tester) async {
    final first = Completer<FlowyResult<SearchResponseStream, FlowyError>>();
    final oldStream = _MetadataStream();
    final currentStream = _MetadataStream();
    final bloc = CommandPaletteBloc(
      search: (query) async => query == 'first'
          ? await first.future
          : FlowyResult.success(currentStream),
      readCachedViews: () async => const [],
      listenToTrash: false,
    );
    bloc.add(const CommandPaletteEvent.searchChanged(search: 'first'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    bloc.add(const CommandPaletteEvent.searchChanged(search: 'second'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    currentStream
        .server([SearchResponseItemPB(id: 'current', displayName: '')]);
    await tester.pump();
    first.complete(FlowyResult.success(oldStream));
    await tester.pump();
    oldStream
        .server([SearchResponseItemPB(id: 'old', displayName: 'Old title')]);
    await tester.pump();
    expect(bloc.state.query, 'second');
    expect(bloc.state.combinedResponseItems.keys, ['current']);
    bloc.setContentSearchEnabled(true);
    currentStream
        .server([SearchResponseItemPB(id: 'leaked', displayName: 'stale')]);
    await tester.pump();
    expect(bloc.state.combinedResponseItems.keys, ['current']);
    var closed = false;
    unawaited(bloc.close().then((_) => closed = true));
    for (var i = 0; i < 10 && !closed; i++) {
      await tester.runAsync(() async {});
      await tester.pump();
    }
    expect(closed, isTrue);
  });

  testWidgets(
      'title result Enter opens the native view ID, not the display title',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('native-view-id', '', name: 'Open this title');
    final navigation = _NavigationRecorder();
    getIt.registerSingleton<ActionNavigationBloc>(navigation);
    addTearDown(() => getIt.unregister<ActionNavigationBloc>());
    final harness = _ModalHarness(reads);
    await harness.mount(tester, routed: true);
    await tester.enterText(find.byType(EditableText), 'open this title');
    await tester.pump();
    await tester.pump();
    expect(find.byType(SearchResultCell), findsOneWidget);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.enter,
      physicalKey: PhysicalKeyboardKey.enter,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteModal), findsNothing);
    expect(navigation.ids, ['native-view-id']);
    expect(reads.calls.where((call) => call.startsWith('document:')), isEmpty);
    await harness.dispose(tester);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final accessibility in ['normal', 'disabled', 'accessible']) {
      testWidgets(
          '$mode/$accessibility real Ctrl+P route keeps focus, scrim and idempotent show',
          (tester) async {
        final reads = WorkspaceSearchReads()
          ..page('cached', '', name: 'Needle plan');
        final stream = _MetadataStream();
        final pending =
            Completer<FlowyResult<SearchResponseStream, FlowyError>>();
        final palette = CommandPaletteBloc(
          search: (query) => query == 'needle'
              ? pending.future
              : Future.value(
                  FlowyResult.success(
                    _MetadataStream(completeOnListen: true),
                  ),
                ),
          readCachedViews: () async => reads.views.values.toList(),
          listenToTrash: false,
        );
        palette
            .add(const CommandPaletteEvent.searchChanged(search: '> sidebar'));
        await tester.pump();
        final workspace = _WorkspaceBloc(
          UserWorkspaceState(
            userProfile: UserProfilePB(id: Int64(7)),
            currentWorkspace:
                UserWorkspacePB(workspaceId: 'workspace', name: 'Fixture'),
          ),
        );
        final notifier = ValueNotifier(
          CommandPaletteNotifierValue(userWorkspaceBloc: workspace),
        );
        final hostFocus = FocusNode();
        late CommandPalette host;
        host = CommandPalette(
          notifier: notifier,
          readProvider: reads.provider(),
          child: Focus(
            autofocus: true,
            focusNode: hostFocus,
            child: const SizedBox(
              key: ValueKey('palette-background'),
              width: 200,
              height: 100,
            ),
          ),
        );
        await _mountSurface(
          tester,
          BlocProvider<CommandPaletteBloc>.value(value: palette, child: host),
          mode: mode,
          disableAnimations: accessibility == 'disabled',
          accessibleNavigation: accessibility == 'accessible',
        );
        final background =
            tester.getRect(find.byKey(const ValueKey('palette-background')));
        await _controlP(tester);
        await tester.pumpAndSettle();
        final modal = find.byType(CommandPaletteModal);
        expect(modal, findsOneWidget);
        final route = ModalRoute.of(tester.element(modal))!;
        expect(route, isA<DialogRoute<void>>());
        expect(route, isA<FloatingModalBarrier<void>>());
        expect(
          route.barrierColor,
          FloatingModal.barrierColor(
            tester.element(find.byKey(const ValueKey('palette-background'))),
          ),
        );
        expect(
          tester
              .widget<BackdropFilter>(
                find.ancestor(
                  of: find.byType(ModalBarrier),
                  matching: find.byType(BackdropFilter),
                ),
              )
              .filter,
          ImageFilter.blur(
            sigmaX: FloatingModal.blur,
            sigmaY: FloatingModal.blur,
          ),
        );
        final animated = accessibility == 'normal';
        expect(
          route.transitionDuration,
          animated ? FloatingModal.enterDuration : Duration.zero,
        );
        expect(
          route.reverseTransitionDuration,
          animated ? FloatingModal.exitDuration : Duration.zero,
        );
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.focusNode.hasFocus, isTrue);
        await tester.enterText(find.byType(EditableText), 'needle');
        await tester.pump();
        await tester.pump();
        expect(find.byType(SearchResultCell), findsOneWidget);
        host.show();
        host.show();
        await tester.pump();
        expect(ModalRoute.of(tester.element(modal)), same(route));
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).focusNode,
          same(field.focusNode),
        );
        expect(_draft(tester), 'needle');
        expect(
          tester.getRect(find.byKey(const ValueKey('palette-background'))),
          background,
        );
        await tester.pump(const Duration(milliseconds: 300));
        pending.complete(FlowyResult.success(stream));
        await tester.pump();
        stream.server([
          SearchResponseItemPB(
            id: 'cached',
            displayName: '',
            workspaceId: 'workspace',
          ),
        ]);
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<SearchResultCell>(find.byType(SearchResultCell))
              .item
              .displayName,
          'Needle plan',
        );
        await tester.enterText(find.byType(EditableText), 'absent');
        // Even a callback arriving before the queued input event is handled
        // must not republish the previous generation.
        stream
            .server([SearchResponseItemPB(id: 'cached', displayName: 'stale')]);
        await tester.pump();
        expect(palette.state.combinedResponseItems, isEmpty);
        expect(find.byType(SearchResultCell), findsNothing);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        expect(modal, findsNothing);
        expect(notifier.value.isOpen, isFalse);
        expect(hostFocus.hasFocus, isTrue);
        await _controlP(tester);
        await tester.pumpAndSettle();
        expect(modal, findsOneWidget);
        await _controlP(tester);
        await tester.pumpAndSettle();
        expect(modal, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        var closed = false;
        unawaited(palette.close().then((_) => closed = true));
        for (var i = 0; i < 10 && !closed; i++) {
          await tester.runAsync(() async {});
          await tester.pump();
        }
        expect(closed, isTrue);
        var workspaceClosed = false;
        unawaited(workspace.close().then((_) => workspaceClosed = true));
        for (var i = 0; i < 10 && !workspaceClosed; i++) {
          await tester.pump();
        }
        expect(workspaceClosed, isTrue);
        notifier.dispose();
        hostFocus.dispose();
        reads.dispose();
        await tester.pump();
      });
    }
  }
}

Future<void> _controlP(WidgetTester tester) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.sendKeyEvent(
    LogicalKeyboardKey.keyP,
    physicalKey: PhysicalKeyboardKey.keyP,
  );
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
}

class _MetadataStream implements SearchResponseStream {
  _MetadataStream({this.completeOnListen = false});
  final bool completeOnListen;
  void Function(List<SearchResponseItemPB>, String, bool, bool)? _server;
  @override
  String get searchId => 'same-millisecond-id';
  void server(List<SearchResponseItemPB> items) =>
      _server?.call(items, searchId, false, false);
  @override
  Future<void> dispose() async {}
  @override
  void listen({
    required void Function(List<SearchResponseItemPB>, String, bool, bool)?
        onServerItems,
    required void Function(List<SearchSummaryPB>, String, bool, bool)?
        onSummaries,
    required void Function(List<LocalSearchResponseItemPB>, String)?
        onLocalItems,
    required void Function(String)? onFinished,
  }) {
    _server = onServerItems;
    if (completeOnListen) onFinished?.call(searchId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NavigationRecorder implements ActionNavigationBloc {
  final ids = <String>[];
  @override
  void add(ActionNavigationEvent event) => event.when(
        performAction: (action, _, __) => ids.add(action.objectId),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _oldQuery = 'zz_previous_metadata_query';

class _ModalHarness {
  _ModalHarness(this.reads) {
    provider = reads.provider();
    palette = _PaletteBloc(
      CommandPaletteState.initial()
          .copyWith(query: _oldQuery, cachedViews: Map.of(reads.views)),
    );
    workspace = _WorkspaceBloc(
      UserWorkspaceState(
        userProfile: UserProfilePB(id: Int64(7)),
        currentWorkspace:
            UserWorkspacePB(workspaceId: 'workspace', name: 'Search fixture'),
      ),
    );
  }

  final WorkspaceSearchReads reads;
  late final DocumentFindReadProvider provider;
  late final _PaletteBloc palette;
  late final _WorkspaceBloc workspace;

  Widget modal() => MultiBlocProvider(
        providers: [
          BlocProvider<CommandPaletteBloc>.value(value: palette),
          BlocProvider<UserWorkspaceBloc>.value(value: workspace),
        ],
        child: CommandPaletteModal(
          shortcutBuilder: (child) => child,
          contentReadProvider: provider,
        ),
      );

  Future<void> mount(WidgetTester tester, {bool routed = false}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountSurface(
      tester,
      routed
          ? Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  final theme = AppFlowyTheme.of(context);
                  unawaited(
                    showDialog<void>(
                      context: context,
                      builder: (_) =>
                          AppFlowyTheme(data: theme, child: modal()),
                    ),
                  );
                },
                child: const Text('Open search fixture'),
              ),
            )
          : modal(),
    );
    if (routed) {
      await tester.tap(find.text('Open search fixture'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> dispose(WidgetTester tester) =>
      _unmount(tester, palette: palette, workspace: workspace, reads: reads);
}

class _PaletteBloc extends Cubit<CommandPaletteState>
    implements CommandPaletteBloc {
  _PaletteBloc(super.initialState);
  final events = <CommandPaletteEvent>[];
  bool contentMode = false;

  @override
  void add(CommandPaletteEvent event) => events.add(event);

  @override
  void setContentSearchEnabled(bool enabled) => contentMode = enabled;

  @override
  Future<List<ViewPB>?> reloadCachedViews() async =>
      state.cachedViews.values.toList();

  void publish(CommandPaletteState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc(super.initialState);

  void publish(UserWorkspaceState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mountSurface(
  WidgetTester tester,
  Widget child, {
  String mode = 'light',
  double textScale = 1,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance().getThemeData(
    mode == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    brightness,
    'Ahem',
    'Ahem',
  );
  await tester.pumpWidget(
    WidgetTestApp(
      child: Theme(
        data: theme,
        child: AppFlowyTheme(
          data: brightness == Brightness.dark
              ? AppFlowyDefaultTheme().dark()
              : AppFlowyDefaultTheme().light(),
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: disableAnimations,
                accessibleNavigation: accessibleNavigation,
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enableContents(WidgetTester tester) async {
  await tester
      .tap(find.byKey(const ValueKey('command-palette-content-filter')));
  await tester.pump();
  expect(
    tester
        .widget<SearchFilterBar>(find.byType(SearchFilterBar))
        .filter
        .pageContents,
    isTrue,
  );
}

String _draft(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

Future<void> _results(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(find.byType(SearchResultCell), findsWidgets);
}

Iterable<TextSpan> _highlightedSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.style?.backgroundColor != null) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _highlightedSpans(child);
  }
}

List<String?> _highlightedText(InlineSpan span) =>
    _highlightedSpans(span).map((span) => span.text).toList();

Future<void> _unmount(
  WidgetTester tester, {
  _PaletteBloc? palette,
  _WorkspaceBloc? workspace,
  WorkspaceSearchReads? reads,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  reads?.dispose();
  var paletteClosed = palette == null;
  var workspaceClosed = workspace == null;
  if (palette != null) {
    unawaited(palette.close().then((_) => paletteClosed = true));
  }
  if (workspace != null) {
    unawaited(workspace.close().then((_) => workspaceClosed = true));
  }
  for (var i = 0; i < 10 && (!paletteClosed || !workspaceClosed); i++) {
    await tester.pump();
  }
  expect(paletteClosed && workspaceClosed, isTrue);
  await tester.pump();
}
