import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_ask_ai_entrance.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_result_cell.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/sidebar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_preview.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_recent_view_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/util.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Command Palette', () {
    testWidgets('Toggle command palette', (tester) async {
      await tester.initializeAppFlowy();
      await _useLightMode(tester);
      await tester.tapAnonymousSignInButton();
      _expectLightMode(tester);
      final workspaceCanvas =
          find.byKey(const ValueKey('workspace-page-canvas')).first;
      expect(
        tester.widget<Container>(workspaceCanvas).color,
        EditorSurfaceStyle.lightCanvasBackground,
      );

      await tester.tapButton(find.text(LocaleKeys.search_label.tr()));
      expect(find.byType(CommandPaletteModal), findsOneWidget);
      expect(
        tester.widget<SimpleDialog>(find.byType(SimpleDialog)).elevation,
        32,
      );
      final dialog = tester.widget<FlowyDialog>(find.byType(FlowyDialog));
      expect(dialog.alignment, Alignment.center);
      expect(
        dialog.insetPadding,
        const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      );
      expect(
        dialog.backgroundColor,
        EditorSurfaceStyle.lightCanvasBackground,
      );
      expect(dialog.width, dialog.constraints?.maxWidth);
      expect(dialog.constraints!.maxWidth, lessThanOrEqualTo(960));
      expect(dialog.constraints!.maxHeight, lessThanOrEqualTo(720));
      expect(
        dialog.constraints!.maxWidth / dialog.constraints!.maxHeight,
        closeTo(4 / 3, 0.001),
      );
      expect(
        tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).any(
              (barrier) => barrier.color == null || barrier.color?.a == 0,
            ),
        isTrue,
      );

      await tester.toggleCommandPalette();
      expect(find.byType(CommandPaletteModal), findsNothing);
    });
  });

  group('Search', () {
    testWidgets('Test for searching', (tester) async {
      await tester.initializeAppFlowy();
      await _useLightMode(tester);
      await tester.tapAnonymousSignInButton();
      _expectLightMode(tester);

      await tester.createNewPageWithNameUnderParent(name: 'Switch To New Page');
      await tester.pumpAndSettle();
      await tester.createNewPageWithNameUnderParent(
        name: 'Preview Table',
        layout: ViewLayoutPB.Grid,
      );
      await tester.pumpAndSettle();

      /// tap getting started page
      await tester.tapButton(
        find.descendant(
          of: find.byType(HomeSideBar),
          matching: find.textContaining(gettingStarted),
        ),
      );

      /// show searching page
      final searchingButton = find.text(LocaleKeys.search_label.tr());
      await tester.tapButton(searchingButton);
      final askAIButton = find.byType(SearchAskAiEntrance);
      expect(askAIButton, findsNothing);
      final recentList = find.byType(RecentViewsList);
      expect(recentList, findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey('command-palette-recent-list-panel'),
              ),
            )
            .width,
        lessThanOrEqualTo(470),
      );
      expect(find.byType(SearchFilterBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('command-palette-title-filter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('command-palette-creator-filter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('command-palette-space-filter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('command-palette-page-type-filter')),
        findsOneWidget,
      );

      /// there is [gettingStarted] in recent list
      final gettingStartedRecentCell = find.descendant(
        of: recentList,
        matching: find.textContaining(gettingStarted),
      );
      expect(gettingStartedRecentCell, findsAtLeast(1));

      /// the first recent page is previewed without requiring a hover
      final pagePreview = find.byType(PagePreview);
      expect(pagePreview, findsOneWidget);
      expect(
        find.byKey(const ValueKey('command-palette-inspection-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('command-palette-open-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('command-palette-open-new-tab-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('command-palette-favorite-action')),
        findsOneWidget,
      );
      final previewCard = find.byKey(const ValueKey('page-preview-card'));
      expect(tester.getSize(previewCard).width, lessThanOrEqualTo(304));
      final previewDecoration =
          tester.widget<Container>(previewCard).decoration! as BoxDecoration;
      expect(
        previewDecoration.color,
        EditorSurfaceStyle.lightPreviewBackground,
      );
      expect(
        tester.widget<PagePreview>(pagePreview).view.name,
        contains(gettingStarted),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: pagePreview,
          matching: find.byType(AppFlowyEditor),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('document-preview-canvas')),
        findsOneWidget,
      );
      final previewEditor = find.descendant(
        of: pagePreview,
        matching: find.byType(AppFlowyEditor),
      );
      expect(tester.getSize(previewEditor).width, 520);
      expect(
        tester
            .widget<AppFlowyEditor>(previewEditor)
            .editorStyle
            .padding
            .vertical,
        0,
      );
      expect(
        tester
            .widget<AppFlowyEditor>(previewEditor)
            .editorStyle
            .textStyleConfiguration
            .lineHeight,
        1.4,
      );

      final databaseCell = find.byWidgetPredicate(
        (widget) =>
            widget is SearchRecentViewCell &&
            widget.view.layout == ViewLayoutPB.Grid,
      );
      expect(databaseCell, findsOneWidget);
      await tester.hoverOnWidget(databaseCell);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(
        find.descendant(
          of: pagePreview,
          matching: find.byType(DatabaseTabBarView),
        ),
        findsOneWidget,
      );

      /// searching for [gettingStarted]
      final searchField = find.byType(SearchField);
      final textFiled =
          find.descendant(of: searchField, matching: find.byType(TextField));
      await tester.enterText(textFiled, gettingStarted);
      await tester.pumpAndSettle(Duration(seconds: 1));

      /// there is [gettingStarted] in result list
      final resultList = find.byType(SearchResultList);
      expect(resultList, findsOneWidget);
      final resultCells = find.byType(SearchResultCell);
      expect(resultCells, findsAtLeast(1));

      /// the best match is previewed without requiring a hover
      expect(find.byType(PagePreview), findsOneWidget);

      /// clear search content
      final clearButton = find.byFlowySvg(FlowySvgs.search_clear_m);
      await tester.tapButton(clearButton);
      expect(find.byType(SearchResultList), findsNothing);
      expect(find.byType(RecentViewsList), findsOneWidget);
    });
  });
}

Future<void> _useLightMode(WidgetTester tester) async {
  final materialApp = find.byType(MaterialApp).first;
  tester
      .element(materialApp)
      .read<AppearanceSettingsCubit>()
      .setThemeMode(ThemeMode.light);
  await tester.pumpAndSettle();
  _expectLightMode(tester);
}

void _expectLightMode(WidgetTester tester) {
  final materialApp = find.byType(MaterialApp).first;
  expect(tester.widget<MaterialApp>(materialApp).themeMode, ThemeMode.light);
}
