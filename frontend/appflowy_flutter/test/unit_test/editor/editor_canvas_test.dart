import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _capture = ValueKey('actual-document-canvas');
const _customCanvas = Color(0xFFE8F2EF);
const _canvases = {
  'default light': Color(0xFFFFFCF6),
  'custom light': _customCanvas,
  'dark': Color(0xFF191A19),
  'paper': PaperTheme.editorBackground,
};

void main() {
  final oldFontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = oldFontFetching);

  for (final entry in _canvases.entries) {
    testWidgets(
        '${entry.key}: context helper uses the semantic canvas, not caller white',
        (tester) async {
      late Color color;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(entry.key),
          home: Builder(
            builder: (context) {
              color = EditorSurfaceStyle.canvasBackground(
                context,
                fallback: Colors.white,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(color, entry.value);
      expect(tester.takeException(), isNull);
    });

    for (final shrinkWrap in [false, true]) {
      testWidgets(
        '${entry.key}: actual document canvas paints correctly (shrinkWrap: $shrinkWrap)',
        (tester) async {
          final fixture = _CanvasFixture(shrinkWrap: shrinkWrap);
          try {
            await tester.pumpWidget(fixture.build(_theme(entry.key)));
            await tester.pumpAndSettle();
            final page = find.byType(CustomPageBlockComponent);
            expect(page, findsOneWidget);
            expect(
              tester.getSize(find.byType(AppFlowyEditor)),
              const Size(600, 400),
            );
            expect(tester.getSize(page), const Size(600, 400));
            expect(await _canvasPixel(tester), entry.value);
            expect(fixture.editor.document.toJson(), fixture.initialDocument);
            expect(fixture.editor.service.selectionService, isNotNull);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            fixture.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets(
      'without a premium extension custom Light keeps its explicit fallback',
      (tester) async {
    const fallback = Color(0xFFDBE8F5);
    const themeSurface = Color(0xFFE6E0F2);
    late Color explicit;
    late Color implicit;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(surface: themeSurface),
        ),
        home: Builder(
          builder: (context) {
            explicit = EditorSurfaceStyle.canvasBackground(
              context,
              fallback: fallback,
            );
            implicit = EditorSurfaceStyle.canvasBackground(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(explicit, fallback);
    expect(implicit, themeSurface);
    // Existing callers of the pure helper still own their non-Paper fallback.
    expect(
      EditorSurfaceStyle.canvasBackgroundFor(Brightness.light, fallback),
      fallback,
    );
  });

  testWidgets('a Paper marker never replaces a custom dark canvas',
      (tester) async {
    const darkCanvas = Color(0xFF242031);
    final base = _theme('dark');
    final palette =
        base.extension<PremiumThemeExtension>()!.copyWith(canvas: darkCanvas);
    late Color color;
    await tester.pumpWidget(
      MaterialApp(
        theme: base.copyWith(
          extensions: [
            ...base.extensions.values.where(
              (extension) =>
                  extension is! PremiumThemeExtension &&
                  extension is! PaperThemeExtension,
            ),
            palette,
            const PaperThemeExtension(enabled: true),
          ],
        ),
        home: Builder(
          builder: (context) {
            color = EditorSurfaceStyle.canvasBackground(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(color, darkCanvas);
  });

  for (final appearance in _canvases.keys) {
    testWidgets('$appearance preview keeps its host canvas without remounting',
        (tester) async {
      final fixture = _CanvasFixture(shrinkWrap: true);
      try {
        await tester.pumpWidget(fixture.build(_theme(appearance)));
        await tester.pumpAndSettle();
        final renderer = tester.state(find.byType(AppFlowyEditor));
        await tester.pumpWidget(
          fixture.build(_theme(appearance), preview: true),
        );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(AppFlowyEditor)), same(renderer));
        // Capture only the editor layer, not its ancestor host. Transparent
        // pixels let any card surface show through instead of painting a page.
        expect(await _canvasPixel(tester), Colors.transparent);
        expect(fixture.editor.document.toJson(), fixture.initialDocument);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    });
  }

  for (final shrinkWrap in [false, true]) {
    testWidgets(
      'theme and pane changes retain document, renderer, scroll and draft (shrinkWrap: $shrinkWrap)',
      (tester) async {
        final fixture = _CanvasFixture(shrinkWrap: shrinkWrap);
        try {
          await tester.pumpWidget(fixture.build(_theme('default light')));
          await tester.pumpAndSettle();
          final renderer = tester.state(find.byType(AppFlowyEditor));
          final page = tester.element(find.byType(CustomPageBlockComponent));
          final selectionService = fixture.editor.service.selectionService;
          final keyboardService = fixture.editor.service.keyboardService;
          final draft = fixture.draftKey.currentState!;
          draft.controller.text = 'retained unsaved content';
          draft.controller.selection =
              const TextSelection(baseOffset: 2, extentOffset: 9);
          final scrollable = Scrollable.of(draft.context);
          final position = scrollable.position;
          position.jumpTo(24);
          await tester.pumpAndSettle();
          final before = position.pixels;
          for (final entry in _canvases.entries) {
            await tester.pumpWidget(
              fixture.build(_theme(entry.key), width: 500, height: 360),
            );
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(AppFlowyEditor)), same(renderer));
            expect(
              tester.element(find.byType(CustomPageBlockComponent)),
              same(page),
            );
            expect(
              fixture.editor.service.selectionService,
              same(selectionService),
            );
            expect(
              fixture.editor.service.keyboardService,
              same(keyboardService),
            );
            expect(fixture.draftKey.currentState, same(draft));
            // Scrollable may replace and absorb its position when the theme's
            // scroll behavior changes. The mounted owner and offset must stay.
            expect(Scrollable.of(draft.context), same(scrollable));
            expect(scrollable.position.pixels, before);
            expect(draft.controller.text, 'retained unsaved content');
            expect(
              draft.controller.selection,
              const TextSelection(baseOffset: 2, extentOffset: 9),
            );
            expect(
              tester.getSize(find.byType(AppFlowyEditor)),
              const Size(500, 360),
            );
            expect(await _canvasPixel(tester), entry.value);
            expect(fixture.editor.document.toJson(), fixture.initialDocument);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

ThemeData _theme(String mode) {
  final base = DesktopAppearance().getThemeData(
    mode == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    mode == 'dark' ? Brightness.dark : Brightness.light,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final palette = base.extension<PremiumThemeExtension>()!;
  return base.copyWith(
    // Deliberately wrong legacy surroundings: the actual page must paint its
    // semantic canvas instead of relying on whichever host happens to be white.
    colorScheme: base.colorScheme.copyWith(surface: Colors.white),
    extensions: [
      ...base.extensions.values
          .where((extension) => extension is! PremiumThemeExtension),
      mode == 'custom light'
          ? palette.copyWith(canvas: _customCanvas)
          : palette,
    ],
  );
}

Future<Color> _canvasPixel(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_capture));
  final color = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData())!;
      final offset = ((image.height - 20) * image.width + image.width - 20) * 4;
      return Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  return color!;
}

class _CanvasFixture {
  _CanvasFixture({required bool shrinkWrap}) {
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            Node(type: 'canvas_draft'),
            for (var index = 0; index < 40; index++)
              paragraphNode(text: 'Document line $index'),
          ],
        ),
      ),
    )..disableSealTimer = true;
    scroll =
        EditorScrollController(editorState: editor, shrinkWrap: shrinkWrap);
    initialDocument = editor.document.toJson();
  }

  final draftKey = GlobalKey<_DraftState>();
  late final EditorState editor;
  late final EditorScrollController scroll;
  late final Map<String, dynamic> initialDocument;

  Widget build(
    ThemeData theme, {
    double width = 600,
    double height = 400,
    bool preview = false,
  }) =>
      MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _capture,
              child: SizedBox(
                width: width,
                height: height,
                child: EditorCanvasScope(
                  color: preview ? Colors.transparent : null,
                  child: AppFlowyEditor(
                    editorState: editor,
                    editorScrollController: scroll,
                    editorStyle: const EditorStyle.desktop(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                    ),
                    contextMenuItems: const [],
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                      'canvas_draft': _DraftBuilder(draftKey),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void dispose() {
    scroll.dispose();
    editor.dispose();
  }
}

class _DraftBuilder extends BlockComponentBuilder {
  _DraftBuilder(this.draftKey);
  final GlobalKey<_DraftState> draftKey;

  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      _DraftBlock(node: context.node, draftKey: draftKey);
}

class _DraftBlock extends BlockComponentStatelessWidget {
  const _DraftBlock({required super.node, required this.draftKey})
      : super(configuration: const BlockComponentConfiguration());

  final GlobalKey<_DraftState> draftKey;

  @override
  Widget build(BuildContext context) => _Draft(key: draftKey);
}

class _Draft extends StatefulWidget {
  const _Draft({super.key});

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final controller = TextEditingController(text: 'Draft');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 72, child: TextField(controller: controller));
}
