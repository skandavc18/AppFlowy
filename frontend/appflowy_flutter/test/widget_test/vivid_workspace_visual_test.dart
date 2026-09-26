import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/codegen_loader.g.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/desktop_field_cell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/desktop_selection_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_items.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Source-only handoff: the main verification run generates, reviews, and then
// compares six NEW references under goldens/vivid_workspace/. No existing
// baseline is replaced. These are labelled component sheets, not a live shell.
// Artwork comes ONLY from compiled production catalogues/renderers. Setup reads
// bundled fonts and actual Windows Segoe UI; translations are compiled English.
// No uploads, icon-pack assets, backend, filesystem fixtures or persisted KV.
const _appearances = ['light', 'dark', 'paper'];
const _locale = Locale('en', 'US');
const _capture = ValueKey('vivid-workspace-sheet');
const _catalogueSize = Size(1800, 1360);
const _chromeSize = Size(1600, 1160);
const _deadline = Duration(seconds: 10);
const _fontNotice = 'Fonts: bundled production DM Sans / Inter and actual '
    'Windows Segoe UI; Material loaded. No font substitution.';
const _categoryCounts = {
  'essentials': 56,
  'navigation': 8,
  'editing': 11,
  'data': 8,
  'work': 11,
  'security': 3,
  'learning': 10,
  'nature': 8,
  'travel': 7,
  'food': 9,
  'health': 8,
  'technology': 11,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = _Environment();

  group('Vivid workspace visual', () {
    setUpAll(() => environment.prepare().timeout(const Duration(seconds: 60)));
    tearDownAll(environment.restore);

    test('catalogue has 150 saved identities in 12 categories', () {
      final groups = appFlowyVividIconGroups;
      expect(groups, hasLength(12));
      expect(groups.map((group) => group.displayName), _categoryCounts.keys);
      expect(
        {for (final group in groups) group.displayName: group.icons.length},
        _categoryCounts,
      );
      final choices = _savedChoices();
      expect(choices, hasLength(150));
      expect(choices.map((choice) => choice.identity).toSet(), hasLength(150));
      expect(choices.map((choice) => choice.name).toSet(), hasLength(150));
      expect(choices.map((choice) => choice.artwork).toSet(), hasLength(150));
      for (final group in groups) {
        expect(group.packId, appFlowyVividIconPackId);
        expect(group.isColorful, isTrue);
        expect(iconPackForGroup(group.name), same(kVividIconPack));
      }
      for (final choice in choices) {
        expect(choice.name, isNot(startsWith('utility-')));
        expect(vividIconSvg(choice.name), choice.artwork);
        expect(
          findLoadedIcon(choice.group, choice.name)?.content,
          choice.artwork,
          reason: choice.identity,
        );
        final restored = IconsData.fromJson(
          jsonDecode(choice.saved.toEmojiIconData().emoji)
              as Map<String, dynamic>,
        );
        expect(restored.groupName, choice.group);
        expect(restored.iconName, choice.name);
        expect(restored.svgString, choice.artwork);
        // A stale saved tint must neither rewrite nor flatten a colorful pack.
        expect(restored.color, _SavedChoice.savedColor);
        choice.expectUnchanged();
      }
      expect(kVividIconPack.asset, isEmpty);
      expect(iconPacksVersion.value, 0);
      expect(isIconPackLoaded(kDefaultIconPack), isFalse);
    });

    test('all known defaults resolve; unknown stays excluded', () {
      final names =
          defaultIconNames.where((name) => name != 'unknown').toList();
      expect(names, isNotEmpty);
      for (final name in names) {
        final resolved = WorkspaceGlyphs.vividNameFor(name);
        expect(resolved, isNotNull, reason: name);
        final artwork = vividIconSvg(resolved!);
        expect(artwork, isNotNull, reason: '$name -> $resolved');
        expect(artwork, isNotEmpty, reason: '$name -> $resolved');
      }
      for (final name in ['unknown', 'not-a-known-default']) {
        expect(WorkspaceGlyphs.vividNameFor(name), isNull);
        expect(vividIconSvg('utility-$name'), isNull);
      }
      expect(_fieldNames.keys.toSet(), FieldType.values.toSet());
    });

    for (final appearance in _appearances) {
      testWidgets(
        'catalogue 32px - $appearance',
        (tester) async {
          final choices = _savedChoices();
          await _withSheet(
            tester,
            environment,
            appearance: appearance,
            size: _catalogueSize,
            child: _CatalogueSheet(appearance, choices),
            inspect: () async {
              expect(find.byType(RawEmojiIconWidget), findsNWidgets(150));
              expect(find.byType(IconWidget), findsNWidgets(150));
              expect(find.byType(SvgPicture), findsNWidgets(150));
              expect(find.byType(WorkspaceGlyph), findsNothing);
              final raster = await _readRaster(tester, find.byKey(_capture));
              final background = EditorSurfaceStyle.canvasBackground(
                tester.element(find.byKey(_capture)),
              );
              for (final group in appFlowyVividIconGroups) {
                final band = find.byKey(ValueKey('category-${group.name}'));
                _inside(tester, band, find.byKey(_capture));
                expect(
                  find.descendant(
                    of: band,
                    matching: find.byType(RawEmojiIconWidget),
                  ),
                  findsNWidgets(group.icons.length),
                );
              }
              for (final choice in choices) {
                final tile = find.byKey(ValueKey('tile-${choice.identity}'));
                final raw = find.byKey(ValueKey('saved-${choice.identity}'));
                _inside(tester, tile, find.byKey(_capture));
                _inside(tester, raw, tile);
                final widget = tester.widget<RawEmojiIconWidget>(raw);
                expect(widget.emojiSize, 32);
                expect(widget.opticalRole, isNull);
                expect(widget.emoji.emoji, choice.saved.value);
                expect(tester.getSize(raw), const Size.square(32));
                _expectPicture(tester, raw, choice.artwork);
                _expectPaintedPixels(
                  tester,
                  raster,
                  raw,
                  background,
                  reason: choice.identity,
                  minimumContrast: 1.2,
                  minimumPixels: 24,
                );
                choice.expectUnchanged();
              }
              await expectLater(
                find.byKey(_capture),
                matchesGoldenFile(
                  'goldens/vivid_workspace/catalogue_$appearance.png',
                ),
              );
            },
          );
          for (final choice in choices) {
            choice.expectUnchanged();
          }
        },
        timeout: const Timeout(Duration(seconds: 90)),
      );

      testWidgets(
        'chrome 16px and 18px - $appearance',
        (tester) async {
          // Presentation inputs only: no DatabaseController, service, viewId,
          // field-style registry, native listener or application startup.
          final fields = [
            for (final type in FieldType.values)
              FieldPB(
                id: 'visual-${type.name}',
                name: type.name,
                fieldType: type,
              ),
          ];
          final before = fields.map((field) => field.writeToBuffer()).toList();
          final editor = EditorState.blank()..disableSealTimer = true;
          final documentBefore = editor.document.toJson();
          try {
            await _withSheet(
              tester,
              environment,
              appearance: appearance,
              size: _chromeSize,
              child: _ChromeSheet(appearance, fields, editor),
              inspect: () async {
                _expectChrome(tester, fields);
                final raster = await _readRaster(tester, find.byKey(_capture));
                final background = EditorSurfaceStyle.canvasBackground(
                  tester.element(find.byKey(_capture)),
                );
                for (final sample in _actions) {
                  for (final size in [16.0, 18.0]) {
                    final finder = find.byKey(_smallKey(sample.name, size));
                    expect(tester.getSize(finder), Size.square(size));
                    _inside(tester, finder, find.byKey(_capture));
                    _expectPaintedPixels(
                      tester,
                      raster,
                      finder,
                      background,
                      reason:
                          '${sample.label} at ${size.toInt()}px / $appearance',
                    );
                    if (sample.palette != null) {
                      expect(
                        WorkspaceGlyphs.vividNameFor(sample.name),
                        'utility-${sample.name}',
                      );
                      // Capture the actual mounted glyph, without its label or
                      // background. Raw RGBA is transient; never write a PNG.
                      final pixels = await _readRaster(tester, finder);
                      _expectUtilityGradient(
                        pixels,
                        sample.palette!,
                        background,
                        '${sample.name} at ${size.toInt()}px / $appearance',
                      );
                    }
                  }
                }
                for (final field in fields) {
                  for (final size in [16.0, 18.0]) {
                    _expectPaintedPixels(
                      tester,
                      raster,
                      find.byKey(_fieldKey(field, size)),
                      background,
                      reason:
                          '${field.name} at ${size.toInt()}px / $appearance',
                    );
                  }
                }
                expect(editor.document.toJson(), documentBefore);
                await expectLater(
                  find.byKey(_capture),
                  matchesGoldenFile(
                    'goldens/vivid_workspace/chrome_$appearance.png',
                  ),
                );
              },
            );
          } finally {
            // _withSheet unmounts both real slash menus before this editor dies.
            editor.dispose();
            for (var index = 0; index < fields.length; index++) {
              expect(fields[index].writeToBuffer(), before[index]);
            }
          }
        },
        timeout: const Timeout(Duration(seconds: 90)),
      );
    }
  });
}

class _SavedChoice {
  _SavedChoice(this.group, this.name, this.artwork)
      : saved = ViewIconPB.fromBuffer(
          IconsData(group, name, savedColor)
              .toEmojiIconData()
              .toViewIcon()
              .writeToBuffer(),
        ) {
    before = saved.writeToBuffer();
  }

  static const savedColor = '4283665274';
  final String group;
  final String name;
  final String artwork;
  final ViewIconPB saved;
  late final List<int> before;
  String get identity => '$group/$name';
  void expectUnchanged() =>
      expect(saved.writeToBuffer(), before, reason: identity);
}

List<_SavedChoice> _savedChoices() => [
      for (final group in appFlowyVividIconGroups)
        for (final icon in group.icons)
          _SavedChoice(group.name, icon.name, icon.content),
    ];

class _CatalogueSheet extends StatelessWidget {
  const _CatalogueSheet(this.appearance, this.choices);
  final String appearance;
  final List<_SavedChoice> choices;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(
              'VIVID CATALOGUE · ${appearance.toUpperCase()}',
              '150 originals / 12 categories / 32px / actual RawEmojiIconWidget '
                  'rendering of saved group/name identities',
            ),
            for (final (index, group) in appFlowyVividIconGroups.indexed) ...[
              if (index != 0) const SizedBox(height: 16),
              Row(
                key: ValueKey('category-${group.name}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.displayName.toUpperCase(),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text('${group.icons.length} originals'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Four complete 14-column rows for Essentials. Every
                        // other category fits one row; no lazy/offscreen cells.
                        for (final choice in choices.where(
                          (choice) => choice.group == group.name,
                        ))
                          SizedBox(
                            key: ValueKey('tile-${choice.identity}'),
                            width: 104,
                            height: 64,
                            child: Column(
                              children: [
                                RawEmojiIconWidget(
                                  key: ValueKey('saved-${choice.identity}'),
                                  emoji: choice.saved.toEmojiIconData(),
                                  emojiSize: 32,
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 26,
                                  child: Text(
                                    choice.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall!
                                        .copyWith(
                                          fontSize: 11,
                                          height: 1.15,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Original AppFlowy vectors · no tint, substituted artwork, '
              'raster fixtures, picker-pack IO, or backend.',
            ),
          ],
        ),
      );
}

const _sidebarActions = [
  (SidebarIcon.search, 'Search'),
  (SidebarIcon.home, 'Home'),
  (SidebarIcon.bell, 'Notifications'),
  (SidebarIcon.newPage, 'New page'),
  (SidebarIcon.templates, 'Templates'),
  (SidebarIcon.extensions, 'Extensions'),
  (SidebarIcon.settings, 'Settings'),
];
const _sidebarPages = [
  (SidebarIcon.document, 'Reading notes'),
  (SidebarIcon.folder, 'Research folder'),
  (SidebarIcon.book, 'Book collection'),
  (SidebarIcon.calendar, 'Team calendar'),
  (SidebarIcon.repository, 'Source repository'),
];

final _fieldNames = <FieldType, String>{
  FieldType.RichText: 'text',
  FieldType.Number: 'hash',
  FieldType.DateTime: 'calendar-blank',
  FieldType.SingleSelect: 'select',
  FieldType.MultiSelect: 'list-checks',
  FieldType.Checkbox: 'checkbox',
  FieldType.URL: 'link-simple',
  FieldType.Checklist: 'list-checks',
  FieldType.LastEditedTime: 'clock',
  FieldType.CreatedTime: 'clock',
  FieldType.Relation: 'connections',
  FieldType.Summary: 'sparkles',
  FieldType.Time: 'clock',
  FieldType.Translate: 'translate',
  FieldType.Media: 'attachment',
};

class _ActionSample {
  const _ActionSample(this.label, this.icon, this.name, [this.palette]);
  final String label;
  final IconData icon;
  final String name;
  final _UtilityPalette? palette;
}

const _actions = [
  _ActionSample('Search', Icons.search_rounded, 'magnifying-glass'),
  _ActionSample('Settings', Icons.settings_rounded, 'gear'),
  _ActionSample('Notifications', Icons.notifications_rounded, 'bell'),
  _ActionSample('Home', Icons.home_rounded, 'house'),
  _ActionSample('Edit', Icons.edit_rounded, 'pen'),
  _ActionSample('Copy', Icons.copy_rounded, 'copy'),
  _ActionSample('Add', Icons.add_rounded, 'plus'),
  _ActionSample('Refresh', Icons.refresh_rounded, 'refresh'),
  _ActionSample(
    'Block grip',
    Icons.drag_indicator_rounded,
    'dots-six-vertical',
  ),
  _ActionSample('Download', Icons.download_rounded, 'download'),
  _ActionSample('Upload', Icons.upload_rounded, 'upload'),
  _ActionSample('History', Icons.history_rounded, 'history'),
  _ActionSample('Lock', Icons.lock_rounded, 'lock'),
  _ActionSample('Extensions', Icons.extension_rounded, 'puzzle-piece'),
  _ActionSample('Folder', Icons.folder_rounded, 'folder'),
  _ActionSample('Trash', Icons.delete_rounded, 'trash'),
  _ActionSample(
    'Back',
    Icons.arrow_back_rounded,
    'arrow-left',
    _UtilityPalette.navigation,
  ),
  _ActionSample('Forward', Icons.arrow_forward_rounded, 'arrow-right'),
  _ActionSample(
    'Check',
    Icons.check_rounded,
    'check',
    _UtilityPalette.confirmation,
  ),
  _ActionSample('Close', Icons.close_rounded, 'x', _UtilityPalette.danger),
  _ActionSample(
    'Bold',
    Icons.format_bold_rounded,
    'bold',
    _UtilityPalette.editing,
  ),
  _ActionSample(
    'Warning',
    Icons.warning_rounded,
    'warning',
    _UtilityPalette.caution,
  ),
  _ActionSample(
    'Line numbers',
    Icons.format_list_numbered_rounded,
    'line-numbers',
  ),
];

ValueKey<String> _smallKey(String name, double size) =>
    ValueKey('small-$name-${size.toInt()}');
ValueKey<String> _fieldKey(FieldPB field, double size) =>
    ValueKey('field-${field.id}-${size.toInt()}');

class _ChromeSheet extends StatelessWidget {
  const _ChromeSheet(this.appearance, this.fields, this.editor);
  final String appearance;
  final List<FieldPB> fields;
  final EditorState editor;

  @override
  Widget build(BuildContext context) {
    // Production entries and metadata, created only after localization is ready.
    // The real menu owns its rows, icon builders, focus and scroll controllers.
    final basic = registerSlashMenuSections([
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
    ]);
    final advanced = registerSlashMenuSections([
      SlashMenuSectionItems(
        section: SlashMenuSection.advanced,
        items: [
          quoteSlashMenuItem,
          codeBlockSlashMenuItem,
          dividerSlashMenuItem,
          twoColumnsSlashMenuItem,
          threeColumnsSlashMenuItem,
          fourColumnsSlashMenuItem,
          outlineSlashMenuItem,
        ],
      ),
      SlashMenuSectionItems(
        section: SlashMenuSection.database,
        items: [tableSlashMenuItem],
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            'VIVID WORKSPACE CHROME · ${appearance.toUpperCase()}',
            'Production presentation components / DefaultIconStyle.vivid / '
                'synthetic FieldPB only / no actions or backend',
          ),
          SizedBox(
            height: 730,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Specimen(
                  title: 'Sidebar',
                  description: 'Real navigation + page rows at 18px; '
                      'utility buttons at 16px.',
                  child: Theme(
                    data: SidebarStyle.themeData(context),
                    child: Builder(
                      builder: (context) => ColoredBox(
                        color: SidebarPalette.of(context).background,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (icon, label) in _sidebarActions)
                                SidebarNavItem(
                                  key: ValueKey('sidebar-${icon.name}'),
                                  icon: icon,
                                  label: label,
                                  selected: icon == SidebarIcon.home,
                                  shortcut: icon == SidebarIcon.search
                                      ? 'Ctrl+P'
                                      : null,
                                  onTap: _noAction,
                                ),
                              const SizedBox(height: 20),
                              const SidebarSectionLabel('Fixture pages'),
                              const SizedBox(height: 8),
                              for (final (icon, label) in _sidebarPages)
                                SidebarRow(
                                  key: ValueKey('page-${icon.name}'),
                                  reserveLeadingSpace: true,
                                  icon: SidebarGlyph(icon),
                                  label: SidebarText.page(label),
                                  onTap: _noAction,
                                ),
                              const SizedBox(height: 20),
                              const Row(
                                children: [
                                  SidebarIconButton(
                                    icon: SidebarIcon.settings,
                                    tooltip: 'Settings',
                                    onPressed: _noAction,
                                  ),
                                  SidebarIconButton(
                                    icon: SidebarIcon.bell,
                                    tooltip: 'Notifications',
                                    onPressed: _noAction,
                                  ),
                                  SidebarIconButton(
                                    icon: SidebarIcon.add,
                                    tooltip: 'Add',
                                    onPressed: _noAction,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                const _Specimen(
                  title: 'Context menu',
                  description: 'Real AppMenuRows; selected, highlighted, '
                      'disabled and destructive ink.',
                  child: AppMenuSurface(
                    key: ValueKey('context-menu'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppMenuSectionLabel(label: 'Page actions'),
                        AppMenuRow(
                          label: 'Open in new tab',
                          icon: Icons.open_in_new_rounded,
                          shortcut: 'Ctrl+Enter',
                        ),
                        AppMenuRow(
                          label: 'Rename',
                          icon: Icons.edit_rounded,
                          shortcut: 'F2',
                          highlighted: true,
                        ),
                        AppMenuRow(
                          label: 'Copy',
                          icon: Icons.copy_rounded,
                          shortcut: 'Ctrl+C',
                        ),
                        AppMenuRow(
                          label: 'Duplicate',
                          icon: Icons.control_point_duplicate_rounded,
                        ),
                        AppMenuRow(
                          label: 'Move to',
                          icon: Icons.drive_file_move_rounded,
                          hasSubmenu: true,
                        ),
                        AppMenuRow(
                          label: 'Pin to sidebar',
                          icon: Icons.push_pin_rounded,
                          selected: true,
                        ),
                        AppMenuSeparatorLine(),
                        AppMenuRow(
                          label: 'Version history',
                          icon: Icons.history_rounded,
                        ),
                        AppMenuRow(
                          label: 'Export',
                          icon: Icons.download_rounded,
                          hasSubmenu: true,
                        ),
                        AppMenuRow(
                          label: 'Locked destination',
                          icon: Icons.folder_rounded,
                          enabled: false,
                        ),
                        AppMenuRow(
                          label: 'Delete',
                          icon: Icons.delete_rounded,
                          destructive: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                _Specimen(
                  title: 'Slash menu',
                  description: 'Two real menus, eight actual items each. '
                      'Every row visible without scrolling.',
                  child: Column(
                    children: [
                      _slashMenu(context, 'slash-basic', basic),
                      const SizedBox(height: 24),
                      _slashMenu(context, 'slash-advanced', advanced),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                _Specimen(
                  title: 'Field types',
                  description: '${fields.length} native types, real FieldIcon '
                      'at 16 / 18px. Protobufs unchanged.',
                  child: Column(
                    children: [
                      for (final field in fields)
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              for (final size in [16.0, 18.0]) ...[
                                FieldIcon(
                                  key: _fieldKey(field, size),
                                  fieldInfo: FieldInfo.initial(field),
                                  dimension: size,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(child: Text(field.name)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'WorkspaceGlyph · 16px / 18px',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Actual-size pairs, left to right. Utility palettes: '
            'blue/violet navigation, teal/blue confirmation, rose close, '
            'violet/blue type, gold/coral warning.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final sample in _actions)
                SizedBox(
                  width: 178,
                  height: 40,
                  child: Row(
                    children: [
                      for (final size in [16.0, 18.0]) ...[
                        RepaintBoundary(
                          key: _smallKey(sample.name, size),
                          child: WorkspaceGlyph(sample.icon, size: size),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: Text(sample.label)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Component review only · fixture labels/constraints, production '
            'artwork and widgets · no screenshot or accessibility-conformance '
            'claim for the running app.',
          ),
        ],
      ),
    );
  }

  Widget _slashMenu(
    BuildContext context,
    String key,
    List<SelectionMenuItem> items,
  ) {
    final style = Theme.of(context).brightness == Brightness.dark
        ? SelectionMenuStyle.dark
        : SelectionMenuStyle.light;
    return AppFlowyDesktopSelectionMenuWidget(
      key: ValueKey(key),
      items: items,
      editorState: editor,
      // The real service is inert until show/activation; neither is called.
      menuService: AppFlowyDesktopSelectionMenu(
        context: context,
        editorState: editor,
        selectionMenuItems: items,
        style: style,
        deleteSlashByDefault: false,
      ),
      onExit: _noAction,
      onSelectionUpdate: _noAction,
      selectionMenuStyle: style,
      deleteSlashByDefault: false,
    );
  }
}

Never _noAction() => throw StateError('Visual fixture actions must not run.');

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.description);
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 88,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(description),
            Text(_fontNotice, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _Specimen extends StatelessWidget {
  const _Specimen({
    required this.title,
    required this.description,
    required this.child,
  });
  final String title;
  final String description;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 370,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      );
}

Future<void> _withSheet(
  WidgetTester tester,
  _Environment environment, {
  required String appearance,
  required Size size,
  required Widget child,
  required Future<void> Function() inspect,
}) =>
    environment.offline(() async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final styles = ValueNotifier(DefaultIconStyle.vivid);
      final holds = keepEditorFocusNotifier.value;
      final bundle = _NoAssets();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // Also intercept rootBundle, which external picker packs use directly.
      // Fonts are already loaded; generated translations require no asset IO.
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final data = message!;
        bundle.requests.add(
          utf8.decode(
            data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            ),
          ),
        );
        return null;
      });
      try {
        final theme = environment.themes[appearance]!;
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: bundle,
            child: EasyLocalization(
              supportedLocales: const [_locale],
              startLocale: _locale,
              fallbackLocale: _locale,
              path: 'compiled-English',
              saveLocale: false,
              assetLoader: const _English(),
              child: Builder(
                builder: (context) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  theme: theme,
                  themeAnimationDuration: Duration.zero,
                  builder: (context, child) => AppFlowyTheme(
                    data: PremiumTheme.appFlowyTheme(
                      base: theme.brightness == Brightness.dark
                          ? AppFlowyDefaultTheme().dark()
                          : AppFlowyDefaultTheme().light(),
                      palette: theme.extension<PremiumThemeExtension>()!,
                      brightness: theme.brightness,
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling,
                        disableAnimations: true,
                        accessibleNavigation: false,
                      ),
                      child: DefaultIconStyleScope(
                        styles: styles,
                        child: TooltipVisibility(
                          visible: false,
                          child: ExcludeFocus(
                            child: IgnorePointer(child: child),
                          ),
                        ),
                      ),
                    ),
                  ),
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => RepaintBoundary(
                        key: _capture,
                        child: ColoredBox(
                          color: EditorSurfaceStyle.canvasBackground(context),
                          child: SizedBox.fromSize(size: size, child: child),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _settlePictures(tester);
        expect(tester.getSize(find.byKey(_capture)), size);
        final context = tester.element(find.byKey(_capture));
        expect(DefaultIconStyleScope.of(context), same(styles));
        expect(PaperTheme.isEnabled(context), appearance == 'paper');
        if (appearance == 'paper') {
          expect(
            EditorSurfaceStyle.canvasBackground(context),
            PaperTheme.editorBackground,
          );
          expect(
            EditorSurfaceStyle.canvasBackground(context),
            isNot(Colors.white),
          );
        }
        environment.expectFonts(context);
        _expectCleanLayout(tester);
        await inspect();
        _expectCleanLayout(tester);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleFrames(tester);
          expect(keepEditorFocusNotifier.value, holds);
          expect(tester.takeException(), isNull);
        } finally {
          messenger.setMockMessageHandler('flutter/assets', null);
          styles.dispose();
        }
      }
      expect(
        bundle.requests,
        isEmpty,
        reason: 'Only setUpAll may read font assets.',
      );
      expect(environment.network.attempts, 0);
      expect(iconPacksVersion.value, 0);
      expect(WorkspaceGlyphs.unknownMappings, isEmpty);
      for (final pack in kIconPacks.where((pack) => pack.asset.isNotEmpty)) {
        expect(isIconPackLoaded(pack), isFalse, reason: pack.id);
      }
    });

class _Environment {
  final _previousFetching = GoogleFonts.config.allowRuntimeFetching;
  final _previousCacheSize = svg.cache.maximumSize;
  final network = _NoNetwork();
  final themes = <String, ThemeData>{};
  final families = <String>{};

  Future<T> offline<T>(Future<T> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, network);

  Future<void> prepare() => offline(() async {
        if (!Platform.isWindows) {
          throw StateError(
            'These six visual references require Windows Segoe UI.',
          );
        }
        GoogleFonts.config.allowRuntimeFetching = false;
        SharedPreferences.setMockInitialValues({});
        await EasyLocalization.ensureInitialized().timeout(_deadline);
        for (final appearance in _appearances) {
          themes[appearance] = DesktopAppearance()
              .getThemeData(
                appearance == 'paper'
                    ? AppTheme.builtins.firstWhere(
                        (theme) => theme.themeName == BuiltInTheme.paper,
                      )
                    : AppTheme.fallback,
                appearance == 'dark' ? Brightness.dark : Brightness.light,
                defaultFontFamily,
                builtInCodeFontFamily,
              )
              .copyWith(platform: TargetPlatform.windows);
        }
        for (final family in {
          preferredFontFamily,
          for (final theme in themes.values)
            theme.textTheme.bodyMedium!.fontFamily!,
        }) {
          if (family.split('_').first.replaceAll(' ', '') != 'DMSans') {
            throw StateError('No bundled production font mapping for $family.');
          }
          await _assetFont(family, const [
            'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
            'assets/google_fonts/DM_Sans/DMSans-VariableItalic.ttf',
          ]);
        }
        await _assetFont(bundledFontFamily, const [
          'assets/google_fonts/Inter/Inter-Variable.ttf',
          'assets/google_fonts/Inter/Inter-VariableItalic.ttf',
        ]);
        await _assetFont(builtInCodeFontFamily, const [
          'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf',
        ]);
        await _assetFont(
          'MaterialIcons',
          const ['fonts/MaterialIcons-Regular.otf'],
        );
        final family =
            SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows);
        expect(family, 'Segoe UI');
        final loader = FontLoader(family);
        final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        for (final file in [
          'segoeui.ttf',
          'seguisb.ttf',
          'segoeuib.ttf',
          'segoeuii.ttf',
        ]) {
          final bytes = await File('$windows/Fonts/$file')
              .readAsBytes()
              .timeout(_deadline);
          expect(bytes.length, greaterThan(1000));
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load().timeout(_deadline);
        families.add(family);

        // Precompile production strings on real time BEFORE any widget mounts.
        // The package cache normally holds only 100 entries; that would evict
        // part of this catalogue and restart compute under a paused fake clock.
        final sources = <String>{
          for (final group in appFlowyVividIconGroups)
            for (final icon in group.icons) icon.content,
          for (final name
              in defaultIconNames.where((name) => name != 'unknown'))
            _vividArtwork(name),
          for (final name in ['check', 'folder', 'trash'])
            defaultIconSvg(name)!,
        };
        svg.cache.maximumSize = math.max(
          _previousCacheSize,
          svg.cache.count + sources.length * 2 + 16,
        );
        for (final source in sources) {
          // SvgPicture and FlowySvg can use explicit or ambient default themes.
          for (final theme in const <SvgTheme?>[null, SvgTheme()]) {
            final bytes = await SvgStringLoader(source, theme: theme)
                .loadBytes(null)
                .timeout(_deadline);
            expect(bytes.lengthInBytes, greaterThan(0));
          }
        }
        expect(network.attempts, 0);
      });

  Future<void> _assetFont(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      final bytes = await rootBundle.load(asset).timeout(_deadline);
      expect(bytes.lengthInBytes, greaterThan(1000));
      loader.addFont(Future.value(bytes));
    }
    await loader.load().timeout(_deadline);
    families.add(family);
  }

  void expectFonts(BuildContext context) {
    final theme = Theme.of(context);
    expect(theme.platform, TargetPlatform.windows);
    expect(families, contains(theme.textTheme.bodyMedium!.fontFamily));
    expect(
      families,
      containsAll(['Segoe UI', bundledFontFamily, 'MaterialIcons']),
    );
    for (final family in families.where(
      (family) => family != 'MaterialIcons' && family != builtInCodeFontFamily,
    )) {
      expect(
        _textWidth('iiii', family),
        lessThan(_textWidth('WWWW', family)),
        reason: '$family must not silently fall back to Ahem.',
      );
    }
  }

  void restore() {
    GoogleFonts.config.allowRuntimeFetching = _previousFetching;
    svg.cache.maximumSize = _previousCacheSize;
  }
}

double _textWidth(String value, String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(fontFamily: family, fontSize: 16),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}

class _English extends AssetLoader {
  const _English();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) {
    if (locale.languageCode != 'en') {
      throw StateError('Unexpected fixture locale: $locale');
    }
    // Real generated copy; not IO and not SynchronousFuture (Future.wait drops
    // that synchronous result inside EasyLocalization's loader aggregation).
    return Future.value(CodegenLoader.en_US);
  }
}

class _NoAssets extends CachingAssetBundle {
  final requests = <String>[];
  @override
  Future<ByteData> load(String key) {
    requests.add(key);
    throw StateError('Unexpected visual-fixture asset read: $key');
  }
}

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Network is forbidden in Vivid visual review.');
  }
}

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 20),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _settlePictures(WidgetTester tester) async {
  await _settleFrames(tester);
  final pictures = find.byType(SvgPicture).evaluate().toList();
  expect(pictures, isNotEmpty);
  for (final element in pictures) {
    final loader =
        (element.widget as SvgPicture).bytesLoader as SvgStringLoader;
    final cached = svg.cache.putIfAbsent(
      loader.cacheKey(element),
      () =>
          throw StateError('A visual SVG was not precompiled before mounting.'),
    );
    expect(cached, isA<SynchronousFuture<ByteData>>());
  }
  // No tester.pump/expectLater/guarded UI operations inside runAsync. Never
  // await a fake-zone parse while fake time is paused; only decode warm bytes.
  await tester.runAsync(() async {
    for (final element in pictures) {
      final picture = element.widget as SvgPicture;
      final decoded = await _ownedUntilDeadline(
        vg.loadPicture(picture.bytesLoader, element),
        (value) => value.picture.dispose(),
      );
      decoded.picture.dispose();
    }
  });
  await _settleFrames(tester);
}

/// Release a resource even if the engine hands it back after the deadline.
Future<T> _ownedUntilDeadline<T>(Future<T> future, void Function(T) dispose) {
  var timedOut = false;
  return future.then((value) {
    if (timedOut) dispose(value);
    return value;
  }).timeout(
    _deadline,
    onTimeout: () {
      timedOut = true;
      throw TimeoutException(
        'Visual fixture engine resource deadline',
        _deadline,
      );
    },
  );
}

String _vividArtwork(String name) {
  final resolved = WorkspaceGlyphs.vividNameFor(name);
  final source = resolved == null ? null : vividIconSvg(resolved);
  if (source == null) throw StateError('Missing Vivid artwork for $name.');
  return source;
}

void _expectPicture(
  WidgetTester tester,
  Finder parent,
  String source, {
  ColorFilter? filter,
}) {
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: parent, matching: find.byType(SvgPicture)),
  );
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(loader.colorMapper, isNull);
  // Public loader equality includes the exact original string. No XML edits,
  // protected provideSvg access, source-file IO or shape replicas in this test.
  expect(loader, SvgStringLoader(source, theme: loader.theme));
  expect(picture.colorFilter, filter);
  expect(
    find.ancestor(of: parent, matching: find.byType(ColorFiltered)),
    findsNothing,
  );
  expect(
    find.ancestor(of: parent, matching: find.byType(ShaderMask)),
    findsNothing,
  );
}

void _expectChrome(WidgetTester tester, List<FieldPB> fields) {
  expect(find.byType(SidebarNavItem), findsNWidgets(_sidebarActions.length));
  expect(
    find.byType(SidebarRow),
    findsNWidgets(_sidebarActions.length + _sidebarPages.length),
  );
  expect(find.byType(SidebarIconButton), findsNWidgets(3));
  expect(find.byType(FieldIcon), findsNWidgets(fields.length * 2));
  expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNWidgets(2));
  expect(find.byType(AppMenuSurface), findsNWidgets(3));
  expect(find.byType(AppMenuRow), findsNWidgets(26));
  for (final (icon, _) in _sidebarActions) {
    final parent = find.byKey(ValueKey('sidebar-${icon.name}'));
    final glyph = tester.widget<WorkspaceGlyph>(
      find.descendant(of: parent, matching: find.byType(WorkspaceGlyph)),
    );
    expect(glyph.name, icon.name);
    expect(glyph.size, 18);
  }
  for (final field in fields) {
    for (final size in [16.0, 18.0]) {
      final parent = find.byKey(_fieldKey(field, size));
      final rendered = tester.widget<FieldIcon>(parent);
      expect(rendered.viewId, isNull);
      expect(rendered.fieldInfo.field, same(field));
      expect(field.icon, isEmpty);
      expect(tester.getSize(parent), Size.square(size));
      expect(
        tester
            .widget<WorkspaceGlyph>(
              find.descendant(
                of: parent,
                matching: find.byType(WorkspaceGlyph),
              ),
            )
            .name,
        _fieldNames[field.fieldType],
      );
    }
  }
  for (final (key, names) in [
    (
      'slash-basic',
      [
        'text',
        'heading-1',
        'heading-2',
        'heading-3',
        'bullets',
        'numbered-list',
        'checkbox',
        'toggle-list',
      ],
    ),
    (
      'slash-advanced',
      [
        'quote',
        'code',
        'divider',
        'columns-2',
        'columns-3',
        'columns-4',
        'rows',
        'table',
      ],
    ),
  ]) {
    final menu = find.byKey(ValueKey(key));
    final rows = find.descendant(of: menu, matching: find.byType(AppMenuRow));
    expect(rows, findsNWidgets(8));
    expect(
      tester
          .widgetList<WorkspaceGlyph>(
            find.descendant(of: menu, matching: find.byType(WorkspaceGlyph)),
          )
          .map((glyph) => glyph.name),
      names,
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: menu, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, 0);
    _inside(tester, menu, find.byKey(_capture));
    for (final element in rows.evaluate()) {
      _inside(tester, _elementFinder(element), menu);
    }
  }
  for (final element in find.byType(WorkspaceGlyph).evaluate()) {
    final glyph = element.widget as WorkspaceGlyph;
    final finder = _elementFinder(element);
    expect(glyph.style, isNull, reason: 'Use the scoped Vivid preference.');
    expect(glyph.name, isNot('unknown'));
    expect(tester.getSize(finder), Size.square(glyph.size));
    final scope = WorkspaceGlyphScope.maybeOf(element);
    final scopedInk = scope?.role == WorkspaceGlyphRole.preserveInk;
    final preserve = scopedInk || glyph.role == WorkspaceGlyphRole.preserveInk;
    _expectPicture(
      tester,
      finder,
      preserve ? defaultIconSvg(glyph.name)! : _vividArtwork(glyph.name),
      filter: preserve
          ? ColorFilter.mode(
              scopedInk
                  ? scope!.color
                  : glyph.color ?? workspaceGlyphInk(element),
              BlendMode.srcIn,
            )
          : null,
    );
    _inside(tester, finder, find.byKey(_capture));
  }
  for (final sample in _actions) {
    for (final size in [16.0, 18.0]) {
      final glyph = tester.widget<WorkspaceGlyph>(
        find.descendant(
          of: find.byKey(_smallKey(sample.name, size)),
          matching: find.byType(WorkspaceGlyph),
        ),
      );
      expect(glyph.name, sample.name);
      expect(glyph.size, size);
    }
  }
}

Finder _elementFinder(Element element) =>
    find.byElementPredicate((candidate) => identical(candidate, element));

void _expectCleanLayout(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: paragraph.text.toPlainText(),
    );
    _inside(tester, _elementFinder(element), find.byKey(_capture));
  }
}

void _inside(WidgetTester tester, Finder child, Finder parent) {
  expect(child, findsOneWidget);
  expect(parent, findsOneWidget);
  final bounds = tester.getRect(child);
  final frame = tester.getRect(parent);
  expect(tester.renderObject(child).attached, isTrue);
  expect(bounds.isFinite, isTrue);
  expect(bounds.isEmpty, isFalse);
  expect(bounds.left, greaterThanOrEqualTo(frame.left - 0.01));
  expect(bounds.top, greaterThanOrEqualTo(frame.top - 0.01));
  expect(bounds.right, lessThanOrEqualTo(frame.right + 0.01));
  expect(bounds.bottom, lessThanOrEqualTo(frame.bottom + 0.01));
}

class _Raster {
  const _Raster(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final ByteData bytes;

  Iterable<Color> colors(Rect rect) sync* {
    final left = rect.left.floor().clamp(0, width).toInt();
    final top = rect.top.floor().clamp(0, height).toInt();
    final right = rect.right.ceil().clamp(0, width).toInt();
    final bottom = rect.bottom.ceil().clamp(0, height).toInt();
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final offset = 4 * (y * width + x);
        yield Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }
    }
  }
}

Future<_Raster> _readRaster(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  expect(boundary.debugNeedsPaint, isFalse);
  final result = await tester.runAsync(() async {
    final image = await _ownedUntilDeadline(
      boundary.toImage(),
      (value) => value.dispose(),
    );
    try {
      final bytes = await image
          .toByteData(format: ui.ImageByteFormat.rawStraightRgba)
          .timeout(_deadline);
      if (bytes == null) {
        throw StateError('Engine returned no raw visual pixels.');
      }
      return _Raster(image.width, image.height, bytes);
    } finally {
      image.dispose();
    }
  });
  expect(result, isNotNull);
  expect(
    Size(result!.width.toDouble(), result.height.toDouble()),
    tester.getSize(finder),
  );
  return result;
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void _expectPaintedPixels(
  WidgetTester tester,
  _Raster raster,
  Finder glyph,
  Color background, {
  required String reason,
  double minimumContrast = 2,
  int minimumPixels = 4,
}) {
  final origin = tester.getTopLeft(find.byKey(_capture));
  final rect = tester.getRect(glyph).shift(-origin);
  final contrasting = raster
      .colors(rect)
      .where(
        (pixel) =>
            _contrast(Color.alphaBlend(pixel, background), background) >=
            minimumContrast,
      )
      .length;
  // A small-size silhouette/blank-paint guard, not a claim that every gradient
  // highlight meets WCAG 3:1. The actual golden still needs human review.
  expect(contrasting, greaterThanOrEqualTo(minimumPixels), reason: reason);
}

enum _UtilityPalette { navigation, confirmation, danger, editing, caution }

/// Independent, semantic palette expectations, NOT colors extracted from XML,
/// hash-derived hues, or a count of arbitrary differently antialiased pixels.
(Color, Color) _utilityStops(_UtilityPalette palette) => switch (palette) {
      _UtilityPalette.navigation => (
          const Color(0xFF489ECC),
          const Color(0xFF9365CD),
        ),
      _UtilityPalette.confirmation => (
          const Color(0xFF43C7A7),
          const Color(0xFF3277BD),
        ),
      _UtilityPalette.danger => (
          const Color(0xFFEA7893),
          const Color(0xFFBD486D),
        ),
      _UtilityPalette.editing => (
          const Color(0xFFAC79E0),
          const Color(0xFF527DDD),
        ),
      _UtilityPalette.caution => (
          const Color(0xFFE5B44F),
          const Color(0xFFD16D55),
        ),
    };

void _expectUtilityGradient(
  _Raster raster,
  _UtilityPalette palette,
  Color background,
  String reason,
) {
  final (start, end) = _utilityStops(palette);
  final pixels = raster
      .colors(
        Rect.fromLTWH(
          0,
          0,
          raster.width.toDouble(),
          raster.height.toDouble(),
        ),
      )
      // A 1.27px stroke on an integer boundary covers two pixels at ~63%.
      // Keep those real strokes, but discard the low-alpha fringe. Straight
      // RGBA and the segment-distance check prevent antialiasing from passing
      // a single tinted color off as a multi-hue gradient.
      .where((pixel) => pixel.a >= 0.6)
      .toList();
  expect(pixels.length, greaterThanOrEqualTo(8), reason: reason);
  final dr = end.r - start.r;
  final dg = end.g - start.g;
  final db = end.b - start.b;
  final lengthSquared = dr * dr + dg * dg + db * db;
  final hues = <int, int>{};
  var firstStop = double.infinity;
  var lastStop = double.negativeInfinity;
  var legible = 0;
  for (final pixel in pixels) {
    final t = ((pixel.r - start.r) * dr +
            (pixel.g - start.g) * dg +
            (pixel.b - start.b) * db) /
        lengthSquared;
    expect(t, inInclusiveRange(-0.04, 1.04), reason: reason);
    final error = [
      (pixel.r - (start.r + t * dr)).abs(),
      (pixel.g - (start.g + t * dg)).abs(),
      (pixel.b - (start.b + t * db)).abs(),
    ].reduce(math.max);
    expect(
      error,
      lessThan(0.025),
      reason: '$reason must use its semantic gradient, not a random tint.',
    );
    final hsv = HSVColor.fromColor(pixel);
    expect(hsv.saturation, greaterThan(0.2), reason: reason);
    // Rose intentionally has a small hue span; one-degree bins distinguish
    // its real ramp without pretending it should contain unrelated colors.
    hues.update(hsv.hue.floor(), (count) => count + 1, ifAbsent: () => 1);
    firstStop = math.min(firstStop, t);
    lastStop = math.max(lastStop, t);
    if (_contrast(Color.alphaBlend(pixel, background), background) >= 2.25) {
      legible++;
    }
  }
  expect(
    hues.values.where((count) => count >= 2).length,
    greaterThanOrEqualTo(2),
    reason: '$reason needs at least two populated hue bins.',
  );
  expect(
    lastStop - firstStop,
    greaterThan(0.2),
    reason: '$reason must paint a gradient, not one solid color.',
  );
  expect(
    legible,
    greaterThanOrEqualTo(4),
    reason: '$reason needs a contrasting small-size silhouette.',
  );
}
