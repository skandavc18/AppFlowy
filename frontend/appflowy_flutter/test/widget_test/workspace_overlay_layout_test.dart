import 'dart:ui' as ui;

import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_inspection_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_preview.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_layout.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  test('search width and height are independent, including keyboard insets',
      () {
    final short = commandPaletteDialogSize(const Size(1280, 480));
    final tall = commandPaletteDialogSize(const Size(1280, 1000));
    final portrait = commandPaletteDialogSize(const Size(480, 1000));
    expect(short.width, tall.width);
    expect(short.height, lessThan(tall.height));
    expect(portrait.height, tall.height);
    expect(portrait.width, lessThan(tall.width));
    expect(short.aspectRatio, isNot(closeTo(4 / 3, 0.01)));
    final keyboard = commandPaletteDialogSize(
      const Size(980, 800),
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    final noKeyboard = commandPaletteDialogSize(const Size(980, 800));
    expect(keyboard.width, noKeyboard.width);
    expect(keyboard.height, noKeyboard.height - 300);
    expect(commandPaletteDialogSize(const Size(20, 20)), Size.zero);
    expect(commandPaletteListWidth(-10), 0);
    expect(commandPaletteListWidth(2000), commandPaletteListMaxWidth);
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance preview is continuous and gives content the height',
        (tester) async {
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          textScale: 2,
          child: const Center(
            child: SizedBox(
              width: 460,
              height: 240,
              child: CommandPalettePreviewSurface(
                header:
                    SizedBox(height: 300, child: Text('Long preview identity')),
                child: SizedBox.expand(key: ValueKey('preview-renderer')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byType(CommandPalettePreviewSurface);
      expect(tester.getSize(surface), const Size(460, 240));
      expect(
        tester.getSize(find.byKey(const ValueKey('preview-renderer'))),
        const Size(460, 132),
      );
      final fill = tester.widget<ColoredBox>(
        find.descendant(of: surface, matching: find.byType(ColoredBox)).first,
      );
      expect(
        fill.color,
        WorkspacePalette.of(tester.element(surface)).elevatedSurface,
      );
      expect(
        find.descendant(
          of: surface,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                ((widget.decoration! as BoxDecoration).border != null ||
                    (widget.decoration! as BoxDecoration).boxShadow != null),
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$appearance long preview title keeps its native keyboard action',
        (tester) async {
      const title =
          'Research 📚 — a long title that must wrap rather than overflow';
      final view = ViewPB(id: 'preview-title', name: title);
      var opened = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            textScale: 2,
            disableAnimations: true,
            child: Center(
              child: SizedBox(
                width: 220,
                child: Builder(
                  builder: (context) => PagePreview(
                    view: view,
                    onViewOpened: () => opened++,
                  ).buildTitle(context, view),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byType(TextButton);
        final node = tester.getSemantics(button);
        expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester.widget<TextButton>(button).style?.animationDuration,
          Duration.zero,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opened, 1);
        expect(tester.getSize(button).width, 220);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
        '$appearance compact folder inspection scrolls without hiding actions',
        (tester) async {
      final folder = ViewPB(
        id: 'root',
        name: 'Research',
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final page = ViewPB(
        id: 'child',
        parentViewId: folder.id,
        name: 'Project brief',
        layout: ViewLayoutPB.Document,
      );
      ViewPB? opened;
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          textScale: 2,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 380,
              child: PageInspectionPanel(
                view: folder,
                cachedViews: {folder.id: folder, page.id: page},
                currentUserId: null,
                onOpen: (value) => opened = value,
                onClose: () {},
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final open = find.byKey(const ValueKey('command-palette-open-action'));
      expect(open.hitTestable(), findsOneWidget);
      expect(
        find
            .byKey(const ValueKey('command-palette-favorite-action'))
            .hitTestable(),
        findsOneWidget,
      );
      final child =
          find.byKey(const ValueKey('command-palette-folder-child-child'));
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(child, 80, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Project brief')).style?.fontSize,
        15,
      );
      await tester.tap(child);
      expect(opened?.id, page.id);
      expect(open.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
