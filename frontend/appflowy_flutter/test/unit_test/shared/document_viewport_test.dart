import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _identity = DocumentIdentity(
  title: 'Quarterly report.md',
  icon: Icons.article_outlined,
  subtitle: 'Markdown  ·  8.5 KB',
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppTheme? appTheme,
  Brightness brightness = Brightness.light,
}) async {
  final defaultTheme = AppFlowyDefaultTheme();
  final materialTheme = DesktopAppearance().getThemeData(
    appTheme ?? AppTheme.fallback,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: materialTheme,
      home: AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: brightness == Brightness.dark
              ? defaultTheme.dark()
              : defaultTheme.light(),
          palette: materialTheme.extension<PremiumThemeExtension>()!,
          brightness: brightness,
        ),
        child: Scaffold(body: SizedBox(height: 420, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollMetrics _metrics({
  double pixels = 0,
  required double maxScrollExtent,
}) =>
    FixedScrollMetrics(
      pixels: pixels,
      minScrollExtent: 0,
      maxScrollExtent: maxScrollExtent,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 2,
    );

void main() {
  group('DocumentViewport chrome', () {
    testWidgets('surrounds any renderer with the same docked header',
        (tester) async {
      await _pump(
        tester,
        const DocumentViewport(
          identity: _identity,
          child: ColoredBox(color: Color(0xFF123456)),
        ),
      );

      expect(find.byType(DocumentViewportHeader), findsOneWidget);
      expect(find.text('Quarterly report.md'), findsOneWidget);
      expect(find.text('Markdown  ·  8.5 KB'), findsOneWidget);

      // No floating card, backdrop blur or animation of the renderer's bounds.
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: find.byType(DocumentViewport),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
      final header = tester.getRect(find.byType(DocumentViewportHeader));
      final viewport = tester.getRect(find.byType(DocumentViewport));
      expect(header.topLeft, viewport.topLeft);
      expect(header.width, viewport.width);
    });

    testWidgets('the renderer is never hidden beneath the header',
        (tester) async {
      await _pump(
        tester,
        const DocumentViewport(
          identity: _identity,
          child: ColoredBox(key: ValueKey('renderer'), color: Colors.white),
        ),
      );

      final header = tester.getRect(find.byType(DocumentViewportHeader));
      final renderer = tester.getRect(find.byKey(const ValueKey('renderer')));
      expect(renderer.top, greaterThanOrEqualTo(header.bottom));
      expect(
        renderer.top,
        closeTo(DocumentViewportStyle.contentTopInset, 0.5),
      );
    });

    testWidgets('actions are visible without hovering and the footer is docked',
        (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        DocumentViewport(
          identity: _identity,
          actions: [
            DocumentViewportButton(
              icon: Icons.download_rounded,
              tooltip: 'Download',
              onPressed: () => pressed++,
            ),
          ],
          floatingToolbar: const DocumentFloatingToolbar(
            children: [DocumentViewportLabel(label: '1 / 12')],
          ),
          child: const SizedBox.expand(key: ValueKey('renderer')),
        ),
      );

      expect(find.text('1 / 12'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.download_rounded));
      expect(pressed, 1);
      final renderer = tester.getRect(find.byKey(const ValueKey('renderer')));
      final footer = tester.getRect(find.byType(DocumentFloatingToolbar));
      expect(renderer.bottom, footer.top);
      expect(
        footer.bottom,
        tester.getRect(find.byType(DocumentViewport)).bottom,
      );

      // Premium controls: no ripple, no Material button chrome.
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('header and actions stay put while the document scrolls',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var pressed = 0;
      await _pump(
        tester,
        DocumentViewport(
          framed: false,
          identity: _identity,
          actions: [
            DocumentViewportButton(
              icon: Icons.fit_screen_rounded,
              tooltip: 'Fit to view',
              onPressed: () => pressed++,
            ),
          ],
          child: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemExtent: 32,
            itemBuilder: (_, index) => Text('Line $index'),
          ),
        ),
      );
      final header = tester.getRect(find.byType(DocumentViewportHeader));
      controller.jumpTo(1200);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(controller.offset, 1200);
      expect(tester.getRect(find.byType(DocumentViewportHeader)), header);
      await tester.tap(find.byTooltip('Fit to view'));
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('viewer actions are keyboard accessible', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        DocumentViewport(
          identity: _identity,
          actions: [
            DocumentViewportButton(
              icon: Icons.tune_rounded,
              tooltip: 'Edit image',
              onPressed: () => pressed++,
            ),
          ],
          child: const SizedBox.expand(),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(pressed, 2);
    });

    testWidgets('long identity and large text fit a narrow pane',
        (tester) async {
      await _pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 300,
            child: DocumentViewport(
              framed: false,
              identity: _identity,
              actions: [
                DocumentViewportButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'Edit image',
                  onPressed: null,
                ),
                DocumentViewportButton(
                  icon: Icons.fit_screen_rounded,
                  tooltip: 'Fit to view',
                  onPressed: null,
                ),
              ],
              child: SizedBox.expand(key: ValueKey('renderer')),
            ),
          ),
        ),
      );
      final header = tester.getRect(find.byType(DocumentViewportHeader));
      expect(header.height, greaterThan(DocumentViewportStyle.headerHeight));
      expect(
        tester.getRect(find.byKey(const ValueKey('renderer'))).top,
        header.bottom,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shell is rounded and lifted, never outlined',
        (tester) async {
      await _pump(
        tester,
        const DocumentViewport(
          identity: _identity,
          child: SizedBox.expand(),
        ),
      );

      final decorated = tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      );
      final shell = decorated.firstWhere(
        (box) =>
            (box.decoration as BoxDecoration).borderRadius ==
            DocumentViewportStyle.borderRadius,
      );
      final decoration = shell.decoration as BoxDecoration;
      expect(decoration.border, isNull);
      expect(decoration.boxShadow, isNotEmpty);
      expect(DocumentViewportStyle.radius, 20);
    });
  });

  group('DocumentViewportStyle', () {
    testWidgets('resolves a distinct calm palette per appearance',
        (tester) async {
      final paperTheme = AppTheme.builtins.firstWhere(
        (theme) => theme.themeName == BuiltInTheme.paper,
      );
      late DocumentViewportStyle light;
      late DocumentViewportStyle dark;
      late DocumentViewportStyle paper;

      Widget probe(void Function(DocumentViewportStyle) capture) => Builder(
            builder: (context) {
              capture(DocumentViewportStyle.of(context));
              return const SizedBox.shrink();
            },
          );

      await _pump(tester, probe((value) => light = value));
      await _pump(
        tester,
        probe((value) => dark = value),
        brightness: Brightness.dark,
      );
      await _pump(
        tester,
        probe((value) => paper = value),
        appTheme: paperTheme,
      );

      // A fixed header is opaque and has no elevation in any appearance.
      for (final style in [light, dark, paper]) {
        expect(style.chrome.a, 1);
        expect(style.chromeShadow, isEmpty);
      }
      expect(light.canvas, isNot(dark.canvas));
      // Paper stays warm rather than falling back to a cool surface.
      expect(paper.canvas.r, greaterThanOrEqualTo(paper.canvas.b));
      expect(paper.chrome, PaperTheme.editorPreviewBackground);
      for (final style in [light, dark, paper]) {
        expect(style.chrome, style.canvas);
      }
    });
  });

  group('seamless viewer chrome', () {
    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets('$appearance uses one borderless header and reading surface',
          (tester) async {
        await _pump(
          tester,
          const DocumentViewport(
            framed: false,
            identity: _identity,
            child: SizedBox.expand(),
          ),
          brightness: appearance == 'dark' ? Brightness.dark : Brightness.light,
          appTheme: appearance == 'paper'
              ? AppTheme.builtins
                  .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
              : null,
        );
        final header = tester.widget<DocumentViewportHeader>(
          find.byType(DocumentViewportHeader),
        );
        final bar = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(DocumentViewportBar),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(bar.decoration, isNull);
        expect(bar.foregroundDecoration, isNull);
        expect(bar.color, header.background);
        expect(
          bar.color,
          DocumentViewportStyle.of(
            tester.element(find.byType(DocumentViewport)),
          ).canvas,
        );
        expect(find.byType(BackdropFilter), findsNothing);
      });
    }

    testWidgets('a custom canvas reaches the header without a second fill',
        (tester) async {
      const background = Color(0xFFF4EFE6);
      await _pump(
        tester,
        const DocumentViewport(
          identity: _identity,
          background: background,
          child: SizedBox.expand(),
        ),
      );
      expect(
        tester
            .widget<DocumentViewportBar>(find.byType(DocumentViewportBar))
            .background,
        background,
      );
    });

    testWidgets('fit is labelled and keyboard accessible without a filled icon',
        (tester) async {
      var fits = 0;
      await _pump(
        tester,
        Center(child: DocumentViewportFitButton(onPressed: () => fits++)),
      );
      expect(find.text('Fit'), findsOneWidget);
      expect(find.byIcon(Icons.fit_screen_rounded), findsNothing);
      await tester.tap(find.byTooltip('Fit to view'));
      expect(fits, 1);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(fits, 2);
    });

    testWidgets('disabled fit cannot be invoked', (tester) async {
      await _pump(
        tester,
        const Center(child: DocumentViewportFitButton(onPressed: null)),
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(find.text('Fit'), findsOneWidget);
      final glyphContext = tester.element(
        find.byKey(const ValueKey('document-fit-glyph')),
      );
      expect(
        IconTheme.of(glyphContext).color,
        DocumentViewportStyle.of(glyphContext).iconMuted,
      );
    });

    testWidgets('toolbar groups are separated by space, not rules',
        (tester) async {
      await _pump(tester, const Center(child: DocumentViewportSeparator()));
      expect(find.byType(DecoratedBox), findsNothing);
      expect(find.byType(ColoredBox), findsNothing);
      expect(tester.getSize(find.byType(DocumentViewportSeparator)).width, 12);
    });
  });

  group('shared scrolling', () {
    test('one kinetic configuration drives every renderer', () {
      expect(documentScrollConfig, const PremiumScrollPhysicsConfig());
      expect(documentFlingFriction, greaterThan(0));
      // Critically damped: settles exactly, never overshoots.
      expect(
        documentSettleSpring.damping * documentSettleSpring.damping,
        closeTo(
          4 * documentSettleSpring.mass * documentSettleSpring.stiffness,
          0.01,
        ),
      );
    });

    test('platform overscroll is honoured, momentum is not', () {
      expect(
        DocumentScrollPhysics.platformBase(TargetPlatform.windows),
        isA<ClampingScrollPhysics>(),
      );
      expect(
        DocumentScrollPhysics.platformBase(TargetPlatform.macOS),
        isA<BouncingScrollPhysics>(),
      );
      expect(
        DocumentScrollPhysics.platformBounces(TargetPlatform.windows),
        isFalse,
      );
    });

    test('a fling decelerates progressively and lands inside the document', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final physics = DocumentScrollPhysics(
        parent: DocumentScrollPhysics.platformBase(TargetPlatform.windows),
      );
      final simulation = physics.createBallisticSimulation(
        _metrics(pixels: 100, maxScrollExtent: 4000),
        2400,
      )!;

      expect(simulation.dx(0.05), greaterThan(simulation.dx(0.4)));
      expect(simulation.dx(0.4), greaterThan(simulation.dx(1.2)));
      expect(simulation.dx(6).abs(), lessThan(20));

      // Arriving at the end eases in rather than colliding.
      final atEdge = physics.createBallisticSimulation(
        _metrics(pixels: 3950, maxScrollExtent: 4000),
        4000,
      )!;
      expect(atEdge.x(4), lessThanOrEqualTo(4000.5));

      // Nothing scrolls the document on its own.
      expect(physics.allowImplicitScrolling, isFalse);
    });

    testWidgets('every scrollable in a viewport shares physics and scrollbar',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        DocumentScrollScope(
          child: ListView.builder(
            controller: controller,
            itemCount: 80,
            itemBuilder: (context, index) => SizedBox(
              height: 40,
              child: Text('row $index'),
            ),
          ),
        ),
      );

      final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
      expect(
        ScrollConfiguration.of(
          tester.element(find.byType(Scrollable)),
        ),
        isA<DocumentScrollBehavior>(),
      );
      expect(scrollable.physics, isNull);
      expect(find.byType(DocumentScrollbar), findsOneWidget);
    });

    testWidgets('the premium wheel dispatcher is never doubled',
        (tester) async {
      late ScrollBehavior inner;
      await _pump(
        tester,
        PremiumScrollScope(
          enabled: true,
          child: DocumentScrollScope(
            child: Builder(
              builder: (context) {
                inner = ScrollConfiguration.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final behavior = inner as DocumentScrollBehavior;
      expect(behavior.delegate, isA<PremiumScrollBehavior>());
      // Doubling would square the desktop manipulation scale.
      expect(
        (behavior.delegate as PremiumScrollBehavior).delegate,
        isNot(isA<PremiumScrollBehavior>()),
      );
    });
  });
}
