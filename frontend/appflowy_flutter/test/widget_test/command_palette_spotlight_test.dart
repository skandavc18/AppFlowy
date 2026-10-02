import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/spell_check/spell_check_settings.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/palette_ai.dart';
import 'package:appflowy/workspace/application/command_palette/palette_scope.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_ai_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_option_picker.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_scope_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_setting_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit_test/search/workspace_content_search_test_support.dart';
import 'workspace_overlay_test_app.dart';

const _appearances = ['light', 'dark', 'paper'];

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  setUp(() {
    SpellCheckSettings.instance.seedForTest();
    WorkspaceGlyphs.clearUnknownMappings();
    // Shadow registrations only for this test; no app services are started.
    getIt.pushNewScope();
    getIt.registerSingleton<CachedRecentService>(_RecentCache());
    getIt.registerSingleton<ViewAncestorCache>(_EmptyAncestorCache());
    getIt.registerSingleton<MenuSharedState>(MenuSharedState());
  });

  tearDown(() async {
    await getIt.popScope();
    SpellCheckSettings.instance.seedForTest();
  });

  group('a setting changed in its row', () {
    for (final appearance in _appearances) {
      testWidgets('$appearance: a switch flips by pointer and by keyboard',
          (tester) async {
        var value = false;
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            child: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 640,
                child: PaletteSettingsList(
                  settings: [
                    PaletteSetting(
                      id: 'spell',
                      title: 'Check spelling',
                      description: 'Underline misspelled words',
                      section: PaletteSettingSection.editor,
                      icon: Icons.spellcheck_rounded,
                      control: PaletteToggle(
                        value: value,
                        onChanged: (next) => setState(() => value = next),
                      ),
                    ),
                  ],
                  onOpenPicker: (_) {},
                  onOpenSettings: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Check spelling'));
        await tester.pumpAndSettle();
        expect(value, isTrue);

        // The thumb of a switch that is on sits on the theme's own floating
        // surface: warm in paper mode, never a stark white.
        final context = tester.element(find.byType(PaletteSwitch));
        final thumbs = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(PaletteSwitch),
                matching: find.byType(Container),
              ),
            )
            .map((container) => container.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) => decoration.shape == BoxShape.circle)
            .toList();
        expect(thumbs, hasLength(1));
        expect(
          thumbs.single.color,
          WorkspacePalette.of(context).elevatedSurface,
        );
        if (appearance == 'paper') {
          expect(PaperTheme.isEnabled(context), isTrue);
          expect(thumbs.single.color, isNot(Colors.white));
        }

        final row = find.byKey(const ValueKey('command-palette-setting-spell'));
        final focus = tester
            .widgetList<Focus>(
              find.descendant(of: row, matching: find.byType(Focus)),
            )
            .firstWhere((widget) => widget.focusNode != null)
            .focusNode!;
        expect(focus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(value, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(value, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a short choice sits in the row and steps with the arrows',
        (tester) async {
      var selected = 'light';
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 640,
              child: PaletteSettingsList(
                settings: [
                  PaletteSetting(
                    id: 'mode',
                    title: 'Appearance',
                    section: PaletteSettingSection.appearance,
                    icon: Icons.dark_mode_rounded,
                    control: PaletteChoice(
                      options: const [
                        PaletteSettingOption(id: 'system', label: 'System'),
                        PaletteSettingOption(id: 'light', label: 'Light'),
                        PaletteSettingOption(id: 'dark', label: 'Dark'),
                      ],
                      selectedId: selected,
                      onSelected: (option) =>
                          setState(() => selected = option.id),
                    ),
                  ),
                ],
                onOpenPicker: (_) => fail('A short choice opens no list'),
                onOpenSettings: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('command-palette-option-dark')));
      await tester.pumpAndSettle();
      expect(selected, 'dark');

      // The heading of the section reads "Appearance" too; use the row.
      await tester.tap(
        find.byKey(const ValueKey('command-palette-setting-mode')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(selected, 'light');
      // Enter steps on round the choices, wrapping at the end.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 'dark');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 'system');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long choice opens its own list, which can be searched',
        (tester) async {
      PaletteSetting? opened;
      PaletteSettingOption? picked;
      var back = 0;
      const options = [
        PaletteSettingOption(id: 'en', label: 'English'),
        PaletteSettingOption(id: 'de', label: 'Deutsch', keywords: ['german']),
        PaletteSettingOption(id: 'fr', label: 'Français'),
        PaletteSettingOption(id: 'es', label: 'Español'),
      ];
      final setting = PaletteSetting(
        id: 'language',
        title: 'Language',
        section: PaletteSettingSection.language,
        icon: Icons.translate_rounded,
        control: PaletteChoice(
          options: options,
          selectedId: 'en',
          onSelected: (_) {},
        ),
      );
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: SizedBox(
            width: 640,
            height: 400,
            child: PaletteSettingsList(
              settings: [setting],
              onOpenPicker: (value) => opened = value,
              onOpenSettings: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The row shows what is chosen now, and opens the list when used.
      expect(find.text('English'), findsOneWidget);
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(opened, same(setting));

      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: SizedBox(
            width: 640,
            height: 400,
            child: PaletteOptionPicker(
              setting: setting,
              options: rankPaletteOptions(options, 'germ'),
              selectedId: 'en',
              onPicked: (option) => picked = option,
              onBack: () => back++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('English'), findsNothing);
      await tester.tap(find.text('Deutsch'));
      await tester.pump();
      expect(picked?.id, 'de');
      await tester
          .tap(find.byKey(const ValueKey('command-palette-picker-back')));
      await tester.pump();
      expect(back, 1);
      expect(tester.takeException(), isNull);
    });
  });

  for (final appearance in _appearances) {
    testWidgets('$appearance: the scope tabs say where the palette looks',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chosen = <PaletteScope>[];
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: SizedBox(
            width: 1000,
            child: PaletteScopeBar(
              scope: PaletteScope.all,
              onChanged: chosen.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final scope in PaletteScope.values) {
        expect(
          find.byKey(ValueKey('command-palette-scope-${scope.name}')),
          findsOneWidget,
        );
      }
      await tester.tap(find.text(LocaleKeys.commandPalette_scope_settings.tr()));
      await tester.tap(find.text(LocaleKeys.commandPalette_scope_ai.tr()));
      await tester.pump();
      expect(chosen, [PaletteScope.settings, PaletteScope.ai]);
      expect(WorkspaceGlyphs.unknownMappings, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  group('a conversation in the palette', () {
    for (final appearance in _appearances) {
      testWidgets('$appearance: streams an answer and offers what to do next',
          (tester) async {
        final engine = _ScriptedEngine();
        final conversation = PaletteAIConversation(
          engine: () => engine,
          newConversationId: () => 'conversation',
          notifyInterval: Duration.zero,
        );
        addTearDown(conversation.dispose);
        var setUp = 0;
        final saved = <PaletteAITurn>[];

        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            disableAnimations: true,
            child: SizedBox(
              width: 760,
              height: 560,
              child: PaletteAIPanel(
                conversation: conversation,
                sources: const [],
                modelLabel: 'Scripted model',
                onAsk: (question) => unawaited(conversation.ask(question)),
                onRemoveSource: (_) {},
                onOpenSource: (_) {},
                onSetUp: () => setUp++,
                onPickModel: () {},
                onNewConversation: () => unawaited(conversation.clear()),
                onSaveAsPage: (turn) async => saved.add(turn),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(LocaleKeys.commandPalette_ai_emptyTitle.tr()),
          findsOneWidget,
        );

        final suggestion = LocaleKeys.commandPalette_ai_suggestionPlan.tr();
        await tester.tap(find.text(suggestion));
        await tester.pumpAndSettle();
        expect(engine.requests.single.question, suggestion);
        expect(find.text(LocaleKeys.commandPalette_ai_thinking.tr()),
            findsWidgets);
        expect(find.byKey(const ValueKey('command-palette-ai-stop')),
            findsOneWidget);

        engine.say('Monday: **write the plan**.');
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('write the plan', findRichText: true),
            findsWidgets);
        // Nothing to act on until the answer is complete.
        expect(find.byKey(const ValueKey('command-palette-ai-save')),
            findsNothing);

        engine.finish();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('command-palette-ai-stop')),
            findsNothing);
        await tester.tap(find.byKey(const ValueKey('command-palette-ai-save')));
        await tester.pumpAndSettle();
        expect(saved.single.answer, 'Monday: **write the plan**.');

        // A failure that needs setting up says so, and leads there.
        await conversation.ask('And Tuesday?');
        await tester.pumpAndSettle();
        engine.failNeedingSetup('No model is set up.');
        await tester.pumpAndSettle();
        expect(find.text('No model is set up.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('command-palette-ai-setup')));
        await tester.pump();
        expect(setUp, 1);
        expect(engine.requests.last.history.single.question, suggestion);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the palette itself', () {
    testWidgets('settings are found, changed and left with the keyboard',
        (tester) async {
      final harness = await _Harness.mount(tester);
      expect(find.byType(PaletteScopeBar), findsOneWidget);
      expect(find.byType(SearchFilterBar), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('command-palette-scope-settings')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('command-palette-settings-panel')),
        findsOneWidget,
      );
      // Pages have filters; settings do not.
      expect(find.byType(SearchFilterBar), findsNothing);
      expect(
        find.text(LocaleKeys.commandPalette_hintAdjust.tr()),
        findsOneWidget,
      );
      expect(_fieldFocus(tester).hasFocus, isTrue);

      await tester.enterText(_field, 'spell');
      await tester.pumpAndSettle();
      final spelling =
          find.byKey(const ValueKey('command-palette-setting-spell_check'));
      expect(spelling, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(SpellCheckSettings.instance.spellingEnabled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(SpellCheckSettings.instance.spellingEnabled, isFalse);
      // The row redraws from the setting itself.
      expect(
        tester
            .widget<PaletteSwitch>(
              find.descendant(of: spelling, matching: find.byType(PaletteSwitch)),
            )
            .value,
        isFalse,
      );

      // Out of the scope again with Backspace in an empty box.
      await tester.enterText(_field, '');
      await tester.pumpAndSettle();
      _fieldFocus(tester).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(find.byType(SearchFilterBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('command-palette-settings-panel')),
        findsNothing,
      );
      await harness.unmount(tester);
    });

    testWidgets('a search offers matching settings beside pages',
        (tester) async {
      final harness = await _Harness.mount(tester);
      await tester.enterText(_field, 'spell');
      await tester.pumpAndSettle();
      final spelling =
          find.byKey(const ValueKey('command-palette-setting-spell_check'));
      expect(spelling, findsOneWidget);
      await tester.tap(spelling);
      await tester.pumpAndSettle();
      expect(SpellCheckSettings.instance.spellingEnabled, isFalse);
      await harness.unmount(tester);
    });

    testWidgets('a command shows the name it will be handed', (tester) async {
      final harness = await _Harness.mount(tester);
      await tester.enterText(_field, 'new page Ideas');
      await tester.pumpAndSettle();
      final argument =
          find.byKey(const ValueKey('command-palette-command-argument'));
      expect(argument, findsOneWidget);
      expect(tester.widget<Text>(argument).data, '\u201cIdeas\u201d');
      final row = find.ancestor(
        of: argument,
        matching: find.byType(PaletteCommandCell),
      );
      // It is the one Enter would run.
      expect(tester.widget<PaletteCommandCell>(row).preselected, isTrue);

      await tester.enterText(_field, '> zoom');
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalettePanel), findsOneWidget);
      expect(find.text(LocaleKeys.commandPalette_hintRun.tr()), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('the assistant has its own scope, with its model a tap away',
        (tester) async {
      final harness = await _Harness.mount(tester, appearance: 'paper');
      await tester.tap(find.byKey(const ValueKey('command-palette-scope-ai')));
      await tester.pumpAndSettle();
      expect(find.byType(PaletteAIPanel), findsOneWidget);
      expect(
        find.text(LocaleKeys.commandPalette_ai_emptyTitle.tr()),
        findsOneWidget,
      );
      expect(
        tester.widget<SearchField>(find.byType(SearchField)).hintText,
        LocaleKeys.commandPalette_scopeHint_ai.tr(),
      );

      await tester.enterText(_field, 'which model');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('command-palette-ai-model')));
      await tester.pumpAndSettle();
      expect(find.byType(PaletteOptionPicker), findsOneWidget);
      expect(
        find.byKey(const ValueKey('command-palette-scope-badge')),
        findsOneWidget,
      );
      // The list of choices starts with an empty box of its own…
      expect(_text(tester), isEmpty);
      _fieldFocus(tester).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PaletteOptionPicker), findsNothing);
      expect(find.byType(PaletteAIPanel), findsOneWidget);
      // …and leaving it puts back what was being typed.
      expect(_text(tester), 'which model');
      await harness.unmount(tester);
    });

    testWidgets('choosing a tab takes over from a typed prefix',
        (tester) async {
      final harness = await _Harness.mount(tester, appearance: 'dark');
      await tester.enterText(_field, '> zoom');
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalettePanel), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('command-palette-scope-commands')),
      );
      await tester.pumpAndSettle();
      expect(_text(tester), 'zoom');
      expect(find.byType(CommandPalettePanel), findsOneWidget);
      // In a tab chosen on purpose, a prefix is only a character.
      await tester.enterText(_field, '?zoom');
      await tester.pumpAndSettle();
      expect(find.byType(PaletteAIPanel), findsNothing);
      await harness.unmount(tester);
    });
  });
}

final _field = find.descendant(
  of: find.byType(SearchField),
  matching: find.byType(EditableText),
);

FocusNode _fieldFocus(WidgetTester tester) =>
    tester.widget<EditableText>(_field).focusNode;

String _text(WidgetTester tester) =>
    tester.widget<EditableText>(_field).controller.text;

/// The real palette, with blocs that hold state but reach no backend.
class _Harness {
  _Harness(this.reads, this.palette, this.workspace);

  final WorkspaceSearchReads reads;
  final _PaletteBloc palette;
  final _WorkspaceBloc workspace;

  static Future<_Harness> mount(
    WidgetTester tester, {
    String appearance = 'light',
  }) async {
    tester.view.physicalSize = const Size(1200, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final reads = WorkspaceSearchReads()
      ..page('alpha', 'Alpha body', name: 'Alpha plan');
    final palette = _PaletteBloc(
      CommandPaletteState.initial().copyWith(cachedViews: Map.of(reads.views)),
    );
    final workspace = _WorkspaceBloc(
      UserWorkspaceState(
        userProfile: UserProfilePB(id: Int64(7)),
        currentWorkspace: UserWorkspacePB(
          workspaceId: 'workspace',
          name: 'Spotlight fixture',
        ),
      ),
    );
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        appearance: appearance,
        disableAnimations: true,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<CommandPaletteBloc>.value(value: palette),
            BlocProvider<UserWorkspaceBloc>.value(value: workspace),
          ],
          child: CommandPaletteModal(
            shortcutBuilder: (child) => child,
            contentReadProvider: reads.provider(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Harness(reads, palette, workspace);
  }

  Future<void> unmount(WidgetTester tester) async {
    // Every glyph the palette drew is one the workspace icon style knows.
    expect(WorkspaceGlyphs.unknownMappings, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    reads.dispose();
    var closed = 0;
    unawaited(palette.close().then((_) => closed++));
    unawaited(workspace.close().then((_) => closed++));
    for (var i = 0; i < 10 && closed < 2; i++) {
      await tester.pump();
    }
    expect(closed, 2);
    expect(tester.takeException(), isNull);
  }
}

class _PaletteBloc extends Cubit<CommandPaletteState>
    implements CommandPaletteBloc {
  _PaletteBloc(super.initialState);

  final events = <CommandPaletteEvent>[];

  @override
  void add(CommandPaletteEvent event) => events.add(event);

  @override
  void setContentSearchEnabled(bool enabled) {}

  @override
  Future<List<ViewPB>?> reloadCachedViews() async =>
      state.cachedViews.values.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecentCache extends Fake implements CachedRecentService {
  @override
  final ValueNotifier<List<SectionViewPB>> notifier = ValueNotifier(const []);

  @override
  Future<List<SectionViewPB>> recentViews() async => notifier.value;
}

class _EmptyAncestorCache extends ViewAncestorCache {
  @override
  Future<ViewAncestor?> getAncestor(
    String viewId, {
    ValueChanged<ViewAncestor>? onRefresh,
  }) async =>
      const ViewAncestor.empty();
}

/// Answers with whatever the test hands it, when the test says so.
class _ScriptedEngine implements PaletteAIEngine {
  final requests = <PaletteAIRequest>[];
  void Function(String delta)? _delta;
  void Function()? _done;
  void Function(PaletteAIFailure failure)? _error;

  @override
  String get label => 'Scripted model';

  @override
  bool get canContinueInChat => false;

  @override
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  }) async {
    requests.add(request);
    _delta = onDelta;
    _done = onDone;
    _error = onError;
  }

  void say(String text) => _delta!(text);

  void finish() => _done!();

  void failNeedingSetup(String message) =>
      _error!(PaletteAIFailure(message, needsSetup: true));

  @override
  Future<void> stop() async {}
}
