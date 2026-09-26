import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/dashboard_plugin.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_panel.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/cover_editor.dart'
    show CoverColorPicker;
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/cover_image_download.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'test_asset_bundle.dart';
import 'workspace_design_fixture.dart'
    show WorkspaceDesignAppearance, workspaceDesignTheme;

const _locale = Locale('en', 'US');
const _scrollKey = PageStorageKey('dashboard-workspace-scroll');
const _titleKey = ValueKey('dashboard-page-title');
const _noteId = 'workspace-dashboard-note';
const _title = 'My dashboard';
const _subtitle = 'A place for useful notes';
const _cover = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#D9C7A4',
);
const _note = DashboardWidgetSpec(
  id: _noteId,
  type: 'text',
  showTitle: false,
  placement: DashboardPlacement(columnSpan: 12, rowSpan: 6),
  settings: {'text': 'Saved dashboard note.'},
);
const _tail = DashboardWidgetSpec(
  id: 'workspace-dashboard-tail',
  type: 'spacer',
  showTitle: false,
  placement: DashboardPlacement(row: 24, columnSpan: 12),
);
const _document = DashboardDocument(
  subtitle: _subtitle,
  settings: DashboardSettings(
    maxWidth: 900,
    showControlBar: false,
    reduceMotion: true,
  ),
  sections: [
    DashboardSection(
      id: 'workspace-dashboard-section',
      widgets: [_note, _tail],
    ),
  ],
);
const _readingType = 'test.dashboard_workspace.retained_reading';
const _readingOwner = 'test.dashboard_workspace.retention';
const _draftKey = ValueKey('dashboard-retention-draft');
const _readingScrollKey = ValueKey('dashboard-retention-list');
const _away = Offset(-20, -20);

late Map<String, dynamic> _translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool runtimeFontsWereEnabled;
  late bool recentsWereEnabled;
  late bool sharedSectionWasEnabled;
  late _MemoryStorage storage;

  setUpAll(() async {
    runtimeFontsWereEnabled = GoogleFonts.config.allowRuntimeFetching;
    recentsWereEnabled = RecentIcons.enable;
    GoogleFonts.config.allowRuntimeFetching = false;
    RecentIcons.enable = false;
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      _locale,
    );
    final families = {
      for (final appearance in WorkspaceDesignAppearance.values)
        workspaceDesignTheme(appearance).textTheme.bodyMedium!.fontFamily!,
    };
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = runtimeFontsWereEnabled;
    RecentIcons.enable = recentsWereEnabled;
  });
  setUp(() async {
    // The real access predicate must see sharing enabled. Never replace it
    // with an assertion against that same predicate or initialize app prefs.
    sharedSectionWasEnabled = FeatureFlag.sharedSection.isOn;
    getIt.pushNewScope();
    storage = _MemoryStorage();
    getIt.registerSingleton<KeyValueStorage>(storage);
    await FeatureFlag.sharedSection.turnOn();
    storage.writes.clear();
    expect(FeatureFlag.sharedSection.isOn, isTrue);
  });
  tearDown(() async {
    try {
      expect(
        storage.writes,
        isEmpty,
        reason: 'No dashboard preference writes.',
      );
    } finally {
      await FeatureFlag.sharedSection.update(sharedSectionWasEnabled);
      await getIt.popScope();
    }
  });

  test('preloaded dashboard translations survive loader aggregation', () async {
    final loaded = await Future.wait([
      _LoadedTranslations(_translations).load('assets/translations', _locale),
    ]);
    expect(loaded, hasLength(1));
    expect(loaded.single, same(_translations));
    expect(loaded.single['dashboard'], isA<Map<String, dynamic>>());
  });

  for (final appearance in WorkspaceDesignAppearance.values) {
    testWidgets('${appearance.name}: identity and board share one page scroll',
        (tester) async {
      _viewport(tester);
      final controller = _controller();
      final view = _view();
      try {
        await tester.pumpWidget(_app(appearance, _page(view, controller)));
        await _settle(tester);
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(find.byType(WorkspacePageHeader), findsOneWidget);
        expect(find.byType(WorkspacePageIdentity), findsOneWidget);
        expect(find.text(_subtitle), findsOneWidget);
        final pageState = tester.state(find.byType(DashboardPage));
        final cardState = tester.state(_card(_noteId));
        final scroll = _pageScroll(tester);
        expect(
          Scrollable.of(tester.element(find.byType(DashboardBoard))),
          same(scroll),
        );
        for (final child in [
          find.byType(WorkspacePageHeader),
          find.byType(DashboardBoard),
        ]) {
          expect(
            find.ancestor(
              of: child,
              matching: find.byType(SingleChildScrollView),
            ),
            findsOneWidget,
          );
        }
        _expectReadingEdges(tester);
        final title = tester.getRect(find.byKey(_titleKey));
        final icon = tester.getRect(find.byType(RawEmojiIconWidget));
        expect(icon.bottom, lessThan(title.top));
        expect(icon.left, closeTo(title.left, 0.01));
        expect(
          tester.getTopLeft(find.text(_subtitle)).dy,
          greaterThan(title.bottom),
        );
        final identity = tester.getRect(find.byType(WorkspacePageIdentity));
        final viewport = tester.getRect(find.byKey(_scrollKey));
        final distance = identity.bottom - viewport.top + 80;
        expect(scroll.position.maxScrollExtent, greaterThan(distance));

        // Drive the real page position, not an extra fixture scroll wrapper.
        scroll.position.jumpTo(distance);
        await _settle(tester);
        expect(
          tester.getBottomLeft(find.byType(WorkspacePageIdentity)).dy,
          lessThan(viewport.top),
        );
        expect(find.byKey(_titleKey).hitTestable(), findsNothing);
        expect(_pageScroll(tester), same(scroll));
        expect(tester.state(find.byType(DashboardPage)), same(pageState));
        expect(tester.state(_card(_noteId)), same(cardState));
        expect(controller.document, same(_document));
        scroll.position.jumpTo(0);
        await _settle(tester);
        expect(find.byKey(_titleKey).hitTestable(), findsOneWidget);
        _expectReadingEdges(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });

    testWidgets(
        '${appearance.name}: narrow and scaled pages keep reading edges',
        (tester) async {
      _viewport(tester);
      final controller = _controller();
      final view = _view(hasCover: true);
      try {
        await tester.pumpWidget(_app(appearance, _page(view, controller)));
        await _settle(tester);
        final pageState = tester.state(find.byType(DashboardPage));
        final canvasState = tester.state(find.byType(DashboardCanvas));
        for (final (width, scale) in [
          (1440.0, 1.0),
          (760.0, 2.0),
          (560.0, 2.0),
          (320.0, 2.0),
          (1440.0, 1.0),
        ]) {
          tester.view.physicalSize = Size(width, 1000);
          await tester.pumpWidget(
            _app(appearance, _page(view, controller), textScale: scale),
          );
          await _settle(tester);
          _expectReadingEdges(tester);
          final frame = tester.getRect(find.byType(DashboardPage));
          for (final finder in [
            find.byType(WorkspacePageIdentity),
            find.byType(ViewCoverImage),
            find.byType(DashboardBoard),
            _card(_noteId),
          ]) {
            final rect = tester.getRect(finder);
            expect(rect.width, greaterThan(0));
            expect(rect.height.isFinite, isTrue);
            expect(rect.left, greaterThanOrEqualTo(frame.left - 0.01));
            expect(rect.right, lessThanOrEqualTo(frame.right + 0.01));
          }
          expect(
            MediaQuery.textScalerOf(tester.element(find.byKey(_titleKey)))
                .scale(10),
            10 * scale,
          );
          expect(tester.state(find.byType(DashboardPage)), same(pageState));
          expect(tester.state(find.byType(DashboardCanvas)), same(canvasState));
          expect(controller.document.settings.maxWidth, 900);
          expect(controller.document, same(_document));
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });

    testWidgets(
        '${appearance.name}: the saved cover and optional profile reach the header',
        (tester) async {
      _viewport(tester);
      final controller = _controller();
      final view = _view(hasCover: true);
      final saved = view.writeToBuffer();
      final profile = UserProfilePB();
      try {
        for (final user in [null, profile]) {
          await tester.pumpWidget(
            _app(appearance, _page(view, controller, userProfile: user)),
          );
          await _settle(tester);
          final cover =
              tester.widget<ViewCoverImage>(find.byType(ViewCoverImage));
          expect(cover.cover, _cover);
          expect(cover.userProfile, same(user));
          expect(
            tester
                .widget<ColoredBox>(
                  find.descendant(
                    of: find.byType(ViewCoverImage),
                    matching: find.byType(ColoredBox),
                  ),
                )
                .color,
            const Color(0xFFD9C7A4),
            reason: 'A fallback surface is not the saved cover.',
          );
          final decoration = tester.widget<ViewDecorationActions>(
            find.byType(ViewDecorationActions),
          );
          expect(decoration.userProfile, same(user));
          final coverRect = tester.getRect(find.byType(ViewCoverImage));
          final identityRect =
              tester.getRect(find.byType(WorkspacePageIdentity));
          expect(coverRect.width, greaterThan(identityRect.width));
          _expectCoveredHeaderGeometry(tester);
          expect(
            PaperTheme.isEnabled(tester.element(find.byType(DashboardPage))),
            appearance == WorkspaceDesignAppearance.paper,
          );
          expect(view.writeToBuffer(), saved);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });

    testWidgets(
      '${appearance.name}: compact header regions reveal without granting access',
      (tester) async {
        _viewport(tester);
        final controller = _DraftController(_document);
        final view = _view(hasCover: true)..id = 'dashboard-header-access';
        view.extra = ViewCoverCodec.mergeCover(
          view.extra,
          const PageStyleCover(
            type: PageStyleCoverImageType.builtInImage,
            value: 'n1',
          ),
        );
        final saved = view.writeToBuffer();
        final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _away);
        try {
          await tester.pumpWidget(
            _app(appearance, _page(view, controller, access: access)),
          );
          await _settle(tester);
          final context = tester.element(find.byType(DashboardPage));
          final translations =
              _translations['dashboard'] as Map<String, dynamic>;
          final optionsLabel = translations['options'] as String;
          expect(optionsLabel, isNotEmpty);
          expect(context.locale, _locale);
          expect(Localizations.localeOf(context), _locale);
          expect(context.tr(LocaleKeys.dashboard_options), optionsLabel);
          expect(LocaleKeys.dashboard_options.tr(), optionsLabel);

          final row = _headerActions();
          var rowElement = tester.element(row);
          final iconActions = _headerIconActions();
          final cover = find.byType(WorkspacePageCover);
          final coverImage = find.byType(ViewCoverImage);
          final coverElement = tester.element(coverImage);
          final coverButtons = _nativeButtons(cover);
          final titleIcon = _nativeTextButton(
            find.byKey(const ValueKey('workspace-page-icon')),
          );
          final decorationState = tester.state(_headerDecorations());
          final pageState = tester.state(find.byType(DashboardPage));
          final canvasState = tester.state(find.byType(DashboardCanvas));
          final cardState = tester.state(_card(_noteId));
          final fieldState = tester.state(_draftField('text'));
          final before = tester.getRect(row);
          final cardBefore = tester.getRect(_card(_noteId));
          final headerBefore = tester.getRect(find.byType(WorkspacePageHeader));
          final iconRowBefore = tester.getRect(
            find.byKey(const ValueKey('workspace-page-icon-row')),
          );
          expect(
            find.descendant(of: row, matching: find.byType(PreviewToolbar)),
            findsOneWidget,
          );
          final wrap = find.descendant(of: row, matching: find.byType(Wrap));
          expect(wrap, findsOneWidget);
          expect(tester.widget<Wrap>(wrap).children, hasLength(2));
          expect(
            find.descendant(
              of: row,
              matching: find.byType(SingleChildScrollView),
            ),
            findsNothing,
          );
          expect(_headerActionButtons(), findsNWidgets(2));
          expect(_nativeButtons(iconActions), findsOneWidget);
          expect(coverButtons, findsNWidgets(3));
          _expectCoveredHeaderGeometry(tester);
          expect(_toolbarOpacity(tester, iconActions), 0);
          expect(_toolbarOpacity(tester, cover), 0);
          expect(_nativeButtons(iconActions).hitTestable(), findsNothing);
          expect(coverButtons.hitTestable(), findsNothing);
          expect(titleIcon.hitTestable(), findsOneWidget);
          _expectNativeButton(tester, titleIcon);
          expect(
            find.byKey(const ValueKey('view-decoration-remove')),
            findsOneWidget,
          );
          _expectPageAccess(tester, controller, readOnly: false);

          void expectRetained() {
            expect(tester.state(_headerDecorations()), same(decorationState));
            expect(tester.state(find.byType(DashboardPage)), same(pageState));
            expect(
              tester.state(find.byType(DashboardCanvas)),
              same(canvasState),
            );
            expect(tester.state(_card(_noteId)), same(cardState));
            expect(tester.state(_draftField('text')), same(fieldState));
            expect(tester.element(coverImage), same(coverElement));
            expect(tester.widget<ViewCoverImage>(coverImage).cover, view.cover);
            expect(controller.document, same(_document));
            expect(controller.editAttempts, 0);
            expect(controller.flushAttempts, 0);
            expect(controller.canUndo, isFalse);
            expect(controller.canRedo, isFalse);
            expect(view.writeToBuffer(), saved);
            expect(storage.writes, isEmpty);
            expect(access.isClosed, isFalse);
          }

          void expectReveal(bool visible) {
            expect(tester.element(row), same(rowElement));
            expect(_headerToolbarOpacity(tester), visible ? 1 : 0);
            expect(
              _headerActionButtons().hitTestable(),
              visible ? findsNWidgets(2) : findsNothing,
            );
            expect(_semanticsHasTooltip(tester, optionsLabel), visible);
            expect(tester.getRect(row), before);
            expect(tester.getRect(_card(_noteId)), cardBefore);
            expect(
              tester.getRect(find.byType(WorkspacePageHeader)),
              headerBefore,
            );
            expectRetained();
          }

          void expectDecorationReveal({
            required bool iconVisible,
            required bool coverVisible,
          }) {
            expect(_toolbarOpacity(tester, iconActions), iconVisible ? 1 : 0);
            expect(_toolbarOpacity(tester, cover), coverVisible ? 1 : 0);
            expect(
              _nativeButtons(iconActions).hitTestable(),
              iconVisible ? findsOneWidget : findsNothing,
            );
            expect(
              coverButtons.hitTestable(),
              coverVisible ? findsNWidgets(3) : findsNothing,
            );
          }

          expectReveal(false);
          // The entire header reveals identity/page tools, not just the icon
          // row. Only entering the picture also reveals image-local tools.
          for (final (point, overCover) in [
            (tester.getCenter(_nativeIconButton(_headerOptions())), false),
            (tester.getCenter(find.byKey(_titleKey)), false),
            (tester.getCenter(find.text(_subtitle)), false),
            // The desktop scrollbar owns the outer edge. Exercise the empty
            // header margin beyond the reading measure, not its scroll track.
            (headerBefore.bottomRight - const Offset(32, 4), false),
            (tester.getCenter(cover), true),
          ]) {
            expect(headerBefore.contains(point), isTrue);
            expect(iconRowBefore.contains(point), isFalse);
            await mouse.moveTo(point);
            await _settle(tester);
            expect(
              _headerToolbarOpacity(tester),
              1,
              reason: 'Header hover at $point inside $headerBefore '
                  '(cover=$overCover) must reveal page tools.',
            );
            expectReveal(true);
            expectDecorationReveal(iconVisible: true, coverVisible: overCover);
            for (final element in _headerActionButtons().evaluate()) {
              _expectNativeButton(tester, find.byWidget(element.widget));
            }
            await mouse.moveTo(_away);
            await _settle(tester);
            expectReveal(false);
            expectDecorationReveal(iconVisible: false, coverVisible: false);
          }

          // Exercise both ends of the actual icon, including the 22px over
          // the image. Popups hold their region AND its header ancestors.
          final iconRect = tester.getRect(titleIcon);
          final changeCover = _nativeTextButton(
            find.byKey(const ValueKey('view-decoration-cover')),
          );
          for (final (trigger, point, isCover) in [
            (
              titleIcon,
              Offset(iconRect.center.dx, iconRect.top + 2),
              false,
            ),
            (
              titleIcon,
              Offset(iconRect.center.dx, iconRect.bottom - 2),
              false,
            ),
            (
              _nativeButtons(iconActions),
              tester.getCenter(_nativeButtons(iconActions)),
              false,
            ),
            (changeCover, tester.getCenter(changeCover), true),
          ]) {
            await mouse.moveTo(point);
            await _settle(tester);
            expectReveal(true);
            expectDecorationReveal(iconVisible: true, coverVisible: isCover);
            final localButtons =
                isCover ? coverButtons : _nativeButtons(iconActions);
            expect(
              localButtons.hitTestable(),
              isCover ? findsNWidgets(3) : findsOneWidget,
            );
            for (final element in localButtons.evaluate()) {
              _expectNativeButton(tester, find.byWidget(element.widget));
            }
            final picker =
                find.byType(isCover ? UploadImageMenu : FlowyIconEmojiPicker);
            final popover = tester.state<PopoverState>(
              find.ancestor(of: trigger, matching: find.byType(Popover)).first,
            );
            Future<void> pumpPicker() async {
              // The emoji tab loads through rootBundle, not TestAssetBundle,
              // and intentionally spins while EmojiData.builtIn is pending.
              // Bound the 140ms toolbar reveal (zero with reduced motion),
              // not asset completion. These popovers have no entrance tween.
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 140));
              expect(tester.takeException(), isNull);
              expect(find.byType(ErrorWidget), findsNothing);
              expect(PopoverState.rootEntry.contains(popover), isTrue);
              expect(popover.animationController.isAnimating, isFalse);
              expect(picker, findsOneWidget);
              expect(
                find.byType(isCover ? FlowyIconEmojiPicker : UploadImageMenu),
                findsNothing,
              );
              final context = tester.element(picker);
              expect(context.mounted, isTrue);
              expect(FocusScope.of(context).hasFocus, isTrue);
              final tabs = find.descendant(
                of: picker,
                matching: find.byType(TabBar),
              );
              expect(tabs.hitTestable(), findsOneWidget);
              expect(tester.widget<TabBar>(tabs).onTap, isNotNull);
              if (isCover) {
                expect(
                  tester.widget<UploadImageMenu>(picker).supportTypes.first,
                  UploadImageType.color,
                );
                expect(
                  DefaultTabController.of(tester.element(tabs)).index,
                  0,
                );
                final colors = find.descendant(
                  of: picker,
                  matching: find.byType(CoverColorPicker),
                );
                expect(colors, findsOneWidget);
                expect(
                  find
                      .descendant(of: colors, matching: find.byType(InkWell))
                      .hitTestable(),
                  findsWidgets,
                );
              } else {
                expect(
                  tester.widget<FlowyIconEmojiPicker>(picker).initialType,
                  PickerTabType.emoji,
                );
                expect(tester.widget<TabBar>(tabs).controller!.index, 0);
                final remove = find.descendant(
                  of: picker,
                  matching: find.widgetWithText(
                    FlowyButton,
                    LocaleKeys.button_remove.tr(),
                  ),
                );
                expect(remove.hitTestable(), findsOneWidget);
                expect(tester.widget<FlowyButton>(remove).onTap, isNotNull);
              }
            }

            await tester.tapAt(point, kind: PointerDeviceKind.mouse);
            await pumpPicker();
            final pickerElement = tester.element(picker);
            await mouse.moveTo(_away);
            await pumpPicker();
            expect(tester.element(picker), same(pickerElement));
            expect(_toolbarOpacity(tester, iconActions), 1);
            expect(_toolbarOpacity(tester, cover), isCover ? 1 : 0);
            expect(_headerToolbarOpacity(tester), 1);
            expectRetained();
            tester
                .widget<AppFlowyPopover>(
                  find
                      .ancestor(
                        of: trigger,
                        matching: find.byType(AppFlowyPopover),
                      )
                      .first,
                )
                .controller!
                .close();
            // Quiescence is required again once the intentional loader is
            // removed, so leaked tickers or a real reveal loop still fail.
            await _settle(tester);
            expect(PopoverState.rootEntry.isEmpty, isTrue);
            expect(picker, findsNothing);
            expect(pickerElement.mounted, isFalse);
            await _focusPage(tester);
            expect(_toolbarOpacity(tester, iconActions), 0);
            expect(_toolbarOpacity(tester, cover), 0);
            expectReveal(false);
          }

          await _tabTo(tester, _nativeTextButton(_headerAdd()));
          expectReveal(true);
          // Keyboard focus reveals its toolbar, unlike header-wide hover.
          expectDecorationReveal(iconVisible: false, coverVisible: false);
          await _focusPage(tester);
          expectReveal(false);
          final options = _nativeIconButton(_headerOptions());
          await mouse.moveTo(tester.getCenter(options));
          await _settle(tester);
          expect(options.hitTestable(), findsOneWidget);
          await mouse.down(tester.getCenter(options));
          await mouse.up();
          await mouse.moveTo(_away);
          await _settle(tester);
          // The real popup, not a forced keepVisible flag, holds the whole row
          // after the pointer has left and the menu owns focus.
          expect(_headerToolbarOpacity(tester), 1);
          expect(_toolbarOpacity(tester, iconActions), 1);
          expect(_toolbarOpacity(tester, cover), 0);
          expect(tester.getRect(row), before);
          expectRetained();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester);
          expect(find.byType(AppMenuSurface), findsNothing);
          await _focusPage(tester);
          expectReveal(false);

          for (final (level, locked) in [
            (ShareAccessLevel.readOnly, false),
            (ShareAccessLevel.fullAccess, true),
          ]) {
            access.change(level, locked: locked);
            await _settle(tester);
            _expectPageAccess(tester, controller, readOnly: true);
            // The empty page row disappears, but the action owner remains.
            // Hovering the image reveals only the non-mutating download.
            expect(row, findsNothing);
            expect(
              find.byKey(const ValueKey('workspace-page-actions')),
              findsNothing,
            );
            expect(iconActions, findsNothing);
            expect(titleIcon, findsNothing);
            await mouse.moveTo(tester.getCenter(find.byKey(_titleKey)));
            await _settle(tester);
            expect(_toolbarOpacity(tester, cover), 0);
            expect(coverButtons.hitTestable(), findsNothing);
            _expectPageAccess(tester, controller, readOnly: true);
            expectRetained();
            await mouse.moveTo(tester.getCenter(cover));
            await _settle(tester);
            expect(_toolbarOpacity(tester, cover), 1);
            expect(coverButtons.hitTestable(), findsOneWidget);
            _expectNativeButton(tester, coverButtons);
            expect(_headerActionButtons(), findsNothing);
            await tester.pump(const Duration(seconds: 2));
            _expectPageAccess(tester, controller, readOnly: true);
            expectRetained();
            await mouse.moveTo(_away);
            await _settle(tester);
            expect(_toolbarOpacity(tester, cover), 0);
            expect(coverButtons.hitTestable(), findsNothing);
          }
          access.change(ShareAccessLevel.fullAccess);
          await _settle(tester);
          _expectPageAccess(tester, controller, readOnly: false);
          // Re-created page controls have no draft to retain; the owner and
          // actual board/editor States above must still be the originals.
          rowElement = tester.element(row);
          await tester.pump(const Duration(seconds: 2));
          expectReveal(false);
          expectDecorationReveal(iconVisible: false, coverVisible: false);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await access.close();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '${appearance.name}: missing icon and cover actions are not pinned',
      (tester) async {
        _viewport(tester);
        final controller = _DraftController(_document);
        final view = _view()
          ..id = 'dashboard-missing-decorations'
          ..icon = EmojiIconData.none().toViewIcon();
        final saved = view.writeToBuffer();
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _away);
        try {
          await tester.pumpWidget(_app(appearance, _page(view, controller)));
          await _settle(tester);
          final iconActions = _headerIconActions();
          final buttons = _nativeButtons(iconActions);
          final header = tester.getRect(find.byType(WorkspacePageHeader));
          final card = tester.getRect(_card(_noteId));
          final ownerState = tester.state(_headerDecorations());
          final pageState = tester.state(find.byType(DashboardPage));
          final canvasState = tester.state(find.byType(DashboardCanvas));
          final fieldState = tester.state(_draftField('text'));
          final addCoverLabel = LocaleKeys.document_plugins_cover_addCover.tr();
          expect(view.icon.value, isEmpty);
          expect(view.cover!.isNone, isTrue);
          expect(find.byType(WorkspacePageCover), findsNothing);
          expect(find.byType(ViewCoverImage), findsNothing);
          expect(
            find.byKey(const ValueKey('view-decoration-remove')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('view-decoration-download')),
            findsNothing,
          );
          expect(
            find.text(LocaleKeys.document_plugins_cover_addIcon.tr()),
            findsOneWidget,
          );
          expect(find.text(addCoverLabel), findsOneWidget);
          expect(buttons, findsNWidgets(2));
          expect(_headerActionButtons(), findsNWidgets(2));

          void expectReveal(bool visible) {
            expect(_toolbarOpacity(tester, iconActions), visible ? 1 : 0);
            expect(_headerToolbarOpacity(tester), visible ? 1 : 0);
            expect(
              buttons.hitTestable(),
              visible ? findsNWidgets(2) : findsNothing,
            );
            expect(
              _headerActionButtons().hitTestable(),
              visible ? findsNWidgets(2) : findsNothing,
            );
            expect(
              find.semantics.byLabel(addCoverLabel),
              visible ? findsOneWidget : findsNothing,
            );
            expect(tester.getRect(find.byType(WorkspacePageHeader)), header);
            expect(tester.getRect(_card(_noteId)), card);
            expect(tester.state(_headerDecorations()), same(ownerState));
            expect(tester.state(find.byType(DashboardPage)), same(pageState));
            expect(
              tester.state(find.byType(DashboardCanvas)),
              same(canvasState),
            );
            expect(tester.state(_draftField('text')), same(fieldState));
            _expectPageAccess(tester, controller, readOnly: false);
            expect(controller.document, same(_document));
            expect(controller.editAttempts, 0);
            expect(controller.flushAttempts, 0);
            expect(controller.canUndo, isFalse);
            expect(controller.canRedo, isFalse);
            expect(view.writeToBuffer(), saved);
            expect(storage.writes, isEmpty);
          }

          expectReveal(false);
          for (final point in [
            tester.getCenter(find.byKey(_titleKey)),
            header.bottomRight - const Offset(32, 4),
          ]) {
            expect(
              tester
                  .getRect(
                    find.byKey(const ValueKey('workspace-page-icon-row')),
                  )
                  .contains(point),
              isFalse,
            );
            await mouse.moveTo(point);
            await _settle(tester);
            expectReveal(true);
            for (final element in buttons.evaluate()) {
              _expectNativeButton(tester, find.byWidget(element.widget));
            }
            await mouse.moveTo(_away);
            await _settle(tester);
            expectReveal(false);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
        '${appearance.name}: native dashboard buttons activate from the keyboard',
        (tester) async {
      _viewport(tester);
      final semantics = tester.ensureSemantics();
      final controller = _controller();
      try {
        await tester.pumpWidget(_app(appearance, _page(_view(), controller)));
        await _settle(tester);
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
        ]) {
          final add = _nativeTextButton(_headerAdd());
          expect(add, findsOneWidget);
          await _tabTo(tester, add);
          _expectNativeButton(tester, add);
          await tester.sendKeyEvent(key);
          await _settle(tester);
          expect(find.byType(Dialog), findsOneWidget);
          expect(controller.document, same(_document));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester);
          expect(find.byType(Dialog), findsNothing);

          final options = _nativeIconButton(_headerOptions());
          expect(options, findsOneWidget);
          await _tabTo(tester, options);
          _expectNativeButton(tester, options);
          await tester.sendKeyEvent(key);
          await _settle(tester);
          expect(_menuRow(LocaleKeys.toolbar_undo), findsOneWidget);
          expect(_menuRow(LocaleKeys.toolbar_redo), findsOneWidget);
          expect(_menuRow(LocaleKeys.dashboard_action_refresh), findsOneWidget);
          expect(_menuRow(LocaleKeys.dashboard_option_layout), findsOneWidget);
          expect(_menuRow(LocaleKeys.dashboard_mode_focus), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester);
          expect(find.byType(AppMenuSurface), findsNothing);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '${appearance.name}: the page menu operates on the borrowed controller',
        (tester) async {
      _viewport(tester);
      final controller = _controller();
      try {
        await tester.pumpWidget(_app(appearance, _page(_view(), controller)));
        await _settle(tester);
        final header = find.byType(WorkspacePageIdentity);
        for (final icon in [
          Icons.undo_rounded,
          Icons.redo_rounded,
          Icons.refresh_rounded,
        ]) {
          expect(
            find.descendant(of: header, matching: find.byIcon(icon)),
            findsNothing,
          );
        }
        await _openOptions(tester);
        expect(
          tester.widget<AppMenuRow>(_menuRow(LocaleKeys.toolbar_undo)).enabled,
          isFalse,
        );
        expect(
          tester.widget<AppMenuRow>(_menuRow(LocaleKeys.toolbar_redo)).enabled,
          isFalse,
        );
        await tester.tap(_menuRow(LocaleKeys.dashboard_action_refresh));
        await _settle(tester);
        expect(controller.refreshToken, 1);
        expect(controller.document, same(_document));

        controller
            .edit((document) => document.copyWith(subtitle: 'Changed locally'));
        await _settle(tester);
        await _openOptions(tester);
        expect(
          tester.widget<AppMenuRow>(_menuRow(LocaleKeys.toolbar_undo)).enabled,
          isTrue,
        );
        await tester.tap(_menuRow(LocaleKeys.toolbar_undo));
        await _settle(tester);
        expect(controller.document, same(_document));
        await _openOptions(tester);
        expect(
          tester.widget<AppMenuRow>(_menuRow(LocaleKeys.toolbar_redo)).enabled,
          isTrue,
        );
        await tester.tap(_menuRow(LocaleKeys.toolbar_redo));
        await _settle(tester);
        expect(controller.document.subtitle, 'Changed locally');

        await _openOptions(tester);
        await tester.tap(_menuRow(LocaleKeys.dashboard_option_layout));
        await _settle(tester);
        await tester.tap(_menuRow(LocaleKeys.dashboard_layout_oneColumn));
        await _settle(tester);
        final section = controller.document.sections.single;
        expect(section.layout, DashboardSectionLayout.oneColumn);
        expect(section.widgets.first.placement.columnSpan, 12);
        expect(section.widgets.last.placement.row, _note.placement.rowSpan);
        expect(
          controller.document.allWidgets.map((spec) => spec.id),
          [_note.id, _tail.id],
        );
        await controller.flush();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });

    testWidgets(
        '${appearance.name}: card actions reveal for focus and selection without reflow',
        (tester) async {
      _viewport(tester);
      final semantics = tester.ensureSemantics();
      final controller = _controller();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      try {
        await tester.pumpWidget(_app(appearance, _page(_view(), controller)));
        await _settle(tester);
        final card = _card(_noteId);
        final state = tester.state(card);
        final rect = tester.getRect(card);
        final configure = _nativeIconButton(_cardConfigure());
        final tooltip = LocaleKeys.dashboard_card_configure.tr();
        expect(_cardToolbarOpacity(tester), 0);
        expect(configure.hitTestable(), findsNothing);
        expect(_semanticsHasTooltip(tester, tooltip), isFalse);

        await _tabTo(tester, configure);
        expect(controller.selectedWidgetId, isNull);
        expect(_cardToolbarOpacity(tester), 1);
        expect(configure.hitTestable(), findsOneWidget);
        _expectNativeButton(tester, configure);
        expect(_semanticsHasTooltip(tester, tooltip), isTrue);
        expect(tester.getRect(card), rect);

        // Blurring must not visit offscreen cards and scroll the page as a
        // side effect: this assertion is about reflow, not Tab auto-scrolling.
        await _focusPage(tester);
        expect(_cardToolbarOpacity(tester), 0);
        expect(configure.hitTestable(), findsNothing);
        expect(_semanticsHasTooltip(tester, tooltip), isFalse);
        controller.select(_noteId);
        await _settle(tester);
        expect(_cardToolbarOpacity(tester), 1);
        expect(configure.hitTestable(), findsOneWidget);
        expect(controller.configuringWidgetId, isNull);
        expect(tester.getRect(card), rect);
        expect(tester.state(card), same(state));
        controller.select(null);
        await _settle(tester);
        expect(_cardToolbarOpacity(tester), 0);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '${appearance.name}: configuration and modal preserve the actual board body',
        (tester) async {
      _viewport(tester);
      final lifecycle = _ReadingLifecycle();
      // A local key deliberately cannot rescue a reparented board. Only this
      // inert renderer is supplied by the test; page/card/canvas/panel are real.
      expect(DashboardWidgetRegistry.definitionFor(_readingType), isNull);
      final originalTextDefinition =
          DashboardWidgetRegistry.definitionFor('text');
      DashboardWidgetRegistry.register(
        DashboardWidgetDefinition(
          type: _readingType,
          extensionId: _readingOwner,
          label: () => 'Retained reading',
          icon: Icons.notes_rounded,
          group: DashboardWidgetGroup.text,
          builder: (context) => _RetainedReading(
            key: ValueKey(context.spec.id),
            dashboard: context,
            lifecycle: lifecycle,
          ),
        ),
      );
      final document = _document.withWidget(
        _note.copyWith(type: _readingType),
      );
      final controller = _controller(document: document);
      try {
        await tester.pumpWidget(_app(appearance, _page(_view(), controller)));
        await _settle(tester);
        final body = find.descendant(
          of: _card(_noteId),
          matching: find.byType(_RetainedReading),
        );
        final field =
            find.descendant(of: body, matching: find.byKey(_draftKey));
        final reading = tester.state<_RetainedReadingState>(body);
        await tester.enterText(field, 'A draft not saved in the dashboard');
        const selection = TextSelection(baseOffset: 2, extentOffset: 14);
        reading.draft.selection = selection;
        reading.scroll.jumpTo(180);
        final pageScroll = _pageScroll(tester);
        pageScroll.position.jumpTo(70);
        controller.select(_noteId);
        await _settle(tester);
        final textFieldState = tester.state<State<TextField>>(field);
        final innerScrollable = find.descendant(
          of: find.descendant(
            of: body,
            matching: find.byKey(_readingScrollKey),
          ),
          matching: find.byType(Scrollable),
        );
        final innerScroll = tester.state<ScrollableState>(innerScrollable);
        final innerPosition = innerScroll.position;
        final cardState = tester.state(_card(_noteId));
        final canvasState = tester.state(find.byType(DashboardCanvas));
        final rect = tester.getRect(_card(_noteId));
        final offset = pageScroll.position.pixels;

        void expectRetained() {
          expect(tester.state(body), same(reading));
          expect(tester.state<State<TextField>>(field), same(textFieldState));
          expect(
            tester.widget<TextField>(field).controller,
            same(reading.draft),
          );
          expect(
            tester.widget<TextField>(field).focusNode,
            same(reading.focus),
          );
          expect(reading.draft.text, 'A draft not saved in the dashboard');
          expect(reading.draft.selection, selection);
          expect(tester.state(innerScrollable), same(innerScroll));
          expect(reading.scroll.position, same(innerPosition));
          expect(reading.scroll.offset, 180);
          expect(_pageScroll(tester), same(pageScroll));
          expect(pageScroll.position.pixels, offset);
          expect(tester.state(_card(_noteId)), same(cardState));
          expect(tester.state(find.byType(DashboardCanvas)), same(canvasState));
          expect(tester.getRect(_card(_noteId)), rect);
          expect(controller.document, same(document));
        }

        await tester.tap(_nativeIconButton(_cardConfigure()));
        await _settle(tester);
        expect(find.byType(DashboardConfigPanel), findsOneWidget);
        expect(controller.configuringWidgetId, _noteId);
        expectRetained();
        expect(lifecycle.created, 1);
        expect(lifecycle.disposed, 0);
        await tester.tap(
          _nativeIconButton(
            find.descendant(
              of: find.byType(DashboardConfigPanel),
              matching: _icon(LocaleKeys.button_close),
            ),
          ),
        );
        await _settle(tester);
        expect(find.byType(DashboardConfigPanel), findsNothing);
        expectRetained();

        await tester.tap(
          _nativeIconButton(
            find.descendant(
              of: _card(_noteId),
              matching: _icon(LocaleKeys.dashboard_card_more),
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(_menuRow(LocaleKeys.dashboard_card_openLarge));
        await _settle(tester);
        expect(controller.modalWidgetId, _noteId);
        expect(find.byType(_RetainedReading), findsNWidgets(2));
        expectRetained();
        expect(lifecycle.created, 2);
        expect(lifecycle.disposed, 0);
        await tester.tap(_nativeIconButton(_icon(LocaleKeys.button_close)));
        await _settle(tester);
        expect(controller.modalWidgetId, isNull);
        expect(find.byType(_RetainedReading), findsOneWidget);
        expectRetained();
        expect(lifecycle.disposed, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(lifecycle.disposed, 2);
        void listenerProbe() {}
        expect(
          () {
            controller.addListener(listenerProbe);
            controller.removeListener(listenerProbe);
          },
          returnsNormally,
        );
        expect(
          controller.refresh,
          returnsNormally,
          reason: 'The page only borrowed it.',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        DashboardWidgetRegistry.unregisterAll(_readingOwner);
      }
      expect(DashboardWidgetRegistry.definitionFor(_readingType), isNull);
      expect(
        DashboardWidgetRegistry.definitionFor('text'),
        same(originalTextDefinition),
      );
    });

    for (final (type, setting, saved, draft, committed) in [
      (
        'text',
        'text',
        'Saved note',
        'A suspended local draft',
        'A suspended local draft',
      ),
      ('metric', 'value', 7.0, '1,234.50', 1234.5),
      (
        'countdown',
        'note',
        '',
        'A first countdown note',
        'A first countdown note',
      ),
    ]) {
      final initialSettings = <String, Object?>{
        if (type == 'countdown') 'target': '2030-01-01',
        setting: saved,
      };
      for (final blocker in ['lock', 'read-only', 'presentation']) {
        testWidgets(
          '${appearance.name}: $type draft survives $blocker before debounce',
          (tester) async {
            _viewport(tester);
            final spec = _note.copyWith(
              type: type,
              title: 'Saved card title',
              showTitle: true,
              settings: initialSettings,
            );
            final document = _document.withWidget(spec);
            final controller = _DraftController(document);
            final view = _view();
            final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
            try {
              await tester.pumpWidget(
                _app(appearance, _page(view, controller, access: access)),
              );
              await _settle(tester);
              final field = _draftField(type);
              final editor = find.descendant(
                of: _card(_noteId),
                matching: find.byType(
                  type == 'metric'
                      ? DashboardEditableNumber
                      : DashboardEditableText,
                ),
              );
              final editorState = tester.state(editor);
              final fieldState = tester.state(field);
              final native = find.descendant(
                of: field,
                matching: find.byType(EditableText),
              );
              final nativeState = tester.state(native);
              final cardState = tester.state(_card(_noteId));
              final pageState = tester.state(find.byType(DashboardPage));
              final originalField = tester.widget<TextField>(field);
              final text = originalField.controller!;
              await tester.enterText(field, draft);
              await tester.pump(const Duration(milliseconds: 100));
              text.selection =
                  const TextSelection(baseOffset: 1, extentOffset: 4);
              final localValue = text.value;
              expect(controller.editAttempts, 0);

              void expectRetained({required bool readOnly}) {
                expect(tester.state(editor), same(editorState));
                expect(tester.state(field), same(fieldState));
                expect(tester.state(native), same(nativeState));
                expect(tester.state(_card(_noteId)), same(cardState));
                expect(
                  tester.state(find.byType(DashboardPage)),
                  same(pageState),
                );
                final live = tester.widget<TextField>(field);
                expect(live.controller, same(text));
                expect(live.focusNode, same(originalField.focusNode));
                expect(live.readOnly, readOnly);
                expect(text.value, localValue);
                expect(
                  tester
                      .widget<WorkspaceInlineEditableText>(
                        find.byKey(_titleKey),
                      )
                      .text,
                  _title,
                );
              }

              if (blocker == 'presentation') {
                controller.setMode(DashboardMode.presentation);
              } else {
                access.change(
                  blocker == 'lock'
                      ? ShareAccessLevel.fullAccess
                      : ShareAccessLevel.readOnly,
                  locked: blocker == 'lock',
                );
              }
              await tester.pump();
              expect(controller.isEditable, isFalse);
              expectRetained(readOnly: true);
              expect(controller.document, same(document));
              expect(
                controller.document.widgetById(_noteId)!.title,
                'Saved card title',
              );

              // Blur and timeouts are both commit paths. Neither may invoke
              // the writer or clear the draft while access is blocked.
              originalField.focusNode!.unfocus();
              await tester.pump(const Duration(seconds: 2));
              expectRetained(readOnly: true);
              expect(controller.editAttempts, 0);
              expect(controller.document, same(document));
              expect(controller.canUndo, isFalse);

              final remote = document.withWidget(
                spec.copyWith(
                  title: 'Retitled elsewhere',
                  settings: {
                    ...initialSettings,
                    setting: type == 'metric' ? 11.0 : 'Remote saved note',
                  },
                ),
              );
              _adoptDraftDocument(controller, remote);
              await tester.pump(const Duration(seconds: 2));
              expect(controller.document, remote);
              expectRetained(readOnly: true);
              expect(controller.editAttempts, 0);

              if (blocker == 'presentation') {
                controller.setMode(DashboardMode.edit);
              } else {
                access.change(ShareAccessLevel.fullAccess);
              }
              await tester.pump();
              await tester.pump(const Duration(seconds: 2));
              expectRetained(readOnly: false);
              expect(controller.document, remote);
              expect(
                controller.editAttempts,
                0,
                reason: 'Unlocking is not an autosave.',
              );

              await _submitDraft(tester, field);
              expect(controller.editAttempts, 1);
              final accepted = controller.document.widgetById(_noteId)!;
              expect(accepted.settings[setting], committed);
              expect(accepted.title, 'Retitled elsewhere');
              expect(tester.state(field), same(fieldState));
              expect(text.text, draft);
              await controller.flush();

              // An accepted value really clears dirty: the next authoritative
              // update should now be adopted rather than suppressed forever.
              _adoptDraftDocument(controller, remote);
              await tester.pump();
              expect(text.text, type == 'metric' ? '11' : 'Remote saved note');
              expect(controller.editAttempts, 1);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              controller.dispose();
              await access.close();
            }
          },
        );
      }

      testWidgets(
        '${appearance.name}: a refused synchronous $type command stays dirty',
        (tester) async {
          _viewport(tester);
          final document = _document.withWidget(
            _note.copyWith(type: type, settings: initialSettings),
          );
          final controller = _DraftController(document)..rejectEdits = true;
          try {
            await tester
                .pumpWidget(_app(appearance, _page(_view(), controller)));
            await _settle(tester);
            final field = _draftField(type);
            final state = tester.state(field);
            final text = tester.widget<TextField>(field).controller!;
            await tester.enterText(field, draft);
            await tester.pump(const Duration(milliseconds: 401));
            expect(controller.editAttempts, 1);
            expect(controller.document, same(document));
            controller.refresh();
            await tester.pump();
            expect(tester.state(field), same(state));
            expect(
              text.text,
              draft,
              reason: 'A void return is not an acknowledgement.',
            );
            controller.rejectEdits = false;
            await _submitDraft(tester, field);
            expect(controller.editAttempts, 2);
            expect(
              controller.document.widgetById(_noteId)!.settings[setting],
              committed,
            );
            await controller.flush();
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          }
        },
      );

      testWidgets(
        '${appearance.name}: $type callbacks and disposal read access before rebuild',
        (tester) async {
          _viewport(tester);
          final document = _document.withWidget(
            _note.copyWith(type: type, settings: initialSettings),
          );
          final controller = _DraftController(document);
          try {
            await tester
                .pumpWidget(_app(appearance, _page(_view(), controller)));
            await _settle(tester);
            final field = _draftField(type);
            await tester.enterText(field, draft);
            final stale = tester.widget<TextField>(field);
            final value = stale.controller!.value;
            controller.setReadOnly(true, notify: false);
            // No intervening build: enabled/readOnly on the old widget are
            // deliberately stale, including when the field is disposed.
            expect(stale.readOnly, isFalse);
            stale.onChanged!('A stale callback');
            stale.onSubmitted!(draft);
            expect(stale.controller!.value, value);
            expect(controller.editAttempts, 0);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 2));
            expect(controller.editAttempts, 0);
            expect(controller.document, same(document));
            expect(controller.canUndo, isFalse);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          }
        },
      );
    }

    testWidgets(
      '${appearance.name}: invalid numeric drafts survive lock and explicit submit',
      (tester) async {
        _viewport(tester);
        final document = _document.withWidget(
          _note.copyWith(type: 'metric', settings: {'value': 7.0}),
        );
        final controller = _DraftController(document);
        try {
          await tester.pumpWidget(_app(appearance, _page(_view(), controller)));
          await _settle(tester);
          final field = _draftField('metric');
          final state = tester.state(field);
          final text = tester.widget<TextField>(field).controller!;
          for (final invalid in ['-', 'NaN', 'Infinity']) {
            await tester.enterText(field, invalid);
            controller.setReadOnly(true);
            await tester.pump();
            await tester.pump(const Duration(seconds: 2));
            expect(text.text, invalid);
            expect(tester.state(field), same(state));
            expect(controller.document, same(document));
            controller.setReadOnly(false);
            await tester.pump();
            await _submitDraft(tester, field);
            expect(text.text, invalid);
            expect(controller.editAttempts, 0);
            expect(controller.document, same(document));
          }
          await tester.enterText(field, '9.25');
          await tester.pump(const Duration(milliseconds: 401));
          expect(
            controller.document
                .widgetById(_noteId)!
                .number('value', fallback: 0),
            9.25,
          );
          expect(controller.editAttempts, 1);
          await controller.flush();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );

    testWidgets(
      '${appearance.name}: gated renderer and scroll survive configuration, modes and access',
      (tester) async {
        _viewport(tester);
        const type = 'test.dashboard_workspace.retained_access';
        final lifecycle = _ReadingLifecycle();
        expect(DashboardWidgetRegistry.definitionFor(type), isNull);
        DashboardWidgetRegistry.register(
          DashboardWidgetDefinition(
            type: type,
            extensionId: type,
            label: () => 'Retained gated reading',
            icon: Icons.notes_rounded,
            group: DashboardWidgetGroup.text,
            requiresScrollActivation: true,
            builder: (context) => _RetainedReading(
              key: ValueKey(context.spec.id),
              dashboard: context,
              lifecycle: lifecycle,
            ),
          ),
        );
        final document = _document.withWidget(_note.copyWith(type: type));
        final controller = _DraftController(document);
        final view = _view();
        final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
        try {
          await tester.pumpWidget(
            _app(appearance, _page(view, controller, access: access)),
          );
          await _settle(tester);
          final body = find.byType(_RetainedReading);
          final reading = tester.state<_RetainedReadingState>(body);
          final field = find.byKey(_draftKey);
          final fieldState = tester.state(field);
          final gate = find.byType(ScrollActivationRegion);
          final gateState = tester.state(gate);
          final inner = find.descendant(
            of: find.byKey(_readingScrollKey),
            matching: find.byType(Scrollable),
          );
          final innerState = tester.state<ScrollableState>(inner);
          final pageScroll = _pageScroll(tester);
          await tester.enterText(field, 'Local renderer draft');
          reading.draft.selection =
              const TextSelection(baseOffset: 1, extentOffset: 6);
          final value = reading.draft.value;
          controller.select(_noteId);
          await tester.pump();
          reading.scroll.jumpTo(180);
          pageScroll.position.jumpTo(70);
          await tester.pump();

          void expectRetained() {
            expect(tester.state(body), same(reading));
            expect(tester.state(field), same(fieldState));
            expect(tester.state(gate), same(gateState));
            expect(tester.state(inner), same(innerState));
            expect(reading.draft.value, value);
            expect(reading.scroll.hasClients, isTrue);
            expect(reading.scroll.offset, 180);
            expect(_pageScroll(tester), same(pageScroll));
            expect(pageScroll.position.pixels, 70);
            expect(lifecycle.created, 1);
            expect(lifecycle.disposed, 0);
            expect(controller.document, same(document));
            expect(controller.editAttempts, 0);
          }

          for (final change in <VoidCallback>[
            () => controller.configure(_noteId),
            controller.closeSettings,
            () => controller.setMode(DashboardMode.focus),
            () => controller.setMode(DashboardMode.presentation),
            () => access.change(ShareAccessLevel.fullAccess, locked: true),
            () => controller.setMode(DashboardMode.edit),
            () => access.change(ShareAccessLevel.readOnly),
            () => access.change(ShareAccessLevel.fullAccess),
          ]) {
            change();
            await tester.pump();
            await tester.pump(const Duration(seconds: 2));
            expectRetained();
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await access.close();
          DashboardWidgetRegistry.unregisterAll(type);
        }
        expect(lifecycle.disposed, 1);
      },
    );

    testWidgets(
      '${appearance.name}: presentation borrows a second body without flushing the first draft',
      (tester) async {
        _viewport(tester);
        final controller = _DraftController(_document);
        final view = _view();
        final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
        try {
          await tester.pumpWidget(
            _app(appearance, _page(view, controller, access: access)),
          );
          await _settle(tester);
          final pageState = tester.state(find.byType(DashboardPage));
          final field = _draftField('text');
          final originalElement = tester.element(field);
          final originalState = tester.state(field);
          final originalField = tester.widget<TextField>(field);
          final text = originalField.controller!;
          final original = find.byElementPredicate(
            (element) => identical(element, originalElement),
            skipOffstage: false,
          );

          // Open the real menu first, then inject a last-keystroke draft into
          // the real field. This isolates mode switching from the legitimate
          // editable blur that normally occurs when opening a menu.
          await _openOptions(tester);
          const draft = 'Pending as presentation opens';
          const value = TextEditingValue(
            text: draft,
            selection: TextSelection(baseOffset: 2, extentOffset: 8),
          );
          text.value = value;
          originalField.onChanged!(draft);
          await tester.tap(_menuRow(LocaleKeys.dashboard_mode_presentation));
          await _settle(tester);
          expect(controller.mode, DashboardMode.presentation);
          expect(
            find.byType(DashboardPage, skipOffstage: false),
            findsNWidgets(2),
          );
          _expectHeaderMutationAccess(tester, editable: false);
          expect(_headerActionButtons(), findsOneWidget);
          final exit = _nativeIconButton(
            find.byKey(const ValueKey('dashboard-exit-immersive')),
          );
          expect(exit.hitTestable(), findsOneWidget);
          expect(tester.widget<IconButton>(exit).onPressed, isNotNull);
          expect(tester.state(original), same(originalState));
          expect(text.value, value);
          final presented = tester.widget<TextField>(_draftField('text'));
          expect(presented.controller, isNot(same(text)));
          expect(presented.controller!.text, _note.setting('text'));
          expect(presented.readOnly, isTrue);
          await tester.pump(const Duration(seconds: 2));
          expect(controller.editAttempts, 0);
          expect(controller.flushAttempts, 0);
          expect(controller.document, same(_document));
          expect(text.value, value);

          access.change(ShareAccessLevel.fullAccess, locked: true);
          await _settle(tester);
          await _focusPage(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.f11);
          await _settle(tester);
          expect(
            find.byType(DashboardPage, skipOffstage: false),
            findsOneWidget,
          );
          expect(tester.state(find.byType(DashboardPage)), same(pageState));
          expect(tester.state(field), same(originalState));
          expect(tester.widget<TextField>(field).readOnly, isTrue);
          expect(text.value, value);
          await tester.pump(const Duration(seconds: 2));
          expect(controller.document, same(_document));
          expect(controller.editAttempts, 0);
          expect(controller.flushAttempts, 0);

          access.change(ShareAccessLevel.fullAccess);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(text.value, value);
          expect(controller.editAttempts, 0);
          expect(controller.flushAttempts, 0);
          await _submitDraft(tester, field);
          expect(
            controller.document.widgetById(_noteId)!.setting('text'),
            draft,
          );
          expect(controller.editAttempts, 1);
          await controller.flush();
          expect(controller.flushAttempts, 1);
          expect(access.isClosed, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await access.close();
        }
      },
    );

    testWidgets(
      '${appearance.name}: a delayed widget command preserves the current title and settings',
      (tester) async {
        _viewport(tester);
        final controller = _DraftController(_document);
        try {
          await tester.pumpWidget(_app(appearance, _page(_view(), controller)));
          await _settle(tester);
          final element = tester.element(_card(_noteId));
          final captured = DashboardWidgetContext(
            context: element,
            controller: controller,
            spec: _note,
            palette: DashboardPalette.of(element),
          );
          final remote = _document.withWidget(
            _note.copyWith(
              title: 'Current title',
              settings: {'text': 'Current text', 'align': 'right'},
            ),
          );
          _adoptDraftDocument(controller, remote);
          // Deliberately invoke the old context before another build.
          captured.setSettings({'text': 'Resumed draft'});
          final accepted = controller.document.widgetById(_noteId)!;
          expect(accepted.title, 'Current title');
          expect(accepted.setting('align'), 'right');
          expect(accepted.setting('text'), 'Resumed draft');
          expect(controller.editAttempts, 1);
          await tester.pump();
          await controller.flush();
          controller.setMode(DashboardMode.presentation);
          captured.setSettings({'text': 'Unauthorized presentation edit'});
          expect(controller.document.widgetById(_noteId), accepted);
          expect(controller.editAttempts, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );

    for (final (name, accessLevel, locked, readOnly) in [
      ('no access bloc', null, false, false),
      ('saved lock without a bloc', null, true, true),
      ('read-only access', ShareAccessLevel.readOnly, false, true),
      ('write access', ShareAccessLevel.readAndWrite, false, false),
      ('full access', ShareAccessLevel.fullAccess, false, false),
      ('saved lock with full access', ShareAccessLevel.fullAccess, true, true),
    ]) {
      testWidgets(
          '${appearance.name}: $name is applied on the first page build',
          (tester) async {
        _viewport(tester);
        final view = _view(locked: locked);
        final controller = _controller();
        final access =
            accessLevel == null ? null : _AccessBloc(view, accessLevel);
        var notifications = 0;
        controller.addListener(() => notifications++);
        try {
          await tester.pumpWidget(
            _app(appearance, _page(view, controller, access: access)),
          );
          await _settle(tester);
          _expectPageAccess(tester, controller, readOnly: readOnly);
          expect(notifications, 0, reason: 'Dependency adoption is silent.');
          expect(controller.document, same(_document));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await access?.close();
        }
      });
    }

    testWidgets(
        '${appearance.name}: live read-only and lock changes block stale edits and shortcuts',
        (tester) async {
      _viewport(tester);
      final view = _view();
      final controller = _controller();
      final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
      final navigation = _NavigationLog();
      final first = _document.copyWith(subtitle: 'First edit');
      final second = _document.copyWith(subtitle: 'Second edit');
      controller.replace(first);
      controller.replace(second);
      controller.undo();
      await controller.flush();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            _page(view, controller, access: access),
            navigation: navigation,
          ),
        );
        await _settle(tester);
        final pageState = tester.state(find.byType(DashboardPage));
        final canvasState = tester.state(find.byType(DashboardCanvas));
        final editable = tester.widget<DashboardEditableText>(_noteEditor());
        final title =
            tester.widget<WorkspaceInlineEditableText>(find.byKey(_titleKey));
        final add = tester.widget<DashboardButton>(_headerAdd()).onPressed!;
        final options =
            tester.widget<DashboardIconButton>(_headerOptions()).onPressed!;
        final configure =
            tester.widget<DashboardIconButton>(_cardConfigure()).onPressed!;
        final widgetContext = DashboardWidgetContext(
          context: tester.element(_card(_noteId)),
          controller: controller,
          spec: controller.document.widgetById(_noteId)!,
          palette: DashboardPalette.of(tester.element(_card(_noteId))),
        );
        expect(widgetContext.isTypable, isTrue);
        configure();
        await _settle(tester);
        expect(controller.selectedWidgetId, _noteId);
        expect(controller.configuringWidgetId, _noteId);
        expect(find.byType(DashboardConfigPanel), findsOneWidget);
        var notifications = 0;
        controller.addListener(() => notifications++);

        for (final (level, locked) in [
          (ShareAccessLevel.readOnly, false),
          (ShareAccessLevel.fullAccess, true),
        ]) {
          access.change(level, locked: locked);
          await _settle(tester);
          _expectPageAccess(tester, controller, readOnly: true);
          expect(widgetContext.isTypable, isFalse);
          expect(widgetContext.isEditable, isFalse);
          expect(notifications, 0);
          final pushes = navigation.pushes;
          editable.onChanged('A stale text callback');
          title.onTap!();
          expect(await title.onSubmitted('A stale rename'), isFalse);
          add();
          options();
          configure();
          widgetContext.setSettings({'text': 'A stale setting'});
          widgetContext.update(
            (spec) => spec.copyWith(hidden: true),
            transient: true,
          );
          final picking =
              widgetContext.pickSource(kind: DashboardSourceKind.page);
          // Assert synchronously: a broken guard must fail before mounting a
          // source picker that would otherwise try to read the native backend.
          expect(navigation.pushes, pushes);
          await picking;
          await _focusPage(tester);
          await _historyKey(tester);
          await _historyKey(tester, redo: true);
          expect(controller.document, same(first));
          expect(controller.canUndo, isTrue);
          expect(controller.canRedo, isTrue);
          expect(controller.configuringWidgetId, isNull);
          expect(find.byType(WorkspaceInlineNameEditor), findsNothing);
          expect(find.byType(DashboardConfigPanel), findsNothing);
          expect(find.byType(Dialog), findsNothing);
          expect(notifications, 0);
          expect(tester.state(find.byType(DashboardPage)), same(pageState));
          expect(tester.state(find.byType(DashboardCanvas)), same(canvasState));
        }

        access.change(ShareAccessLevel.fullAccess);
        await _settle(tester);
        _expectPageAccess(tester, controller, readOnly: false);
        expect(widgetContext.isTypable, isTrue);
        expect(notifications, 0);
        await _focusPage(tester);
        await _historyKey(tester, redo: true);
        expect(controller.document, same(second));
        await _historyKey(tester);
        expect(controller.document, same(first));
        final field = find.descendant(
          of: _noteEditor(),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'Editing restored');
        await tester.pump(const Duration(milliseconds: 401));
        expect(
          controller.document.widgetById(_noteId)!.setting('text'),
          'Editing restored',
        );
        expect(
          notifications,
          3,
          reason: 'Only redo, undo and the accepted edit notify.',
        );
        await controller.flush();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await access.close();
      }
    });

    testWidgets(
        '${appearance.name}: fullscreen carries access and returns the borrowed page intact',
        (tester) async {
      _viewport(tester);
      final view = _view();
      final profile = UserProfilePB();
      final controller = _controller();
      final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
      try {
        // This provider is BELOW the root Navigator. A pushed page must
        // explicitly carry it; it cannot inherit it accidentally from the app.
        await tester.pumpWidget(
          _app(
            appearance,
            _page(view, controller, access: access, userProfile: profile),
          ),
        );
        await _settle(tester);
        final original = tester.state(find.byType(DashboardPage));
        await _openOptions(tester);
        await tester.tap(_menuRow(LocaleKeys.dashboard_mode_focus));
        await _settle(tester);
        final fullscreen =
            tester.widget<DashboardPage>(find.byType(DashboardPage));
        expect(fullscreen.immersive, isTrue);
        expect(fullscreen.controller, same(controller));
        expect(fullscreen.userProfile, same(profile));
        expect(
          tester
              .element(find.byType(DashboardPage))
              .read<PageAccessLevelBloc>(),
          same(access),
        );
        expect(
          find.byType(DashboardPage, skipOffstage: false),
          findsNWidgets(2),
        );
        expect(controller.mode, DashboardMode.focus);

        access.change(ShareAccessLevel.readOnly);
        await _settle(tester);
        _expectPageAccess(tester, controller, readOnly: true);
        await _focusPage(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await _settle(tester);
        expect(find.byType(DashboardPage, skipOffstage: false), findsOneWidget);
        expect(tester.state(find.byType(DashboardPage)), same(original));
        expect(controller.mode, DashboardMode.edit);
        expect(controller.isReadOnly, isTrue);
        expect(access.isClosed, isFalse);

        access.change(ShareAccessLevel.fullAccess);
        await _settle(tester);
        _expectPageAccess(tester, controller, readOnly: false);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(access.isClosed, isFalse);
        expect(controller.refresh, returnsNormally);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await access.close();
      }
    });
  }

  for (final withProfile in [false, true]) {
    testWidgets(
        'plugin forwards access and ${withProfile ? 'a profile' : 'no profile'} to the real page',
        (tester) async {
      _viewport(tester);
      final view = _view();
      final profile = withProfile ? UserProfilePB() : null;
      final access = _AccessBloc(view, ShareAccessLevel.readOnly);
      final ambient = _AccessBloc(view, ShareAccessLevel.fullAccess);
      final notifier = _Notifier(view);
      final controller = _controller();
      try {
        final builder = DashboardPluginWidgetBuilder(
          notifier: notifier,
          viewInfoBloc: _ViewInfoBloc(),
          pageAccessLevelBloc: access,
        );
        final built = builder.buildWidget(
          context: PluginContext(userProfile: profile),
          shrinkWrap: false,
        );
        expect(builder.contentPadding, EdgeInsets.zero);
        expect(built, isA<BlocProvider<PageAccessLevelBloc>>());
        final provider = built as BlocProvider<PageAccessLevelBloc>;
        expect(provider.child, isA<DashboardPage>());
        final declared = provider.child! as DashboardPage;
        expect(declared.view, same(view));
        expect(declared.key, ValueKey(view.id));
        expect(declared.userProfile, same(profile));

        // Mount the returned provider itself. Only supply the page's existing
        // borrowed-controller seam instead of starting its native ViewListener.
        final page = DashboardPage(
          key: declared.key,
          view: declared.view,
          immersive: declared.immersive,
          userProfile: declared.userProfile,
          controller: controller,
        );
        await tester.pumpWidget(
          _app(
            WorkspaceDesignAppearance.paper,
            BlocProvider<PageAccessLevelBloc>.value(
              value: ambient,
              child: MultiBlocProvider(providers: [provider], child: page),
            ),
          ),
        );
        await _settle(tester);
        expect(
          tester.element(find.byWidget(page)).read<PageAccessLevelBloc>(),
          same(access),
        );
        _expectPageAccess(tester, controller, readOnly: true);
        access.change(ShareAccessLevel.fullAccess);
        await _settle(tester);
        _expectPageAccess(tester, controller, readOnly: false);
        access.change(ShareAccessLevel.fullAccess, locked: true);
        await _settle(tester);
        _expectPageAccess(tester, controller, readOnly: true);
        expect(ambient.state.isLocked, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(access.isClosed, isFalse);
        expect(ambient.isClosed, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await access.close();
        await ambient.close();
        notifier.dispose();
      }
    });
  }
}

/// Records attempts as well as accepted document changes; no native backend
/// is used. Rejection is synchronous, just like the real controller's guard.
class _DraftController extends DashboardController {
  _DraftController(DashboardDocument document)
      : super(
          viewId: '',
          document: document,
          persistDebounce: const Duration(days: 1),
        );

  int editAttempts = 0;
  int flushAttempts = 0;
  bool rejectEdits = false;

  @override
  void edit(
    DashboardDocument Function(DashboardDocument) change, {
    bool transient = false,
  }) {
    editAttempts++;
    if (rejectEdits) return;
    super.edit(change, transient: transient);
  }

  @override
  Future<void> flush() {
    flushAttempts++;
    return super.flush();
  }
}

Finder _draftField(String type) => find.descendant(
      of: find.descendant(
        of: _card(_noteId),
        matching: find.byType(
          type == 'metric' ? DashboardEditableNumber : DashboardEditableText,
        ),
      ),
      matching: find.byType(TextField),
    );

Future<void> _submitDraft(WidgetTester tester, Finder field) async {
  await tester.showKeyboard(field);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void _adoptDraftDocument(
  DashboardController controller,
  DashboardDocument document,
) {
  controller.adoptFromView(
    ViewPB(
      id: controller.viewId,
      extra: DashboardMetadata(document: document).mergeIntoExtra(''),
    ),
  );
}

DashboardController _controller({DashboardDocument document = _document}) =>
    DashboardController(
      viewId: '',
      document: document,
      persistDebounce: const Duration(days: 1),
    );

ViewPB _view({bool hasCover = false, bool locked = false}) => ViewPB.fromBuffer(
      ViewPB(
        name: _title,
        layout: ViewLayoutPB.Document,
        icon: EmojiIconData.emoji('📘').toViewIcon(),
        isLocked: locked,
        extra: ViewCoverCodec.mergeCover(
          const DashboardMetadata(document: _document).mergeIntoExtra(''),
          hasCover ? _cover : const PageStyleCover.none(),
        ),
      ).writeToBuffer(),
    );

Widget _page(
  ViewPB view,
  DashboardController controller, {
  PageAccessLevelBloc? access,
  UserProfilePB? userProfile,
}) {
  final page = DashboardPage(
    view: view,
    controller: controller,
    userProfile: userProfile,
  );
  return access == null
      ? page
      : BlocProvider<PageAccessLevelBloc>.value(value: access, child: page);
}

Widget _app(
  WorkspaceDesignAppearance appearance,
  Widget child, {
  double textScale = 1,
  _NavigationLog? navigation,
}) {
  final theme = workspaceDesignTheme(appearance);
  final base = AppFlowyDefaultTheme();
  return DefaultAssetBundle(
    bundle: testAssetBundle,
    // startLocale + saveLocale:false avoid EasyLocalization's preferences
    // initialization. The already-loaded asset map requires no fake-clock IO.
    child: EasyLocalization(
      supportedLocales: const [_locale],
      startLocale: _locale,
      path: 'assets/translations',
      saveLocale: false,
      assetLoader: _LoadedTranslations(_translations),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          navigatorObservers: [if (navigation != null) navigation],
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
              accessibleNavigation: false,
            ),
            child: AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: theme.brightness == Brightness.dark
                    ? base.dark()
                    : base.light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: child!,
            ),
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
}

class _LoadedTranslations extends AssetLoader {
  const _LoadedTranslations(this.values);
  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      // EasyLocalization aggregates loaders with Future.wait. A synchronous
      // then callback runs before that aggregator registers its pending result.
      Future<Map<String, dynamic>>.value(values);
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 20),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
}

Finder _card(String id) => find.byWidgetPredicate(
      (widget) => widget is DashboardCard && widget.spec.id == id,
    );

Finder _icon(String tooltipKey) => find.byWidgetPredicate(
      (widget) =>
          widget is DashboardIconButton && widget.tooltip == tooltipKey.tr(),
    );

Finder _headerAdd() => find.descendant(
      of: find.byType(WorkspacePageIdentity),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DashboardButton &&
            widget.label == LocaleKeys.dashboard_add_widget.tr(),
      ),
    );

Finder _headerOptions() => find.descendant(
      of: find.byType(WorkspacePageIdentity),
      matching: _icon(LocaleKeys.dashboard_options),
    );

Finder _headerDecorations() => find.descendant(
      of: find.byType(DashboardPage),
      matching: find.byType(ViewDecorationActions),
    );

Finder _headerIconActions() => find.descendant(
      of: find.byType(WorkspacePageIdentity),
      matching: find.byKey(const ValueKey('view-decoration-icon-actions')),
    );

Finder _headerActions() => find.descendant(
      of: _headerDecorations(),
      matching: find.byType(WorkspaceActionRow),
    );

Finder _headerActionButtons() => _nativeButtons(_headerActions());

Finder _nativeButtons(Finder scope) => find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is TextButton || widget is IconButton,
      ),
    );

Finder _cardConfigure() => find.descendant(
      of: _card(_noteId),
      matching: _icon(LocaleKeys.dashboard_card_configure),
    );

Finder _nativeTextButton(Finder owner) =>
    find.descendant(of: owner, matching: find.byType(TextButton));

Finder _nativeIconButton(Finder owner) =>
    find.descendant(of: owner, matching: find.byType(IconButton));

Finder _menuRow(String labelKey) =>
    find.widgetWithText(AppMenuRow, labelKey.tr());

Finder _noteEditor() => find.descendant(
      of: _card(_noteId),
      matching: find.byType(DashboardEditableText),
    );

ScrollableState _pageScroll(WidgetTester tester) =>
    Scrollable.of(tester.element(find.byType(WorkspacePageHeader)));

void _expectReadingEdges(WidgetTester tester) {
  final identity = tester.getRect(find.byType(WorkspacePageIdentity));
  final board = tester.getRect(find.byType(DashboardBoard));
  expect(identity.left, closeTo(board.left, 0.01));
  expect(identity.right, closeTo(board.right, 0.01));
  expect(
    tester.getTopLeft(find.byKey(_titleKey)).dx,
    closeTo(board.left, 0.01),
  );
  expect(tester.getTopLeft(_card(_noteId)).dx, closeTo(board.left, 0.01));
  expect(tester.getTopRight(_card(_noteId)).dx, closeTo(board.right, 0.01));
}

void _expectCoveredHeaderGeometry(WidgetTester tester) {
  final cover = tester.getRect(find.byType(ViewCoverImage));
  final identity = tester.getRect(find.byType(WorkspacePageIdentity));
  final header = tester.getRect(find.byType(WorkspacePageHeader));
  final title = tester.getRect(find.byKey(_titleKey));
  final button = _nativeTextButton(
    find.byKey(const ValueKey('workspace-page-icon')),
  );
  final icon = tester.getRect(button);
  final iconActions = tester.getRect(_headerIconActions());
  expect(cover.bottom - identity.top, closeTo(22, 0.01));
  expect(icon.top, closeTo(identity.top, 0.01));
  expect(cover.intersect(icon).height, closeTo(22, 0.01));
  expect(icon.bottom, greaterThan(cover.bottom));
  expect(icon.bottom, lessThan(title.top));
  expect(icon.left, closeTo(title.left, 0.01));
  expect(iconActions.top, greaterThanOrEqualTo(cover.bottom + 8));
  expect(iconActions.overlaps(cover), isFalse);

  // Geometry alone would also accept a painted translation whose upper icon
  // misses its parent's hit bounds. Both ends must reach the native button.
  for (final (point, overCover) in [
    (Offset(icon.center.dx, icon.top + 2), true),
    (Offset(icon.center.dx, icon.bottom - 2), false),
  ]) {
    expect(header.contains(point), isTrue);
    expect(cover.contains(point), overCover);
    expect(
      tester.hitTestOnBinding(point).path.map((entry) => entry.target),
      contains(tester.renderObject(button)),
    );
  }
  for (final element
      in _nativeButtons(find.byType(WorkspacePageCover)).evaluate()) {
    final action = tester.getRect(find.byWidget(element.widget));
    expect(cover.intersect(action), action);
    expect(action.overlaps(icon), isFalse);
    expect(action.overlaps(iconActions), isFalse);
  }
}

Future<void> _openOptions(WidgetTester tester) async {
  final options = _nativeIconButton(_headerOptions());
  expect(options, findsOneWidget);
  final rect = tester.getRect(options);
  expect(rect.isFinite, isTrue);
  expect(rect.isEmpty, isFalse);
  expect(
    tester.getRect(find.byKey(_scrollKey)).contains(rect.center),
    isTrue,
    reason: 'Reveal the existing header without moving its page scroll.',
  );
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: _away);
  try {
    await mouse.moveTo(tester.getCenter(options));
    await _settle(tester);
    expect(_headerToolbarOpacity(tester), 1);
    expect(options.hitTestable(), findsOneWidget);
    await mouse.down(tester.getCenter(options));
    await mouse.up();
    await _settle(tester);
    expect(find.byType(AppMenuSurface), findsOneWidget);
  } finally {
    await mouse.removePointer();
    await _settle(tester);
  }
}

bool _hasFocusWithin(Finder target) {
  final element = target.evaluate().single;
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (identical(focusedContext, element)) return true;
  var found = false;
  focusedContext?.visitAncestorElements((ancestor) {
    if (identical(ancestor, element)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  for (var step = 0; step < 40 && !_hasFocusWithin(target); step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _settle(tester);
  }
  expect(
    _hasFocusWithin(target),
    isTrue,
    reason: 'Reach the native button by Tab.',
  );
}

void _expectNativeButton(WidgetTester tester, Finder finder) {
  final data = tester.getSemantics(finder).getSemanticsData();
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
}

double _headerToolbarOpacity(WidgetTester tester) =>
    _toolbarOpacity(tester, _headerActions());

double _toolbarOpacity(WidgetTester tester, Finder scope) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: scope,
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

double _cardToolbarOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.descendant(
              of: _card(_noteId),
              matching: find.byType(PreviewToolbar),
            ),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

bool _semanticsHasTooltip(WidgetTester tester, String tooltip) {
  var found = false;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().tooltip == tooltip) found = true;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  // Walk the live tree, not cached debugSemantics on an excluded element.
  final owners = [tester.binding.rootPipelineOwner];
  for (var index = 0; index < owners.length; index++) {
    final owner = owners[index];
    final root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
    owner.visitChildren(owners.add);
  }
  return found;
}

void _expectPageAccess(
  WidgetTester tester,
  DashboardController controller, {
  required bool readOnly,
}) {
  expect(controller.isReadOnly, readOnly);
  expect(controller.isEditable, !readOnly);
  expect(
    tester.widget<DashboardEditableText>(_noteEditor()).enabled,
    !readOnly,
  );
  final title =
      tester.widget<WorkspaceInlineEditableText>(find.byKey(_titleKey));
  expect(title.onTap != null, !readOnly);
  _expectHeaderMutationAccess(tester, editable: !readOnly);
  expect(_cardConfigure(), readOnly ? findsNothing : findsOneWidget);
  if (readOnly) {
    expect(controller.selectedWidgetId, isNull);
    expect(controller.configuringWidgetId, isNull);
    expect(find.byType(DashboardConfigPanel), findsNothing);
  }
}

void _expectHeaderMutationAccess(
  WidgetTester tester, {
  required bool editable,
}) {
  expect(_headerAdd(), editable ? findsOneWidget : findsNothing);
  expect(_headerOptions(), editable ? findsOneWidget : findsNothing);
  // The artwork picker and labelled picker share the icon region, not the
  // page-action row. Access changes retain their single decoration owner.
  expect(
    find.byType(ViewIconPicker),
    editable ? findsNWidgets(2) : findsNothing,
  );
  expect(_headerDecorations(), findsOneWidget);
  final page = tester.widget<DashboardPage>(find.byType(DashboardPage));
  final immersive =
      page.immersive || (page.controller?.mode.isImmersive ?? false);
  expect(
    _headerActions(),
    editable || immersive ? findsOneWidget : findsNothing,
  );
  final decoration = tester.widget<ViewDecorationActions>(_headerDecorations());
  expect(decoration.showIconAction, editable);
  expect(decoration.showCoverAction, editable);
  expect(decoration.showDownloadAction, !immersive);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('workspace-page-icon-row')),
      matching: find.byType(ViewIconPicker),
    ),
    editable ? findsNWidgets(2) : findsNothing,
  );
  expect(
    find.descendant(
      of: _headerActions(),
      matching: find.byType(DecorationActionButton),
    ),
    findsNothing,
  );
  for (final key in ['view-decoration-icon', 'view-decoration-cover']) {
    expect(find.byKey(ValueKey(key)), editable ? findsOneWidget : findsNothing);
  }
  final downloadable = !immersive &&
      DownloadableCoverImage.fromPageStyleCover(decoration.view.cover) != null;
  final download = find.byKey(const ValueKey('view-decoration-download'));
  expect(download, downloadable ? findsOneWidget : findsNothing);
  if (downloadable) {
    expect(
      find.descendant(of: find.byType(WorkspacePageCover), matching: download),
      findsOneWidget,
    );
    expect(
      tester.widget<TextButton>(_nativeTextButton(download)).onPressed,
      isNotNull,
    );
  }
  if (!editable) {
    expect(
      find.byType(DecorationActionButton),
      downloadable ? findsOneWidget : findsNothing,
    );
    expect(find.byKey(const ValueKey('view-decoration-remove')), findsNothing);
    expect(find.byType(FlowyIconEmojiPicker), findsNothing);
    expect(find.byType(UploadImageMenu), findsNothing);
  }
}

Future<void> _focusPage(WidgetTester tester) async {
  final node = Focus.of(tester.element(find.byKey(_scrollKey)));
  node.requestFocus();
  await _settle(tester);
  expect(node.hasPrimaryFocus, isTrue);
}

Future<void> _historyKey(WidgetTester tester, {bool redo = false}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  try {
    if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    } finally {
      if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  } finally {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await _settle(tester);
}

class _AccessBloc extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  _AccessBloc(ViewPB view, ShareAccessLevel level)
      : super(
          PageAccessLevelState.initial(view).copyWith(
            accessLevel: level,
            isLocked: view.isLocked,
            isLoadingLockStatus: false,
          ),
        );

  @override
  ViewPB get view => state.view;

  void change(ShareAccessLevel level, {bool locked = false}) {
    final updated = ViewPB.fromBuffer(view.writeToBuffer())..isLocked = locked;
    emit(state.copyWith(view: updated, accessLevel: level, isLocked: locked));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStorage implements KeyValueStorage {
  final values = <String, String>{};
  final writes = <String>[];

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> set(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    writes.add(key);
    values.remove(key);
  }

  @override
  Future<void> clear() async {
    writes.add('clear');
    values.clear();
  }
}

class _NavigationLog extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

class _Notifier extends Fake implements ViewPluginNotifier {
  _Notifier(this.view);

  @override
  final ViewPB view;

  @override
  final isDeleted = ValueNotifier<DeletedViewPB?>(null);

  @override
  void dispose() => isDeleted.dispose();
}

class _ViewInfoBloc extends Fake implements ViewInfoBloc {}

class _ReadingLifecycle {
  int created = 0;
  int disposed = 0;
}

class _RetainedReading extends StatefulWidget {
  const _RetainedReading({
    super.key,
    required this.dashboard,
    required this.lifecycle,
  });

  final DashboardWidgetContext dashboard;
  final _ReadingLifecycle lifecycle;

  @override
  State<_RetainedReading> createState() => _RetainedReadingState();
}

class _RetainedReadingState extends State<_RetainedReading> {
  final draft = TextEditingController(text: 'Unsaved preview draft');
  final focus = FocusNode();
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.lifecycle.created++;
  }

  @override
  void dispose() {
    widget.lifecycle.disposed++;
    draft.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            key: _draftKey,
            controller: draft,
            focusNode: focus,
            readOnly: !widget.dashboard.isTypable,
          ),
          Expanded(
            child: ListView.builder(
              key: _readingScrollKey,
              controller: scroll,
              primary: false,
              itemExtent: 32,
              itemCount: 80,
              itemBuilder: (_, index) => Text('Retained line $index'),
            ),
          ),
        ],
      );
}
