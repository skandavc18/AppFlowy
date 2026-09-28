import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/home_profile_test_support.dart';
import 'vivid_icon_test_support.dart';

const _cover = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#B8C6AF',
);
const _iconAction = ValueKey('view-decoration-icon');
const _coverAction = ValueKey('view-decoration-cover');
const _iconTools = ValueKey('view-decoration-icon-actions');
const _title = ValueKey('workspace-inline-name-editor');

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    for (final (style, layout) in [
      for (final style in DefaultIconStyle.values)
        for (final layout in [
          ViewLayoutPB.Grid,
          ViewLayoutPB.Board,
          ViewLayoutPB.Calendar,
        ])
          (style, layout),
    ]) {
      testWidgets(
        '$appearance/$style/${layout.name} bare actions reveal from the header and keyboard',
        (tester) async {
          final frame = _Frame()
            ..styles.value = style
            ..view.layout = layout;
          final access = _Access(frame.view);
          final semantics = tester.ensureSemantics();
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(-20, -20));
          try {
            await _mount(tester, appearance, frame, access);
            for (final (width, scale, direction) in [
              (720.0, 1.0, ui.TextDirection.ltr),
              (320.0, 2.0, ui.TextDirection.ltr),
              (320.0, 2.0, ui.TextDirection.rtl),
            ]) {
              frame
                ..width = width
                ..scale = scale
                ..direction = direction
                ..rebuild();
              await tester.pumpAndSettle();
              final tools =
                  tester.widget<PreviewToolbar>(find.byKey(_iconTools));
              expect(tools.keepVisible, isFalse);
              expect(find.byType(ViewDecorationActions), findsOneWidget);
              expect(find.byType(ViewCoverImage), findsNothing);
              final bounds =
                  tester.getRect(find.byType(DatabasePageDecoration));
              for (final key in [_iconAction, _coverAction]) {
                expect(_button(key).hitTestable(), findsNothing);
                final label = tester
                    .widget<DecorationActionButton>(
                      find.descendant(
                        of: find.byKey(key),
                        matching: find.byType(DecorationActionButton),
                      ),
                    )
                    .label;
                expect(
                  find.semantics.byLabel(label),
                  key == _iconAction ? findsOneWidget : findsNothing,
                  reason:
                      'The identity glyph stays accessible, not its hidden action.',
                );
              }
              await mouse.moveTo(
                tester.getCenter(
                  find.byKey(const ValueKey('database-page-title')),
                ),
              );
              await tester.pumpAndSettle();
              for (final key in [_iconAction, _coverAction]) {
                final button = _button(key);
                expect(button.hitTestable(), findsOneWidget);
                final data = tester.getSemantics(button).getSemanticsData();
                expect(data.label, isNotEmpty);
                expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
                expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
                final rect = tester.getRect(button);
                final row = tester.getRect(
                  find.byKey(const ValueKey('workspace-page-icon-row')),
                );
                expect(row.inflate(.01).contains(rect.topLeft), isTrue);
                expect(row.inflate(.01).contains(rect.bottomRight), isTrue);
              }
              expect(
                tester.getRect(find.byType(DatabasePageDecoration)),
                bounds,
              );
              await mouse.moveTo(const Offset(-20, -20));
              await tester.pumpAndSettle();
              expect(_button(_iconAction).hitTestable(), findsNothing);
              expect(_button(_coverAction).hitTestable(), findsNothing);
              expect(tester.takeException(), isNull);
            }
            await _tabTo(tester, _button(_iconAction));
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
            _closePopover(tester, _iconAction);
            await tester.pumpAndSettle();
            await _tabTo(tester, _button(_coverAction));
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(find.byType(UploadImageMenu), findsOneWidget);
            final stale =
                tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
            final owner = tester.state(find.byType(ViewDecorationActions));
            access.setEditable(false);
            await tester.pumpAndSettle();
            expect(
              tester.state(find.byType(ViewDecorationActions)),
              same(owner),
            );
            expect(find.byType(UploadImageMenu), findsNothing);
            expect(find.byType(DecorationActionButton), findsNothing);
            // A revoked selection must be rejected before the default backend
            // is called. No storage service is replaced by a permissive fake.
            stale.onSelectedColor!('#123456');
            await tester.pumpAndSettle();
            expect(frame.view.cover, isNull);
            expect(
              tester.widget<_Renderer>(find.byType(_Renderer)).view.cover,
              isNull,
            );
            expect(tester.takeException(), isNull);
          } finally {
            try {
              await mouse.removePointer();
              await disposeVividIconPicker(tester);
              await pumpHomeProfileClose(
                tester,
                access.close(),
                description: 'Page decoration access fixture close',
              );
            } finally {
              frame.dispose();
              semantics.dispose();
            }
          }
        },
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      '$appearance host updates retain cover, title draft and renderer',
      (tester) async {
        final frame = _Frame();
        final access = _Access(frame.view);
        try {
          await _mount(tester, appearance, frame, access);
          final host = tester.state(find.byType(DatabasePageDecorationHost));
          final owner = tester.state(find.byType(ViewDecorationActions));
          final renderer = tester.state(find.byType(_Renderer));
          await tester.tap(find.byKey(const ValueKey('database-page-title')));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(_title), 'Unfinished view name');
          final titleState = tester.state(find.byKey(_title));
          final title = tester.widget<EditableText>(find.byKey(_title));
          title.controller.selection =
              const TextSelection(baseOffset: 2, extentOffset: 8);
          final draft = title.controller.value;
          Element? coverElement;
          for (final (width, scale, showCover) in [
            (720.0, 1.0, true),
            (320.0, 2.0, true),
            (720.0, 1.0, false),
            (320.0, 2.0, true),
          ]) {
            final updated = ViewPB.fromBuffer(frame.view.writeToBuffer())
              ..icon = EmojiIconData.emoji('🌿').toViewIcon()
              ..extra = AutomaticViewCover.markCoverChosenByHand(
                ViewCoverCodec.mergeCover(
                  '{"appflowy_chart":{"show_table":true},"unrelated":42}',
                  showCover ? _cover : const PageStyleCover.none(),
                ),
              );
            frame.listeners.single.updated!(updated);
            frame
              ..width = width
              ..scale = scale
              ..rebuild();
            await tester.pumpAndSettle();
            expect(
              tester.state(find.byType(DatabasePageDecorationHost)),
              same(host),
            );
            expect(
              tester.state(find.byType(ViewDecorationActions)),
              same(owner),
            );
            expect(tester.state(find.byType(_Renderer)), same(renderer));
            expect(
              tester.widget<_Renderer>(find.byType(_Renderer)).view.extra,
              updated.extra,
            );
            expect(tester.state(find.byKey(_title)), same(titleState));
            expect(title.controller.value, draft);
            expect(title.focusNode.hasFocus, isTrue);
            expect(
              find.byType(ViewCoverImage),
              showCover ? findsOneWidget : findsNothing,
            );
            if (showCover) {
              final next = tester.element(find.byType(ViewCoverImage));
              if (coverElement != null) expect(next, same(coverElement));
              coverElement = next;
            } else {
              coverElement = null;
            }
            expect(
              tester.getSize(find.byType(_Renderer)).height,
              greaterThan(0),
            );
            expect(tester.takeException(), isNull);
          }
          access.setEditable(false);
          await tester.pumpAndSettle();
          expect(tester.state(find.byKey(_title)), same(titleState));
          // The existing rename editor selects its retained draft after a
          // refused blur-submit. Access revocation must not persist/discard it.
          expect(title.controller.text, draft.text);
          expect(title.focusNode.hasFocus, isFalse);
          expect(find.byType(DecorationActionButton), findsNothing);
          expect(tester.state(find.byType(_Renderer)), same(renderer));
          expect(frame.view.name, 'View identity');
          access.setEditable(true);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(_title));
          title.focusNode.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        } finally {
          try {
            await disposeVividIconPicker(tester);
            await pumpHomeProfileClose(
              tester,
              access.close(),
              description: 'Page decoration access fixture close',
            );
            expect(
              frame.listeners.every((listener) => listener.stopped),
              isTrue,
            );
          } finally {
            frame.dispose();
          }
        }
      },
      timeout: homeProfileTestTimeout,
    );
  }

  testWidgets(
    'old notifications cannot decorate a rebound or disposed host',
    (tester) async {
      final frame = _Frame();
      final access = _Access(frame.view);
      try {
        await _mount(tester, 'paper', frame, access);
        final old = frame.listeners.single;
        frame.view =
            ViewPB(id: 'B', name: 'Current view', layout: ViewLayoutPB.Grid);
        frame.rebuild();
        await tester.pumpAndSettle();
        expect(old.stopped, isTrue);
        old.updated!(ViewPB(id: 'A', name: 'Stale result'));
        frame
            .listeners.last.updated!(ViewPB(id: 'not-B', name: 'Wrong target'));
        await tester.pumpAndSettle();
        expect(tester.widget<_Renderer>(find.byType(_Renderer)).view.id, 'B');
        expect(find.text('Current view'), findsOneWidget);
        await disposeVividIconPicker(tester);
        frame.listeners.last.updated!(ViewPB(id: 'B', name: 'After close'));
        await tester.pump();
        expect(frame.listeners.every((listener) => listener.stopped), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await disposeVividIconPicker(tester);
          await pumpHomeProfileClose(
            tester,
            access.close(),
            description: 'Page decoration access fixture close',
          );
        } finally {
          frame.dispose();
        }
      }
    },
    timeout: homeProfileTestTimeout,
  );

  testWidgets(
    'embedded decoration host is inert and does not subscribe',
    (tester) async {
      final frame = _Frame()
        ..view.icon = EmojiIconData.emoji('🌿').toViewIcon()
        ..view.extra = ViewCoverCodec.mergeCover('', _cover);
      await tester.pumpWidget(
        vividIconTestApp(
          'paper',
          DatabasePageDecorationHost(
            view: frame.view,
            enabled: false,
            listenerFactory: frame.listen,
            builder: (view) => _Renderer(view: view),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DatabasePageDecoration), findsNothing);
      expect(find.byType(ViewDecorationActions), findsNothing);
      expect(find.byType(WorkspacePageHeader), findsNothing);
      expect(find.byType(ViewCoverImage), findsNothing);
      expect(frame.listeners, isEmpty);
      await tester.pumpWidget(const SizedBox());
      frame.dispose();
    },
    timeout: homeProfileTestTimeout,
  );

  // Installed MultiBlocProvider/MultiProvider/Nested expose neither a child
  // getter nor unmounted child diagnostics. These pages start backend reads
  // on mount without an injectable boundary. Keep ONLY their wiring as a
  // source contract; the mounted tests above exercise the actual host behavior.
  for (final (fileName, pageName) in [
    ('chart_plugin.dart', 'ChartPage'),
    ('map_plugin.dart', 'MapPage'),
    ('slide_plugin.dart', 'SlidePage'),
    ('table_view_plugin.dart', 'TableViewPage'),
  ]) {
    test(
      '$fileName wires one full-page decoration owner (source contract)',
      () {
        final source =
            File('lib/plugins/collection/$fileName').readAsStringSync();
        // Stop at the next member: providers in rightBarItem must not satisfy
        // a missing provider or decoration owner in buildWidget.
        final methods = RegExp(
          r'\bWidget\s+buildWidget\(\{.*?(?=\n\s*@override)',
          dotAll: true,
        ).allMatches(source);
        expect(
          methods,
          hasLength(1),
          reason: 'Expected exactly one bounded buildWidget in $fileName.',
        );
        final method = methods.single.group(0)!.replaceAll(RegExp(r'\s+'), '');
        expect(method, contains('MultiBlocProvider('));
        expect(
          method,
          contains('BlocProvider<ViewInfoBloc>.value(value:viewInfoBloc)'),
        );
        expect(
          method,
          contains(
            'BlocProvider<PageAccessLevelBloc>.value(value:pageAccessLevelBloc)',
          ),
        );
        expect(
          RegExp(r'\bDatabasePageDecorationHost\(').allMatches(method),
          hasLength(1),
        );
        expect(
          method,
          contains(
            'child:DatabasePageDecorationHost(view:view,'
            'enabled:!shrinkWrap&&data?[kDatabasePluginWidgetBuilderNode]==null,',
          ),
        );
        final rendererArguments = fileName == 'table_view_plugin.dart'
            ? 'view:view,kind:kind'
            : 'view:view';
        expect(
          method,
          contains(
            'builder:(view)=>$pageName('
            'key:ValueKey(view.id),$rendererArguments),',
          ),
        );
      },
      timeout: homeProfileTestTimeout,
    );
  }
}

class _Frame extends ChangeNotifier {
  ViewPB view =
      ViewPB(id: 'A', name: 'View identity', layout: ViewLayoutPB.Grid);
  final styles = ValueNotifier(DefaultIconStyle.monochrome);
  final listeners = <_Listener>[];
  double width = 720;
  double scale = 1;
  ui.TextDirection direction = ui.TextDirection.ltr;
  void rebuild() => notifyListeners();
  ViewListener listen(String id) {
    final listener = _Listener(id);
    listeners.add(listener);
    return listener;
  }

  @override
  void dispose() {
    styles.dispose();
    super.dispose();
  }
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  _Frame frame,
  _Access access,
) async {
  await tester.pumpWidget(
    vividIconTestApp(
      appearance,
      BlocProvider<PageAccessLevelBloc>.value(
        value: access,
        child: DefaultIconStyleScope(
          styles: frame.styles,
          child: AnimatedBuilder(
            animation: frame,
            builder: (context, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(frame.scale)),
              child: Directionality(
                textDirection: frame.direction,
                child: SizedBox(
                  width: frame.width,
                  height: 580,
                  child: DatabasePageDecorationHost(
                    view: frame.view,
                    listenerFactory: frame.listen,
                    builder: (view) => _Renderer(view: view),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _button(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextButton));

void _closePopover(WidgetTester tester, Key key) {
  final root = find.byKey(key);
  final popover = tester.widget(root) is AppFlowyPopover
      ? root
      : find.descendant(of: root, matching: find.byType(AppFlowyPopover));
  tester.widget<AppFlowyPopover>(popover).controller!.close();
}

Future<void> _tabTo(WidgetTester tester, Finder button) async {
  for (var i = 0; i < 12; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    if (tester
        .getSemantics(button)
        .getSemanticsData()
        .hasFlag(ui.SemanticsFlag.isFocused)) {
      return;
    }
  }
  fail('Native Tab traversal did not reach the decoration action');
}

class _Listener extends ViewListener {
  _Listener(String id) : super(viewId: id);
  void Function(ViewPB)? updated;
  bool stopped = false;
  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) =>
      updated = onViewUpdated;
  @override
  Future<void> stop() async => stopped = true;
}

class _Access extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  _Access(this.view) : super(_AccessState(view, true));
  @override
  final ViewPB view;
  void setEditable(bool editable) => emit(_AccessState(view, editable));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Permission is an injected boundary, not a global feature/preference write.
class _AccessState extends Fake implements PageAccessLevelState {
  _AccessState(this.view, this.isEditable);
  @override
  final ViewPB view;
  @override
  bool get isLoadingLockStatus => false;
  @override
  bool get isReadOnly => !isEditable;
  @override
  final bool isEditable;
}

class _Renderer extends StatefulWidget {
  const _Renderer({required this.view});
  final ViewPB view;
  @override
  State<_Renderer> createState() => _RendererState();
}

class _RendererState extends State<_Renderer> {
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Colors.transparent,
        child: Center(child: Text('Retained renderer')),
      );
}
