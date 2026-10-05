import 'dart:async';
import 'dart:convert';

import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_card.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_embeds.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_view_resolver.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_add_menu.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_host.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/page_block_widget.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/dashboard_widget/dashboard_widget_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/plugins/document/presentation/embedded_blocks/embedded_blocks_view.dart';
import 'package:appflowy/plugins/document/presentation/embedded_blocks/page_block_catalog.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide QuoteBlockKeys;
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// Pages, dashboards and canvases offer one set of things to place.
///
/// These tests read the registries rather than a fixed list, so a widget or a
/// `/` entry added later is held to the same contract: a widget reaches `/`
/// and canvases, and a `/` block reaches dashboards and canvases.
const _appearances = ['light', 'dark', 'paper'];
const _lateWidget = 'parity_late_widget';
const _lateBlock = 'parity_late_block';
const _extension = 'parity-test';

// The app provides these above every page, dashboard and canvas.
late AppearanceSettingsCubit _appearanceCubit;
late DocumentAppearanceCubit _documentAppearanceCubit;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(DartKeyValue());
    _appearanceCubit = AppearanceSettingsCubit(
      AppearanceSettingsPB(
        locale: LocaleSettingsPB(languageCode: 'en', countryCode: 'US'),
      ),
      DateTimeSettingsPB(),
      AppTheme.fallback,
    );
    _documentAppearanceCubit = DocumentAppearanceCubit();
  });

  tearDownAll(() async {
    await _appearanceCubit.close();
    await _documentAppearanceCubit.close();
    await getIt.popScope();
  });

  group('widgets reach pages', () {
    testWidgets(
        'every offered widget is a page block already, or hosted by a / entry',
        (tester) async {
      final builders = await _pageBlockBuilders(tester);
      final widgetEntries = _slashSection(SlashMenuSection.widgets);
      expect(widgetEntries, isNotEmpty);

      var hosted = 0;
      for (final definition in DashboardWidgetRegistry.offered()) {
        final twin = definition.pageBlock;
        final entry = widgetEntries[definition.label()];
        if (twin != null) {
          expect(
            builders.containsKey(twin),
            isTrue,
            reason: '${definition.type} says pages already have "$twin"',
          );
          expect(entry, isNull, reason: '${definition.type} is offered once');
          continue;
        }
        expect(entry, isNotNull, reason: '${definition.type} must be in /');
        final document = await _insert(tester, entry!);
        final node = _onlyBlock(document);
        expect(node.type, DashboardWidgetBlockKeys.type);
        final spec = DashboardWidgetSpec.fromJson(
          Map<String, Object?>.from(
            node.attributes[DashboardWidgetBlockKeys.spec] as Map,
          ),
        );
        expect(spec.type, definition.type);
        hosted++;
      }
      // The audit's own result: what pages could not hold before now can.
      for (final type in const [
        'metric',
        'clock',
        'countdown',
        'weather',
        'calendar',
        'reminders',
        'toggle',
        'list',
        'page_link',
        'spacer',
      ]) {
        expect(
          widgetEntries.containsKey(
            DashboardWidgetRegistry.definitionFor(type)!.label(),
          ),
          isTrue,
          reason: type,
        );
      }
      expect(hosted, greaterThanOrEqualTo(10));
      expect(builders.containsKey(DashboardWidgetBlockKeys.type), isTrue);
    });

    testWidgets('a widget registered later is offered in / and on canvases',
        (tester) async {
      await _mount(tester, 'light', const SizedBox.shrink());
      DashboardWidgetRegistry.register(
        DashboardWidgetDefinition(
          type: _lateWidget,
          extensionId: _extension,
          label: () => 'Parity late widget',
          icon: Icons.star_rounded,
          group: DashboardWidgetGroup.info,
          builder: (_) => const Text('late widget body'),
        ),
      );
      try {
        expect(
          _slashSection(SlashMenuSection.widgets)
              .containsKey('Parity late widget'),
          isTrue,
        );
        expect(
          DashboardWidgetRegistry.search('parity late').map((d) => d.type),
          contains(_lateWidget),
        );
        final icons = EditorState.blank();
        addTearDown(icons.dispose);
        final entries = canvasWidgetAndBlockEntries(
          iconEditor: icons,
          ink: Colors.black,
          onWidget: (_) {},
          onBlock: (_) {},
        );
        expect(_menuLabels(entries), contains('Parity late widget'));
      } finally {
        DashboardWidgetRegistry.unregisterAll(_extension);
      }
      expect(
        _slashSection(SlashMenuSection.widgets)
            .containsKey('Parity late widget'),
        isFalse,
      );
    });

    testWidgets('a widget in a page keeps its changes in the page and undoes',
        (tester) async {
      final spec = DashboardWidgetRegistry.definitionFor('counter')!.create();
      final editorState = EditorState(
        document: Document(
          root: pageNode(children: [dashboardWidgetNode(spec)]),
        ),
      );
      addTearDown(editorState.dispose);
      await _mount(
        tester,
        'paper',
        _PageEditor(editorState: editorState),
        height: 640,
      );
      expect(find.byType(DashboardWidgetHost), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      await tester.tap(_inHost(_glyph(Icons.add_rounded)));
      await tester.pumpAndSettle();
      Map<Object?, Object?> stored() => editorState.document.root.children
          .single.attributes[DashboardWidgetBlockKeys.spec] as Map;
      expect((stored()['settings']! as Map)['value'], 1);
      expect(find.text('1'), findsOneWidget);

      // The page's own history carries the widget's change.
      editorState.undoManager.undo();
      await tester.pumpAndSettle();
      expect(
        stored()['settings'],
        anyOf(isNull, isNot(containsPair('value', 1))),
      );
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('page blocks reach dashboards and canvases', () {
    testWidgets('every / block is offered, once, unless a widget already is it',
        (tester) async {
      await _mount(tester, 'light', const SizedBox.shrink());
      final twins = {
        for (final definition in DashboardWidgetRegistry.offered())
          if (definition.pageBlock != null) definition.pageBlock!,
      };
      final catalog = pageBlockCatalog();
      expect(catalog, isNotEmpty);
      // Entries are rebuilt on every read, so they are known by section and
      // name — the key the catalog itself offers each one once under.
      String keyOf(SlashMenuSection section, String name) =>
          '${section.name}/$name';
      final catalogKeys = <String>{};
      for (final entry in catalog) {
        expect(
          catalogKeys.add(keyOf(entry.section, entry.name)),
          isTrue,
          reason: '"${entry.name}" is offered once',
        );
      }
      for (final item in slashMenuItemsBuilder()) {
        final metadata = slashMenuMetadataFor(item)!;
        final offered =
            catalogKeys.contains(keyOf(metadata.section, item.name));
        if (metadata.pageOnly || metadata.section == SlashMenuSection.widgets) {
          expect(offered, isFalse, reason: item.name);
          continue;
        }
        expect(
          offered || twins.contains(metadata.blockType),
          isTrue,
          reason: '"${item.name}" must reach dashboards and canvases',
        );
        expect(
          offered && twins.contains(metadata.blockType),
          isFalse,
          reason: '"${item.name}" is offered once',
        );
      }
      // The blocks a dashboard could not show before.
      final names = {for (final entry in catalog) entry.name.toLowerCase()};
      for (final expected in const [
        'mermaid',
        'mind map',
        'math',
        'code',
        'map',
        'excalidraw',
      ]) {
        expect(
          names.any((name) => name.contains(expected)),
          isTrue,
          reason: expected,
        );
      }
      final icons = EditorState.blank();
      addTearDown(icons.dispose);
      final fromPages = canvasWidgetAndBlockEntries(
        iconEditor: icons,
        ink: Colors.black,
        onWidget: (_) {},
        onBlock: (_) {},
      ).whereType<AppMenuItem>().last;
      expect(fromPages.submenu, hasLength(catalog.length));
    });

    testWidgets('a block registered later is offered and carried by value',
        (tester) async {
      await _mount(tester, 'light', const SizedBox.shrink());
      ExtensionBlockRegistry.register(
        ExtensionBlockDefinition(
          extensionId: _extension,
          type: _lateBlock,
          builder: (configuration) =>
              DividerBlockComponentBuilder(configuration: configuration),
          slashName: 'Parity late block',
          newNode: () => Node(type: _lateBlock),
        ),
      );
      addTearDown(() => ExtensionBlockRegistry.unregister(_lateBlock));

      final entry = pageBlockCatalog()
          .singleWhere((entry) => entry.name == 'Parity late block');
      final context = tester.element(find.byType(Scaffold));
      final run = await runPageBlockEntry(entry, context);
      expect(run.asked, isFalse);
      expect(run.dismissed, isFalse);
      expect(run.document, isNotNull);
      expect(_onlyBlock(run.document!).type, _lateBlock);

      // On a dashboard: the page-block widget, carrying the block.
      final (:definition, :dismissed) =
          await dashboardDefinitionForPageBlock(entry, context);
      expect(dismissed, isFalse);
      expect(definition, isNotNull);
      final spec = definition!.create();
      expect(spec.type, dashboardPageBlockType);
      expect(spec.title, 'Parity late block');
      expect(
        _onlyBlock(
          Map<String, Object?>.from(
            spec.settings[dashboardPageBlockDocumentKey]! as Map,
          ),
        ).type,
        _lateBlock,
      );

      // On a canvas: a block card holding the same.
      final card = canvasCardFor(definition);
      expect(card.kind, CanvasNodeKind.block);
      expect(card.needsSetUp, isFalse);
      final roundTrip = _persisted(card);
      expect(roundTrip.kind, CanvasNodeKind.block);
      expect(
        _onlyBlock(
          Map<String, Object?>.from(
            roundTrip.data[canvasBlockDocumentKey]! as Map,
          ),
        ).type,
        _lateBlock,
      );
    });

    testWidgets('an entry whose question is dismissed has not failed',
        (tester) async {
      await _mount(tester, 'light', const SizedBox.shrink());
      final item = SelectionMenuItem(
        getName: () => 'Parity asking block',
        icon: (_, __, ___) => const SizedBox.shrink(),
        keywords: const ['parity'],
        handler: (_, __, context) => unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('parity question')),
          ),
        ),
      );
      PageBlockRun? run;
      unawaited(
        runPageBlockEntry(
          PageBlockEntry(
            item: item,
            metadata: const SlashMenuItemMetadata(
              section: SlashMenuSection.advanced,
            ),
          ),
          tester.element(find.byType(Scaffold)),
          grace: Duration.zero,
        ).then((value) => run = value),
      );
      await tester.pumpAndSettle();
      expect(find.text('parity question'), findsOneWidget);
      expect(run, isNull, reason: 'it waits while it is asking');

      Navigator.of(tester.element(find.text('parity question'))).pop();
      for (var tick = 0; tick < 10 && run == null; tick++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(run, isNotNull);
      expect(run!.document, isNull);
      expect(run!.asked, isTrue);
      expect(run!.dismissed, isTrue);
    });

    testWidgets('blocks on a dashboard are edited in place and kept by value',
        (tester) async {
      final changes = <Map<String, Object?>>[];
      final initial = Document(
        root: pageNode(children: [paragraphNode(text: 'hello')]),
      ).toJson();
      await _mount(
        tester,
        'dark',
        EmbeddedBlocksView(
          document: Map<String, Object?>.from(initial),
          onChanged: changes.add,
        ),
      );
      final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
      final transaction = editor.editorState.transaction
        ..insertText(
          editor.editorState.document.root.children.first,
          5,
          ' world',
        );
      await editor.editorState.apply(transaction);
      await tester.pump(const Duration(milliseconds: 300));
      expect(changes, hasLength(1));
      final saved = Document.fromJson(Map<String, dynamic>.from(changes.last));
      expect(
        saved.root.children.first.delta!.toPlainText(),
        'hello world',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'an equal copy handed back by the host keeps the editor and what was '
        'typed since', (tester) async {
      final changes = <Map<String, Object?>>[];
      Map<String, Object?> document = Document(
        root: pageNode(children: [paragraphNode(text: 'hello')]),
      ).toJson();
      late StateSetter rebuild;
      await _mount(
        tester,
        'light',
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return EmbeddedBlocksView(
              document: document,
              onChanged: changes.add,
            );
          },
        ),
      );
      EditorState editing() => tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .editorState;
      final editorState = editing();
      Node first() => editorState.document.root.children.first;

      await editorState.apply(
        editorState.transaction..insertText(first(), 5, ' world'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(changes, hasLength(1));

      // Typed after that save and not handed out yet.
      await editorState
          .apply(editorState.transaction..insertText(first(), 11, '!'));
      // The host saved and read its copy back: equal, but not the same map.
      rebuild(
        () => document =
            jsonDecode(jsonEncode(changes.last)) as Map<String, Object?>,
      );
      await tester.pump();
      expect(editing(), same(editorState));
      expect(first().delta!.toPlainText(), 'hello world!');

      // A document really changed elsewhere replaces what is shown.
      rebuild(
        () => document = Document(
          root: pageNode(children: [paragraphNode(text: 'from elsewhere')]),
        ).toJson(),
      );
      await tester.pump();
      expect(editing(), isNot(same(editorState)));
      expect(
        editing().document.root.children.first.delta!.toPlainText(),
        'from elsewhere',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('canvases hold widgets and blocks', () {
    test('widget and block cards round trip and know when they are empty', () {
      final spec = DashboardWidgetRegistry.definitionFor('counter')!.create();
      final card = canvasCardFor(
        DashboardWidgetRegistry.definitionFor('counter')!,
      );
      expect(card.kind, CanvasNodeKind.widget);
      expect(card.needsSetUp, isFalse);
      expect(
        (card.data[canvasWidgetSpecKey]! as Map)['type'],
        spec.type,
      );
      final decoded = _persisted(card);
      expect(decoded.kind, CanvasNodeKind.widget);
      expect(decoded.data[canvasWidgetSpecKey], isA<Map>());

      final empty = CanvasNode.create(
        kind: CanvasNodeKind.widget,
        position: Offset.zero,
      );
      expect(empty.needsSetUp, isTrue);
      expect(
        CanvasNode.create(kind: CanvasNodeKind.block, position: Offset.zero)
            .needsSetUp,
        isTrue,
      );
      expect(CanvasNodeKind.widget.isInteractive, isTrue);
      expect(CanvasNodeKind.block.isInteractive, isTrue);
      expect(CanvasNodeKind.widget.referencesWorkspaceObject, isFalse);
    });

    for (final appearance in _appearances) {
      testWidgets('$appearance: a widget card is used in place, vividly',
          (tester) async {
        WorkspaceGlyphs.clearUnknownMappings();
        final resolver = CanvasViewResolver();
        addTearDown(resolver.dispose);
        final definition = DashboardWidgetRegistry.definitionFor('counter')!;
        var node = canvasCardFor(definition).copyWith(
          size: const Size(360, 240),
        );
        Widget card({required bool editing}) => Builder(
              builder: (context) => CanvasCard(
                node: node,
                palette: canvasPaletteOf(context),
                resolver: resolver,
                zoom: 1,
                selected: true,
                editing: editing,
                editable: true,
                onTap: (_) {},
                onDoubleTap: () {},
                onContextMenu: (_) {},
                onDragStart: () {},
                onDragUpdate: (_, __) {},
                onDragEnd: () {},
                onResizeStart: (_) {},
                onResizeUpdate: (_, __) {},
                onResizeEnd: () {},
                onConnectStart: (_) {},
                onConnectUpdate: (_) {},
                onConnectEnd: (_) {},
                onTextChanged: (_) {},
                onEditingFinished: () {},
                onOpen: () {},
                onSetUp: () {},
                onEdit: () {},
                onDataChanged: (key, value) => node = node.withData(key, value),
              ),
            );

        await _mount(
          tester,
          appearance,
          SizedBox(width: 360, height: 240, child: card(editing: false)),
        );
        expect(find.byType(DashboardWidgetHost), findsOneWidget);
        // At rest the card can be carried: the widget does not take clicks,
        // and the card offers to hand it the pointer.
        expect(
          _glyph(Icons.touch_app_rounded),
          findsOneWidget,
          reason: 'The "Use" action is drawn with the shared glyphs.',
        );
        await tester.tap(
          _inHost(_glyph(Icons.add_rounded)),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(
          (node.data[canvasWidgetSpecKey]! as Map)['settings'],
          isNull,
        );

        await _mount(
          tester,
          appearance,
          SizedBox(width: 360, height: 240, child: card(editing: true)),
        );
        await tester.tap(_inHost(_glyph(Icons.add_rounded)));
        await tester.pumpAndSettle();
        expect(
          ((node.data[canvasWidgetSpecKey]! as Map)['settings']!
              as Map)['value'],
          1,
        );
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('a hosted widget is configured from a side sheet',
      (tester) async {
    final spec = DashboardWidgetRegistry.definitionFor('counter')!.create();
    final changes = <DashboardWidgetSpec>[];
    await _mount(
      tester,
      'light',
      DashboardWidgetHost(spec: spec, onChanged: changes.add),
    );
    final panel = find.byKey(
      ValueKey('dashboard-widget-host-panel-${spec.id}'),
    );
    expect(panel, findsNothing);
    // The settings button is revealed under the pointer, as on a dashboard.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(2, 2));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(DashboardWidgetHost)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('dashboard-widget-host-settings-${spec.id}')),
        matching: _glyph(Icons.tune_rounded),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    // Hosted widgets leave size, visibility and removal to their host.
    expect(find.text(LocaleKeys.dashboard_config_size.tr()), findsNothing);
    expect(find.text(LocaleKeys.button_delete.tr()), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard Add panel offers blocks from pages',
      (tester) async {
    DashboardWidgetDefinition? chosen;
    await _mount(
      tester,
      'light',
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => chosen = await showDashboardWidgetPicker(
            context: context,
            palette: DashboardPalette.of(context),
          ),
          child: const Text('open add'),
        ),
      ),
    );
    await tester.tap(find.text('open add'));
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('dashboard-add-group-blocks'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final code = pageBlockCatalog().firstWhere(
      (entry) => entry.name.toLowerCase().contains('code'),
    );
    final tile = find.byKey(ValueKey('dashboard-add-block-${code.name}'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(chosen, isNotNull);
    final spec = chosen!.create();
    expect(spec.type, dashboardPageBlockType);
    expect(spec.settings[dashboardPageBlockDocumentKey], isA<Map>());

    // And it draws, on a dashboard, as the page's own block.
    final controller = DashboardController(
      viewId: '',
      document: DashboardDocument.blank().addWidget(spec),
    );
    addTearDown(controller.dispose);
    await _mount(
      tester,
      'paper',
      Builder(
        builder: (context) => DashboardCard(
          controller: controller,
          spec: spec,
          palette: DashboardPalette.of(context),
          selected: false,
          dragging: false,
        ),
      ),
    );
    expect(find.byType(EmbeddedBlocksView), findsOneWidget);
    expect(find.byType(AppFlowyEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// ---------------------------------------------------------------- helpers

/// `/` entries in [section], by name.
Map<String, SelectionMenuItem> _slashSection(SlashMenuSection section) => {
      for (final item in slashMenuItemsBuilder())
        if (slashMenuMetadataFor(item)?.section == section) item.name: item,
    };

Future<Map<String, BlockComponentBuilder>> _pageBlockBuilders(
  WidgetTester tester,
) async {
  late Map<String, BlockComponentBuilder> builders;
  final editorState = EditorState.blank();
  addTearDown(editorState.dispose);
  await _mount(
    tester,
    'light',
    Builder(
      builder: (context) {
        builders = buildBlockComponentBuilders(
          context: context,
          editorState: editorState,
          styleCustomizer: EditorStyleCustomizer(
            context: context,
            padding: EdgeInsets.zero,
            width: 720,
            editorState: editorState,
          ),
          editable: false,
        );
        return const SizedBox.shrink();
      },
    ),
  );
  return builders;
}

/// Runs a `/` entry the way a dashboard or a canvas does.
Future<Map<String, Object?>> _insert(
  WidgetTester tester,
  SelectionMenuItem item,
) async {
  final context = tester.element(find.byType(Scaffold));
  final run = await runPageBlockEntry(
    PageBlockEntry(item: item, metadata: slashMenuMetadataFor(item)!),
    context,
  );
  expect(run.document, isNotNull, reason: item.name);
  return run.document!;
}

Node _onlyBlock(Map<String, Object?> json) {
  final document = Document.fromJson(Map<String, dynamic>.from(json));
  return document.root.children.single;
}

/// [card] as a canvas file stores and reopens it.
CanvasNode _persisted(CanvasNode card) {
  final decoded = CanvasNode.fromJson(
    Map<String, Object?>.from(jsonDecode(jsonEncode(card.toJson())) as Map),
  );
  expect(decoded, isNotNull);
  return decoded!;
}

Iterable<String> _menuLabels(List<AppMenuEntry> entries) sync* {
  for (final entry in entries) {
    if (entry is AppMenuItem) {
      yield entry.label;
      yield* _menuLabels(entry.submenu);
    }
  }
}

Finder _glyph(IconData icon) => find.byWidgetPredicate(
      (widget) => widget is WorkspaceGlyph && widget.icon == icon,
    );

Finder _inHost(Finder finder) => find.descendant(
      of: find.byType(DashboardWidgetHost),
      matching: finder,
    );

/// A page holding [editorState], drawn by the page's own block builders.
class _PageEditor extends StatelessWidget {
  const _PageEditor({required this.editorState});

  final EditorState editorState;

  @override
  Widget build(BuildContext context) {
    final styleCustomizer = EditorStyleCustomizer(
      context: context,
      padding: EdgeInsets.zero,
      width: 720,
      editorState: editorState,
    );
    return AppFlowyEditor(
      editorState: editorState,
      editorStyle: styleCustomizer.style(),
      blockComponentBuilders: buildBlockComponentBuilders(
        context: context,
        editorState: editorState,
        styleCustomizer: styleCustomizer,
        editable: false,
      ),
      disableAutoScroll: true,
    );
  }
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      '',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget child, {
  double width = 760,
  double height = 520,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  final theme = _theme(appearance);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AppearanceSettingsCubit>.value(value: _appearanceCubit),
        BlocProvider<DocumentAppearanceCubit>.value(
          value: _documentAppearanceCubit,
        ),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        saveLocale: false,
        assetLoader: const TestBundleAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            theme: theme,
            themeAnimationDuration: Duration.zero,
            builder: (context, navigator) => AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: appearance == 'dark'
                    ? AppFlowyDefaultTheme().dark()
                    : AppFlowyDefaultTheme().light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: TooltipVisibility(visible: false, child: navigator!),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
