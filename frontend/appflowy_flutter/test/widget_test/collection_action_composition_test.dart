import 'dart:ui' as ui;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _away = Offset(-20, -20);

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
      '$appearance: persistent collection tabs share one retained action row',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1400, 1600);
        addTearDown(tester.view.reset);
        final definition = CollectionRegistry.typeFor(CollectionKind.database);
        CollectionRegistry.register(
          definition.withViews([
            for (final mode in definition.views)
              CollectionViewDefinition(
                id: mode.id,
                labelKey: mode.labelKey,
                icon: mode.icon,
                isAvailable: mode.isAvailable,
                builder: (_, collection) => _Reading(collection: collection),
              ),
          ]),
        );
        final selectedId = definition.views.last.id;
        final view = ViewPB(
          id: 'collection-action-composition',
          name: 'Research library',
          layout: ViewLayoutPB.Document,
          extra: CollectionMetadata(
            kind: CollectionKind.database,
            activeViewId: selectedId,
          ).mergeIntoExtra(
            const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
          ),
        );
        final saved = view.writeToBuffer();
        final repository = _Repository();
        final controller = WorkspaceExplorerController(
          root: view,
          repository: repository,
          listenForUpdates: false,
        );
        final access = _Access(view);
        final frame = _Frame();
        final outside = FocusNode();
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _away);
        try {
          await controller.initialize();
          await tester.pumpWidget(
            _app(appearance, frame, access, controller, outside),
          );
          await tester.pumpAndSettle();
          final page = find.byType(CollectionPage);
          final row = find.descendant(
            of: page,
            matching: find.byType(WorkspaceActionRow),
          );
          final tabs = find.descendant(
            of: row,
            matching: find.byType(CollectionViewSwitcher),
          );
          final toolbar = find.descendant(
            of: row,
            matching: find.byType(PreviewToolbar),
          );
          final iconRow = find.descendant(
            of: page,
            matching: find.byKey(const ValueKey('workspace-page-icon-row')),
          );
          final iconToolbar = find.descendant(
            of: iconRow,
            matching:
                find.byKey(const ValueKey('view-decoration-icon-actions')),
          );
          final iconRegion = find
              .ancestor(
                of: iconRow,
                matching: find.byType(PreviewToolbarRegion),
              )
              .first;
          expect(row, findsOneWidget);
          expect(tabs, findsOneWidget);
          expect(toolbar, findsOneWidget);
          expect(iconRow, findsOneWidget);
          expect(iconToolbar, findsOneWidget);
          expect(iconRegion, findsOneWidget);
          expect(
            find.ancestor(of: row, matching: find.byType(PreviewToolbarRegion)),
            findsNWidgets(2),
          );
          expect(
            find.descendant(
              of: page,
              matching: find.byType(PreviewToolbarRegion),
            ),
            findsNWidgets(2),
          );
          // Four persistent view tabs plus Search/Add belong to the page row;
          // Add Icon/Add Cover belong only to the separate identity row.
          expect(_buttons(row), findsNWidgets(6));
          expect(_buttons(toolbar), findsNWidgets(2));
          expect(_buttons(iconToolbar), findsNWidgets(2));
          expect(
            find.descendant(
              of: row,
              matching: find.byType(DecorationActionButton),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: iconRow,
              matching: find.byType(WorkspaceActionRow),
            ),
            findsNothing,
          );
          for (final key in ['view-decoration-icon', 'view-decoration-cover']) {
            expect(
              find.descendant(
                of: iconToolbar,
                matching: find.byKey(ValueKey(key)),
              ),
              findsOneWidget,
            );
          }
          final searchButton = find.descendant(
            of: toolbar,
            matching: find.byType(IconButton),
          );
          final addButton = _buttons(
            find.descendant(
              of: toolbar,
              matching: find.byKey(const ValueKey('collection-add')),
            ),
          );
          expect(searchButton, findsOneWidget);
          expect(addButton, findsOneWidget);
          expect(
            find.ancestor(of: tabs, matching: find.byType(PreviewToolbar)),
            findsNothing,
          );
          expect(
            tester.widget<WorkspaceActionRow>(row).leading,
            same(tester.widget<CollectionViewSwitcher>(tabs)),
          );
          final tabElement = tester.element(tabs);
          final toolbarState = tester.state(toolbar);
          final iconToolbarState = tester.state(iconToolbar);
          final iconRegionState = tester.state(iconRegion);
          final decoration = tester.state(find.byType(ViewDecorationActions));
          final reading = tester.state(find.byType(_Reading));
          final nested = tester.state<NestedScrollViewState>(
            find.byType(NestedScrollView),
          );
          final borrowed = nested.innerController;
          final wide = tester.getRect(row);
          final body = tester.getRect(find.byType(_Reading));
          final tabBounds = tester.getRect(tabs);
          final actionBounds = tester.getRect(toolbar);
          final iconBounds = tester.getRect(iconRow);
          expect(tester.getSize(find.byType(CollectionPage)).width, 1120);
          expect(wide.width, 1120 - 48);
          expect(
            wide.left,
            tester
                .getTopLeft(find.byKey(const ValueKey('collection-title')))
                .dx,
          );
          expect(tabBounds.left, wide.left);
          expect(actionBounds.left, closeTo(tabBounds.right + 8, 0.01));
          _expectOneLine(tester, row);
          _expectInside(tester, row);
          expect(
            PaperTheme.isEnabled(tester.element(row)),
            appearance == 'paper',
          );
          expect(_opacity(tester, toolbar), 0);
          expect(_buttons(toolbar).hitTestable(), findsNothing);
          expect(_opacity(tester, iconToolbar), 0);
          expect(_buttons(iconToolbar).hitTestable(), findsNothing);
          final switcher = tester.widget<CollectionViewSwitcher>(tabs);
          expect(switcher.activeViewId, selectedId);
          expect(switcher.views, hasLength(4));
          expect(_buttons(tabs).hitTestable(), findsNWidgets(4));
          for (final mode in switcher.views) {
            expect(find.semantics.byLabel(mode.label), findsOneWidget);
          }
          final coverAction = find.descendant(
            of: iconToolbar,
            matching: find.byKey(const ValueKey('view-decoration-cover')),
          );
          final coverLabel = tester
              .widget<DecorationActionButton>(
                find.descendant(
                  of: coverAction,
                  matching: find.byType(DecorationActionButton),
                ),
              )
              .label;
          expect(find.semantics.byLabel(coverLabel), findsNothing);

          // The whole header reveals both groups. Missing decorations follow
          // exactly the same contextual policy as configured decorations.
          await mouse.moveTo(tester.getCenter(tabs));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          final fade = tester.widget<FadeTransition>(
            find
                .descendant(
                  of: toolbar,
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect(fade.opacity.value, greaterThan(0));
          expect(fade.opacity.value, lessThan(1));
          expect(tester.getRect(row), wide);
          await tester.pumpAndSettle();
          expect(_opacity(tester, toolbar), 1);
          expect(_buttons(toolbar).hitTestable(), findsNWidgets(2));
          for (final button in [searchButton, addButton]) {
            expect(button.hitTestable(), findsOneWidget);
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          }
          expect(_opacity(tester, iconToolbar), 1);
          expect(_buttons(iconToolbar).hitTestable(), findsNWidgets(2));
          expect(find.semantics.byLabel(coverLabel), findsOneWidget);
          expect(tester.getRect(find.byType(_Reading)), body);

          // Hovering the icon also preserves both groups' geometry and state.
          await mouse.moveTo(
            tester.getCenter(
              find.descendant(
                of: iconRow,
                matching: find.byKey(const ValueKey('collection-header-icon')),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(_opacity(tester, iconToolbar), 1);
          expect(_buttons(iconToolbar).hitTestable(), findsNWidgets(2));
          expect(find.semantics.byLabel(coverLabel), findsOneWidget);
          for (final element in _buttons(iconToolbar).evaluate()) {
            final data = tester
                .getSemantics(find.byWidget(element.widget))
                .getSemanticsData();
            expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          }
          expect(tester.state(iconToolbar), same(iconToolbarState));
          expect(tester.getRect(iconRow), iconBounds);
          expect(tester.getRect(row), wide);
          expect(tester.getRect(find.byType(_Reading)), body);
          await mouse.moveTo(_away);
          await tester.pumpAndSettle();
          expect(_opacity(tester, toolbar), 0);
          expect(_opacity(tester, iconToolbar), 0);
          expect(_buttons(iconToolbar).hitTestable(), findsNothing);
          expect(find.semantics.byLabel(coverLabel), findsNothing);
          expect(tester.getRect(row), wide);

          // Native Tab traversal enters the hidden group and reveals it;
          // focus on persistent tabs alone does not pin contextual actions.
          final lastLabel = find.descendant(
            of: tabs,
            matching: find.text(switcher.views.last.label),
          );
          Focus.of(tester.element(lastLabel)).requestFocus();
          await tester.pumpAndSettle();
          expect(_opacity(tester, toolbar), 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final searchGlyph = find.descendant(
            of: searchButton,
            matching: find.byType(WorkspaceGlyph),
          );
          expect(Focus.of(tester.element(searchGlyph)).hasFocus, isTrue);
          expect(_opacity(tester, toolbar), 1);
          expect(_opacity(tester, iconToolbar), 0);
          expect(find.semantics.byLabel(coverLabel), findsNothing);
          final data = tester.getSemantics(searchButton).getSemanticsData();
          expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          final search = find.descendant(
            of: toolbar,
            matching: find.byKey(const ValueKey('collection-search')),
          );
          final field = find.descendant(
            of: search,
            matching: find.byType(EditableText),
          );
          expect(field, findsOneWidget);
          await tester.enterText(
            find.descendant(of: search, matching: find.byType(TextField)),
            'Retained query',
          );
          await tester.pump(const Duration(milliseconds: 180));
          await tester.pumpAndSettle();
          final fieldState = tester.state(field);
          final editor = tester.widget<EditableText>(field);
          const selection = TextSelection(baseOffset: 2, extentOffset: 7);
          editor.controller.selection = selection;

          void expectRetained({bool canEdit = true}) {
            expect(tester.element(tabs), same(tabElement));
            expect(tester.state(toolbar), same(toolbarState));
            expect(tester.state(iconRegion), same(iconRegionState));
            expect(iconToolbar, canEdit ? findsOneWidget : findsNothing);
            if (canEdit) {
              expect(_opacity(tester, iconToolbar), 1);
              expect(_buttons(iconToolbar), findsNWidgets(2));
              expect(_buttons(iconToolbar).hitTestable(), findsNWidgets(2));
            }
            expect(
              find.semantics.byLabel(coverLabel),
              canEdit ? findsOneWidget : findsNothing,
            );
            expect(
              tester.state(find.byType(ViewDecorationActions)),
              same(decoration),
            );
            expect(tester.state(field), same(fieldState));
            expect(
              tester.widget<EditableText>(field).controller,
              same(editor.controller),
            );
            expect(editor.controller.text, 'Retained query');
            expect(editor.controller.selection, selection);
            expect(editor.focusNode.hasFocus, isTrue);
            expect(controller.query, 'Retained query');
            expect(
              tester.widget<CollectionViewSwitcher>(tabs).activeViewId,
              selectedId,
            );
            expect(_buttons(tabs).hitTestable(), findsNWidgets(4));
            expect(tester.state(find.byType(_Reading)), same(reading));
            expect(
              tester
                  .widget<_Reading>(find.byType(_Reading))
                  .collection
                  .explorer,
              same(controller),
            );
            expect(
              tester
                  .widget<_Reading>(find.byType(_Reading))
                  .collection
                  .definition
                  .id,
              selectedId,
            );
            expect(nested.innerController, same(borrowed));
            expect(borrowed.positions, hasLength(1));
            expect(_opacity(tester, toolbar), 1);
            expect(
              _buttons(toolbar).hitTestable(),
              findsNWidgets(canEdit ? 2 : 1),
            );
            _expectInside(tester, row);
            _expectInside(tester, iconRow);
            expect(tester.takeException(), isNull);
          }

          for (final (width, scale, direction) in [
            (320.0, 1.0, ui.TextDirection.ltr),
            (320.0, 2.0, ui.TextDirection.ltr),
            (320.0, 2.0, ui.TextDirection.rtl),
            (1120.0, 1.0, ui.TextDirection.ltr),
          ]) {
            frame
              ..width = width
              ..scale = scale
              ..direction = direction
              ..rebuild();
            await tester.pumpAndSettle();
            expectRetained();
            expect(tester.state(iconToolbar), same(iconToolbarState));
            if (width == 320) {
              expect(tester.getSize(page).width, 320);
              expect(tester.getSize(row).width, 272);
              expect(tester.getSize(row).height, greaterThan(wide.height));
              expect(
                tester.getSize(tabs).height,
                greaterThan(tabBounds.height),
              );
            } else {
              _expectOneLine(tester, row, includeSearch: false);
            }
          }

          // Inherited permission changes must rebuild without replacing the
          // decoration/action subtree. No explicit frame rebuild is involved.
          for (final locked in [true, false]) {
            access.setLocked(locked);
            await tester.pumpAndSettle();
            final actions = tester.widget<ViewDecorationActions>(
              find.byType(ViewDecorationActions),
            );
            expect(actions.showIconAction, !locked);
            expect(actions.showCoverAction, !locked);
            for (final action in [
              addButton,
              find.descendant(
                of: iconToolbar,
                matching: find.byKey(const ValueKey('view-decoration-icon')),
              ),
              coverAction,
            ]) {
              expect(
                action,
                locked ? findsNothing : findsOneWidget,
              );
            }
            expectRetained(canEdit: !locked);
          }
          controller.updateRoot(ViewPB.fromBuffer(saved)..isLocked = true);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('collection-add')), findsNothing);
          expect(find.byType(DecorationActionButton), findsNothing);
          expectRetained(canEdit: false);
          controller.updateRoot(view);
          await tester.pumpAndSettle();
          expectRetained();

          final close = find.descendant(
            of: search,
            matching: find.byType(IconButton),
          );
          await mouse.moveTo(tester.getCenter(close));
          await mouse.down(tester.getCenter(close));
          await mouse.up();
          await mouse.moveTo(_away);
          outside.requestFocus();
          await tester.pumpAndSettle();
          expect(field, findsNothing);
          expect(controller.query, isEmpty);
          expect(_opacity(tester, toolbar), 0);
          expect(_opacity(tester, iconToolbar), 0);
          expect(find.semantics.byLabel(coverLabel), findsNothing);
          expect(tester.getRect(row), wide);
          expect(_buttons(tabs).hitTestable(), findsNWidgets(4));
          expect(view.writeToBuffer(), saved);
          expect(repository.unexpectedCalls, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await disposeVividIconPicker(tester);
          expect(() => controller.updateRoot(view), returnsNormally);
          controller.dispose();
          await access.close();
          outside.dispose();
          frame.dispose();
          semantics.dispose();
          CollectionRegistry.register(definition);
        }
      },
    );
  }
}

class _Frame extends ChangeNotifier {
  double width = 1120;
  double scale = 1;
  ui.TextDirection direction = ui.TextDirection.ltr;
  final styles = ValueNotifier(DefaultIconStyle.monochrome);

  void rebuild() => notifyListeners();

  @override
  void dispose() {
    styles.dispose();
    super.dispose();
  }
}

Widget _app(
  String appearance,
  _Frame frame,
  _Access access,
  WorkspaceExplorerController controller,
  FocusNode outside,
) =>
    vividIconTestApp(
      appearance,
      BlocProvider<PageAccessLevelBloc>.value(
        value: access,
        child: AnimatedBuilder(
          animation: frame,
          builder: (context, _) => DefaultIconStyleScope(
            styles: frame.styles,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(frame.scale),
              ),
              child: Directionality(
                textDirection: frame.direction,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: frame.width,
                    height: 1400,
                    child: Column(
                      children: [
                        Expanded(
                          child: CollectionPage(
                            view: access.view,
                            controller: controller,
                            shellOwnsBreadcrumbs: true,
                          ),
                        ),
                        TextButton(
                          focusNode: outside,
                          onPressed: () {},
                          child: const Text('Outside'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Finder _buttons(Finder scope) => find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is TextButton || widget is IconButton,
      ),
    );

double _opacity(WidgetTester tester, Finder toolbar) => tester
    .widget<AnimatedOpacity>(
      find
          .descendant(of: toolbar, matching: find.byType(AnimatedOpacity))
          .first,
    )
    .opacity;

void _expectOneLine(
  WidgetTester tester,
  Finder row, {
  bool includeSearch = true,
}) {
  final buttons = _buttons(row);
  final center = tester.getCenter(buttons.first).dy;
  for (final element in buttons.evaluate()) {
    // The close button is laid out inside the search field, not by the row.
    if (!includeSearch && element.widget is IconButton) continue;
    expect(
      tester.getCenter(find.byWidget(element.widget)).dy,
      closeTo(center, 0.01),
    );
  }
}

void _expectInside(WidgetTester tester, Finder row) {
  expect(
    find.descendant(of: row, matching: find.byType(SingleChildScrollView)),
    findsNothing,
  );
  final bounds = tester.getRect(row);
  expect(bounds.isFinite, isTrue);
  // Include the retained editor, not just its close button, when search is
  // expanded: a narrow/RTL reflow must leave the typing surface inside the row.
  final controls = find.descendant(
    of: row,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is TextButton ||
          widget is IconButton ||
          widget is EditableText,
    ),
  );
  for (final element in controls.evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    expect(rect.isFinite, isTrue);
    expect(rect.isEmpty, isFalse);
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
    expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
  }
}

// Only data/backend boundaries are replaced; the page and toolbar are real.
class _Repository extends Fake implements WorkspaceItemRepository {
  int unexpectedCalls = 0;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async =>
      FlowyResult.success([]);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected collection write: ${invocation.memberName}');
  }
}

class _Access extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  _Access(this.view)
      : super(
          PageAccessLevelState.initial(view).copyWith(
            accessLevel: ShareAccessLevel.fullAccess,
            isLoadingLockStatus: false,
          ),
        );

  @override
  final ViewPB view;

  void setLocked(bool value) => emit(state.copyWith(isLocked: value));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reading extends StatefulWidget {
  const _Reading({required this.collection});
  final CollectionViewContext collection;

  @override
  State<_Reading> createState() => _ReadingState();
}

class _ReadingState extends State<_Reading> {
  @override
  Widget build(BuildContext context) => ListView(
        controller: CollectionPageScrollScope.maybeOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: const [
          Text('Retained collection content'),
          SizedBox(height: 1600),
        ],
      );
}
