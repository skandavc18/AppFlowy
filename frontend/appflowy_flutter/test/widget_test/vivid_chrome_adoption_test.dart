import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/column_heading_menu.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/desktop_field_cell.dart';
import 'package:appflowy/plugins/database/widgets/field/field_editor.dart';
import 'package:appflowy/plugins/database/widgets/field/property_type_picker.dart';
import 'package:appflowy/plugins/database/widgets/field/type_option_editor/date/date_time_format.dart';
import 'package:appflowy/plugins/database/widgets/field/type_option_editor/property_style_editor.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/desktop_selection_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_items.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/settings/notifications/notification_settings_cubit.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/move_to/workspace_destination_picker.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_more_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:appflowy/workspace/presentation/notifications/number_red_dot.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_button.dart';
import 'package:appflowy/workspace/presentation/settings/shared/setting_list_tile.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_input_field.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_workspace_layout.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/common_view_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/encrypt_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/font_size_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/page_versions_action.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/spell_check_page_action.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/reminder.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;
import 'workspace_overlay_test_app.dart';

const _appearances = ['light', 'dark', 'paper'];
const _styleCycle = [
  DefaultIconStyle.monochrome,
  DefaultIconStyle.vivid,
  DefaultIconStyle.monochrome,
];
const _swatch = Color(0xFFE08030);
late _Translations _translations;

void main() {
  setUpAll(() async {
    await initializeWorkspaceOverlayTests();
    _translations = _Translations(
      await const TestBundleAssetLoader().load(
        'assets/translations',
        const Locale('en', 'US'),
      ),
    );
  });

  for (final appearance in _appearances) {
    testWidgets('$appearance mounted sidebar and page chrome toggles live',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final view = _page('native-page');
      final original = view.writeToBuffer();
      final reminders = _Reminders();
      final home = _HomeSettings();
      final actions = <String>[];
      final queries = <String>[];
      var hostBuilds = 0;
      final semantics = tester.ensureSemantics();
      getIt.pushNewScope();
      getIt.registerSingleton<ReminderBloc>(reminders);
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            MultiBlocProvider(
              providers: [
                BlocProvider<HomeSettingBloc>.value(value: home),
                BlocProvider<NotificationSettingsCubit>.value(
                  value: _NotificationSettings(),
                ),
                BlocProvider<PageAccessLevelBloc>.value(
                  value: _PageAccess(view),
                ),
              ],
              child: Builder(
                builder: (context) {
                  hostBuilds++;
                  return Center(
                    child: SizedBox(
                      width: 480,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const SidebarSearchIcon(
                                key: ValueKey('legacy-search'),
                              ),
                              Expanded(
                                child: SidebarNavItem(
                                  key: const ValueKey('sidebar-search'),
                                  icon: SidebarIcon.search,
                                  label: 'Search',
                                  onTap: () => actions.add('search'),
                                ),
                              ),
                              SidebarIconButton(
                                key: const ValueKey('sidebar-settings'),
                                icon: SidebarIcon.settings,
                                onPressed: () => actions.add('settings'),
                              ),
                              const NotificationButton(
                                key: ValueKey('notifications'),
                              ),
                              SpaceMorePopup(
                                key: const ValueKey('space-options'),
                                space: view,
                                onAction: (_, __) {},
                                onEditing: (_) {},
                              ),
                              SettingsResetButton(
                                key: const ValueKey('reset'),
                                onResetRequested: () => actions.add('reset'),
                              ),
                              AppMenuIconButton(
                                key: const ValueKey('menu-trigger'),
                                icon: Icons.settings_rounded,
                                iconColor: Theme.of(context).hintColor,
                                entries: () => const [
                                  AppMenuItem(
                                    label: 'Copy',
                                    icon: Icons.copy_rounded,
                                  ),
                                ],
                              ),
                              BlockActionButton(
                                key: const ValueKey('block-trigger'),
                                svg: FlowySvgs.add_s,
                                showTooltip: false,
                                richMessage: const TextSpan(text: 'Add block'),
                                onTap: () => actions.add('block'),
                              ),
                            ],
                          ),
                          SpaceSearchField(
                            key: const ValueKey('space-search'),
                            width: 480,
                            onSearch: (_, query) => queries.add(query),
                          ),
                          const SettingsCategory(
                            key: ValueKey('category'),
                            title: 'Settings section',
                            tooltip: 'About this section',
                            children: [SizedBox.shrink()],
                          ),
                          const SettingsInputField(
                            key: ValueKey('settings-input'),
                            label: 'Name',
                            tooltip: 'Your display name',
                            value: 'Existing draft',
                            hideActions: true,
                          ),
                          SizedBox(
                            height: 100,
                            child: SettingsWorkspaceLayout(
                              key: const ValueKey('settings-layout'),
                              navigation: const SizedBox.shrink(),
                              navigationPicker: const Text('Settings'),
                              onClose: () => actions.add('close-settings'),
                              child: const SizedBox.shrink(),
                            ),
                          ),
                          CustomViewAction(
                            key: const ValueKey('page-custom'),
                            view: view,
                            leftIcon: FlowySvgs.copy_s,
                            label: 'Copy page',
                            onTap: () => actions.add('copy'),
                          ),
                          PageVersionsAction(
                            key: const ValueKey('page-history'),
                            view: view,
                          ),
                          EncryptPageAction(
                            key: const ValueKey('page-encryption'),
                            view: view,
                          ),
                          SpellCheckPageAction(
                            key: const ValueKey('page-spellcheck'),
                            view: view,
                          ),
                          LockPageAction(
                            key: const ValueKey('page-lock'),
                            view: view,
                          ),
                          const FontSizeAction(key: ValueKey('page-font')),
                          DateFormatButton(
                            key: const ValueKey('date-format'),
                            onTap: () => actions.add('date'),
                          ),
                          TimeFormatButton(
                            key: const ValueKey('time-format'),
                            onTap: () => actions.add('time'),
                          ),
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
        final search = find.descendant(
          of: _key('space-search'),
          matching: find.byType(EditableText),
        );
        await tester.enterText(search, 'Keep this query');
        final editable = tester.widget<EditableText>(search);
        editable.controller.selection =
            const TextSelection(baseOffset: 2, extentOffset: 8);
        await tester.pump();
        final editorState = tester.state(search);
        final clear = find.ancestor(
          of: _glyph(_key('space-search'), 'x'),
          matching: find.byType(CupertinoButton),
        );
        final clearElement = tester.element(clear);
        final clearBounds = tester.getRect(clear);
        final builds = hostBuilds;
        const expected = {
          'legacy-search': 'magnifying-glass',
          'sidebar-search': 'magnifying-glass',
          'sidebar-settings': 'gear',
          'notifications': 'bell',
          'space-options': 'dots-three',
          'reset': 'history',
          'menu-trigger': 'gear',
          'block-trigger': 'plus',
          'space-search': 'magnifying-glass',
          'category': 'info',
          'settings-input': 'info',
          'settings-layout': 'x',
          'page-custom': 'copy',
          'page-history': 'history',
          'page-encryption': 'shield',
          'page-spellcheck': 'spellcheck',
          'page-lock': 'lock',
          'page-font': 'text',
          'date-format': 'caret-down',
          'time-format': 'caret-down',
        };
        final elements = {
          for (final key in expected.keys) key: tester.element(_key(key)),
        };
        final rectangles = {
          for (final key in expected.keys) key: tester.getRect(_key(key)),
        };
        final switches = tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .map((control) => (control.value, control.activeTrackColor))
            .toList();
        expect(switches, hasLength(2));
        final badge = find.descendant(
          of: find.byType(NumberedRedDot),
          matching: find.byType(Container),
        );
        final badgeDecoration = tester.widget<Container>(badge).decoration;

        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (final entry in expected.entries) {
            _expectDefault(tester, _key(entry.key), entry.value, style);
            expect(tester.element(_key(entry.key)), same(elements[entry.key]));
            expect(tester.getRect(_key(entry.key)), rectangles[entry.key]);
          }
          _expectDefault(tester, _key('space-search'), 'x', style);
          expect(tester.element(clear), same(clearElement));
          expect(tester.getRect(clear), clearBounds);
          expect(hostBuilds, builds);
          expect(tester.state(search), same(editorState));
          expect(editable.controller.text, 'Keep this query');
          expect(
            editable.controller.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(
            tester
                .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
                .map((control) => (control.value, control.activeTrackColor))
                .toList(),
            switches,
          );
          expect(tester.widget<Container>(badge).decoration, badgeDecoration);
          expect(view.writeToBuffer(), original);
          expect(reminders.events, [const ReminderEvent.started()]);
          expect(home.events, isEmpty);
        }
        final settingsButton = find.descendant(
          of: _key('sidebar-settings'),
          matching: find.byType(IconButton),
        );
        final data = tester.getSemantics(settingsButton).getSemanticsData();
        expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        await tester.tap(settingsButton);
        await tester.tap(
          find.descendant(
            of: _key('notifications'),
            matching: find.byType(IconButton),
          ),
        );
        await tester.tap(_key('reset'));
        await tester.tap(_key('page-custom'));
        await tester.tap(_key('block-trigger'));
        await tester.tap(_key('settings-close'));
        await tester.pumpAndSettle();
        expect(
          actions,
          ['settings', 'reset', 'copy', 'block', 'close-settings'],
        );
        expect(home.events, [HomeSettingEvent.collapseNotificationPanel()]);
        expect(queries, ['Keep this query']);
        expect(clear.hitTestable(), findsOneWidget);
        // Cupertino's outer focus boundary is separate from its native
        // button semantics. Inspect the actual button node, not the wrapper.
        final clearNode = tester.getSemantics(
          find.descendant(
            of: clear,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.button == true,
            ),
          ),
        );
        expect(clearNode.attached, isTrue);
        final clearSemantics = clearNode.getSemanticsData();
        expect(clearSemantics.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(clearSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(
          clearSemantics.label,
          CupertinoLocalizations.of(clearElement).clearButtonLabel,
        );
        await tester.tap(clear);
        await tester.pump();
        expect(queries, ['Keep this query', '']);
        expect(editable.controller.text, isEmpty);
        expect(tester.state(search), same(editorState));
        expect(
          PaperTheme.isEnabled(tester.element(_key('category'))),
          appearance == 'paper',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await getIt.popScope();
        styles.dispose();
        semantics.dispose();
      }
    });

    testWidgets('$appearance disabled, locked and destructive ink is retained',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final view = _page('locked-page')..isLocked = true;
      final primary = FieldInfo.initial(
        FieldPB(id: 'primary', fieldType: FieldType.RichText, isPrimary: true),
      );
      final field = FieldInfo.initial(
        FieldPB(id: 'field', fieldType: FieldType.RichText),
      );
      var blockedCalls = 0;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(-10, -10));
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Center(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomViewAction(
                      key: const ValueKey('disabled-action'),
                      view: view,
                      leftIcon: FlowySvgs.document_s,
                      label: 'Read only',
                      disabled: true,
                      onTap: () => blockedCalls++,
                    ),
                    const SettingsResetButton(key: ValueKey('disabled-reset')),
                    AppMenuIconButton(
                      key: const ValueKey('disabled-trigger'),
                      icon: Icons.settings_rounded,
                      enabled: false,
                      entries: () {
                        blockedCalls++;
                        return const [AppMenuItem(label: 'Not reachable')];
                      },
                    ),
                    AppMenuIconButton(
                      key: const ValueKey('swatch-trigger'),
                      icon: Icons.palette_rounded,
                      iconColor: _swatch,
                      iconRole: WorkspaceGlyphRole.preserveInk,
                      entries: () => const [],
                    ),
                    LockPageButtonWrapper(
                      key: const ValueKey('locked-action'),
                      child: CustomViewAction(
                        view: view,
                        leftIcon: FlowySvgs.copy_s,
                        label: 'Locked copy',
                        onTap: () => blockedCalls++,
                      ),
                    ),
                    _sample(
                      'locked-native-row',
                      Builder(
                        builder: (context) => ViewMoreActionTypeWrapper(
                          ViewMoreActionType.rename,
                          view,
                          (_, __) => blockedCalls++,
                        ).buildWithContext(context, PopoverController(), null),
                      ),
                    ),
                    FieldActionCell(
                      key: const ValueKey('primary-duplicate'),
                      viewId: 'chrome-only',
                      fieldInfo: primary,
                      action: FieldAction.duplicate,
                    ),
                    FieldActionCell(
                      key: const ValueKey('field-delete'),
                      viewId: 'chrome-only',
                      fieldInfo: field,
                      action: FieldAction.delete,
                    ),
                    const AppMenuRow(
                      key: ValueKey('danger-row'),
                      label: 'Destructive folder',
                      icon: Icons.folder_rounded,
                      destructive: true,
                    ),
                    const AppMenuRow(
                      key: ValueKey('selected-row'),
                      label: 'Selected folder',
                      icon: Icons.folder_rounded,
                      selected: true,
                    ),
                    const AppMenuRow(
                      key: ValueKey('swatch-row'),
                      label: 'Explicit color sample',
                      iconWidget: WorkspaceGlyph(
                        Icons.palette_rounded,
                        color: _swatch,
                        role: WorkspaceGlyphRole.preserveInk,
                      ),
                      trailing: Icon(
                        Icons.radio_button_checked_rounded,
                        color: _swatch,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final theme = Theme.of(tester.element(_key('disabled-action')));
        final menuStyle = AppMenuStyle.of(tester.element(_key('danger-row')));
        final radio = find.descendant(
          of: _key('swatch-row'),
          matching: find.byIcon(Icons.radio_button_checked_rounded),
        );
        final radioElement = tester.element(radio);
        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectInk(tester, _key('disabled-action'), theme.disabledColor);
          _expectInk(tester, _key('disabled-reset'), theme.disabledColor);
          _expectInk(tester, _key('locked-action'), theme.disabledColor);
          _expectInk(tester, _key('primary-duplicate'), theme.disabledColor);
          _expectInk(
            tester,
            _key('disabled-trigger'),
            menuStyle.iconMuted.withValues(alpha: 0.5),
          );
          _expectInk(
            tester,
            _key('locked-native-row'),
            menuStyle.iconMuted.withValues(alpha: 0.5),
          );
          _expectInk(tester, _key('danger-row'), menuStyle.danger);
          _expectInk(tester, _key('swatch-trigger'), _swatch);
          _expectInk(tester, _key('swatch-row'), _swatch);
          _expectDefault(tester, _key('selected-row'), 'folder', style);
          _expectInk(
            tester,
            _glyph(_key('selected-row'), 'check'),
            menuStyle.icon,
          );
          expect(tester.element(radio), same(radioElement));
          expect(tester.widget<Icon>(radio).color, _swatch);
          await tester.tap(_key('disabled-action'));
          await tester.tap(_key('disabled-trigger'));
          await tester.tap(_key('primary-duplicate'));
          await tester.pump();
          expect(blockedCalls, 0);
          expect(find.byType(AppMenuSurface), findsNothing);
          final lockedRow = tester.widget<AppMenuRow>(
            find.descendant(
              of: _key('locked-native-row'),
              matching: find.byType(AppMenuRow),
            ),
          );
          expect(lockedRow.enabled, isFalse);
          await mouse.moveTo(tester.getCenter(_key('field-delete')));
          await tester.pumpAndSettle();
          _expectInk(tester, _key('field-delete'), theme.colorScheme.error);
          await mouse.moveTo(const Offset(-10, -10));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance file emphasis differs from status ink',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      var activated = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArchivePillButton(
                      key: const ValueKey('primary-file-action'),
                      icon: Icons.add_rounded,
                      label: 'Add files',
                      primary: true,
                      onPressed: () => activated++,
                    ),
                    const ArchivePillButton(
                      key: ValueKey('disabled-file-action'),
                      icon: Icons.add_rounded,
                      label: 'Add files',
                      primary: true,
                    ),
                    WorkspaceControlButton(
                      key: const ValueKey('normal-file-action'),
                      icon: Icons.search_rounded,
                      tooltip: 'Search',
                      onPressed: () => activated++,
                    ),
                    CodeToolbarButton(
                      key: const ValueKey('destructive-file-action'),
                      palette: CodeBlockPalette.resolve(context),
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      onPressed: () => activated++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final primary = _key('primary-file-action');
        final button = find.descendant(
          of: primary,
          matching: find.byType(TextButton),
        );
        final element = tester.element(button);
        final bounds = tester.getRect(button);
        final foreground = tester
            .widget<TextButton>(button)
            .style!
            .foregroundColor!
            .resolve({});
        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectDefault(tester, primary, 'plus', style);
          _expectDefault(
            tester,
            _key('normal-file-action'),
            'magnifying-glass',
            style,
          );
          _expectInk(
            tester,
            _key('disabled-file-action'),
            PremiumThemeExtension.of(element).textMuted,
          );
          _expectInk(
            tester,
            _key('destructive-file-action'),
            CodeBlockPalette.resolve(element).error,
          );
          expect(tester.element(button), same(element));
          expect(tester.getRect(button), bounds);
          expect(
            tester
                .widget<TextButton>(button)
                .style!
                .foregroundColor!
                .resolve({}),
            foreground,
          );
        }
        await tester.tap(button);
        await tester.tap(_key('disabled-file-action'));
        await tester.pump();
        expect(activated, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance real column menu and option states toggle live',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final field = FieldInfo.initial(
        FieldPB(
          id: 'primary-menu',
          fieldType: FieldType.RichText,
          isPrimary: true,
        ),
      );
      var edited = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) => AppMenuIconButton(
                  key: const ValueKey('column-menu-trigger'),
                  icon: Icons.settings_rounded,
                  entries: () => columnHeadingMenuEntries(
                    context: context,
                    viewId: 'no-backend-column-menu',
                    fieldInfo: field,
                    style:
                        const PropertyStyle(kind: PropertyStyleKind.progress),
                    isLocation: false,
                    onEditProperty: () => edited++,
                  ),
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        await tester.tap(_key('column-menu-trigger'));
        await settleVividIconPictures(tester);
        final edit = find.widgetWithText(
          AppMenuRow,
          LocaleKeys.grid_field_editProperty.tr(),
        );
        final propertyType = find.widgetWithText(
          AppMenuRow,
          LocaleKeys.interactive_property_type.tr(),
        );
        final wrap = find.widgetWithText(
          AppMenuRow,
          LocaleKeys.grid_field_wrapCellContent.tr(),
        );
        final editState = tester.state(edit);
        final editRect = tester.getRect(edit);
        final style = AppMenuStyle.of(tester.element(edit));
        final unchecked = find.descendant(
          of: wrap,
          matching: find.byIcon(Icons.check_box_outline_blank_rounded),
        );
        expect(unchecked, findsOneWidget);
        final uncheckedElement = tester.element(unchecked);
        final uncheckedInk = IconTheme.of(uncheckedElement).color;
        for (final choice in _styleCycle) {
          styles.value = choice;
          await settleVividIconPictures(tester);
          _expectDefault(tester, edit, 'sliders', choice);
          _expectInk(
            tester,
            _glyph(propertyType, 'gauge'),
            style.iconMuted.withValues(alpha: 0.5),
          );
          expect(tester.widget<AppMenuRow>(propertyType).enabled, isFalse);
          expect(tester.element(unchecked), same(uncheckedElement));
          expect(IconTheme.of(tester.element(unchecked)).color, uncheckedInk);
          expect(tester.state(edit), same(editState));
          expect(tester.getRect(edit), editRect);
          expect(
            DefaultIconStyleScope.of(tester.element(edit)),
            same(styles),
          );
          expect(
            find.descendant(of: wrap, matching: find.byType(WorkspaceGlyph)),
            findsNothing,
          );
          expect(propertyType.hitTestable(), findsOneWidget);
          await tester.tap(propertyType);
          await tester.pumpAndSettle();
          expect(edit, findsOneWidget);
          expect(edited, 0);
        }
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(edited, 1);
        expect(find.byType(AppMenuSurface), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance field defaults and native property toggles differ',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final fields = [
        for (final type in FieldType.values)
          FieldPB(id: type.name, name: type.name, fieldType: type),
      ];
      final originals = fields.map((field) => field.writeToBuffer()).toList();
      final writes = <Map<String, Object?>>[];
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Center(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final field in fields)
                          FieldIcon(
                            key: ValueKey('field-${field.id}'),
                            fieldInfo: FieldInfo.initial(field),
                          ),
                      ],
                    ),
                    PropertyStyleEditor(
                      viewId: 'no-backend-property',
                      fieldId: 'progress',
                      style:
                          const PropertyStyle(kind: PropertyStyleKind.progress),
                      onSettingsChanged: (settings) async =>
                          writes.add(settings),
                    ),
                    DateFormatCell(
                      dateFormat: DateFormatPB.ISO,
                      isSelected: true,
                      onSelected: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final property = find.byType(PropertyStyleEditor);
        final toggleIcons = find.descendant(
          of: property,
          matching: find.byType(Icon),
        );
        final toggleElements = toggleIcons.evaluate().toList();
        expect(toggleElements, hasLength(2));
        final toggleInk = [
          for (final element in toggleElements) IconTheme.of(element).color,
        ];
        final check = find.descendant(
          of: find.byType(DateFormatCell),
          matching: find.byType(FlowySvg),
        );
        final checkElement = tester.element(check);
        final checkWidget = tester.widget<FlowySvg>(check);
        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (var i = 0; i < fields.length; i++) {
            final parent = _key('field-${fields[i].id}');
            final glyph = tester.widget<WorkspaceGlyph>(
              find.descendant(
                of: parent,
                matching: find.byType(WorkspaceGlyph),
              ),
            );
            expect(glyph.name, isNot('unknown'), reason: fields[i].name);
            _expectDefault(tester, parent, glyph.name, style);
            expect(fields[i].writeToBuffer(), originals[i]);
          }
          _expectDefault(tester, property, 'ruler', style);
          _expectDefault(tester, property, 'spacing', style);
          expect(toggleIcons.evaluate().toList(), toggleElements);
          expect(
            [for (final element in toggleElements) IconTheme.of(element).color],
            toggleInk,
          );
          expect(tester.element(check), same(checkElement));
          expect(tester.widget<FlowySvg>(check).svg, checkWidget.svg);
          expect(tester.widget<FlowySvg>(check).color, checkWidget.color);
          expect(writes, isEmpty);
        }
        final firstToggle = find.ancestor(
          of: find.byWidget(toggleElements.first.widget),
          matching: find.byType(FlowyButton),
        );
        await tester.tap(firstToggle);
        await tester.pump();
        expect(writes, hasLength(1));
        expect(writes.single, {'show_buttons': false});
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance mounted slash and property picker keep state',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final editor = EditorState.blank()..disableSealTimer = true;
      final before = editor.document.toJson();
      final choices = <String>[];
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 330,
                  child: AppFlowyDesktopSelectionMenuWidget(
                    items: [
                      paragraphSlashMenuItem,
                      twoColumnsSlashMenuItem,
                      threeColumnsSlashMenuItem,
                      tableSlashMenuItem,
                      outlineSlashMenuItem,
                    ],
                    editorState: editor,
                    menuService: _SelectionMenu(),
                    onExit: () {},
                    onSelectionUpdate: () {},
                    selectionMenuStyle: SelectionMenuStyle.light,
                    deleteSlashByDefault: false,
                  ),
                ),
                SizedBox(
                  width: 310,
                  height: 520,
                  child: PropertyTypePicker(
                    selectedId: 'text',
                    onSelected: (choice) => choices.add(choice.id),
                  ),
                ),
              ],
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final slash = find.byType(AppFlowyDesktopSelectionMenuWidget);
        final picker = find.byType(PropertyTypePicker);
        final slashState = tester.state(slash);
        final pickerState = tester.state(picker);
        final search =
            find.descendant(of: picker, matching: find.byType(TextField));
        await tester.enterText(search, 'text');
        await tester.pumpAndSettle();
        final editable = find.descendant(
          of: picker,
          matching: find.byType(EditableText),
        );
        final searchState = tester.state(editable);
        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (final name in [
            'text',
            'columns-2',
            'columns-3',
            'table',
            'rows',
          ]) {
            _expectDefault(tester, slash, name, style);
          }
          _expectDefault(tester, picker, 'magnifying-glass', style);
          _expectDefault(tester, picker, 'text', style);
          expect(tester.state(slash), same(slashState));
          expect(tester.state(picker), same(pickerState));
          expect(tester.state(editable), same(searchState));
          expect(tester.widget<TextField>(search).controller!.text, 'text');
          expect(choices, isEmpty);
          expect(editor.document.toJson(), before);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(choices, ['text']);
        expect(editor.document.toJson(), before);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
        styles.dispose();
      }
    });

    testWidgets('$appearance saved icons and inline artwork bypass the style',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final previousGroups = kIconGroups;
      kIconGroups = appFlowyDefaultIconGroups;
      final saved = [
        EmojiIconData.emoji('📚'),
        IconsData('appflowy_default_collections', 'book', '4283665274')
            .toEmojiIconData(),
        IconsData('appflowy_vivid_essentials', 'rocket', null)
            .toEmojiIconData(),
      ];
      final field = FieldPB(
        id: 'chosen-field',
        fieldType: FieldType.RichText,
        icon: 'appflowy_default_collections/book',
      );
      final originalField = field.writeToBuffer();
      final savedIcons = saved.map((icon) => icon.toViewIcon()).toList();
      final originals = savedIcons.map((icon) => icon.writeToBuffer()).toList();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Center(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < saved.length; i++)
                      AppMenuRow(
                        key: ValueKey('saved-$i'),
                        label: 'Chosen $i',
                        destructive: true,
                        iconWidget: RawEmojiIconWidget(
                          emoji: saved[i],
                          emojiSize: 18,
                        ),
                      ),
                    AppMenuRow(
                      key: const ValueKey('inline-svg'),
                      label: 'Uploaded inline artwork',
                      enabled: false,
                      iconWidget: FlowySvg.string(
                        _inlineSvg,
                        blendMode: null,
                        size: const Size.square(18),
                      ),
                    ),
                    const AppMenuRow(
                      key: ValueKey('brand-svg'),
                      label: 'Brand artwork',
                      iconWidget: FlowySvg(
                        FlowySvgs.app_logo_s,
                        blendMode: null,
                      ),
                    ),
                    FieldIcon(fieldInfo: FieldInfo.initial(field)),
                  ],
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final rawStates = find
            .byType(RawEmojiIconWidget)
            .evaluate()
            .map((element) => (element as StatefulElement).state)
            .toList();
        final artwork = _savedArtwork(tester);
        expect(rawStates, hasLength(3));
        expect(artwork, hasLength(5));
        final library = find.descendant(
          of: _key('saved-1'),
          matching: find.byType(FlowySvg),
        );
        final colorful = find.descendant(
          of: _key('saved-2'),
          matching: find.byType(FlowySvg),
        );
        expect(tester.widget<FlowySvg>(library).color, const Color(0xFF538B7A));
        expect(tester.widget<FlowySvg>(library).blendMode, BlendMode.srcIn);
        expect(tester.widget<FlowySvg>(colorful).blendMode, isNull);
        expect(artwork.where((svg) => svg.$1 == _inlineSvg).single.$3, isNull);
        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          expect(find.byType(WorkspaceGlyph), findsNothing);
          expect(_savedArtwork(tester), artwork);
          expect(
            find
                .byType(RawEmojiIconWidget)
                .evaluate()
                .map((element) => (element as StatefulElement).state)
                .toList(),
            rawStates,
          );
          expect(_picture(tester, _key('inline-svg')).colorFilter, isNull);
          final logo = tester.widget<FlowySvg>(
            find.descendant(
              of: _key('brand-svg'),
              matching: find.byType(FlowySvg),
            ),
          );
          expect(logo.svg.path, FlowySvgs.app_logo_s.path);
          expect(logo.blendMode, isNull);
          for (var i = 0; i < savedIcons.length; i++) {
            expect(savedIcons[i].writeToBuffer(), originals[i]);
          }
          expect(field.writeToBuffer(), originalField);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        kIconGroups = previousGroups;
        styles.dispose();
      }
    });

    testWidgets('$appearance destination search keeps drafts and disabled ink',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final source = _page('source')..parentViewId = 'root';
      final folder = _page('folder')
        ..parentViewId = 'root'
        ..extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
      final table = ViewPB(
        id: 'table',
        name: 'Table',
        layout: ViewLayoutPB.Grid,
        parentViewId: 'root',
      );
      final repository = _Destinations([source, folder, table]);
      final originals =
          repository.views.map((view) => view.writeToBuffer()).toList();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            WorkspaceDestinationPicker(
              sourceViews: [source],
              rootId: 'root',
              rootName: 'Test workspace',
              rootIcon: '🌿',
              operation: WorkspaceDestinationOperation.move,
              repository: repository,
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final picker = find.byType(WorkspaceDestinationPicker);
        final state = tester.state(picker);
        final search = find.byType(TextField);
        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectDefault(tester, search, 'magnifying-glass', style);
          _expectDefault(
            tester,
            _key('workspace-destination-folder'),
            'folder',
            style,
          );
          final disabled = _key('workspace-destination-table');
          final glyph = _glyph(disabled, 'table');
          expect(tester.widget<InkWell>(disabled).onTap, isNull);
          final scope = WorkspaceGlyphScope.maybeOf(tester.element(glyph))!;
          expect(scope.role, WorkspaceGlyphRole.preserveInk);
          _expectInk(tester, disabled, scope.color);
          expect(tester.state(picker), same(state));
        }
        await tester.enterText(search, 'folder');
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        editable.controller.selection =
            const TextSelection(baseOffset: 1, extentOffset: 4);
        await tester.pump();
        styles.value = DefaultIconStyle.vivid;
        await settleVividIconPictures(tester);
        expect(editable.controller.text, 'folder');
        expect(
          editable.controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(editable.focusNode.hasFocus, isTrue);
        expect(repository.reads, 1);
        for (var i = 0; i < originals.length; i++) {
          expect(repository.views[i].writeToBuffer(), originals[i]);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));

Widget _sample(String name, Widget child) =>
    KeyedSubtree(key: ValueKey(name), child: child);

Finder _glyph(Finder parent, String name) => find.descendant(
      of: parent,
      matching: find.byWidgetPredicate(
        (widget) => widget is WorkspaceGlyph && widget.name == name,
      ),
    );

SvgPicture _picture(WidgetTester tester, Finder parent) =>
    tester.widget<SvgPicture>(
      find.descendant(of: parent, matching: find.byType(SvgPicture)),
    );

void _expectSource(SvgPicture picture, String source) {
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      source,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
}

void _expectDefault(
  WidgetTester tester,
  Finder parent,
  String name,
  DefaultIconStyle style,
) {
  final finder = _glyph(parent, name);
  expect(
    finder,
    findsOneWidget,
    reason: 'The mounted caller must route $name.',
  );
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  final context = tester.element(finder);
  final scope = WorkspaceGlyphScope.maybeOf(context);
  expect(glyph.role, isNot(WorkspaceGlyphRole.preserveInk));
  expect(scope?.role, isNot(WorkspaceGlyphRole.preserveInk));
  final vividName = style == DefaultIconStyle.vivid
      ? WorkspaceGlyphs.vividNameFor(name)
      : null;
  final illustration = vividName == null ? null : vividIconSvg(vividName);
  final picture = _picture(tester, finder);
  _expectSource(picture, illustration ?? defaultIconSvg(name)!);
  expect(
    picture.colorFilter,
    illustration != null
        ? null
        : ColorFilter.mode(
            style == DefaultIconStyle.vivid
                ? workspaceGlyphAccent(context)
                : glyph.color ?? scope?.color ?? workspaceGlyphInk(context),
            BlendMode.srcIn,
          ),
  );
}

void _expectInk(WidgetTester tester, Finder parent, Color color) {
  final glyphs = parent.evaluate().single.widget is WorkspaceGlyph
      ? parent
      : find.descendant(of: parent, matching: find.byType(WorkspaceGlyph));
  expect(glyphs, findsOneWidget);
  final glyph = tester.widget<WorkspaceGlyph>(glyphs);
  final picture = _picture(tester, glyphs);
  _expectSource(picture, defaultIconSvg(glyph.name)!);
  expect(picture.colorFilter, ColorFilter.mode(color, BlendMode.srcIn));
}

List<(String?, Color?, BlendMode?)> _savedArtwork(WidgetTester tester) => tester
    .widgetList<FlowySvg>(find.byType(FlowySvg))
    .map((svg) => (svg.svgString, svg.color, svg.blendMode))
    .toList();

ViewPB _page(String id) =>
    ViewPB(id: id, name: id, layout: ViewLayoutPB.Document);

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1400);
  addTearDown(tester.view.reset);
}

Widget _app(
  String appearance,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child,
) {
  final app = workspaceOverlayTestApp(
    appearance: appearance,
    child: DefaultIconStyleScope(styles: styles, child: child),
  ) as EasyLocalization;
  return EasyLocalization(
    supportedLocales: app.supportedLocales,
    path: app.path,
    fallbackLocale: app.fallbackLocale,
    useFallbackTranslations: app.useFallbackTranslations,
    saveLocale: false,
    assetLoader: _translations,
    child: app.child,
  );
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(english);
}

/// Only backend/host inputs are faked; NotificationButton and its badge remain
/// the actual mounted application components. No live preferences or timers.
class _Reminders extends Fake implements ReminderBloc {
  final events = <ReminderEvent>[];

  @override
  final state = ReminderState(reminders: [ReminderPB(id: 'unread')]);

  @override
  Stream<ReminderState> get stream => const Stream.empty();

  @override
  void add(ReminderEvent event) => events.add(event);
}

class _NotificationSettings extends Fake implements NotificationSettingsCubit {
  @override
  NotificationSettingsState get state => NotificationSettingsState.initial();

  @override
  Stream<NotificationSettingsState> get stream => const Stream.empty();
}

class _HomeSettings extends Fake implements HomeSettingBloc {
  final events = <HomeSettingEvent>[];

  @override
  final state = HomeSettingState(
    panelContext: null,
    workspaceSetting: WorkspaceLatestPB(workspaceId: 'chrome-workspace'),
    unauthorized: false,
    menuStatus: MenuStatus.expanded,
    isNotificationPanelCollapsed: true,
    isScreenSmall: false,
    hasColappsedMenuManually: false,
    resizeOffset: 0,
    resizeStart: 0,
    resizeType: MenuResizeType.slide,
  );

  @override
  Stream<HomeSettingState> get stream => const Stream.empty();

  @override
  void add(HomeSettingEvent event) => events.add(event);
}

class _PageAccess extends Fake implements PageAccessLevelBloc {
  _PageAccess(ViewPB view)
      : state = PageAccessLevelState.initial(view)
            .copyWith(isLoadingLockStatus: false);

  @override
  final PageAccessLevelState state;

  @override
  Stream<PageAccessLevelState> get stream => const Stream.empty();
}

class _SelectionMenu extends Fake implements SelectionMenuService {}

class _Destinations extends Fake implements WorkspaceItemRepository {
  _Destinations(this.views);

  final List<ViewPB> views;
  int reads = 0;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async {
    reads++;
    return FlowyResult.success(views);
  }
}

const _inlineSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path fill="#ff0000" d="M0 0h12v24H0z"/>'
    '<path fill="#0000ff" d="M12 0h12v24H12z"/></svg>';
