import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

void main() {
  fileControlTestSetup();

  for (final mode in fileControlAppearances) {
    for (final reduced in [false, true]) {
      testWidgets(
          '$mode/reduced=$reduced: shared, native and menu hover use the same subtle wash',
          (tester) async {
        late BuildContext sample;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final semantics = tester.ensureSemantics();
        var activated = 0;
        try {
          await mouse.addPointer(location: const Offset(1080, 880));
          await mountFileControls(
            tester,
            Builder(
              builder: (context) {
                sample = context;
                final palette = CodeBlockPalette.resolve(context);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WorkspaceControlButton(
                      key: const ValueKey('workspace-control'),
                      icon: Icons.refresh_rounded,
                      tooltip: 'Shared action',
                      label: 'Shared action',
                      onPressed: () => activated++,
                    ),
                    CodeToolbarButton(
                      palette: palette,
                      tooltip: 'Code action',
                      icon: Icons.code_rounded,
                      onPressed: () {},
                    ),
                    ArchivePillButton(
                      tooltip: 'Archive action',
                      icon: Icons.folder_zip_rounded,
                      onPressed: () {},
                    ),
                    DocumentViewportButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Viewport action',
                      onPressed: () {},
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Global text button'),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                    SizedBox(
                      width: 280,
                      child: AppMenuRow(
                        key: const ValueKey('menu-row'),
                        label: 'Global menu row',
                        icon: Icons.settings_rounded,
                        tracksHover: true,
                        onTap: () {},
                      ),
                    ),
                  ],
                );
              },
            ),
            mode: mode,
            reduced: reduced,
          );
          final premium = PremiumThemeExtension.of(sample);
          final hover = premium.subtleHover;
          expect(hover.a, greaterThan(0));
          expect(hover.a, lessThanOrEqualTo(0.07));
          expect(hover.a, closeTo(premium.hoverOverlay.a * 0.65, 0.000001));
          expect(WorkspaceChrome.hoverColor(sample), hover);
          expect(DocumentViewportStyle.of(sample).controlHover, hover);
          expect(CodeBlockPalette.resolve(sample).hover, hover);
          expect(AppMenuStyle.of(sample).hover, hover);
          expect(AppFlowyTheme.of(sample).fillColorScheme.contentHover, hover);
          expect(Theme.of(sample).hoverColor, hover);

          for (final style in [
            WorkspaceChrome.controlStyle(sample),
            Theme.of(sample).textButtonTheme.style!,
            Theme.of(sample).iconButtonTheme.style!,
            Theme.of(sample).outlinedButtonTheme.style!,
          ]) {
            final rest = style.backgroundColor!.resolve({})!;
            final hovered =
                style.backgroundColor!.resolve({WidgetState.hovered})!;
            final disabled = style.backgroundColor!
                .resolve({WidgetState.disabled, WidgetState.hovered})!;
            expect(rest.a, 0);
            expect(disabled.a, 0);
            expect(hovered, hover);
            expect([rest.r, rest.g, rest.b], [hover.r, hover.g, hover.b]);
            expect(
              style.foregroundColor!.resolve({}),
              style.foregroundColor!.resolve({WidgetState.hovered}),
            );
          }
          final lowAlpha =
              premium.copyWith(hoverOverlay: const Color(0x08675443));
          expect(lowAlpha.subtleHover.a, closeTo((8 / 255) * 0.65, 0.000001));
          expect(lowAlpha.subtlePressed.a, closeTo((8 / 255) * 1.2, 0.000001));

          // Inspect the actual interpolated menu decoration, not only the
          // target token. Its zero-alpha endpoint must retain the same RGB.
          final row = find.byKey(const ValueKey('menu-row'));
          final idle = _menuFill(tester, row);
          expect([idle.r, idle.g, idle.b], [hover.r, hover.g, hover.b]);
          await mouse.moveTo(tester.getCenter(row));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          final mid = _menuFill(tester, row);
          expect(mid.a, inInclusiveRange(0.0, hover.a));
          expect(mid.r, closeTo(hover.r, 0.005));
          expect(mid.g, closeTo(hover.g, 0.005));
          expect(mid.b, closeTo(hover.b, 0.005));
          await settleFileControls(tester);
          expect(_menuFill(tester, row).a, closeTo(hover.a, 0.005));

          final control = find.byKey(const ValueKey('workspace-control'));
          final native =
              find.descendant(of: control, matching: find.byType(TextButton));
          await mouse.moveTo(const Offset(1080, 880));
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await settleFileControls(tester);
          expect(
            tester
                .getSemantics(native)
                .getSemanticsData()
                .hasFlag(ui.SemanticsFlag.isFocused),
            isTrue,
          );
          expect(
            tester
                .getSemantics(native)
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          final style = tester.widget<TextButton>(native).style!;
          expect(
            style.side!.resolve({WidgetState.focused})!.color,
            premium.accent,
          );
          expect(
            style.animationDuration,
            reduced ? Duration.zero : const Duration(milliseconds: 140),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await settleFileControls(tester);
          expect(activated, 2);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await mouse.removePointer();
          await unmountFileControls(tester);
        }
      });
    }

    testWidgets(
        '$mode: disabled and destructive controls preserve semantic ink',
        (tester) async {
      try {
        await mountFileControls(
          tester,
          Builder(
            builder: (context) => Column(
              children: [
                const WorkspaceControlButton(
                  key: ValueKey('disabled'),
                  icon: Icons.refresh_rounded,
                  tooltip: 'Unavailable',
                  onPressed: null,
                ),
                CodeToolbarButton(
                  key: const ValueKey('destructive'),
                  palette: CodeBlockPalette.resolve(context),
                  tooltip: 'Delete case',
                  icon: Icons.delete_outline_rounded,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          mode: mode,
        );
        for (final name in ['disabled', 'destructive']) {
          final glyph = tester.widget<WorkspaceGlyph>(
            find.descendant(
              of: find.byKey(ValueKey(name)),
              matching: find.byType(WorkspaceGlyph),
            ),
          );
          expect(glyph.role, WorkspaceGlyphRole.preserveInk);
        }
        final disabled = tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const ValueKey('disabled')),
            matching: find.byType(TextButton),
          ),
        );
        expect(disabled.onPressed, isNull);
        expect(
          disabled.style!.backgroundColor!
              .resolve({WidgetState.disabled, WidgetState.hovered})!.a,
          0,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
      }
    });
  }
}

Color _menuFill(WidgetTester tester, Finder row) => (tester
        .widget<DecoratedBox>(
          find.descendant(of: row, matching: find.byType(DecoratedBox)).first,
        )
        .decoration as BoxDecoration)
    .color!;
