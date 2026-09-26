import 'dart:io';

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _providers = 'lib/plugins/collection/providers';
const _collections = 'lib/plugins/collection/views';
const _folders = 'lib/workspace/presentation/widgets/folder_explorer';
const _editor = 'lib/plugins/document/presentation/editor_plugins';

// Only palettes verified to supply an overlay belong in this list. In
// particular, WorkspacePalette.hover and VisualBlockPalette.hover also supply
// deliberate opaque selection/focus/editor surfaces; they are NOT blanket
// candidates for replacing alpha. Their pointer branches are exercised below.
const _overlayConsumers = [
  '$_providers/connect_dialog.dart',
  '$_providers/external_content_view.dart',
  '$_providers/external_folder_stage.dart',
  '$_providers/external_picker.dart',
  '$_providers/external_repository_view.dart',
  '$_providers/git/git_panel.dart',
  '$_providers/provider_chrome.dart',
  '$_providers/provider_text_field.dart',
  '$_providers/source_picker.dart',
  '$_collections/bookmark/bookmark_chrome.dart',
  '$_collections/database/database_chrome.dart',
  '$_collections/email/email_chrome.dart',
  '$_collections/repository/repository_style.dart',
  '$_folders/explorer_toolbar.dart',
  '$_folders/folder_collection_preview.dart',
  '$_folders/folder_gallery_header.dart',
  '$_folders/folder_picker_dialog.dart',
  '$_editor/file/notebook/notebook_markup.dart',
  // Map palettes can supply either an opaque surface or a custom overlay.
  // Multiplication must preserve both cases in this consumer.
  'lib/plugins/database/widgets/cell/desktop_grid/location_picker_card.dart',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('known overlay consumers preserve alpha', () {
    for (final path in _overlayConsumers) {
      test(path, () {
        expect(
          _absoluteHoverAlphas(File(path).readAsStringSync()),
          isEmpty,
          reason: '$path must keep hover alpha or multiply it, never replace '
              'it with a fixed nonzero alpha or a hovered ? 1 : 0 toggle.',
        );
      });
    }

    test('the guard catches low constants, full opacity and multiline calls',
        () {
      for (final source in [
        'palette.hover.withValues(alpha: 0.35)',
        'palette.hover.withValues(alpha: 0.01)',
        'widget.palette.hover.withValues(alpha: hovered ? 1 : 0)',
        'palette.hover\n.withValues(\n alpha: hovered && enabled ? 1 : 0,\n)',
        'palette.hover.withOpacity(0.8)',
        'palette.hover.withAlpha(255)',
        'palette.hover.withValues(alpha: other.hover.a * 0.5)',
      ]) {
        expect(_absoluteHoverAlphas(source), hasLength(1), reason: source);
      }
      for (final source in [
        'hovered ? palette.hover : palette.hover.withValues(alpha: 0)',
        'palette.hover.withValues(alpha: palette.hover.a * 0.35)',
        'palette.hover.withValues(\n alpha: palette.hover.a * '
            '(isDark ? 0.62 : 0.8),\n)',
        'widget.palette.hover.withValues(alpha: widget.palette.hover.a * 0.5)',
      ]) {
        expect(_absoluteHoverAlphas(source), isEmpty, reason: source);
      }
    });
  });

  group('pointer-only scopes in mixed surface palettes', () {
    const scopes = [
      (
        '$_editor/math_equation/math_equation_block_component.dart',
        'class _TextActionState',
        '',
      ),
      (
        '$_editor/math_equation/math_source_editor.dart',
        'class _CategoryPillState',
        '',
      ),
      (
        '$_editor/mermaid/mermaid_source_editor.dart',
        'class _SampleChipState',
        '',
      ),
      (
        '$_editor/interactive/interactive_style.dart',
        'case InteractiveEmphasis.subtle:',
        'static Color _onColour',
      ),
      (
        'lib/plugins/templates/presentation/templates_page.dart',
        'class _ShelfRowState',
        'class _Grid',
      ),
    ];
    for (final (path, startMarker, endMarker) in scopes) {
      test('$path: $startMarker', () {
        final source = File(path).readAsStringSync();
        final start = source.indexOf(startMarker);
        expect(start, greaterThanOrEqualTo(0));
        final end = endMarker.isEmpty
            ? source.length
            : source.indexOf(endMarker, start);
        expect(end, greaterThan(start));
        final pointerScope = source.substring(start, end);
        expect(pointerScope, contains('WorkspaceChrome.hoverColor(context)'));
        expect(_absoluteHoverAlphas(pointerScope), isEmpty);
      });
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final lowAlpha in [false, true]) {
      testWidgets('$mode/lowAlpha=$lowAlpha: palette derivations stay quiet',
          (tester) async {
        try {
          final context = await _mount(
            tester,
            mode,
            overlay: lowAlpha ? const Color(0x08675443) : null,
            builder: (_) => const SizedBox.shrink(),
          );
          final premium = PremiumThemeExtension.of(context);
          final folder = FolderExplorerPalette.of(context);
          final hover = premium.subtleHover;
          final isDark = mode == 'dark';

          expect(folder.hover, hover);
          expect(hover.a, closeTo(premium.hoverOverlay.a * 0.65, 0.000001));
          expect(hover.a, inExclusiveRange(0.0, 0.07));
          expect(
            folder.selected,
            mode == 'paper' ? PaperTheme.controlSelected : premium.selected,
          );
          expect(folder.accent, premium.accent);
          expect(folder.danger, Theme.of(context).colorScheme.error);
          expect(folder.surface.a, 1);
          expect(folder.floatingSurface.a, 1);
          if (mode == 'paper') {
            expect(folder.surface, PaperTheme.editorPreviewBackground);
            expect(folder.floatingSurface, PaperTheme.popupBackground);
            expect(folder.hover.r, greaterThan(folder.hover.b));
          }

          // These are intentionally opaque surface roles, not pointer washes.
          expect(WorkspacePalette.of(context).hover, premium.hover);
          expect(VisualBlockPalette.of(context).hover, premium.hover);
          expect(premium.hover.a, 1);

          final collection =
              CollectionPalette.of(context, CollectionKind.repository);
          final repository = RepoTheme.of(context, collection);
          final bookmark = BookmarkTheme.of(context, collection);
          final database = DatabaseTheme.of(context, collection);
          final email = EmailTheme.of(context, collection);
          final derivedHover = hover.withValues(
            alpha: hover.a * (isDark ? 0.62 : 0.8),
          );
          final sunken = Color.alphaBlend(
            hover.withValues(alpha: hover.a * (isDark ? 0.42 : 0.6)),
            collection.background,
          );
          for (final color in [
            repository.rowHover,
            bookmark.hover,
            database.hover,
            email.hover,
          ]) {
            expect(color, derivedHover);
            expect(color.a, lessThan(hover.a));
          }
          for (final color in [
            repository.sunken,
            bookmark.sunken,
            database.sunken,
            email.sunken,
          ]) {
            expect(color, sunken);
            expect(color.a, 1);
          }
          expect(
            repository.rowSelected,
            collection.accent.withValues(alpha: isDark ? 0.15 : 0.09),
          );
          expect(
            bookmark.selected,
            collection.accent.withValues(alpha: isDark ? 0.16 : 0.10),
          );
          expect(database.selected, bookmark.selected);
          expect(
            email.selected,
            collection.accent.withValues(alpha: isDark ? 0.18 : 0.11),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }

    testWidgets('$mode: provider and AF controls retain low alpha during hover',
        (tester) async {
      final controller = TextEditingController(text: 'Retained draft');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(790, 590));
        final context = await _mount(
          tester,
          mode,
          overlay: const Color(0x08675443),
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProviderTextField(
                label: 'Provider field',
                controller: controller,
                palette: FolderExplorerPalette.of(context),
                showPasteButton: true,
              ),
              ProviderBadge(
                key: const ValueKey('provider-badge'),
                source: const CollectionSource(
                  service: ProviderService.googleDrive,
                ),
                detail: 'Provider badge',
                palette: CollectionPalette.of(context, CollectionKind.folder),
                onTap: () {},
              ),
              AFMenuItem(
                key: const ValueKey('af-menu'),
                title: const Text('AF menu'),
                onTap: () {},
              ),
              AFGhostButton.normal(
                key: const ValueKey('af-ghost'),
                onTap: () {},
                builder: (_, __, ___) => const Text('AF ghost'),
              ),
            ],
          ),
        );
        final hover = PremiumThemeExtension.of(context).subtleHover;
        final paste = find
            .ancestor(
              of: find.byIcon(Icons.content_paste_rounded),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final badge = find.descendant(
          of: find.byKey(const ValueKey('provider-badge')),
          matching: find.byType(AnimatedContainer),
        );
        final menu = find.descendant(
          of: find.byKey(const ValueKey('af-menu')),
          matching: find.byType(AnimatedContainer),
        );
        final ghost = find.descendant(
          of: find.byKey(const ValueKey('af-ghost')),
          matching: find.byType(AnimatedContainer),
        );
        expect(badge, findsOneWidget);
        expect(menu, findsNWidgets(2));
        expect(ghost, findsNWidgets(2));
        final fieldState =
            tester.state<EditableTextState>(find.byType(EditableText));

        for (final target in [paste, badge, menu.last, ghost.last]) {
          expect(_paintedFill(tester, target).a, 0);
          await mouse.moveTo(tester.getCenter(target));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(
            _paintedFill(tester, target).a,
            inInclusiveRange(0.0, hover.a),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(_paintedFill(tester, target), hover);
          await mouse.moveTo(const Offset(790, 590));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          expect(_paintedFill(tester, target).a, 0);
        }
        for (final target in [paste, badge]) {
          final rest = _paintedFill(tester, target);
          expect([rest.r, rest.g, rest.b], [hover.r, hover.g, hover.b]);
        }
        expect(controller.text, 'Retained draft');
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(fieldState),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        controller.dispose();
      }
    });

    testWidgets('$mode: pointer wash does not rewrite semantic states',
        (tester) async {
      final searchController = TextEditingController();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(790, 590));
        final context = await _mount(
          tester,
          mode,
          overlay: const Color(0x08675443),
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectionWorkspaceAction(
                key: const ValueKey('action'),
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: () {},
              ),
              CollectionWorkspaceAction(
                key: const ValueKey('selected-action'),
                icon: Icons.check_rounded,
                tooltip: 'Selected',
                selected: true,
                onPressed: () {},
              ),
              const CollectionWorkspaceAction(
                key: ValueKey('disabled-action'),
                icon: Icons.refresh_rounded,
                tooltip: 'Disabled',
              ),
              CollectionWorkspaceAction(
                key: const ValueKey('danger-action'),
                icon: Icons.delete_rounded,
                tooltip: 'Delete',
                color: Theme.of(context).colorScheme.error,
                onPressed: () {},
              ),
              CollectionWorkspaceNavRow(
                key: const ValueKey('nav-row'),
                onTap: () {},
                child: const Text('Navigation'),
              ),
              VisualBlockButton(
                icon: Icons.edit_rounded,
                tooltip: 'Visual action',
                selected: true,
                onTap: () {},
              ),
              VisualBlockSegments<int>(
                value: 0,
                segments: const [
                  (value: 0, icon: Icons.visibility_rounded, label: 'Preview'),
                  (value: 1, icon: Icons.code_rounded, label: 'Source'),
                ],
                onChanged: (_) {},
              ),
              InteractiveIconButton(
                key: const ValueKey('interactive-icon'),
                icon: Icons.add_rounded,
                tooltip: 'Interactive action',
                onPressed: () {},
              ),
              InteractiveButton(
                key: const ValueKey('interactive-button'),
                label: 'Subtle action',
                emphasis: InteractiveEmphasis.subtle,
                onPressed: () {},
              ),
              ExplorerToolbar(
                searchController: searchController,
                onNewFile: (_) {},
                onNewFolder: () {},
                onCreateCollection: (_) {},
                onCreateDatabase: (_) {},
                onPaste: null,
                onRefresh: () {},
                onMore: () {},
                onSearchChanged: (_) {},
                canPaste: false,
                isSearching: false,
              ),
            ],
          ),
        );
        final hover = WorkspaceChrome.hoverColor(context);
        final workspace = WorkspacePalette.of(context);
        final visual = VisualBlockPalette.of(context);
        final action = _textButton(tester, 'action').style!;
        expect(action.overlayColor!.resolve({WidgetState.hovered}), hover);
        expect(
          action.overlayColor!.resolve({WidgetState.focused}),
          workspace.hover.withValues(alpha: 0.4),
        );
        expect(
          action.overlayColor!.resolve({WidgetState.pressed}),
          workspace.hover.withValues(alpha: 0.4),
        );
        expect(
          action.side!.resolve({WidgetState.focused})!.color,
          workspace.focus,
        );
        expect(
          _textButton(tester, 'selected-action')
              .style!
              .backgroundColor!
              .resolve({WidgetState.hovered}),
          workspace.hover.withValues(alpha: 0.35),
        );
        final disabled = _textButton(tester, 'disabled-action');
        expect(disabled.onPressed, isNull);
        expect(
          disabled.style!.overlayColor!
              .resolve({WidgetState.disabled, WidgetState.hovered})!.a,
          0,
        );
        expect(
          _textButton(tester, 'danger-action')
              .style!
              .foregroundColor!
              .resolve({WidgetState.hovered}),
          Theme.of(context).colorScheme.error,
        );

        final visualButton = tester.widget<IconButton>(
          find.descendant(
            of: find.byType(VisualBlockButton),
            matching: find.byType(IconButton),
          ),
        );
        expect(visualButton.isSelected, isTrue);
        expect(
          visualButton.style!.backgroundColor!.resolve({}),
          visual.accentSoft,
        );
        expect(
          visualButton.style!.overlayColor!.resolve({WidgetState.hovered}),
          hover,
        );
        expect(
          visualButton.style!.overlayColor!.resolve({WidgetState.focused}),
          visual.hover,
        );
        final legacySegmentOverlay = TextButton.styleFrom(
          overlayColor: visual.hover,
        ).overlayColor!;
        for (final segment in tester.widgetList<TextButton>(
          find.descendant(
            of: find.byType(VisualBlockSegments<int>),
            matching: find.byType(TextButton),
          ),
        )) {
          expect(
            segment.style!.overlayColor!.resolve({WidgetState.hovered}),
            hover,
          );
          expect(
            segment.style!.backgroundColor!.resolve({WidgetState.hovered})!.a,
            0,
            reason: 'The hover overlay must not stack with a background wash',
          );
          for (final states in [
            {WidgetState.focused},
            {WidgetState.pressed},
            {WidgetState.focused, WidgetState.hovered},
          ]) {
            expect(
              segment.style!.overlayColor!.resolve(states),
              legacySegmentOverlay.resolve(states),
            );
            expect(segment.style!.backgroundColor!.resolve(states), isNull);
          }
        }

        final folder = FolderExplorerPalette.of(context);
        final toolbarButtons = find.descendant(
          of: find.byType(ExplorerToolbar),
          matching: find.byType(IconButton),
        );
        expect(toolbarButtons, findsNWidgets(4));
        for (final button in tester.widgetList<IconButton>(toolbarButtons)) {
          expect(button.hoverColor, hover);
          expect(button.highlightColor, folder.selected);
          expect(
            button.style!.backgroundColor!.resolve({WidgetState.hovered})!.a,
            0,
          );
          expect(
            button.style!.backgroundColor!.resolve({WidgetState.focused}),
            isNull,
          );
        }

        for (final (key, factor) in [
          ('nav-row', 1.0),
          ('interactive-icon', 1.0),
          ('interactive-button', 0.9),
        ]) {
          final target = find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(AnimatedContainer),
          );
          expect(target, findsOneWidget);
          final rest = _paintedFill(tester, target);
          expect(rest.a, 0);
          expect([rest.r, rest.g, rest.b], [hover.r, hover.g, hover.b]);
          await mouse.moveTo(tester.getCenter(target));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          expect(
            _paintedFill(tester, target).a,
            closeTo(hover.a * factor, 0.000001),
          );
          await mouse.moveTo(const Offset(790, 590));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          expect(_paintedFill(tester, target).a, 0);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        searchController.dispose();
      }
    });
  }

  test('a custom overlay has no minimum alpha floor', () {
    final premium = _theme('paper').extension<PremiumThemeExtension>()!;
    for (final alpha in [0.0, 1 / 255, 8 / 255, 0.5, 1.0]) {
      final custom = premium.copyWith(
        hoverOverlay: premium.hoverOverlay.withValues(alpha: alpha),
      );
      expect(
        custom.subtleHover.a,
        closeTo((alpha * 0.65).clamp(0.0, 0.07), 0.000001),
      );
      expect(custom.selected, premium.selected);
      expect(custom.focusRing, premium.focusRing);
      expect(custom.hover, premium.hover);
    }
  });
}

// A small, deliberately scoped lexical guard, not a Dart analyzer. It accepts
// zero-alpha endpoints and multiplication of the SAME receiver's alpha. The
// nested factor need not be parsed to detect the old literal/ternary overrides.
List<String> _absoluteHoverAlphas(String source) {
  final calls = RegExp(
    r'\b((?:[A-Za-z_]\w*\s*\.\s*)*hover)\s*\.\s*'
    r'(withValues|withOpacity|withAlpha)\s*\(\s*(?:alpha\s*:\s*)?',
  );
  final violations = <String>[];
  for (final match in calls.allMatches(source)) {
    final receiver = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    final argument = RegExp('^[^,)]+')
        .stringMatch(source.substring(match.end))!
        .replaceAll(RegExp(r'\s+'), '');
    if (argument == '0' ||
        argument == '0.0' ||
        (match.group(2) != 'withAlpha' &&
            argument.startsWith('$receiver.a*'))) {
      continue;
    }
    final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    violations.add('line $line: $receiver.${match.group(2)}($argument)');
  }
  return violations;
}

ThemeData _theme(String mode, {Color? overlay}) {
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  final appTheme = mode == 'paper'
      ? AppTheme.builtins
          .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
      : AppTheme.fallback;
  final legacy =
      brightness == Brightness.dark ? appTheme.darkTheme : appTheme.lightTheme;
  final palette = PremiumTheme.resolve(
    appTheme: appTheme,
    legacy: legacy,
    brightness: brightness,
  ).copyWith(hoverOverlay: overlay);
  return PremiumTheme.materialTheme(
    legacy: legacy,
    palette: palette,
    brightness: brightness,
    fontFamily: 'Ahem',
    textTheme: ThemeData(brightness: brightness).textTheme,
    isDesktop: true,
  ).copyWith(
    platform: TargetPlatform.windows,
    extensions: [palette, PaperThemeExtension(enabled: mode == 'paper')],
  );
}

Future<BuildContext> _mount(
  WidgetTester tester,
  String mode, {
  required WidgetBuilder builder,
  Color? overlay,
}) async {
  final theme = _theme(mode, overlay: overlay);
  final defaults = AppFlowyDefaultTheme();
  late BuildContext sample;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: mode == 'dark' ? defaults.dark() : defaults.light(),
          palette: theme.extension<PremiumThemeExtension>()!,
          brightness: theme.brightness,
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 560,
              child: Builder(
                builder: (context) {
                  sample = context;
                  return builder(context);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return sample;
}

Color _paintedFill(WidgetTester tester, Finder animatedContainer) {
  final decoration = tester
      .widget<DecoratedBox>(
        find
            .descendant(
              of: animatedContainer,
              matching: find.byType(DecoratedBox),
            )
            .first,
      )
      .decoration as BoxDecoration;
  return decoration.color!;
}

TextButton _textButton(WidgetTester tester, String key) =>
    tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextButton),
      ),
    );
