import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_preview.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_template_gallery.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_variables_bar.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// The dashboard's visual language: each widget is painted with the
/// treatment it was designed for (a sheet, a wash, an atmosphere, or type set
/// straight onto the page), in light, dark and paper alike, and management
/// controls only appear when they are wanted.
const _appearances = ['light', 'dark', 'paper'];
const _probe = 'redesign_probe';
const _reservedProbe = 'redesign_probe_reserved';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    DashboardWidgetRegistry.register(
      DashboardWidgetDefinition(
        type: _probe,
        label: () => 'Probe',
        icon: Icons.star_rounded,
        group: DashboardWidgetGroup.text,
        showsTitleByDefault: false,
        builder: (_) => const SizedBox.expand(),
      ),
    );
    DashboardWidgetRegistry.register(
      DashboardWidgetDefinition(
        type: _reservedProbe,
        label: () => 'Reserved probe',
        icon: Icons.table_chart_rounded,
        group: DashboardWidgetGroup.data,
        showsTitleByDefault: false,
        reservesHeader: true,
        builder: (_) => const SizedBox.expand(),
      ),
    );
  });

  for (final appearance in _appearances) {
    group(appearance, () {
      testWidgets('every treatment paints the surface it promises',
          (tester) async {
        final palette = await _palette(tester, appearance);
        final shape = BorderRadius.circular(DashboardMetrics.cardRadius);
        for (final accent in DashboardAccent.values) {
          final tone = palette.toneFor(accent);
          final reason = '$appearance ${accent.name}';

          // Set straight onto the page: no fill and no shadow, even under
          // the pointer, until the widget is picked up and carried.
          for (final hovered in [false, true]) {
            final plain = palette.surfaceDecoration(
              DashboardSurface.plain,
              tone,
              hovered: hovered,
            );
            expect(plain.color, isNull, reason: reason);
            expect(plain.boxShadow, isEmpty, reason: reason);
          }
          final carried = palette.surfaceDecoration(
            DashboardSurface.plain,
            tone,
            dragging: true,
          );
          expect(carried.color, palette.surface, reason: reason);
          expect(carried.boxShadow, isNotEmpty, reason: reason);

          final floating =
              palette.surfaceDecoration(DashboardSurface.floating, tone);
          expect(floating.color, palette.surface, reason: reason);
          expect(floating.boxShadow, isNotEmpty, reason: reason);
          expect(floating.borderRadius, shape, reason: reason);
          expect(floating.border, isNull, reason: reason);

          final tinted =
              palette.surfaceDecoration(DashboardSurface.tinted, tone);
          expect(tinted.color, tone.tint, reason: reason);
          expect(tinted.color!.a, 1, reason: reason);
          expect(tinted.border, isNull, reason: reason);

          final atmospheric =
              palette.surfaceDecoration(DashboardSurface.gradient, tone);
          expect(
            (atmospheric.gradient! as LinearGradient).colors,
            tone.gradient,
            reason: reason,
          );
          expect(atmospheric.borderRadius, shape, reason: reason);
        }
        expect(palette.sheenFor(DashboardSurface.gradient).gradient, isNotNull);
        for (final kind in [
          DashboardSurface.plain,
          DashboardSurface.floating,
          DashboardSurface.tinted,
        ]) {
          expect(palette.sheenFor(kind).gradient, isNull);
        }

        if (appearance == 'paper') {
          // Paper keeps its warm cream: no white or cool-grey sheet.
          expect(palette.isPaper, isTrue);
          final neutral = palette.toneFor(DashboardAccent.neutral);
          for (final colour in [
            palette.surface,
            neutral.tint,
            palette
                .surfaceDecoration(
                  DashboardSurface.plain,
                  neutral,
                  dragging: true,
                )
                .color!,
          ]) {
            expect(colour.r, greaterThan(colour.b));
          }
        }
      });

      testWidgets('words written in a colour stay legible on its wash',
          (tester) async {
        final palette = await _palette(tester, appearance);
        for (final accent in DashboardAccent.values) {
          if (accent == DashboardAccent.neutral) continue;
          final tone = palette.toneFor(accent);
          for (final ground in [tone.tint, ...tone.gradient]) {
            for (final ink in [tone.label, tone.figure, tone.ink]) {
              expect(
                _contrast(ink, ground),
                greaterThanOrEqualTo(3),
                reason: '$appearance ${accent.name}: $ink on $ground',
              );
            }
          }
        }
      });

      testWidgets('floating controls appear on hover without moving content',
          (tester) async {
        final spec = DashboardWidgetRegistry.definitionFor(_probe)!.create();
        final controller = _controller([spec], DashboardMode.edit);
        addTearDown(controller.dispose);
        await _mountCard(tester, appearance, controller, spec);

        final header = find.byKey(ValueKey('dashboard-card-header-${spec.id}'));
        final body = find.byKey(ValueKey('dashboard-card-body-${spec.id}'));
        final management =
            find.byKey(ValueKey('dashboard-card-management-${spec.id}'));
        final card = tester.getRect(find.byType(DashboardCard));
        expect(tester.getSize(header).height, 0);
        expect(management, findsOneWidget);
        expect(_opacityOf(tester, management), 0);
        expect(_glyph(Icons.tune_rounded).hitTestable(), findsNothing);
        final resting = tester.getRect(body);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await tester.pump();
        await mouse.moveTo(card.center);
        await tester.pumpAndSettle();

        expect(_opacityOf(tester, management), 1);
        expect(_glyph(Icons.tune_rounded).hitTestable(), findsOneWidget);
        expect(_glyph(Icons.more_horiz_rounded).hitTestable(), findsOneWidget);
        expect(
          find
              .byKey(ValueKey('dashboard-card-handle-${spec.id}'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(body), resting);
        final pill = tester.getRect(management);
        expect(card.contains(pill.topLeft), isTrue);
        expect(card.contains(pill.bottomRight), isTrue);
        expect(pill.center.dx, greaterThan(card.center.dx));
        expect(pill.center.dy, lessThan(card.center.dy));

        await mouse.moveTo(card.bottomRight + const Offset(60, 60));
        await tester.pumpAndSettle();
        expect(_opacityOf(tester, management), 0);
        expect(tester.getRect(body), resting);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a presented dashboard carries no management chrome',
          (tester) async {
        final spec = DashboardWidgetRegistry.definitionFor(_probe)!.create();
        final controller = _controller([spec], DashboardMode.presentation);
        addTearDown(controller.dispose);
        await _mountCard(tester, appearance, controller, spec);
        expect(
          find.byKey(ValueKey('dashboard-card-management-${spec.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('dashboard-card-handle-${spec.id}')),
          findsNothing,
        );
        expect(
          tester
              .getSize(find.byKey(ValueKey('dashboard-card-header-${spec.id}')))
              .height,
          0,
        );
      });
    });
  }

  testWidgets('widgets with navigation along the top keep a header row',
      (tester) async {
    final spec =
        DashboardWidgetRegistry.definitionFor(_reservedProbe)!.create();
    final controller = _controller([spec], DashboardMode.edit);
    addTearDown(controller.dispose);
    await _mountCard(tester, 'light', controller, spec);
    final header = tester
        .getRect(find.byKey(ValueKey('dashboard-card-header-${spec.id}')));
    final management = tester
        .getRect(find.byKey(ValueKey('dashboard-card-management-${spec.id}')));
    expect(header.height, DashboardMetrics.headerHeight);
    expect(management.top, greaterThanOrEqualTo(header.top));
    expect(management.bottom, lessThanOrEqualTo(header.bottom));
    expect(
      tester
          .getRect(find.byKey(ValueKey('dashboard-card-body-${spec.id}')))
          .top,
      greaterThanOrEqualTo(header.bottom),
    );
    // The handle belongs to the floating pill; a header is its own handle.
    expect(
      find.byKey(ValueKey('dashboard-card-handle-${spec.id}')),
      findsNothing,
    );
    expect(_glyph(Icons.tune_rounded), findsOneWidget);
  });

  testWidgets('each widget resolves the treatment it was designed for',
      (tester) async {
    final palette = await _palette(tester, 'light');
    DashboardAppearance of(
      String type, {
      DashboardAccent? accent,
      DashboardSurface? chosen,
    }) {
      var spec = DashboardWidgetRegistry.definitionFor(type)!.create();
      if (accent != null) spec = spec.copyWith(accent: accent);
      if (chosen != null) {
        spec = spec.copyWith(
          settings: {...spec.settings, dashboardSurfaceKey: chosen.name},
        );
      }
      return dashboardAppearanceOf(spec, palette);
    }

    // A sheet by default, carrying no colour of its own.
    final text = of('text');
    expect(text.surface, DashboardSurface.floating);
    expect(text.accent, DashboardAccent.neutral);
    expect(text.tone.surface, palette.surface);
    expect(text.onColour, isFalse);

    // Picking a colour for a sheet has always meant "paint me in it".
    final blue = of('text', accent: DashboardAccent.blue);
    expect(blue.surface, DashboardSurface.tinted);
    expect(blue.tone.surface, palette.toneFor(DashboardAccent.blue).tint);
    expect(blue.onColour, isTrue);

    // Widgets with an identity wear it while their colour is automatic.
    final clock = of('clock');
    expect(clock.surface, DashboardSurface.tinted);
    expect(clock.accent, DashboardAccent.purple);
    final countdown = of('countdown', accent: DashboardAccent.neutral);
    expect(countdown.surface, DashboardSurface.gradient);
    expect(countdown.accent, DashboardAccent.orange);
    expect(
      countdown.tone.surface,
      palette.toneFor(DashboardAccent.orange).gradient.first,
    );

    // Type set straight onto the page, unless somebody colours it.
    final metric = of('metric');
    expect(metric.surface, DashboardSurface.plain);
    expect(metric.tone.surface, palette.canvas);
    expect(
      of('metric', accent: DashboardAccent.green).surface,
      DashboardSurface.tinted,
    );

    // A surface somebody chose always wins.
    final chosen = of(
      'metric',
      accent: DashboardAccent.green,
      chosen: DashboardSurface.plain,
    );
    expect(chosen.surface, DashboardSurface.plain);
    expect(chosen.accent, DashboardAccent.green);
    expect(
      of('clock', chosen: DashboardSurface.floating).surface,
      DashboardSurface.floating,
    );

    // Pictures and embeds paint themselves edge to edge.
    final image = of('image');
    expect(image.media, isTrue);
    expect(image.onColour, isFalse);
  });

  test('section subtitles round-trip and stay out of untouched JSON', () {
    const section = DashboardSection(
      id: 'today',
      title: 'Good morning',
      subtitle: 'Your day at a glance',
    );
    final json = section.toJson();
    expect(json['subtitle'], 'Your day at a glance');
    expect(DashboardSection.fromJson(json), section);
    expect(
      const DashboardSection(id: 'plain').toJson().containsKey('subtitle'),
      isFalse,
    );
    expect(
      DashboardSection.fromJson(const {'id': 'old'}).subtitle,
      isEmpty,
    );
  });

  testWidgets('an empty variables strip takes no room at all', (tester) async {
    final controller = _controller(const [], DashboardMode.edit);
    addTearDown(controller.dispose);
    await _mount(
      tester,
      'light',
      Builder(
        builder: (context) => Align(
          alignment: Alignment.topLeft,
          child: DashboardVariablesBar(
            controller: controller,
            palette: DashboardPalette.of(context),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DashboardVariablesBar)), Size.zero);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  for (final appearance in _appearances) {
    testWidgets('$appearance: templates show a picture of their board',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 2400);
      addTearDown(tester.view.reset);
      DashboardTemplate? chosen;
      await _mount(
        tester,
        appearance,
        Builder(
          builder: (context) => DashboardTemplateGallery(
            palette: DashboardPalette.of(context),
            onChosen: (template) => chosen = template,
          ),
        ),
        width: 1200,
        height: 2300,
      );
      final templates = dashboardTemplates();
      final pictured =
          templates.where((template) => template.build().widgetCount > 0);
      expect(find.byType(DashboardMiniature), findsNWidgets(pictured.length));
      for (final template in templates) {
        expect(find.text(template.label()), findsOneWidget);
      }
      await tester.tap(find.text(LocaleKeys.dashboard_template_blank.tr()));
      await tester.pumpAndSettle();
      expect(chosen?.id, 'blank');
      expect(tester.takeException(), isNull);
    });
  }
}

DashboardController _controller(
  List<DashboardWidgetSpec> widgets,
  DashboardMode mode,
) =>
    DashboardController(
      viewId: '',
      document: DashboardDocument(
        sections: [DashboardSection(id: 'section', widgets: widgets)],
      ),
      mode: mode,
      persistDebounce: const Duration(days: 1),
    );

Future<void> _mountCard(
  WidgetTester tester,
  String appearance,
  DashboardController controller,
  DashboardWidgetSpec spec,
) =>
    _mount(
      tester,
      appearance,
      Center(
        child: SizedBox(
          width: 360,
          height: 220,
          child: Builder(
            builder: (context) => DashboardCard(
              controller: controller,
              spec: spec,
              palette: DashboardPalette.of(context),
              selected: false,
              dragging: false,
            ),
          ),
        ),
      ),
    );

Future<DashboardPalette> _palette(
  WidgetTester tester,
  String appearance,
) async {
  late DashboardPalette palette;
  await _mount(
    tester,
    appearance,
    Builder(
      builder: (context) {
        palette = DashboardPalette.of(context);
        return const SizedBox.shrink();
      },
    ),
  );
  return palette;
}

double _opacityOf(WidgetTester tester, Finder toolbar) => tester
    .widget<AnimatedOpacity>(
      find
          .descendant(of: toolbar, matching: find.byType(AnimatedOpacity))
          .first,
    )
    .opacity;

Finder _glyph(IconData icon) => find.byWidgetPredicate(
      (widget) => widget is WorkspaceGlyph && widget.icon == icon,
    );

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final light = first > second ? first : second;
  final dark = first > second ? second : first;
  return (light + 0.05) / (dark + 0.05);
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      '',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget child, {
  double width = 760,
  double height = 520,
}) async {
  final theme = _theme(appearance);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, navigator) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: appearance == 'dark'
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: TooltipVisibility(visible: false, child: navigator!),
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: width, height: height, child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
