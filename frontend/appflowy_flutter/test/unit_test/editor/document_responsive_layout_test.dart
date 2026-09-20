import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_list.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/cover_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_layout.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

const _widths = [320.0, 480.0, 800.0, 1280.0, 1920.0, 2560.0];
const _title = ValueKey('responsive-title-draft');
const _body = ValueKey('responsive-body-draft');
const _titleField = ValueKey('responsive-title-field');
const _bodyField = ValueKey('responsive-body-field');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Load the family the real desktop theme resolves, not a test-only alias.
    final loader = FontLoader(preferredFontFamily)
      ..addFont(
        rootBundle.load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
      );
    await loader.load();
    await binding.handleSystemMessage({'type': 'fontsChange'});
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
  });

  test('main document geometry uses the actual action row, not the old 44px',
      () {
    expect(BlockActionList.gutterWidth, 63);
    expect(BlockActionList.gutterWidth, BlockActionButton.size * 2 + 7);
    expect(
      EditorStyleCustomizer.documentHeaderPadding(
        const EdgeInsets.only(left: 17, top: 3, right: 80, bottom: 4),
      ),
      const EdgeInsets.fromLTRB(80, 3, 80, 4),
    );
    expect(
      EditorStyleCustomizer.documentHeaderPadding(
        const EdgeInsets.only(left: 80, right: 17),
        textDirection: TextDirection.rtl,
      ),
      const EdgeInsets.symmetric(horizontal: 80),
    );
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final shrinkWrap in [false, true]) {
      testWidgets(
        '$mode shrinkWrap=$shrinkWrap: aligned reading edges and retained drafts',
        (tester) async {
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          final fixture = _DocumentFixture(shrinkWrap: shrinkWrap);
          final documentBefore = fixture.editor.document.toJson();
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(2560, 1200);
            await tester.pumpWidget(fixture.build(mode));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await mouse.addPointer(location: const Offset(2500, 1150));
            final editorWidgetState = tester.state(find.byType(AppFlowyEditor));
            final selectionService = fixture.editor.service.selectionService;
            final keyboardService = fixture.editor.service.keyboardService;
            expect(keyboardService, isNotNull);
            final titleState =
                tester.state<_DraftFieldState>(find.byKey(_title));
            final bodyState = tester.state<_DraftFieldState>(find.byKey(_body));
            final coverState = tester.state(find.byType(DocumentCover));
            await tester.enterText(find.byKey(_bodyField), 'An unsaved draft');
            bodyState.controller.selection =
                const TextSelection(baseOffset: 3, extentOffset: 7);
            final baselines = <(double, double), List<Rect>>{};

            for (final width in _widths) {
              for (final dpr in [1.0, 2.0]) {
                tester.view.devicePixelRatio = dpr;
                tester.view.physicalSize = Size(2560 * dpr, 1200 * dpr);
                for (final (scale, disableAnimations) in [
                  (1.0, false),
                  (1.0, true),
                  (2.0, false),
                  (2.0, true),
                ]) {
                  // The window stays wide; only this editor pane changes size.
                  // A MediaQuery-based page measurement fails these assertions.
                  await mouse.moveTo(const Offset(2500, 1150));
                  fixture.width = width;
                  fixture.textScale = scale;
                  fixture.disableAnimations = disableAnimations;
                  fixture.rebuild();
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  final geometry = WorkspaceDocumentGeometry.resolve(
                    availableWidth: width,
                    preferredMaxWidth: fixture.preferredMaxWidth,
                    actionGutterWidth: BlockActionList.gutterWidth,
                  );
                  final title = tester.getRect(find.byKey(_titleField));
                  final body = tester.getRect(find.byKey(_bodyField));
                  final cover = tester.getRect(find.byType(DesktopCover));
                  final gutter = tester.getRect(find.byType(BlockActionList));
                  expect(gutter.width, BlockActionList.gutterWidth);
                  expect(gutter.right, closeTo(body.left, 0.01));
                  for (final rect in [title, body, cover]) {
                    expect(
                      rect.left,
                      closeTo(geometry.outerInset + geometry.contentLeft, 0.01),
                    );
                    expect(
                      width - rect.right,
                      closeTo(
                        geometry.outerInset + geometry.contentRight,
                        0.01,
                      ),
                    );
                    expect(rect.width, closeTo(geometry.contentWidth, 0.01));
                  }
                  final key = (width, scale);
                  final rects = [title, body, cover, gutter];
                  if (baselines.containsKey(key)) {
                    expect(
                      rects,
                      baselines[key],
                      reason:
                          'DPR and reduced motion must not change logical geometry',
                    );
                  } else {
                    baselines[key] = rects;
                  }

                  await mouse.moveTo(Offset(body.left - 8, body.top + 14));
                  await tester.pumpAndSettle();
                  final buttons = find.byType(BlockActionButton);
                  expect(buttons, findsNWidgets(2));
                  expect(buttons.hitTestable(), findsNWidgets(2));
                  for (var index = 0; index < 2; index++) {
                    final button = tester.getRect(buttons.at(index));
                    expect(button.width, BlockActionButton.size);
                    expect(
                      button.height,
                      greaterThanOrEqualTo(BlockActionButton.size),
                    );
                    expect(button.left, greaterThanOrEqualTo(0));
                    expect(button.right, lessThanOrEqualTo(body.left));
                  }
                  expect(
                    tester.state(find.byType(AppFlowyEditor)),
                    same(editorWidgetState),
                  );
                  expect(
                    fixture.editor.service.selectionService,
                    same(selectionService),
                  );
                  expect(
                    fixture.editor.service.keyboardService,
                    same(keyboardService),
                  );
                  expect(tester.state(find.byKey(_title)), same(titleState));
                  expect(tester.state(find.byKey(_body)), same(bodyState));
                  expect(
                    tester.state(find.byType(DocumentCover)),
                    same(coverState),
                  );
                  expect(
                    Directionality.of(tester.element(find.byKey(_body))),
                    TextDirection.ltr,
                  );
                  expect(
                    MediaQuery.disableAnimationsOf(
                      tester.element(find.byKey(_body)),
                    ),
                    disableAnimations,
                  );
                  expect(bodyState.focus.hasFocus, isTrue);
                  expect(bodyState.controller.text, 'An unsaved draft');
                  expect(
                    bodyState.controller.selection,
                    const TextSelection(baseOffset: 3, extentOffset: 7),
                  );
                  expect(fixture.preferredMaxWidth, 1920);
                  expect(
                    PaperTheme.isEnabled(tester.element(find.byKey(_body))),
                    mode == 'paper',
                  );
                  expect(tester.takeException(), isNull);
                }
              }
            }

            // A custom saved width and a focused title survive narrowing too.
            await tester.enterText(find.byKey(_titleField), 'Title draft');
            titleState.controller.selection =
                const TextSelection(baseOffset: 1, extentOffset: 4);
            fixture.preferredMaxWidth = 1111;
            for (final width in [2560.0, 320.0, 800.0, 1920.0]) {
              fixture.width = width;
              fixture.rebuild();
              await tester.pumpAndSettle();
              expect(tester.state(find.byKey(_title)), same(titleState));
              expect(titleState.focus.hasFocus, isTrue);
              expect(titleState.controller.text, 'Title draft');
              expect(
                titleState.controller.selection,
                const TextSelection(baseOffset: 1, extentOffset: 4),
              );
              expect(fixture.preferredMaxWidth, 1111);
              expect(
                fixture.editor.editorStyle.maxWidth,
                width < 1111 ? width : 1111,
              );
              expect(tester.takeException(), isNull);
            }
            expect(fixture.editor.document.toJson(), documentBefore);
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox.shrink());
            fixture.scroll.dispose();
            fixture.editor.dispose();
            semantics.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets(
    'RTL mirrors the action gutter without moving reading edges',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(2560, 1200);
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final fixture = _DocumentFixture(
        shrinkWrap: false,
        textDirection: TextDirection.rtl,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(2500, 1150));
      try {
        await tester.pumpWidget(fixture.build('paper'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final editorWidgetState = tester.state(find.byType(AppFlowyEditor));
        final titleState = tester.state<_DraftFieldState>(find.byKey(_title));
        final bodyState = tester.state<_DraftFieldState>(find.byKey(_body));
        final coverState = tester.state(find.byType(DocumentCover));
        await tester.enterText(find.byKey(_bodyField), 'An unsaved RTL draft');
        bodyState.controller.selection =
            const TextSelection(baseOffset: 3, extentOffset: 7);
        final documentBefore = fixture.editor.document.toJson();
        final baselines = <(double, double), List<Rect>>{};
        for (final width in _widths) {
          for (final dpr in [1.0, 2.0]) {
            tester.view.devicePixelRatio = dpr;
            tester.view.physicalSize = Size(2560 * dpr, 1200 * dpr);
            for (final (scale, disableAnimations) in [
              (1.0, false),
              (1.0, true),
              (2.0, false),
              (2.0, true),
            ]) {
              await mouse.moveTo(const Offset(2500, 1150));
              fixture.width = width;
              fixture.textScale = scale;
              fixture.disableAnimations = disableAnimations;
              fixture.rebuild();
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final geometry = WorkspaceDocumentGeometry.resolve(
                availableWidth: width,
                preferredMaxWidth: fixture.preferredMaxWidth,
                actionGutterWidth: BlockActionList.gutterWidth,
              );
              final title = tester.getRect(find.byKey(_titleField));
              final body = tester.getRect(find.byKey(_bodyField));
              final cover = tester.getRect(find.byType(DesktopCover));
              final gutter = tester.getRect(find.byType(BlockActionList));
              for (final rect in [title, body, cover]) {
                expect(
                  rect.left,
                  closeTo(geometry.outerInset + geometry.contentRight, 0.01),
                );
                expect(
                  width - rect.right,
                  closeTo(geometry.outerInset + geometry.contentLeft, 0.01),
                );
                expect(rect.width, closeTo(geometry.contentWidth, 0.01));
              }
              expect(gutter.width, BlockActionList.gutterWidth);
              expect(gutter.left, closeTo(body.right, 0.01));
              final key = (width, scale);
              final rects = [title, body, cover, gutter];
              if (baselines.containsKey(key)) {
                expect(
                  rects,
                  baselines[key],
                  reason:
                      'DPR and reduced motion must not change logical RTL geometry',
                );
              } else {
                baselines[key] = rects;
              }
              await mouse.moveTo(Offset(body.right + 8, body.top + 14));
              await tester.pumpAndSettle();
              final buttons = find.byType(BlockActionButton);
              expect(buttons, findsNWidgets(2));
              expect(buttons.hitTestable(), findsNWidgets(2));
              for (var index = 0; index < 2; index++) {
                final button = tester.getRect(buttons.at(index));
                expect(button.left, greaterThanOrEqualTo(body.right));
                expect(button.right, lessThanOrEqualTo(width));
                expect(button.width, BlockActionButton.size);
                expect(
                  button.height,
                  greaterThanOrEqualTo(BlockActionButton.size),
                );
              }
              expect(
                tester.state(find.byType(AppFlowyEditor)),
                same(editorWidgetState),
              );
              expect(tester.state(find.byKey(_title)), same(titleState));
              expect(tester.state(find.byKey(_body)), same(bodyState));
              expect(
                tester.state(find.byType(DocumentCover)),
                same(coverState),
              );
              expect(bodyState.focus.hasFocus, isTrue);
              expect(bodyState.controller.text, 'An unsaved RTL draft');
              expect(
                bodyState.controller.selection,
                const TextSelection(baseOffset: 3, extentOffset: 7),
              );
              for (final field in [_title, _body]) {
                expect(
                  Directionality.of(tester.element(find.byKey(field))),
                  TextDirection.rtl,
                );
              }
              expect(
                MediaQuery.disableAnimationsOf(
                  tester.element(find.byKey(_body)),
                ),
                disableAnimations,
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
        expect(fixture.editor.document.toJson(), documentBefore);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.scroll.dispose();
        fixture.editor.dispose();
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('title first-line measurement follows accessibility scaling',
      (tester) async {
    const titleLineKey = ValueKey('measured-title-line');
    final theme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    double? normalHeight;
    late double height;
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) {
                height = coverTitleLineHeight(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: RichText(
                    key: titleLineKey,
                    text: TextSpan(
                      text: 'A',
                      style: coverTitleTextStyle(context),
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
      );
      final rendered = tester.widget<RichText>(find.byKey(titleLineKey));
      final painter = TextPainter(
        text: rendered.text,
        textDirection: rendered.textDirection,
        textScaler: rendered.textScaler,
        maxLines: rendered.maxLines,
      );
      try {
        painter.layout();
        expect(height, painter.height);
        expect(tester.getSize(find.byKey(titleLineKey)).height, height);
      } finally {
        painter.dispose();
      }
      if (normalHeight == null) {
        normalHeight = height;
      } else {
        // Line boxes round independently at each scale (43px can become 85px,
        // not 86px). Match the actual metrics above, but still require growth.
        expect(height, greaterThan(normalHeight * 1.9));
      }
      expect(tester.takeException(), isNull);
    }
  });
}

class _DocumentFixture {
  _DocumentFixture({
    required bool shrinkWrap,
    this.textDirection = TextDirection.ltr,
  }) {
    final root = pageNode(children: [Node(type: 'responsive_draft')]);
    root.updateAttributes({
      DocumentHeaderBlockKeys.coverType: CoverType.color.toString(),
      DocumentHeaderBlockKeys.coverDetails: '0xffb9a6d6',
    });
    editor = EditorState(document: Document(root: root))
      ..disableSealTimer = true;
    scroll =
        EditorScrollController(editorState: editor, shrinkWrap: shrinkWrap);
    when(() => appearance.state).thenReturn(
      _appearance().copyWith(
        layoutDirection: textDirection == TextDirection.rtl
            ? LayoutDirection.rtlLayout
            : LayoutDirection.ltrLayout,
      ),
    );
    when(() => appearance.stream)
        .thenAnswer((_) => const Stream<AppearanceSettingsState>.empty());
  }

  final appearance = _MockAppearanceCubit();
  final TextDirection textDirection;
  late final EditorState editor;
  late final EditorScrollController scroll;
  late VoidCallback rebuild;
  double width = 1280;
  double preferredMaxWidth = 1920;
  double textScale = 1;
  bool disableAnimations = false;

  Widget build(String mode) => BlocProvider<AppearanceSettingsCubit>.value(
        value: appearance,
        child: MaterialApp(
          theme: DesktopAppearance().getThemeData(
            mode == 'paper'
                ? AppTheme.builtins.firstWhere(
                    (theme) => theme.themeName == BuiltInTheme.paper,
                  )
                : AppTheme.fallback,
            mode == 'dark' ? Brightness.dark : Brightness.light,
            defaultFontFamily,
            builtInCodeFontFamily,
          ),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => Directionality(
            textDirection: textDirection,
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = () => setState(() {});
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(textScale),
                    disableAnimations: disableAnimations,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      height: 1100,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final customizer = EditorStyleCustomizer.document(
                            context: context,
                            constraints: constraints,
                            preferredMaxWidth: preferredMaxWidth,
                            editorState: editor,
                            textDirection: textDirection,
                          );
                          final style = EditorStyle.desktop(
                            padding: customizer.padding,
                            maxWidth: customizer.width,
                            textScaleFactor: textScale,
                            // The editor resolves block direction from its style,
                            // not only the surrounding Directionality widget.
                            defaultTextDirection: textDirection.name,
                          );
                          return AppFlowyEditor(
                            editorState: editor,
                            editorStyle: style,
                            editorScrollController: scroll,
                            // Keep real services: the page header and action
                            // buttons register selection gesture interceptors.
                            contextMenuItems: const [],
                            header: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DocumentCover(
                                  view: ViewPB(id: 'responsive-test-cover'),
                                  node: editor.document.root,
                                  editorState: editor,
                                  coverType: CoverType.color,
                                  coverDetails: '0xffb9a6d6',
                                  onChangeCover: (_, __) {},
                                ),
                                DocumentHeaderContent(
                                  editorStyle: style,
                                  child: const _DraftField(
                                    key: _title,
                                    fieldKey: _titleField,
                                    initialText: 'Page title',
                                    isTitle: true,
                                  ),
                                ),
                              ],
                            ),
                            blockComponentBuilders: {
                              ...standardBlockComponentBuilderMap,
                              PageBlockKeys.type:
                                  CustomPageBlockComponentBuilder(),
                              'responsive_draft':
                                  _ResponsiveBlockBuilder(editor),
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _ResponsiveBlockBuilder extends BlockComponentBuilder {
  _ResponsiveBlockBuilder(this.editor);

  final EditorState editor;

  @override
  BlockComponentWidget build(BlockComponentContext context) => _ResponsiveBlock(
        key: context.node.key,
        node: context.node,
        editor: editor,
      );
}

class _ResponsiveBlock extends BlockComponentStatelessWidget {
  const _ResponsiveBlock({
    super.key,
    required super.node,
    required this.editor,
  }) : super(configuration: const BlockComponentConfiguration());

  final EditorState editor;

  @override
  Widget build(BuildContext context) => BlockComponentActionWrapper(
        node: node,
        actionBuilder: (context, state) => BlockActionList(
          blockComponentContext: BlockComponentContext(context, node),
          blockComponentState: state,
          editorState: editor,
          actions: const [],
          showSlashMenu: () {},
          blockComponentBuilder: const {},
        ),
        child: const _DraftField(
          key: _body,
          fieldKey: _bodyField,
          initialText: 'Body draft',
        ),
      );
}

class _DraftField extends StatefulWidget {
  const _DraftField({
    super.key,
    required this.fieldKey,
    required this.initialText,
    this.isTitle = false,
  });

  final Key fieldKey;
  final String initialText;
  final bool isTitle;

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  late final controller = TextEditingController(text: widget.initialText);
  final focus = FocusNode();

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: widget.fieldKey,
        controller: controller,
        focusNode: focus,
        maxLines: null,
        style: widget.isTitle
            ? coverTitleTextStyle(context)
            : const TextStyle(fontSize: 16),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
        ),
      );
}

class _MockAppearanceCubit extends Mock implements AppearanceSettingsCubit {}

AppearanceSettingsState _appearance() {
  final dates = DateTimeSettingsPB();
  return AppearanceSettingsState(
    appTheme: AppTheme.fallback,
    themeMode: ThemeMode.light,
    font: defaultFontFamily,
    layoutDirection: LayoutDirection.ltrLayout,
    textDirection: AppFlowyTextDirection.ltr,
    enableRtlToolbarItems: false,
    locale: const Locale('en', 'US'),
    isMenuCollapsed: false,
    menuOffset: 0,
    dateFormat: dates.dateFormat,
    timeFormat: dates.timeFormat,
    timezoneId: dates.timezoneId,
    documentCursorColor: null,
    documentSelectionColor: null,
    textScaleFactor: 1,
    enableKineticScrolling: true,
  );
}
