import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/deferred_code_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/context_menu/app_menu_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_inspection_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_preview.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_delete_button.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_row_surface.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'workspace_overlay_test_app.dart';

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  test('a code excerpt is coloured with its viewer grammar', () {
    ViewPB file(String name, {String? stored}) => ViewPB(
          id: name,
          name: name,
          extra: stored == null
              ? ''
              : WorkspaceFilePreviewCodec.merge('', {'code_language': stored}),
        );
    expect(searchPreviewCodeLanguage(file('main.dart'), 'main.dart'), 'dart');
    expect(searchPreviewCodeLanguage(file('app.py'), 'app.py'), 'python');
    // The language picked in the viewer wins over the extension.
    expect(
      searchPreviewCodeLanguage(file('lib.rs', stored: 'go'), 'lib.rs'),
      'go',
    );
    expect(searchPreviewCodeLanguage(file('notes.txt'), 'notes.txt'), isNull);
    expect(searchPreviewCodeLanguage(file('read.md'), 'read.md'), isNull);
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: a code file previews as coloured source',
        (tester) async {
      final folder = Directory.systemTemp.createTempSync('palette_excerpt');
      addTearDown(() => folder.deleteSync(recursive: true));
      const source = 'class Greeter {\n'
          '  // Says hello.\n'
          '  String greet() => "hello";\n'
          '}\n';
      final file = File(p.join(folder.path, 'main.dart'))
        ..writeAsStringSync(source);
      // Already parsed, so the colours are there without a worker isolate.
      buildSyntaxHighlightedTextSpan(
        code: source,
        language: 'dart',
        brightness: appearance == 'dark' ? Brightness.dark : Brightness.light,
        isPaper: appearance == 'paper',
      );

      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: SizedBox(
            width: 420,
            height: 300,
            child: FilePreviewExcerpt(
              path: file.path,
              fallback: const Text('fallback'),
              language: 'dart',
            ),
          ),
        ),
      );
      final highlight = find.byType(DeferredCodeHighlight);
      for (var i = 0; i < 50 && highlight.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final widget = tester.widget<DeferredCodeHighlight>(highlight);
      final context = tester.element(highlight);
      expect(widget.code, source);
      expect(widget.language, 'dart');
      expect(widget.brightness, Theme.of(context).brightness);
      expect(widget.isPaper, PaperTheme.isEnabled(context));
      final span = tester
          .widget<Text>(
            find.descendant(of: highlight, matching: find.byType(Text)),
          )
          .textSpan!;
      expect(span.toPlainText(), source);
      final colors = <Color>{};
      span.visitChildren((child) {
        final color = child.style?.color;
        if (color != null) colors.add(color);
        return true;
      });
      expect(colors.length, greaterThanOrEqualTo(3));
      expect(find.text('fallback'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: rows ease between the theme tints',
        (tester) async {
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      var hovers = 0;
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: Center(
            child: SizedBox(
              width: 320,
              child: ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, value, __) => PaletteRowSurface(
                  active: value,
                  onHover: () => hovers++,
                  child: const SizedBox(height: 40, child: Text('Row')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Row'));
      final hover = WorkspaceChrome.hoverColor(context);
      final selected = WorkspaceChrome.selectedColor(context);
      if (appearance == 'paper') {
        expect(selected, PaperTheme.selectedOverlay);
      }
      AnimatedContainer surface() => tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(PaletteRowSurface),
              matching: find.byType(AnimatedContainer),
            ),
          );
      Color? fill() => (surface().decoration! as BoxDecoration).color;

      expect(surface().duration, WorkspaceTokens.hoverDuration);
      expect(fill(), selected.withValues(alpha: 0));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Row')));
      await tester.pump();
      expect(hovers, greaterThan(0));
      expect(fill(), hover);

      active.value = true;
      await tester.pump();
      final before = hovers;
      await mouse.moveBy(const Offset(4, 0));
      await tester.pump();
      expect(hovers, before, reason: 'An active row is not re-selected.');
      expect(fill(), Color.alphaBlend(hover, selected));

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(fill(), selected);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: the delete button is themed and slides in',
        (tester) async {
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      final view = ViewPB(id: 'page', parentViewId: 'parent', name: 'Notes');
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, value, __) =>
                  PaletteDeleteButton(view: view, visible: value),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byType(PaletteDeleteButton);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.descendant(of: button, matching: find.byType(AnimatedOpacity)),
          )
          .opacity;
      bool ignoring() => tester
          .widget<IgnorePointer>(
            find
                .descendant(of: button, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring;
      expect(opacity(), 0);
      expect(ignoring(), isTrue);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(
        find.descendant(of: button, matching: find.byType(WorkspaceGlyph)),
        findsOneWidget,
      );

      visible.value = true;
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(ignoring(), isFalse);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pumpAndSettle();
      final danger = AppMenuStyle.of(tester.element(button)).danger;
      final wash = tester.widget<AnimatedContainer>(
        find.descendant(of: button, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (wash.decoration! as BoxDecoration).color,
        danger.withValues(alpha: 0.12),
      );
      expect(
        tester
            .widget<WorkspaceGlyph>(
              find.descendant(
                of: button,
                matching: find.byType(WorkspaceGlyph),
              ),
            )
            .color,
        danger,
      );
      expect(PaletteDeleteButton.canDelete(ViewPB(id: 'root')), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$appearance: an active filter reads in the accent',
        (tester) async {
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: SearchFilterBar(
            filter: const CommandPaletteFilter(titleOnly: true),
            spaces: const [],
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = find.byKey(const ValueKey('command-palette-title-filter'));
      final context = tester.element(chip);
      final accent = WorkspacePalette.of(context).accent;
      final label = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)),
      );
      expect(label.style?.color, accent);
      expect(
        tester
            .widgetList<AnimatedContainer>(
              find.descendant(
                of: chip,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .map((box) => (box.decoration as BoxDecoration?)?.color),
        contains(WorkspaceChrome.selectedColor(context)),
      );
      final idle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('command-palette-content-filter')),
          matching: find.byType(Text),
        ),
      );
      expect(idle.style?.color, isNot(accent));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$appearance: the preview settles, cross-fades and never lingers '
        'once access is gone', (tester) async {
      ViewPB folder(String id, String name) => ViewPB(
            id: id,
            parentViewId: 'workspace',
            name: name,
            layout: ViewLayoutPB.Document,
            extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
          );
      final alpha = folder('alpha', 'Alpha shelf');
      final beta = folder('beta', 'Beta shelf');
      final gamma = folder('gamma', 'Gamma shelf');
      final views = {alpha.id: alpha, beta.id: beta, gamma.id: gamma};
      final allowed = {...views.keys};
      final selected = ValueNotifier(alpha);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: Center(
            child: SizedBox(
              width: 520,
              height: 600,
              child: ValueListenableBuilder<ViewPB>(
                valueListenable: selected,
                builder: (_, view, __) => PageInspectionPanel(
                  view: view,
                  cachedViews: views,
                  currentUserId: null,
                  onOpen: (_) {},
                  onClose: () {},
                  canUseView: allowed.contains,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final panel = tester.state(find.byType(PageInspectionPanel));
      expect(find.text('Alpha shelf'), findsWidgets);

      // Passing over Beta on the way to Gamma never builds Beta's preview.
      selected.value = beta;
      await tester.pump(const Duration(milliseconds: 40));
      selected.value = gamma;
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('Beta shelf'), findsNothing);
      expect(find.text('Gamma shelf'), findsNothing);
      expect(find.text('Alpha shelf'), findsWidgets);

      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Gamma shelf'), findsWidgets);
      // The outgoing preview is still fading but no longer takes input.
      final leaving = find.text('Alpha shelf').first;
      expect(leaving, findsOneWidget);
      expect(
        tester
            .widgetList<IgnorePointer>(
              find.ancestor(of: leaving, matching: find.byType(IgnorePointer)),
            )
            .any((widget) => widget.ignoring),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text('Alpha shelf'), findsNothing);
      expect(find.text('Beta shelf'), findsNothing);
      expect(find.text('Gamma shelf'), findsWidgets);
      expect(tester.state(find.byType(PageInspectionPanel)), same(panel));

      // Revoked content is cut at once, not faded out.
      allowed.remove(gamma.id);
      selected.value = alpha;
      await tester.pump();
      expect(find.text('Gamma shelf'), findsNothing);
      expect(find.text('Alpha shelf'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
