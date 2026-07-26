import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    testWidgets('surrounds any renderer with the same floating header',
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

      // Chrome, never a Material app bar or a bordered toolbar strip.
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
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

    testWidgets('actions and a floating toolbar have somewhere to live',
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
          child: const SizedBox.expand(),
        ),
      );

      expect(find.text('1 / 12'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.download_rounded));
      expect(pressed, 1);

      // Premium controls: no ripple, no Material button chrome.
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
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

      // Chrome is translucent so the document reads through it.
      for (final style in [light, dark, paper]) {
        expect(style.chrome.a, lessThan(1));
        expect(style.chromeShadow, isNotEmpty);
      }
      expect(light.canvas, isNot(dark.canvas));
      // Paper stays warm rather than falling back to a cool surface.
      expect(paper.canvas.r, greaterThanOrEqualTo(paper.canvas.b));
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
