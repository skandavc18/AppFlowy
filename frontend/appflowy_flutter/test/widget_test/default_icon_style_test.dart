import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_header.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/desktop_selection_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/settings/pages/default_icon_style_setting.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show MatrixUtils, RenderAbstractViewport;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;
import 'workspace_overlay_test_app.dart';

const _key = DefaultIconStyleStore.storageKey;
const _appearances = ['light', 'dark', 'paper'];
late _PreloadedTranslations _translations;

void main() {
  setUpAll(() async {
    await initializeWorkspaceOverlayTests();
    _translations = await _PreloadedTranslations.read();
  });
  setUp(() {
    resetIconPacksForTesting();
    WorkspaceGlyphs.clearUnknownMappings();
  });

  test('preloaded English survives localization loader aggregation', () async {
    const locale = Locale('en', 'US');
    final english = _translations.resources[locale];
    expect(english, isNotNull);
    final loaded = await Future.wait([
      _translations.load('assets/translations', locale),
    ]);
    expect(loaded, hasLength(1));
    expect(loaded.single, same(english));
  });

  group('device preference (fake KV only)', () {
    test('reading the default is inert and early initialization is retryable',
        () async {
      _MemoryKeyValue? storage;
      var resolutions = 0;
      final store = DefaultIconStyleStore(
        resolveStorage: () {
          resolutions++;
          return storage;
        },
      );
      addTearDown(store.dispose);
      expect(store.value, DefaultIconStyle.vivid);
      expect(store.styles.value, DefaultIconStyle.vivid);
      expect(resolutions, 0);
      expect(await store.ensureLoaded(), isFalse);
      expect(store.isLoaded, isFalse);
      expect(store.failure, DefaultIconStyleFailure.unavailable);
      expect(await store.setStyle(DefaultIconStyle.monochrome), isFalse);
      expect(store.value, DefaultIconStyle.vivid);
      storage = _MemoryKeyValue({_key: 'monochrome', 'unrelated': 'keep'});
      expect(await store.ensureLoaded(), isTrue);
      expect(store.value, DefaultIconStyle.monochrome);
      expect(store.styles.value, DefaultIconStyle.monochrome);
      expect(storage.writes, isEmpty);
      expect(storage.values['unrelated'], 'keep');
    });

    test('missing and future IDs default to Vivid without rewriting them',
        () async {
      for (final id in [null, '', 'a-future-style']) {
        final storage = _MemoryKeyValue({
          if (id != null) _key: id,
          'unrelated': 'keep',
        });
        final store = _store(storage);
        expect(await store.ensureLoaded(), isTrue);
        expect(store.value, DefaultIconStyle.vivid);
        expect(store.styles.value, DefaultIconStyle.vivid);
        expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
        expect(storage.values[_key], id);
        expect(storage.values['unrelated'], 'keep');
        expect(storage.writes, isEmpty);
      }
    });

    test('simultaneous initial reads share one pending storage read', () async {
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..readGate = Completer<void>();
      final store = _store(storage);
      final first = store.ensureLoaded();
      final second = store.ensureLoaded();
      await storage.readStarted.future;
      expect(storage.reads, 1);
      expect(store.isLoaded, isFalse);
      expect(store.value, DefaultIconStyle.vivid);
      storage.readGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(store.value, DefaultIconStyle.monochrome);
      expect(storage.writes, isEmpty);
    });

    test(
        'an early mutation waits for restore, even when it matches the default',
        () async {
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..readGate = Completer<void>();
      final store = _store(storage);
      final published = <DefaultIconStyle>[];
      store.styles.addListener(() => published.add(store.value));
      expect(store.value, DefaultIconStyle.vivid);
      final saved = store.setStyle(DefaultIconStyle.vivid);
      final simultaneousLoad = store.ensureLoaded();
      await storage.readStarted.future;
      expect(storage.writes, isEmpty);
      expect(store.isLoaded, isFalse);
      expect(published, isEmpty);
      storage.readGate!.complete();
      expect(await saved, isTrue);
      expect(await simultaneousLoad, isTrue);
      expect(storage.reads, 1);
      expect(storage.writes, [(_key, 'vivid')]);
      expect(published, [DefaultIconStyle.monochrome, DefaultIconStyle.vivid]);
      expect(storage.values[_key], 'vivid');
    });

    test('read failures block writes and a subsequent selection retries',
        () async {
      final storage = _MemoryKeyValue({_key: 'monochrome'})..readFailures = 1;
      final store = _store(storage);
      expect(await store.setStyle(DefaultIconStyle.vivid), isFalse);
      expect(store.value, DefaultIconStyle.vivid);
      expect(store.isLoaded, isFalse);
      expect(store.failure, DefaultIconStyleFailure.load);
      expect(storage.writes, isEmpty);
      expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
      expect(storage.reads, 2);
      expect(storage.writes, [(_key, 'vivid')]);
      expect(storage.values[_key], 'vivid');
      expect(store.failure, isNull);
    });

    test('writes serialize and publish only after their acknowledgements',
        () async {
      final gate = Completer<void>();
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..writeGates[0] = gate;
      final store = _store(storage);
      expect(await store.ensureLoaded(), isTrue);
      final published = <DefaultIconStyle>[];
      store.styles.addListener(() => published.add(store.value));
      final first = store.setStyle(DefaultIconStyle.vivid);
      final second = store.setStyle(DefaultIconStyle.monochrome);
      final third = store.setStyle(DefaultIconStyle.vivid);
      await storage.writeStarted(0).future;
      expect(storage.writes, [(_key, 'vivid')]);
      expect(store.value, DefaultIconStyle.monochrome);
      expect(store.isSaving, isTrue);
      expect(published, isEmpty);
      gate.complete();
      expect(await Future.wait([first, second, third]), [true, true, true]);
      expect(storage.maximumConcurrentWrites, 1);
      expect(storage.writes, [
        (_key, 'vivid'),
        (_key, 'monochrome'),
        (_key, 'vivid'),
      ]);
      expect(published, [
        DefaultIconStyle.vivid,
        DefaultIconStyle.monochrome,
        DefaultIconStyle.vivid,
      ]);
      expect(store.isSaving, isFalse);
      final reopened = _store(storage);
      expect(await reopened.ensureLoaded(), isTrue);
      expect(reopened.value, DefaultIconStyle.vivid);
    });

    test(
        're-entrant listeners cannot overtake the selection that notified them',
        () async {
      final storage = _MemoryKeyValue({_key: 'monochrome'});
      final store = _store(storage);
      await store.ensureLoaded();
      Future<bool>? second;
      var queued = false;
      store.addListener(() {
        if (store.isSaving && !queued) {
          queued = true;
          second = store.setStyle(DefaultIconStyle.monochrome);
        }
      });
      expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
      expect(await second!, isTrue);
      expect(storage.writes, [(_key, 'vivid'), (_key, 'monochrome')]);
      expect(store.value, DefaultIconStyle.monochrome);
    });

    test('a failed write preserves the last acknowledged value and queue',
        () async {
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..failingWrites.add(0);
      final store = _store(storage);
      expect(await store.ensureLoaded(), isTrue);
      final published = <DefaultIconStyle>[];
      store.styles.addListener(() => published.add(store.value));
      expect(await store.setStyle(DefaultIconStyle.vivid), isFalse);
      expect(store.value, DefaultIconStyle.monochrome);
      expect(store.failure, DefaultIconStyleFailure.save);
      expect(published, isEmpty);
      expect(storage.values[_key], 'monochrome');
      expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
      expect(store.value, DefaultIconStyle.vivid);
      expect(store.failure, isNull);
      expect(storage.writes, [(_key, 'vivid'), (_key, 'vivid')]);
      expect(published, [DefaultIconStyle.vivid]);
    });

    test(
        'a queued return to the old value still writes after an uncertain save',
        () async {
      final gate = Completer<void>();
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..writeGates[0] = gate
        ..failingWrites.add(0);
      final store = _store(storage);
      final failed = store.setStyle(DefaultIconStyle.vivid);
      final restore = store.setStyle(DefaultIconStyle.monochrome);
      await storage.writeStarted(0).future;
      gate.complete();
      expect(await failed, isFalse);
      expect(await restore, isTrue);
      expect(storage.writes, [(_key, 'vivid'), (_key, 'monochrome')]);
      expect(storage.values[_key], 'monochrome');
      expect(store.value, DefaultIconStyle.monochrome);
      expect(store.isSaving, isFalse);
    });

    for (final throws in [false, true]) {
      test('DartKeyValue refusal (throws=$throws) cannot falsely persist',
          () async {
        final preferences = _AcknowledgingPreferences()
          ..disk[_key] = 'monochrome'
          ..cache[_key] = 'monochrome'
          ..throwOnWrite = throws;
        final storage = _AcknowledgingKeyValue(preferences);
        final store = DefaultIconStyleStore(resolveStorage: () => storage);
        addTearDown(store.dispose);
        expect(await store.ensureLoaded(), isTrue);
        expect(await store.setStyle(DefaultIconStyle.vivid), isFalse);
        expect(store.value, DefaultIconStyle.monochrome);
        expect(store.failure, DefaultIconStyleFailure.save);
        expect(preferences.disk[_key], 'monochrome');
        expect(preferences.cache[_key], 'monochrome');
        expect(preferences.reloads, 1);
        preferences
          ..throwOnWrite = false
          ..acknowledge = true;
        expect(await store.setStyle(DefaultIconStyle.monochrome), isTrue);
        expect(preferences.attempts, ['vivid', 'monochrome']);
        expect(preferences.disk[_key], 'monochrome');
        expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
        final reopened = DefaultIconStyleStore(resolveStorage: () => storage);
        addTearDown(reopened.dispose);
        expect(await reopened.ensureLoaded(), isTrue);
        expect(reopened.value, DefaultIconStyle.vivid);
      });
    }

    test('disposing during a read cannot notify or start a later write',
        () async {
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..readGate = Completer<void>();
      final store = DefaultIconStyleStore(resolveStorage: () => storage);
      final pending = store.setStyle(DefaultIconStyle.vivid);
      await storage.readStarted.future;
      store.dispose();
      storage.readGate!.complete();
      expect(await pending, isFalse);
      expect(storage.writes, isEmpty);
      expect(await store.setStyle(DefaultIconStyle.vivid), isFalse);
    });
  });

  test('Vivid catalogue preserves legacy essentials across categories', () {
    final groups = appFlowyVividIconGroups;
    final essentials = groups.firstWhere(
      (group) => group.name == 'appflowy_vivid_essentials',
    );
    expect(essentials.icons, hasLength(56));
    expect(groups.length, greaterThan(1));
    final icons = groups.expand((group) => group.icons).toList();
    expect(icons.length, greaterThanOrEqualTo(128));
    expect(icons.map((icon) => icon.name).toSet(), hasLength(icons.length));
    for (final icon in icons) {
      final svg = vividIconSvg(icon.name);
      expect(svg, isNotNull, reason: icon.name);
      expect(icon.content, svg, reason: icon.name);
    }
  });

  test('Vivid aliases retain object and core-action identities', () {
    const aliases = {
      'book-open': 'book',
      'folder': 'folder',
      'images': 'album',
      'file-pdf': 'pdf',
      'table': 'table',
      'file-text': 'page',
      'git-branch': 'repository',
      'magnifying-glass': 'search',
      'gear': 'settings',
      'bell': 'bell',
      'trash': 'trash',
      'puzzle-piece': 'puzzle',
      'plus': 'plus',
      'copy': 'copy',
      'download': 'download',
      'upload': 'upload',
      'pen': 'pen',
      'note-pencil': 'pen',
      'push-pin': 'pin',
      'history': 'history',
      'clock': 'clock',
      'user': 'user',
      'users': 'users',
      'workspace': 'workspace',
      'lock': 'lock',
      'shield': 'shield',
      'text': 'text',
      'hash': 'number',
      'checkbox': 'checkbox',
      'select': 'select',
      'connections': 'connections',
      'attachment': 'attachment',
      'sigma': 'sigma',
      'keyboard': 'keyboard',
      'filter': 'filter',
      'sort': 'sort',
      'refresh': 'refresh',
      'scissors': 'scissors',
      'paste': 'clipboard',
    };
    for (final entry in aliases.entries) {
      expect(
        WorkspaceGlyphs.vividNameFor(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    // Utility variants keep their meaning without needing picker entries.
    for (final name in [
      'arrow-left',
      'check',
      'line-numbers',
      'line-numbers-off',
    ]) {
      expect(WorkspaceGlyphs.vividNameFor(name), 'utility-$name');
    }
    expect(WorkspaceGlyphs.vividNameFor('unknown'), isNull);
    expect(WorkspaceGlyphs.vividNameFor('future-noun'), isNull);
    expect(vividIconSvg('utility-unknown'), isNull);
    expect(vividIconSvg('utility-future-noun'), isNull);
  });

  test('known default names have self-contained Vivid artwork and geometry',
      () {
    // "unknown" is a diagnostic sentinel, not a known default identity.
    for (final name in defaultIconNames.where((name) => name != 'unknown')) {
      final vivid = WorkspaceGlyphs.vividNameFor(name);
      expect(vivid, isNotNull, reason: name);
      final artwork = vividIconSvg(vivid!);
      expect(artwork, isNotNull, reason: '$name -> $vivid');
      final svg = artwork!;
      expect(svg, startsWith('<svg '), reason: name);
      expect(svg, contains('viewBox="0 0 32 32"'), reason: name);
      expect(svg, endsWith('</svg>'), reason: name);
      expect(svg, contains('<linearGradient '), reason: name);
      expect(svg, isNot(contains('currentColor')), reason: name);
      expect(
        RegExp(r'<(?:image|use|filter|text)\b|\bhref\s*=|url\((?!#)')
            .hasMatch(svg),
        isFalse,
        reason: '$name must be self-contained vector artwork.',
      );
      if (vivid.startsWith('utility-')) {
        expect(vivid, 'utility-$name', reason: name);
        final outline = defaultIconSvg(name)!;
        final body = outline
            .substring(outline.indexOf('>') + 1, outline.lastIndexOf('</svg>'))
            .replaceAll('currentColor', 'url(#utility)');
        expect(svg, contains('<linearGradient id="utility"'), reason: name);
        expect(
          svg.substring(svg.indexOf('</defs>') + '</defs>'.length),
          '<g transform="scale(1.3333333333)" fill="none" '
          'stroke="url(#utility)" stroke-width="1.9" '
          'stroke-linecap="round" stroke-linejoin="round">$body</g></svg>',
          reason: '$name must retain its exact original geometry.',
        );
      }
    }
  });

  for (final appearance in _appearances) {
    testWidgets(
        '$appearance default leaves update without rebuilding their host',
        (tester) async {
      final storage = _MemoryKeyValue({
        _key: 'monochrome',
        'unrelated': 'keep',
      });
      final store = _store(storage);
      await store.ensureLoaded();
      final page =
          ViewPB(id: 'page', name: 'Draft', layout: ViewLayoutPB.Document);
      final folder = ViewPB(
        id: 'folder',
        name: 'Folder',
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final book = ViewPB(
        id: 'book',
        name: 'Book',
        layout: ViewLayoutPB.Document,
        extra: CollectionMetadata.newExtra(CollectionKind.book),
      );
      final table = ViewPB(
        id: 'calendar',
        name: 'Calendar',
        layout: ViewLayoutPB.Calendar,
      );
      final snapshots = {
        for (final view in [page, folder, book, table])
          view: view.writeToBuffer(),
      };
      final draft = TextEditingController(text: 'Unsaved editor text');
      final focus = FocusNode();
      var builds = 0;
      try {
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            child: DefaultIconStyleScope(
              styles: store.styles,
              child: Builder(
                builder: (context) {
                  builds++;
                  return Center(
                    child: SizedBox(
                      width: 440,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _sidebarRow(page),
                          Wrap(
                            spacing: 16,
                            children: [
                              _sample(
                                'sidebar',
                                const SidebarGlyph(SidebarIcon.book),
                              ),
                              _sample(
                                'folder',
                                WorkspaceItemIcon.fromView(view: folder),
                              ),
                              _sample(
                                'collection',
                                WorkspaceItemIcon.fromView(view: book),
                              ),
                              _sample(
                                'header',
                                page.defaultIcon(
                                  size: const Size.square(56),
                                ),
                              ),
                              _sample(
                                'attachment',
                                FileIdentityGlyph(
                                  icon: EmojiIconData.none(),
                                  name: 'file.pdf',
                                ),
                              ),
                              _sample(
                                'table',
                                DatabaseTabBarItem(
                                  view: table,
                                  isSelected: false,
                                  onTap: (_) {},
                                ),
                              ),
                            ],
                          ),
                          SettingsMenuElement(
                            key: const ValueKey('settings-item'),
                            page: SettingsPage.workspace,
                            selectedPage: SettingsPage.workspace,
                            label: 'Workspace',
                            icon: const FlowySvg(
                              FlowySvgs.settings_page_workspace_m,
                            ),
                            changeSelectedPage: (SettingsPage _) {},
                          ),
                          TextField(controller: draft, focusNode: focus),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        focus.requestFocus();
        draft.selection = const TextSelection(baseOffset: 2, extentOffset: 9);
        await tester.pump();
        final hostBuilds = builds;
        final editorState = tester.state(find.byType(EditableText));
        final sidebarPicker = find.byKey(const ValueKey('sidebar-icon-page'));
        expect(find.byType(ViewIconPicker), findsOneWidget);
        final pickerState = tester.state(sidebarPicker);
        final pickerRect = tester.getRect(sidebarPicker);
        final positions = {
          for (final key in [
            'sidebar',
            'folder',
            'collection',
            'header',
            'attachment',
            'table',
          ])
            key: tester.getRect(find.byKey(ValueKey(key))),
        };
        _expectAllDefaultGlyphs(tester, DefaultIconStyle.monochrome);
        expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
        await settleVividIconPictures(tester);
        _expectAllDefaultGlyphs(tester, DefaultIconStyle.vivid);
        expect(builds, hostBuilds);
        expect(tester.state(find.byType(EditableText)), same(editorState));
        expect(draft.text, 'Unsaved editor text');
        expect(
          draft.selection,
          const TextSelection(baseOffset: 2, extentOffset: 9),
        );
        expect(focus.hasFocus, isTrue);
        expect(tester.state(sidebarPicker), same(pickerState));
        expect(tester.getRect(sidebarPicker), pickerRect);
        for (final entry in positions.entries) {
          expect(tester.getRect(find.byKey(ValueKey(entry.key))), entry.value);
        }
        for (final entry in snapshots.entries) {
          expect(entry.key.writeToBuffer(), entry.value);
        }
        expect(storage.values, {_key: 'vivid', 'unrelated': 'keep'});
        expect(storage.writes, [(_key, 'vivid')]);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        draft.dispose();
        focus.dispose();
      }
    });

    testWidgets(
        '$appearance an already open menu captures the live style source',
        (tester) async {
      final store = _store(_MemoryKeyValue({_key: 'monochrome'}));
      await store.ensureLoaded();
      await tester.pumpWidget(
        _localizedIconTestApp(
          appearance: appearance,
          child: DefaultIconStyleScope(
            styles: store.styles,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppMenu<void>(
                  context: context,
                  globalPosition: const Offset(24, 24),
                  entries: const [
                    AppMenuItem(label: 'Folder', icon: Icons.folder_rounded),
                    AppMenuItem(
                      label: 'Settings',
                      icon: Icons.settings_rounded,
                    ),
                    AppMenuItem(
                      label: 'Selected',
                      icon: Icons.copy_rounded,
                      selected: true,
                    ),
                    AppMenuItem(
                      label: 'Disabled folder',
                      icon: Icons.folder_rounded,
                      enabled: false,
                    ),
                    AppMenuItem(
                      label: 'Destructive folder',
                      icon: Icons.folder_rounded,
                      destructive: true,
                    ),
                  ],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      final open = find.widgetWithText(TextButton, 'Open');
      await _finishLocalization(tester, open);
      await tester.tap(await _revealControl(tester, open));
      await settleVividIconPictures(tester);
      final folderRow = find.widgetWithText(AppMenuRow, 'Folder');
      expect(folderRow, findsOneWidget);
      expect(
        DefaultIconStyleScope.of(tester.element(folderRow)),
        same(store.styles),
        reason: 'The real popup must capture the source, not a style snapshot.',
      );
      final menuState = tester.state(folderRow);
      final rect = tester.getRect(folderRow);
      final outline = _picture(tester, folderRow);
      expect(outline.colorFilter, isNotNull);
      expect(await store.setStyle(DefaultIconStyle.vivid), isTrue);
      await settleVividIconPictures(tester);
      expect(tester.state(folderRow), same(menuState));
      expect(tester.getRect(folderRow), rect);
      expect(_picture(tester, folderRow).colorFilter, isNull);
      _expectSvg(tester, folderRow, vividIconSvg('folder')!);
      final settingsRow = find.widgetWithText(AppMenuRow, 'Settings');
      _expectSvg(tester, settingsRow, vividIconSvg('settings')!);
      expect(_picture(tester, settingsRow).colorFilter, isNull);
      final style = AppMenuStyle.of(tester.element(folderRow));
      final disabled = find.widgetWithText(AppMenuRow, 'Disabled folder');
      final destructive = find.widgetWithText(AppMenuRow, 'Destructive folder');
      _expectSvg(tester, disabled, defaultIconSvg('folder')!);
      _expectSvg(tester, destructive, defaultIconSvg('folder')!);
      expect(
        _picture(tester, disabled).colorFilter,
        ColorFilter.mode(
          style.iconMuted.withValues(alpha: 0.5),
          BlendMode.srcIn,
        ),
      );
      expect(
        _picture(tester, destructive).colorFilter,
        ColorFilter.mode(style.danger, BlendMode.srcIn),
      );
      await tester.tap(disabled);
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSurface), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSurface), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance deferred default builders cannot bypass state ink',
        (tester) async {
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: Center(
            child: SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final destructive in [false, true])
                    AppMenuRow(
                      label: destructive
                          ? 'Destructive builder'
                          : 'Disabled builder',
                      enabled: destructive,
                      destructive: destructive,
                      iconWidget: Builder(
                        builder: (_) => const WorkspaceGlyph(
                          Icons.folder_rounded,
                          color: Colors.blue,
                          style: DefaultIconStyle.vivid,
                          role: WorkspaceGlyphRole.standard,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await settleVividIconPictures(tester);
      for (final destructive in [false, true]) {
        final row = find.widgetWithText(
          AppMenuRow,
          destructive ? 'Destructive builder' : 'Disabled builder',
        );
        final style = AppMenuStyle.of(tester.element(row));
        _expectSvg(tester, row, defaultIconSvg('folder')!);
        expect(
          _picture(tester, row).colorFilter,
          ColorFilter.mode(
            destructive ? style.danger : style.iconMuted.withValues(alpha: 0.5),
            BlendMode.srcIn,
          ),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance mounted slash icons observe only the glyph change',
        (tester) async {
      final store = _store(_MemoryKeyValue({_key: 'monochrome'}));
      await store.ensureLoaded();
      final editor = EditorState.blank();
      try {
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            child: DefaultIconStyleScope(
              styles: store.styles,
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: AppFlowyDesktopSelectionMenuWidget(
                    items: slashMenuItemsBuilder(isLocalMode: true)
                        .take(4)
                        .toList(),
                    editorState: editor,
                    menuService: _SelectionMenuService(),
                    onExit: () {},
                    onSelectionUpdate: () {},
                    selectionMenuStyle: SelectionMenuStyle.light,
                    deleteSlashByDefault: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final menu = find.byType(AppFlowyDesktopSelectionMenuWidget);
        final state = tester.state(menu);
        final before = editor.document.toJson();
        _expectAllDefaultGlyphs(tester, DefaultIconStyle.monochrome);
        await store.setStyle(DefaultIconStyle.vivid);
        await settleVividIconPictures(tester);
        _expectAllDefaultGlyphs(tester, DefaultIconStyle.vivid);
        expect(tester.state(menu), same(state));
        expect(editor.document.toJson(), before);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
      }
    });

    testWidgets(
        '$appearance chosen emoji, default pack and Vivid stay unchanged',
        (tester) async {
      final store = _store(_MemoryKeyValue({_key: 'monochrome'}));
      await store.ensureLoaded();
      final icons = [
        EmojiIconData.emoji('📚'),
        IconsData('appflowy_default_collections', 'book', '4283665274')
            .toEmojiIconData(),
        IconsData('appflowy_vivid_essentials', 'rocket', '4278255360')
            .toEmojiIconData(),
      ];
      final views = [
        for (var i = 0; i < icons.length; i++)
          ViewPB(
            id: 'chosen-$i',
            name: 'Chosen $i',
            layout: ViewLayoutPB.Document,
            icon: icons[i].toViewIcon(),
          ),
      ];
      final bytes = views.map((view) => view.writeToBuffer()).toList();
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: DefaultIconStyleScope(
            styles: store.styles,
            child: Center(
              child: SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final view in views) _sidebarRow(view),
                    AppMenuRow(
                      label: 'Uploaded SVG artwork',
                      destructive: true,
                      iconWidget: SvgPicture.string(
                        _uploadedSvg,
                        width: 18,
                        height: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settleVividIconPictures(tester);
      // Use actual State identities, not a second icon renderer or fake pack.
      final rawStates = [
        for (final element in find.byType(RawEmojiIconWidget).evaluate())
          (element as StatefulElement).state,
      ];
      expect(rawStates, hasLength(icons.length));
      final originalSvg = tester
          .widgetList<FlowySvg>(find.byType(FlowySvg))
          .map((svg) => (svg.svgString, svg.color, svg.blendMode))
          .toList();
      expect(originalSvg, hasLength(2));
      expect(originalSvg.first.$2, const Color(0xFF538B7A));
      expect(originalSvg.first.$3, BlendMode.srcIn);
      expect(originalSvg.last.$2, isNull);
      expect(originalSvg.last.$3, isNull);
      for (final style in [
        DefaultIconStyle.vivid,
        DefaultIconStyle.monochrome,
      ]) {
        expect(await store.setStyle(style), isTrue);
        await settleVividIconPictures(tester);
        final currentStates = [
          for (final element in find.byType(RawEmojiIconWidget).evaluate())
            (element as StatefulElement).state,
        ];
        for (var i = 0; i < rawStates.length; i++) {
          expect(currentStates[i], same(rawStates[i]));
          expect(views[i].writeToBuffer(), bytes[i]);
        }
        expect(
          tester
              .widgetList<FlowySvg>(find.byType(FlowySvg))
              .map((svg) => (svg.svgString, svg.color, svg.blendMode))
              .toList(),
          originalSvg,
        );
        final upload = find.widgetWithText(AppMenuRow, 'Uploaded SVG artwork');
        expect(_picture(tester, upload).colorFilter, isNull);
        _expectSvg(tester, upload, _uploadedSvg);
        expect(find.byType(WorkspaceGlyph), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
          '$appearance/$scale native settings previews and keyboard save',
          (tester) async {
        final gate = Completer<void>();
        final storage = _MemoryKeyValue({_key: 'monochrome'})
          ..writeGates[0] = gate;
        final store = _settingStore(storage);
        final semantics = tester.ensureSemantics();
        try {
          await _mountSetting(
            tester,
            store,
            appearance: appearance,
            scale: scale,
          );
          expect(
            find.byType(RadioListTile<DefaultIconStyle>),
            findsNWidgets(2),
          );
          final mono = _option(DefaultIconStyle.monochrome);
          final vivid = _option(DefaultIconStyle.vivid);
          expect(store.isLoaded, isTrue);
          expect(storage.reads, 1);
          expect(tester.getTopLeft(mono).dy, tester.getTopLeft(vivid).dy);
          expect(
            tester.getRect(mono).right,
            lessThan(tester.getRect(vivid).left),
          );
          expect(
            _radioSemantics(tester, DefaultIconStyle.monochrome)
                .hasFlag(ui.SemanticsFlag.isChecked),
            isTrue,
          );
          expect(
            _radioSemantics(tester, DefaultIconStyle.vivid)
                .hasFlag(ui.SemanticsFlag.isChecked),
            isFalse,
          );
          expect(
            _radioSemantics(tester, DefaultIconStyle.vivid)
                .hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          final previews = find.descendant(
            of: find.byType(DefaultIconStyleSetting),
            matching: find.byType(WorkspaceGlyph),
          );
          for (final element in previews.evaluate()) {
            final glyph = element.widget as WorkspaceGlyph;
            _expectGlyph(tester, find.byWidget(glyph), glyph.style!);
          }
          final liveGlyph = find.byKey(const ValueKey('settings-live-default'));
          final liveElement = tester.element(liveGlyph);
          _expectGlyph(tester, liveGlyph, DefaultIconStyle.monochrome);
          if (appearance == 'paper') {
            final material = tester.widget<Material>(
              find.ancestor(of: vivid, matching: find.byType(Material)).first,
            );
            expect(material.color, EditorSurfaceStyle.lightPreviewBackground);
            expect(material.color, isNot(Colors.white));
            expect(PaperTheme.isEnabled(tester.element(vivid)), isTrue);
          }
          // Follow the real native focus traversal rather than invoking the
          // onChanged callback or installing test-only focus handlers.
          await _revealControl(tester, vivid);
          for (var i = 0;
              i < 8 &&
                  !_radioSemantics(tester, DefaultIconStyle.vivid)
                      .hasFlag(ui.SemanticsFlag.isFocused);
              i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(
            _radioSemantics(tester, DefaultIconStyle.vivid)
                .hasFlag(ui.SemanticsFlag.isFocused),
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(store.isSaving, isTrue);
          expect(store.value, DefaultIconStyle.monochrome);
          expect(
            _radioSemantics(tester, DefaultIconStyle.monochrome)
                .hasFlag(ui.SemanticsFlag.isChecked),
            isTrue,
          );
          expect(
            _radioSemantics(tester, DefaultIconStyle.vivid)
                .hasFlag(ui.SemanticsFlag.isChecked),
            isFalse,
          );
          expect(
            _radioSemantics(tester, DefaultIconStyle.vivid)
                .hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          _expectGlyph(tester, liveGlyph, DefaultIconStyle.monochrome);
          expect(find.text('Saving your icon preference…'), findsOneWidget);
          expect(storage.writes, [(_key, 'vivid')]);
          final saving = store.lastSave;
          expect(saving, isNotNull);
          gate.complete();
          expect(await saving!, isTrue);
          await settleVividIconPictures(tester);
          expect(store.value, DefaultIconStyle.vivid);
          expect(store.isSaving, isFalse);
          expect(
            _radioSemantics(tester, DefaultIconStyle.vivid)
                .hasFlag(ui.SemanticsFlag.isChecked),
            isTrue,
          );
          expect(tester.element(liveGlyph), same(liveElement));
          _expectGlyph(tester, liveGlyph, DefaultIconStyle.vivid);
          expect(storage.values[_key], 'vivid');
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await tester.pumpWidget(const SizedBox());
          await store.lastSave;
          semantics.dispose();
        }
      });
    }

    testWidgets(
        '$appearance failed saves report an error, not a selected value',
        (tester) async {
      final storage = _MemoryKeyValue({_key: 'monochrome'})
        ..failingWrites.add(0);
      final store = _settingStore(storage);
      final semantics = tester.ensureSemantics();
      try {
        await _mountSetting(tester, store, appearance: appearance);
        final vivid = _option(DefaultIconStyle.vivid);
        await tester.tap(await _revealControl(tester, vivid));
        expect(store.lastSave, isNotNull);
        expect(await store.lastSave!, isFalse);
        await tester.pump();
        expect(store.value, DefaultIconStyle.monochrome);
        expect(store.failure, DefaultIconStyleFailure.save);
        expect(
          _radioSemantics(tester, DefaultIconStyle.monochrome)
              .hasFlag(ui.SemanticsFlag.isChecked),
          isTrue,
        );
        expect(
          _radioSemantics(tester, DefaultIconStyle.vivid)
              .hasFlag(ui.SemanticsFlag.isChecked),
          isFalse,
        );
        final feedback =
            find.byKey(const ValueKey('default-icon-style-status'));
        expect(
          tester.widget<Text>(feedback).data,
          contains('could not be saved'),
        );
        await tester.ensureVisible(feedback);
        await tester.pump();
        expect(
          tester
              .getSemantics(feedback)
              .getSemanticsData()
              .hasFlag(ui.SemanticsFlag.isLiveRegion),
          isTrue,
        );
        expect(find.textContaining('private-storage'), findsNothing);
        final failedSave = store.lastSave;
        await tester.tap(await _revealControl(tester, vivid));
        expect(store.lastSave, isNot(same(failedSave)));
        expect(await store.lastSave!, isTrue);
        await tester.pump();
        expect(store.value, DefaultIconStyle.vivid);
        expect(storage.writes, [(_key, 'vivid'), (_key, 'vivid')]);
        expect(storage.values[_key], 'vivid');
        expect(
          _radioSemantics(tester, DefaultIconStyle.vivid)
              .hasFlag(ui.SemanticsFlag.isChecked),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('default-icon-style-status')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      }
    });
  }

  testWidgets('a failed initial read has no false selected radio and can retry',
      (tester) async {
    final storage = _MemoryKeyValue({_key: 'monochrome'})..readFailures = 1;
    final store = _settingStore(storage);
    final semantics = tester.ensureSemantics();
    try {
      await _mountSetting(tester, store);
      expect(store.isLoaded, isFalse);
      expect(store.value, DefaultIconStyle.vivid);
      expect(store.failure, DefaultIconStyleFailure.load);
      for (final style in DefaultIconStyle.values) {
        final tile = tester.widget<RadioListTile<DefaultIconStyle>>(
          _option(style),
        );
        expect(tile.groupValue, isNull);
        expect(tile.onChanged, isNull);
        final data = _radioSemantics(tester, style);
        expect(data.hasFlag(ui.SemanticsFlag.isChecked), isFalse);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
      }
      expect(find.textContaining('could not be read'), findsOneWidget);
      final failedLoad = store.lastLoad;
      final retry = find.widgetWithText(TextButton, 'Retry');
      await tester.tap(await _revealControl(tester, retry));
      expect(store.lastLoad, isNot(same(failedLoad)));
      expect(await store.lastLoad!, isTrue);
      await tester.pump();
      expect(storage.reads, 2);
      expect(store.value, DefaultIconStyle.monochrome);
      expect(storage.writes, isEmpty);
      expect(store.failure, isNull);
      await _revealControl(tester, _option(DefaultIconStyle.monochrome));
      expect(
        _radioSemantics(tester, DefaultIconStyle.monochrome)
            .hasFlag(ui.SemanticsFlag.isChecked),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    }
  });

  testWidgets(
      'closing during save and reopening restores the acknowledged style',
      (tester) async {
    final gate = Completer<void>();
    final storage = _MemoryKeyValue({_key: 'monochrome'})..writeGates[0] = gate;
    final store = _settingStore(storage);
    final semantics = tester.ensureSemantics();
    try {
      await _mountSetting(tester, store);
      final vivid = _option(DefaultIconStyle.vivid);
      await tester.tap(await _revealControl(tester, vivid));
      await tester.pump();
      expect(storage.writes, [(_key, 'vivid')]);
      expect(store.isSaving, isTrue);
      expect(store.value, DefaultIconStyle.monochrome);
      final saving = store.lastSave;
      expect(saving, isNotNull);
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      expect(await saving!, isTrue);

      final reopened = _settingStore(storage);
      await _mountSetting(tester, reopened);
      expect(reopened.value, DefaultIconStyle.vivid);
      expect(storage.reads, 2);
      expect(storage.writes, [(_key, 'vivid')]);
      expect(
        _radioSemantics(tester, DefaultIconStyle.vivid)
            .hasFlag(ui.SemanticsFlag.isChecked),
        isTrue,
      );
      _expectGlyph(
        tester,
        find.byKey(const ValueKey('settings-live-default')),
        DefaultIconStyle.vivid,
      );
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox());
      await store.lastSave;
      semantics.dispose();
    }
  });

  testWidgets('all known defaults render both styles without picker assets',
      (tester) async {
    final bundle = _NoAssetReads();
    for (final style in DefaultIconStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: bundle,
            child: Center(
              child: Wrap(
                children: [
                  for (final name
                      in defaultIconNames.where((name) => name != 'unknown'))
                    WorkspaceGlyph.named(name, style: style),
                  WorkspaceGlyph(Icons.settings_rounded, style: style),
                  WorkspaceGlyph(Icons.check_rounded, style: style),
                  WorkspaceGlyph(Icons.close_rounded, style: style),
                ],
              ),
            ),
          ),
        ),
      );
      await settleVividIconPictures(tester);
      _expectAllDefaultGlyphs(tester, style);
      expect(bundle.requests, isEmpty);
      expect(iconPacksVersion.value, 0);
      expect(WorkspaceGlyphs.unknownMappings, isEmpty);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new source icons and unknown names never get a question mark',
      (tester) async {
    const icon = Icons.healing_rounded;
    expect(WorkspaceGlyphs.nameForIcon(icon), isNull);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: const Row(
            children: [
              WorkspaceGlyph(
                icon,
                style: DefaultIconStyle.vivid,
                semanticLabel: 'New action',
              ),
              WorkspaceGlyph.named(
                'future-noun',
                key: ValueKey('future-noun'),
                style: DefaultIconStyle.vivid,
              ),
            ],
          ),
        ),
      );
      await settleVividIconPictures(tester);
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.bySemanticsLabel('New action'), findsOneWidget);
      _expectSvg(
        tester,
        find.byKey(const ValueKey('future-noun')),
        defaultIconSvg('file')!,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    }
  });

  test('saved/upload renderers are never adapted, even in state-ink scopes',
      () {
    final choices = [
      EmojiIconData.emoji('📚'),
      IconsData('appflowy_default_collections', 'book', '4283665274')
          .toEmojiIconData(),
      IconsData('appflowy_vivid_essentials', 'book', null).toEmojiIconData(),
      EmojiIconData.custom('C:\\synthetic-fixture\\chosen.svg'),
      EmojiIconData.custom('https://example.invalid/chosen.png'),
    ];
    for (final choice in choices) {
      final saved = choice.toViewIcon();
      final bytes = saved.writeToBuffer();
      final renderer =
          RawEmojiIconWidget(emoji: saved.toEmojiIconData(), emojiSize: 18);
      expect(
        WorkspaceGlyph.adapt(
          renderer,
          role: WorkspaceGlyphRole.preserveInk,
          color: Colors.red,
        ),
        same(renderer),
      );
      expect(saved.writeToBuffer(), bytes);
    }
    final library = IconWidget(
      size: 18,
      iconsData: IconsData('phosphor_bold_office', 'book', '4283665274'),
    );
    expect(
      WorkspaceGlyph.adapt(library, role: WorkspaceGlyphRole.preserveInk),
      same(library),
    );
    final inline = FlowySvg.string(_uploadedSvg);
    expect(WorkspaceGlyph.adapt(inline, color: Colors.red), same(inline));
  });
}

DefaultIconStyleStore _store(_MemoryKeyValue storage) {
  final store = DefaultIconStyleStore(resolveStorage: () => storage);
  addTearDown(store.dispose);
  return store;
}

_SettingStore _settingStore(_MemoryKeyValue storage) {
  final store = _SettingStore(storage);
  addTearDown(store.dispose);
  return store;
}

/// Observe the real store futures without bypassing native control activation
/// or implementing an alternative persistence/selection policy in the fixture.
class _SettingStore extends DefaultIconStyleStore {
  _SettingStore(_MemoryKeyValue storage) : super(resolveStorage: () => storage);

  Future<bool>? lastLoad;
  Future<bool>? lastSave;

  @override
  Future<bool> ensureLoaded() => lastLoad = super.ensureLoaded();

  @override
  Future<bool> setStyle(DefaultIconStyle style) =>
      lastSave = super.setStyle(style);
}

class _MemoryKeyValue extends Fake implements KeyValueStorage {
  _MemoryKeyValue([Map<String, String> initial = const {}])
      : values = Map.of(initial);

  final Map<String, String> values;
  final writes = <(String, String)>[];
  final readStarted = Completer<void>();
  final writeGates = <int, Completer<void>>{};
  final _writeStarts = <int, Completer<void>>{};
  final failingWrites = <int>{};
  Completer<void>? readGate;
  int reads = 0;
  int readFailures = 0;
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;

  Completer<void> writeStarted(int index) =>
      _writeStarts.putIfAbsent(index, Completer<void>.new);

  @override
  Future<String?> get(String key) async {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    final stored = values[key];
    await readGate?.future;
    if (readFailures > 0) {
      readFailures--;
      throw StateError('private-storage-read-details');
    }
    return stored;
  }

  @override
  Future<void> set(String key, String value) async {
    final index = writes.length;
    writes.add((key, value));
    _activeWrites++;
    if (_activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = _activeWrites;
    }
    writeStarted(index).complete();
    try {
      await writeGates[index]?.future;
      if (failingWrites.contains(index)) {
        throw StateError('private-storage-write-details');
      }
      values[key] = value;
    } finally {
      _activeWrites--;
    }
  }
}

/// Test the production DartKeyValue acknowledgement branch without any native
/// preferences, method channel, GetIt registration or live profile access.
class _AcknowledgingKeyValue extends DartKeyValue {
  _AcknowledgingKeyValue(this.preferences);
  final _AcknowledgingPreferences preferences;

  @override
  SharedPreferences get sharedPreferences => preferences;

  @override
  Future<String?> get(String key) async => preferences.disk[key];

  @override
  Future<void> set(String key, String value) =>
      throw StateError('The void set wrapper cannot verify acknowledgement');
}

class _AcknowledgingPreferences extends Fake implements SharedPreferences {
  final disk = <String, String>{};
  final cache = <String, String>{};
  final attempts = <String>[];
  bool acknowledge = false;
  bool throwOnWrite = false;
  int reloads = 0;

  @override
  Future<bool> setString(String key, String value) async {
    attempts.add(value);
    cache[key] = value;
    if (throwOnWrite) throw StateError('private-storage-platform-details');
    if (acknowledge) disk[key] = value;
    return acknowledge;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cache
      ..clear()
      ..addAll(disk);
  }
}

class _SelectionMenuService extends Fake implements SelectionMenuService {}

class _NoAssetReads extends CachingAssetBundle {
  final requests = <String>[];

  @override
  Future<ByteData> load(String key) {
    requests.add(key);
    throw StateError('Default glyphs must not read assets');
  }
}

Widget _sample(String key, Widget child) =>
    KeyedSubtree(key: ValueKey(key), child: child);

SvgPicture _picture(WidgetTester tester, Finder parent) =>
    tester.widget<SvgPicture>(
      find.descendant(of: parent, matching: find.byType(SvgPicture)),
    );

void _expectSvg(WidgetTester tester, Finder parent, String source) {
  final loader = _picture(tester, parent).bytesLoader as SvgStringLoader;
  // SvgStringLoader's source is private; its public value equality compares
  // the exact SVG source, theme and colour mapper without decoding an asset.
  expect(
    loader,
    SvgStringLoader(
      source,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
}

void _expectGlyph(WidgetTester tester, Finder finder, DefaultIconStyle style) {
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  final picture = _picture(tester, finder);
  final vivid = style == DefaultIconStyle.vivid
      ? WorkspaceGlyphs.vividNameFor(glyph.name)
      : null;
  _expectSvg(
    tester,
    finder,
    (vivid == null ? defaultIconSvg(glyph.name) : vividIconSvg(vivid))!,
  );
  final context = tester.element(finder);
  expect(
    picture.colorFilter,
    vivid != null
        ? null
        : ColorFilter.mode(
            style == DefaultIconStyle.vivid
                ? workspaceGlyphAccent(context)
                : glyph.color ?? workspaceGlyphInk(context),
            BlendMode.srcIn,
          ),
  );
  expect(tester.getSize(finder), Size.square(glyph.size));
}

void _expectAllDefaultGlyphs(WidgetTester tester, DefaultIconStyle style) {
  final glyphs =
      tester.widgetList<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).toList();
  expect(glyphs, isNotEmpty);
  for (final glyph in glyphs) {
    expect(glyph.name, isNot('unknown'));
    _expectGlyph(tester, find.byWidget(glyph), style);
  }
}

Finder _option(DefaultIconStyle style) =>
    find.byKey(ValueKey('default-icon-style-${style.name}'));

SemanticsData _radioSemantics(WidgetTester tester, DefaultIconStyle style) {
  final finder = _option(style);
  final tile = tester.widget<RadioListTile<DefaultIconStyle>>(finder);
  final node = tester.getSemantics(finder);
  expect(node.attached, isTrue);
  expect(node.isMergedIntoParent, isFalse);
  expect(
    find.semantics.byPredicate((candidate) => identical(candidate, node)),
    findsOneWidget,
  );
  // RadioListTile owns MergeSemantics. SemanticsNode.hasFlag reads only that
  // boundary's raw flags; getSemanticsData includes its Radio and focus child,
  // exactly as the engine's accessibility update does.
  final data = node.getSemanticsData();
  expect(data.hasFlag(ui.SemanticsFlag.hasCheckedState), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isChecked), tile.checked);
  expect(data.label, contains((tile.title! as Text).data!));
  return data;
}

Future<void> _finishLocalization(WidgetTester tester, Finder content) async {
  // Asset IO was awaited in setUpAll. The asynchronous localization delegate
  // schedules the route after the first pump; render that frame, not a timer.
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(content, findsOneWidget, reason: 'Localized content must be mounted.');

  final context = tester.element(content);
  const locale = Locale('en', 'US');
  expect(context.locale, locale);
  expect(Localizations.localeOf(context), locale);
  final english = _translations.resources[locale]!;
  final settings = english['settings'] as Map<String, dynamic>;
  final workspace = settings['workspacePage'] as Map<String, dynamic>;
  final copy = workspace['defaultIconStyle'] as Map<String, dynamic>;
  expect(copy, isNotEmpty);
  for (final entry in copy.entries) {
    expect(entry.value, isA<String>());
    expect(entry.value, isNotEmpty);
    final key = 'settings.workspacePage.defaultIconStyle.${entry.key}';
    expect(
      key.tr(context: context),
      entry.value,
      reason: 'The widget delegate must retain the real bundled English copy.',
    );
    expect(
      key.tr(),
      entry.value,
      reason: 'The setting uses context-free tr(), not a separate test map.',
    );
  }
}

Widget _localizedIconTestApp({
  required Widget child,
  String appearance = 'light',
  double textScale = 1,
}) {
  final app = workspaceOverlayTestApp(
    child: child,
    appearance: appearance,
    textScale: textScale,
  ) as EasyLocalization;
  return EasyLocalization(
    supportedLocales: app.supportedLocales,
    path: app.path,
    fallbackLocale: app.fallbackLocale,
    useFallbackTranslations: app.useFallbackTranslations,
    saveLocale: app.saveLocale,
    assetLoader: _translations,
    child: app.child,
  );
}

/// Real translations, loaded outside the fake clock. Keep the shared app's
/// themes, Navigator and localization delegate; replace only asynchronous IO.
class _PreloadedTranslations extends AssetLoader {
  _PreloadedTranslations(this.resources);

  final Map<Locale, Map<String, dynamic>> resources;

  static Future<_PreloadedTranslations> read() async {
    const loader = TestBundleAssetLoader();
    final resources = <Locale, Map<String, dynamic>>{};
    for (final locale in const [Locale('en', 'US'), Locale('en')]) {
      try {
        resources[locale] = await loader.load('assets/translations', locale);
      } on FlutterError {
        // EasyLocalization also tolerates a missing language-only fallback,
        // but a missing primary locale must fail setup, not return fake copy.
        if (locale.countryCode != null) rethrow;
      }
    }
    return _PreloadedTranslations(resources);
  }

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) {
    final resource = resources[locale];
    if (resource == null) {
      throw FlutterError('No bundled translation for $locale');
    }
    // EasyLocalization 3.0.7 combines loaders with Future.wait. A
    // SynchronousFuture fires before wait initializes its result collection,
    // silently dropping this map. Preload the IO, not the Future contract.
    return Future.value(resource);
  }
}

Future<Finder> _revealControl(WidgetTester tester, Finder control) async {
  expect(control, findsOneWidget);
  // A scaled RadioListTile subtitle can exceed the viewport height. Revealing
  // the tile's leading edge does not reveal its center; use the native Radio's
  // hit area, not the entire description/preview card, for scrolling and taps.
  final isRadio = tester.widget(control) is RadioListTile<DefaultIconStyle>;
  final target = isRadio
      ? find.descendant(
          of: control,
          matching: find.byType(Radio<DefaultIconStyle>),
        )
      : control;
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  final bounds = tester.getRect(control);
  expect(bounds.isFinite, isTrue);
  expect(bounds.isEmpty, isFalse);
  final targetBounds = tester.getRect(target);
  final surface =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(targetBounds.isFinite, isTrue);
  expect(targetBounds.isEmpty, isFalse);
  expect(surface.contains(targetBounds.center), isTrue);
  final renderObject = tester.renderObject(target);
  expect(renderObject.attached, isTrue);
  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (isRadio) expect(viewport, isNotNull);
  if (viewport != null) {
    final viewportBounds = MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      viewport.paintBounds,
    );
    expect(viewportBounds.isFinite, isTrue);
    expect(viewportBounds.isEmpty, isFalse);
    expect(viewportBounds.contains(targetBounds.center), isTrue);
    expect(
      viewportBounds.intersect(targetBounds),
      targetBounds,
      reason: 'The native hit area must be fully inside the scroll viewport.',
    );
  }
  expect(target.hitTestable(), findsOneWidget);
  return target;
}

Future<void> _mountSetting(
  WidgetTester tester,
  _SettingStore store, {
  String appearance = 'light',
  double scale = 1,
}) async {
  await tester.pumpWidget(
    _localizedIconTestApp(
      appearance: appearance,
      textScale: scale,
      child: DefaultIconStyleScope(
        styles: store.styles,
        child: Center(
          child: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: WorkspaceGlyph.named(
                      'folder',
                      key: ValueKey('settings-live-default'),
                    ),
                  ),
                  DefaultIconStyleSetting(store: store),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _finishLocalization(tester, find.byType(DefaultIconStyleSetting));
  expect(store.lastLoad, isNotNull);
  await store.lastLoad!;
  await tester.pump();
  await settleVividIconPictures(tester);
}

Widget _sidebarRow(ViewPB view) => SingleInnerViewItem(
      view: view,
      parentView: null,
      isExpanded: false,
      level: 0,
      leftPadding: SidebarMetrics.indent,
      spaceType: FolderSpaceType.unknown,
      showActions: false,
      onSelected: (_, __) {},
      isFeedback: false,
      height: SidebarMetrics.rowHeight,
      leftIconBuilder: (_, __) => const SizedBox.shrink(),
      rightIconsBuilder: (_, __) => [],
      includeDefaultMoreAction: false,
      extendBuilder: null,
      disableSelectedStatus: null,
      shouldIgnoreView: null,
      isSelected: false,
    );

const _uploadedSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path fill="#ff0000" d="M0 0h12v24H0z"/>'
    '<path fill="#0000ff" d="M12 0h12v24H12z"/></svg>';
