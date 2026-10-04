import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/align_toolbar_item/align_toolbar_item.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/heading/heading_toolbar_item.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as editor;
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _outside = Offset(780, 580);
const _halfFade = Duration(milliseconds: 70);
const _finishFade = Duration(milliseconds: 71);
const _settle = Duration(milliseconds: 141);
const _rowNames = ['media', 'relation', 'notification'];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final mode in ['light', 'dark', 'paper']) {
    for (final motion in ['normal', 'disabled', 'accessible']) {
      final reduced = motion != 'normal';

      testWidgets(
          '$mode/$motion: legacy toolbar paint and native popup ownership',
          (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _outside);
        try {
          for (final entry in {
            'heading': headingsToolbarItem,
            'alignment': alignToolbarItem,
          }.entries) {
            final state = editor.EditorState(
              document: editor.Document.blank()
                ..insert([0], [editor.paragraphNode(text: 'Retained text')]),
            );
            final selection = editor.Selection(
              start: editor.Position(path: [0]),
              end: editor.Position(path: [0], offset: 8),
            );
            state.selection = selection;
            final holds = editor.keepEditorFocusNotifier.value;
            PopoverState? ownedPopover;
            try {
              final context = await _mount(tester, mode, motion, (context) {
                final palette = PremiumThemeExtension.of(context);
                return ColoredBox(
                  key: const ValueKey('toolbar-surface'),
                  color: palette.floatingSurface,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeyedSubtree(
                        key: const ValueKey('trigger'),
                        child: entry.value.builder!(
                          context,
                          state,
                          palette.accent,
                          palette.textSecondary,
                          null,
                        ),
                      ),
                      if (entry.key == 'heading')
                        HeadingButton(
                          key: const ValueKey('selected-heading'),
                          icon: FlowySvgs.h2_s,
                          tooltip: 'Selected heading',
                          onTap: () {},
                          highlightColor: palette.accent,
                          isHighlight: true,
                        ),
                    ],
                  ),
                );
              });
              final palette = PremiumThemeExtension.of(context);
              final trigger = _key('trigger');
              final popoverHost = find.descendant(
                of: trigger,
                matching: find.byType(Popover),
              );
              expect(popoverHost, findsOneWidget);
              final nativePopover = tester.state<PopoverState>(popoverHost);
              ownedPopover = nativePopover;
              expect(
                _glyphs(tester, trigger).map((glyph) => glyph.color),
                everyElement(palette.textSecondary),
              );
              await _checkPointerFade(
                tester,
                mouse,
                trigger,
                palette,
                reduced: reduced,
              );
              if (entry.key == 'heading') {
                final selected = _key('selected-heading');
                expect(_glyphs(tester, selected).single.color, palette.accent);
                await _checkPointerFade(
                  tester,
                  mouse,
                  selected,
                  palette,
                  reduced: reduced,
                );
              }
              expect(state.selection, selection);
              expect(
                state.getNodeAtPath([0])!.delta!.toPlainText(),
                'Retained text',
              );
              expect(editor.keepEditorFocusNotifier.value, holds);

              await tester.tap(trigger, kind: PointerDeviceKind.mouse);
              await tester.pump();
              await tester.pump();
              final popup = find.byWidgetPredicate(
                (widget) =>
                    widget is PopoverContainer &&
                    identical(widget.delegate, nativePopover.layoutDelegate),
                description: '${entry.key} trigger-owned native popup',
              );
              expect(popup, findsOneWidget);
              expect(PopoverState.rootEntry.contains(nativePopover), isTrue);
              expect(editor.keepEditorFocusNotifier.value, holds + 1);
              expect(state.selection, selection);
              final surface = find.descendant(
                of: popup,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is DecoratedBox &&
                      widget.decoration is ShapeDecoration,
                ),
              );
              expect(surface, findsOneWidget);
              expect(
                (tester.widget<DecoratedBox>(surface).decoration
                        as ShapeDecoration)
                    .color,
                palette.floatingSurface,
              );
              expect(tester.getSize(surface).height, 32);
              expect(
                find.descendant(
                  of: popup,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is ColoredBox &&
                        widget.color == Theme.of(context).dividerColor,
                  ),
                ),
                findsNWidgets(2),
              );
              final options = find.descendant(
                of: popup,
                matching: find.byType(FlowyButton),
              );
              expect(options, findsNWidgets(3));
              final popupState = tester.state<PopoverContainerState>(popup);
              final optionContexts = [
                for (var index = 0; index < 3; index++)
                  tester.element(options.at(index)),
              ];
              expect(
                _glyphs(tester, popup).map((glyph) => glyph.color),
                everyElement(palette.textPrimary),
              );
              for (var index = 0; index < 3; index++) {
                await _checkPointerFade(
                  tester,
                  mouse,
                  options.at(index),
                  palette,
                  reduced: reduced,
                );
                expect(
                  tester.state<PopoverContainerState>(popup),
                  same(popupState),
                );
                final optionContext = optionContexts[index];
                expect(tester.element(options.at(index)), same(optionContext));
                expect(optionContext.mounted, isTrue);
                expect(tester.renderObject(options.at(index)).attached, isTrue);
                expect(PopoverContainer.maybeOf(optionContext), isNotNull);
                expect(
                  PopoverContainer.maybeOf(optionContext),
                  same(popupState),
                );
                expect(PopoverState.rootEntry.contains(nativePopover), isTrue);
                expect(editor.keepEditorFocusNotifier.value, holds + 1);
                expect(state.selection, selection);
              }

              // Dismiss without mutating the document: native popup ownership
              // must retain the original, non-null editor selection.
              await _escape(tester);
              expect(popup, findsNothing);
              expect(PopoverState.rootEntry.contains(nativePopover), isFalse);
              expect(popupState.mounted, isFalse);
              expect(
                optionContexts.every((context) => !context.mounted),
                isTrue,
              );
              expect(nativePopover.mounted, isTrue);
              expect(
                tester.state<PopoverState>(popoverHost),
                same(nativePopover),
              );
              expect(editor.keepEditorFocusNotifier.value, holds);
              expect(state.selection, isNotNull);
              expect(state.selection, selection);
              expect(
                state.getNodeAtPath([0])!.delta!.toPlainText(),
                'Retained text',
              );

              await tester.tap(trigger, kind: PointerDeviceKind.mouse);
              await tester.pump();
              await tester.pump();
              expect(popup, findsOneWidget);
              expect(options, findsNWidgets(3));
              expect(editor.keepEditorFocusNotifier.value, holds + 1);
              expect(state.selection, isNotNull);
              expect(state.selection, selection);
              final actionPopupState =
                  tester.state<PopoverContainerState>(popup);
              final actionContext = tester.element(options.at(1));

              // Exercise the real handlers; neither menu auto-closes on selection.
              await tester.tap(options.at(1), kind: PointerDeviceKind.mouse);
              await tester.pump();
              await tester.pump();
              final node = state.getNodeAtPath([0])!;
              if (entry.key == 'heading') {
                expect(node.type, editor.HeadingBlockKeys.type);
                expect(node.attributes[editor.HeadingBlockKeys.level], 2);
              } else {
                expect(
                  node.attributes[editor.blockComponentAlign],
                  centerAlignmentKey,
                );
              }
              expect(node.delta!.toPlainText(), 'Retained text');
              expect(popup, findsOneWidget);
              expect(
                tester.state<PopoverContainerState>(popup),
                same(actionPopupState),
              );
              expect(tester.element(options.at(1)), same(actionContext));
              expect(actionContext.mounted, isTrue);
              expect(tester.renderObject(options.at(1)).attached, isTrue);
              expect(PopoverContainer.maybeOf(actionContext), isNotNull);
              expect(
                PopoverContainer.maybeOf(actionContext),
                same(actionPopupState),
              );
              expect(PopoverState.rootEntry.contains(nativePopover), isTrue);
              expect(editor.keepEditorFocusNotifier.value, holds + 1);

              // Heading replacement deletes the selected node and applies a
              // null transaction.afterSelection before Escape is dispatched.
              // Closing must preserve the action's result, not restore selection.
              final selectionAfterAction = state.selection;
              await _escape(tester);
              expect(popup, findsNothing);
              expect(PopoverState.rootEntry.contains(nativePopover), isFalse);
              expect(actionPopupState.mounted, isFalse);
              expect(actionContext.mounted, isFalse);
              expect(nativePopover.mounted, isTrue);
              expect(editor.keepEditorFocusNotifier.value, holds);
              expect(state.selection, selectionAfterAction);
              expect(tester.takeException(), isNull);
            } finally {
              // Close owned overlays before disposal even if an assertion fails.
              ownedPopover?.close();
              await _unmount(tester);
              state.dispose();
            }
          }
        } finally {
          await mouse.removePointer();
        }
      });

      testWidgets(
          '$mode/$motion: row paint adapter retains surface, geometry and drafts',
          (tester) async {
        // The dependency-heavy row call sites are guarded by the companion AST
        // suite. This renders their common paint boundary, NOT a database editor.
        final active = ValueNotifier(false);
        final controllers = {
          for (final name in _rowNames)
            name: TextEditingController(text: '$name draft'),
        };
        try {
          final context = await _mount(tester, mode, motion, (context) {
            final palette = PremiumThemeExtension.of(context);
            final legacy = AFThemeExtension.of(context);
            final surfaces = [
              palette.surface,
              palette.mutedSurface,
              palette.floatingSurface,
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _rowNames.length; index++)
                  ColoredBox(
                    key: ValueKey('${_rowNames[index]}-surface'),
                    color: surfaces[index],
                    child: ValueListenableBuilder<bool>(
                      valueListenable: active,
                      builder: (context, hovering, child) =>
                          FlowyHoverContainer(
                        key: ValueKey(_rowNames[index]),
                        applyStyle: hovering,
                        style: HoverStyle(
                          hoverColor: index == 0
                              ? legacy.greyHover
                              : legacy.lightGreyHover,
                          borderRadius:
                              BorderRadius.circular([4.0, 6.0, 0.0][index]),
                        ),
                        child: child!,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: index == 2
                              ? Border(
                                  left: BorderSide(
                                    width: 2,
                                    color: palette.accent,
                                  ),
                                )
                              : null,
                        ),
                        child: SizedBox(
                          width: 320,
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextField(
                              key: ValueKey('${_rowNames[index]}-field'),
                              controller: controllers[_rowNames[index]],
                              style: TextStyle(color: palette.textSecondary),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          });
          final palette = PremiumThemeExtension.of(context);
          final wash = palette.subtleHover;
          await tester.enterText(_key('relation-field'), 'Edited draft stays');
          await tester.pump();
          final focus = FocusManager.instance.primaryFocus;
          final fields = {
            for (final name in _rowNames)
              name: tester.state<EditableTextState>(_editable(name)),
          };
          final bounds = {
            for (final name in _rowNames) name: tester.getRect(_key(name)),
          };
          final fieldBounds = {
            for (final name in _rowNames)
              name: tester.getRect(_key('$name-field')),
          };
          for (final name in _rowNames) {
            expect(_fill(tester, _key(name)), wash.withValues(alpha: 0));
            expect(fieldBounds[name]!.left - bounds[name]!.left, 16);
            _checkMotion(tester, _key(name), reduced: reduced);
          }

          active.value = true;
          await tester.pump();
          await tester.pump(_halfFade);
          for (final name in _rowNames) {
            _checkMidpoint(_fill(tester, _key(name)), wash, reduced: reduced);
          }
          await tester.pump(_finishFade);
          for (final name in _rowNames) {
            final scope = _key(name);
            final base = tester.widget<ColoredBox>(_key('$name-surface')).color;
            expect(_fill(tester, scope), wash);
            expect(
              Color.alphaBlend(_fill(tester, scope), base),
              palette.hoverOn(base),
            );
            expect(tester.getRect(scope), bounds[name]);
            expect(tester.getRect(_key('$name-field')), fieldBounds[name]);
            expect(
              tester.state<EditableTextState>(_editable(name)),
              same(fields[name]),
            );
            expect(
              tester.widget<EditableText>(_editable(name)).style.color,
              palette.textSecondary,
            );
          }
          expect(FocusManager.instance.primaryFocus, same(focus));

          active.value = false;
          await tester.pump();
          await tester.pump(_settle);
          for (final name in _rowNames) {
            expect(_fill(tester, _key(name)), wash.withValues(alpha: 0));
            expect(
              tester.state<EditableTextState>(_editable(name)),
              same(fields[name]),
            );
            expect(
              controllers[name]!.text,
              name == 'relation' ? 'Edited draft stays' : '$name draft',
            );
          }
          expect(FocusManager.instance.primaryFocus, same(focus));
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
          active.dispose();
          for (final controller in controllers.values) {
            controller.dispose();
          }
        }
      });
    }
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));

Finder _editable(String name) => find.descendant(
      of: _key('$name-field'),
      matching: find.byType(EditableText),
    );

List<FlowySvg> _glyphs(WidgetTester tester, Finder scope) => tester
    .widgetList<FlowySvg>(
      find.descendant(of: scope, matching: find.byType(FlowySvg)),
    )
    .toList();

Color _fill(WidgetTester tester, Finder scope) => (tester
        .widget<DecoratedBox>(
          find.descendant(of: scope, matching: find.byType(DecoratedBox)).first,
        )
        .decoration as BoxDecoration)
    .color!;

void _checkMotion(WidgetTester tester, Finder scope, {required bool reduced}) {
  final animation = tester.widget<AnimatedContainer>(
    find.descendant(of: scope, matching: find.byType(AnimatedContainer)).first,
  );
  expect(
    animation.duration,
    reduced ? Duration.zero : const Duration(milliseconds: 140),
  );
  expect(animation.curve, Curves.easeOutCubic);
}

void _checkMidpoint(Color actual, Color wash, {required bool reduced}) {
  expect(actual.r, closeTo(wash.r, 1e-6));
  expect(actual.g, closeTo(wash.g, 1e-6));
  expect(actual.b, closeTo(wash.b, 1e-6));
  if (reduced) {
    expect(actual, wash);
  } else {
    expect(actual.a, inExclusiveRange(0.0, wash.a));
  }
}

Future<void> _checkPointerFade(
  WidgetTester tester,
  TestGesture mouse,
  Finder scope,
  PremiumThemeExtension palette, {
  required bool reduced,
}) async {
  final wash = palette.subtleHover;
  final rect = tester.getRect(scope);
  final glyphFinder =
      find.descendant(of: scope, matching: find.byType(FlowySvg));
  final glyphRects = [
    for (var i = 0; i < glyphFinder.evaluate().length; i++)
      tester.getRect(glyphFinder.at(i)),
  ];
  final ink = _glyphs(tester, scope).map((glyph) => glyph.color).toList();
  expect(ink, isNotEmpty);
  expect(_fill(tester, scope), wash.withValues(alpha: 0));
  _checkMotion(tester, scope, reduced: reduced);

  await mouse.moveTo(tester.getCenter(scope));
  await tester.pump();
  await tester.pump(_halfFade);
  _checkMidpoint(_fill(tester, scope), wash, reduced: reduced);
  expect(tester.getRect(scope), rect);
  expect(
    _glyphs(tester, scope).map((glyph) => glyph.color),
    orderedEquals(ink),
  );
  for (var i = 0; i < glyphRects.length; i++) {
    expect(tester.getRect(glyphFinder.at(i)), glyphRects[i]);
  }
  await tester.pump(_finishFade);
  expect(_fill(tester, scope), wash);
  expect(
    Color.alphaBlend(_fill(tester, scope), palette.floatingSurface),
    palette.hoverOn(palette.floatingSurface),
  );
  await mouse.moveTo(_outside);
  await tester.pump();
  await tester.pump(_settle);
  expect(_fill(tester, scope), wash.withValues(alpha: 0));
  expect(tester.getRect(scope), rect);
}

Future<BuildContext> _mount(
  WidgetTester tester,
  String mode,
  String motion,
  WidgetBuilder builder,
) async {
  final app = mode == 'paper'
      ? AppTheme.builtins
          .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
      : AppTheme.fallback;
  final theme = DesktopAppearance()
      .getThemeData(
        app,
        mode == 'dark' ? Brightness.dark : Brightness.light,
        'Ahem',
        builtInCodeFontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
  late BuildContext sample;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      // Above the Navigator so native popover overlays inherit both motion flags.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: motion == 'disabled',
          accessibleNavigation: motion == 'accessible',
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(32),
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
  );
  await tester.pump();
  return sample;
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(
    LogicalKeyboardKey.escape,
    physicalKey: PhysicalKeyboardKey.escape,
  );
  await tester.pump();
  await tester.pump(_settle);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(_settle);
}
