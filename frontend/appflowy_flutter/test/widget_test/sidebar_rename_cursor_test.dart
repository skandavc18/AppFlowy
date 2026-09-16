import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });
  setUp(getIt.pushNewScope);
  tearDown(getIt.popScope);

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final kind in ['page', 'folder', 'file']) {
      testWidgets('$appearance $kind: text cursor only during explicit rename',
          (tester) async {
        final view = ViewPB(
          id: 'sidebar-$kind',
          name: kind == 'file' ? 'Report.txt' : 'Research',
          extra: switch (kind) {
            'folder' => const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
            'file' => const WorkspaceItemMetadata.file(
                contentKind: WorkspaceFileContentKind.collaborativeText,
                storageUrl: '',
              ).mergeIntoExtra(''),
            _ => '',
          },
        );
        final bloc = _ViewBloc(view);
        var opened = 0;
        final mouse = TestGesture(
          dispatcher: tester.sendEventToBinding,
          kind: PointerDeviceKind.mouse,
          device: 42,
        );
        try {
          await tester.pumpWidget(_app(appearance, const SizedBox()));
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            _app(
              appearance,
              BlocProvider<ViewBloc>.value(
                value: bloc,
                child: BlocBuilder<ViewBloc, ViewState>(
                  builder: (_, state) => SingleInnerViewItem(
                    view: state.view,
                    parentView: null,
                    isExpanded: false,
                    level: 0,
                    leftPadding: SidebarMetrics.indent,
                    isDraggable: false,
                    spaceType: FolderSpaceType.public,
                    showActions: state.isEditing,
                    enableRightClickContext: true,
                    onSelected: (_, __) => opened++,
                    isFeedback: false,
                    height: SidebarMetrics.rowHeight,
                    leftIconBuilder: (_, __) => null,
                    rightIconsBuilder: (_, __) => [],
                    includeDefaultMoreAction: true,
                    extendBuilder: null,
                    disableSelectedStatus: null,
                    shouldIgnoreView: null,
                    isSelected: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            PaperTheme.isEnabled(tester.element(find.byType(SidebarRow))),
            appearance == 'paper',
          );
          final label = find.text(view.name);
          await mouse.addPointer(location: tester.getCenter(label));
          await tester.pumpAndSettle();
          expect(
            tester.binding.mouseTracker.debugDeviceActiveCursor(42),
            SystemMouseCursors.click,
          );
          expect(find.byType(EditableText), findsNothing);

          await tester.tap(label);
          await tester.pump(const Duration(milliseconds: 350));
          expect(opened, 1);
          expect(find.byType(EditableText), findsNothing);

          await tester.tap(label);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(label);
          await tester.pump(const Duration(milliseconds: 350));
          var editor = find.byType(EditableText);
          expect(editor, findsOneWidget);
          expect(opened, 1);
          await mouse.moveTo(tester.getCenter(editor));
          await tester.pump();
          expect(
            tester.binding.mouseTracker.debugDeviceActiveCursor(42),
            SystemMouseCursors.text,
          );
          final field = tester.widget<EditableText>(editor);
          expect(field.focusNode.hasFocus, isTrue);
          expect(
            field.controller.selection,
            TextSelection(
              baseOffset: 0,
              extentOffset: kind == 'file'
                  ? view.name.lastIndexOf('.')
                  : view.name.length,
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await mouse.moveTo(tester.getCenter(label));
          await tester.pump();
          expect(find.byType(EditableText), findsNothing);
          expect(
            tester.binding.mouseTracker.debugDeviceActiveCursor(42),
            SystemMouseCursors.click,
          );

          // Opening a context menu alone is not rename mode. The real Rename
          // action enters it, even when this is not the selected sidebar row.
          await tester.tap(label, buttons: kSecondaryMouseButton);
          await tester.pumpAndSettle();
          expect(find.text('Rename'), findsOneWidget);
          expect(find.byType(EditableText), findsNothing);
          await tester.tap(find.text('Rename'));
          await tester.pump(const Duration(milliseconds: 350));
          editor = find.byType(EditableText);
          expect(editor, findsOneWidget);
          await mouse.moveTo(tester.getCenter(editor));
          await tester.pump();
          expect(
            tester.binding.mouseTracker.debugDeviceActiveCursor(42),
            SystemMouseCursors.text,
          );
          expect(opened, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await mouse.moveTo(tester.getCenter(label));
          await tester.pump();
          expect(
            tester.binding.mouseTracker.debugDeviceActiveCursor(42),
            SystemMouseCursors.click,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await bloc.close();
        }
      });
    }
  }
}

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: DesktopAppearance()
              .getThemeData(
                appearance == 'paper'
                    ? AppTheme.builtins
                        .firstWhere((t) => t.themeName == BuiltInTheme.paper)
                    : AppTheme.fallback,
                appearance == 'dark' ? Brightness.dark : Brightness.light,
                defaultFontFamily,
                builtInCodeFontFamily,
              )
              .copyWith(platform: TargetPlatform.windows),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 280, child: child),
            ),
          ),
        ),
      ),
    );

/// Only the hover/menu edit-state notifications are needed; no native backend
/// or user workspace is initialized by these interaction tests.
class _ViewBloc extends Cubit<ViewState> implements ViewBloc {
  _ViewBloc(ViewPB view) : super(ViewState.init(view));

  @override
  void add(ViewEvent event) {
    event.mapOrNull(
      setIsEditing: (event) => emit(state.copyWith(isEditing: event.isEditing)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
