import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/shared/document_viewer/document_viewport.dart';
import 'package:appflowy/shared/document_viewer/document_viewport_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _outside = Offset(790, 590);
const _settle = Duration(milliseconds: 180);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final mode in ['light', 'dark', 'paper']) {
    for (final reduced in [false, true]) {
      testWidgets(
          '$mode/reduced=$reduced: chrome matches and hover keeps geometry, ink and draft',
          (tester) async {
        final controller = TextEditingController(text: 'Keep this draft');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _outside);
          final context =
              await _mount(tester, mode, reduced: reduced, builder: (context) {
            final sidebar = SidebarPalette.of(context);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WindowTitleBar(
                  key: ValueKey('caption'),
                  showCaptionButtons: false,
                  height: 40,
                ),
                ColoredBox(
                  key: const ValueKey('sidebar-surface'),
                  color: SidebarStyle.background(context),
                  child: SizedBox(
                    width: 320,
                    child: SidebarRow(
                      key: const ValueKey('row'),
                      icon: Icon(Icons.folder_outlined,
                          key: const ValueKey('row-icon'), color: sidebar.icon),
                      label: Text('Open entry',
                          key: const ValueKey('row-label'),
                          style: TextStyle(color: sidebar.textPrimary)),
                      onTap: () {},
                      trailingSlots: 1,
                      trailingBuilder: (_) => [
                        const SizedBox.square(
                            dimension: 24, child: Icon(Icons.more_horiz))
                      ],
                    ),
                  ),
                ),
                TextField(
                  key: const ValueKey('draft'),
                  controller: controller,
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ],
            );
          });
          final palette = PremiumThemeExtension.of(context);
          final sidebar = SidebarPalette.of(context);
          final caption = tester.widget<ColoredBox>(
            find
                .descendant(
                    of: _key('caption'), matching: find.byType(ColoredBox))
                .first,
          );
          expect(caption.color, sidebar.background);
          expect(caption.color, WorkspacePalette.of(context).chrome);
          expect(tester.widget<ColoredBox>(_key('sidebar-surface')).color,
              caption.color);
          expect(caption.color,
              mode == 'paper' ? PaperTheme.chromeBackground : palette.sidebar);

          final rowRect = tester.getRect(_key('row'));
          final labelRect = tester.getRect(_key('row-label'));
          final iconRect = tester.getRect(_key('row-icon'));
          final iconInk = tester.widget<Icon>(_key('row-icon')).color;
          final field =
              tester.state<EditableTextState>(find.byType(EditableText));
          final idle = _fill(tester, _key('row'));
          expect(idle, palette.subtleHover.withValues(alpha: 0));

          await mouse.moveTo(tester.getCenter(_key('row')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          final mid = _fill(tester, _key('row'));
          expect(
              mid.a,
              reduced
                  ? closeTo(sidebar.hover.a, 1e-6)
                  : inExclusiveRange(0.0, sidebar.hover.a));
          _sameRgb(mid, sidebar.hover);
          expect(tester.getRect(_key('row')), rowRect);
          expect(tester.getRect(_key('row-label')), labelRect);
          expect(tester.getRect(_key('row-icon')), iconRect);
          expect(tester.widget<Icon>(_key('row-icon')).color, iconInk);
          expect(
              find.descendant(
                  of: _key('row'), matching: find.byType(SlideTransition)),
              findsNothing);

          await tester.pump(_settle);
          expect(_fill(tester, _key('row')), sidebar.hover);
          final painted = Color.alphaBlend(sidebar.hover, sidebar.background);
          expect(_difference(painted, sidebar.background),
              inExclusiveRange(0.003, 0.055));
          expect(
              _contrast(sidebar.textPrimary, painted), greaterThanOrEqualTo(7));
          for (final animation in tester.widgetList<AnimatedContainer>(
            find.descendant(
                of: _key('row'), matching: find.byType(AnimatedContainer)),
          )) {
            expect(animation.duration,
                reduced ? Duration.zero : WorkspaceTokens.hoverDuration);
            expect(animation.curve, WorkspaceTokens.curve);
          }

          await mouse.moveTo(_outside);
          await tester.pump();
          await tester.pump(_settle);
          expect(_fill(tester, _key('row')), idle);
          expect(controller.text, 'Keep this draft');
          expect(tester.state<EditableTextState>(find.byType(EditableText)),
              same(field));
          await tester.tap(_key('draft'));
          await tester.pump();
          final decoration = tester
              .widget<InputDecorator>(find.byType(InputDecorator))
              .decoration;
          expect(decoration.border, InputBorder.none);
          expect(decoration.enabledBorder, isNull);
          expect(decoration.focusedBorder, isNull);
          expect(decoration.filled, isNot(true));
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await _unmount(tester);
          controller.dispose();
        }
      });

      testWidgets(
          '$mode/reduced=$reduced: selected native controls keep keyboard focus and activation',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final calls = <String, int>{};
        void activate(String name) =>
            calls.update(name, (count) => count + 1, ifAbsent: () => 1);
        try {
          final context = await _mount(tester, mode,
              reduced: reduced,
              builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SidebarRow(
                          key: const ValueKey('row'),
                          label: const Text('Open entry'),
                          selected: true,
                          onTap: () => activate('row')),
                      DocumentViewportButton(
                          key: const ValueKey('document'),
                          icon: Icons.refresh,
                          tooltip: 'Document action',
                          selected: true,
                          onPressed: () => activate('document')),
                      WorkspaceControlButton(
                        key: const ValueKey('shared'),
                        icon: Icons.check,
                        tooltip: 'Shared action',
                        selected: true,
                        onPressed: () => activate('shared'),
                      ),
                      CollectionWorkspaceAction(
                          key: const ValueKey('collection'),
                          icon: Icons.check,
                          tooltip: 'Collection action',
                          label: 'Collection action',
                          selected: true,
                          onPressed: () => activate('collection')),
                      DocumentViewportFitButton(
                        key: const ValueKey('fit'),
                        onPressed: () => activate('fit'),
                      ),
                      const DocumentViewportButton(
                        key: ValueKey('document-disabled'),
                        icon: Icons.refresh,
                        tooltip: 'Unavailable document action',
                        onPressed: null,
                      ),
                      const CollectionWorkspaceAction(
                          key: ValueKey('disabled'),
                          icon: Icons.close,
                          tooltip: 'Unavailable'),
                      AFGhostButton.normal(
                          key: const ValueKey('ghost'),
                          onTap: () => activate('ghost'),
                          builder: (_, __, ___) => const Text('Ghost action')),
                      CollectionWorkspaceAction(
                          key: const ValueKey('danger'),
                          icon: Icons.delete_rounded,
                          tooltip: 'Delete',
                          color: Theme.of(context).colorScheme.error,
                          onPressed: () => activate('danger')),
                    ],
                  ));
          final palette = PremiumThemeExtension.of(context);
          final document = DocumentViewportStyle.of(context);
          final sidebar = SidebarPalette.of(context);
          expect(_fill(tester, _key('row')), sidebar.selected);
          expect(document.controlHover, palette.subtleHover);
          expect(document.chrome, document.canvas);
          expect(_fill(tester, _key('document')), document.controlActive);
          final documentSelected =
              Color.alphaBlend(document.controlActive, document.canvas);
          expect(
            _difference(documentSelected, document.canvas),
            greaterThan(
              _difference(palette.hoverOn(document.canvas), document.canvas) *
                  1.5,
            ),
          );
          expect(_contrast(document.accent, documentSelected),
              greaterThanOrEqualTo(3));

          for (final name in ['shared', 'collection']) {
            final style = _button(tester, name).style!;
            final selected = style.backgroundColor!.resolve({})!;
            final hovered =
                style.backgroundColor!.resolve({WidgetState.hovered})!;
            final pressed =
                style.backgroundColor!.resolve({WidgetState.pressed})!;
            expect(selected, palette.selectedOverlay);
            expect(hovered, Color.alphaBlend(palette.subtleHover, selected));
            expect(pressed, Color.alphaBlend(palette.subtlePressed, selected));
            expect(style.overlayColor!.resolve({WidgetState.hovered})!.a, 0);
            expect(style.animationDuration,
                reduced ? Duration.zero : WorkspaceTokens.hoverDuration);
            expect(
              _difference(
                  Color.alphaBlend(selected, palette.canvas), palette.canvas),
              greaterThan(
                  _difference(palette.hoverOn(palette.canvas), palette.canvas) *
                      1.5),
            );
          }

          final disabled = _button(tester, 'disabled');
          expect(disabled.onPressed, isNull);
          expect(
              disabled.style!.backgroundColor!
                  .resolve({WidgetState.disabled, WidgetState.hovered})!.a,
              0);
          expect(
            tester
                .widget<DocumentViewportButton>(_key('document-disabled'))
                .onPressed,
            isNull,
          );
          expect(_fill(tester, _key('document-disabled')), document.control);
          final disabledSemantics = _buttonSemantics('document-disabled');
          expect(disabledSemantics, findsOneWidget);
          final disabledNode = tester.getSemantics(disabledSemantics);
          expect(disabledNode.attached, isTrue);
          expect(disabledNode.getSemanticsData().label,
              'Unavailable document action');
          expect(
            disabledNode.getSemanticsData().hasFlag(ui.SemanticsFlag.isEnabled),
            isFalse,
          );
          expect(
              disabledNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse);
          final danger = _button(tester, 'danger').style!;
          expect(danger.foregroundColor!.resolve({WidgetState.hovered}),
              Theme.of(context).colorScheme.error);
          expect(danger.foregroundColor!.resolve({}),
              danger.foregroundColor!.resolve({WidgetState.hovered}));

          // Tab skips both disabled controls. Inspect the actual button
          // boundary: a keyed outer Tooltip can return the route's semantics.
          // Activation is real key dispatch, never a direct callback call.
          for (final entry in const {
            'row': 'Open entry',
            'document': 'Document action',
            'shared': 'Shared action',
            'collection': 'Collection action',
            'fit': 'Fit',
            'ghost': 'Ghost action',
          }.entries) {
            final name = entry.key;
            final rect = tester.getRect(_key(name));
            await tester.sendKeyEvent(LogicalKeyboardKey.tab,
                physicalKey: PhysicalKeyboardKey.tab);
            await tester.pump();
            await tester.pump(_settle);
            final target = _buttonSemantics(name);
            expect(target, findsOneWidget, reason: name);
            final node = tester.getSemantics(target);
            expect(node.attached, isTrue, reason: name);
            final data = node.getSemanticsData();
            expect(data.label, entry.value, reason: name);
            expect(
              data.hasFlag(ui.SemanticsFlag.isFocused),
              isTrue,
              reason: '$name; primary=${FocusManager.instance.primaryFocus}; '
                  '${node.toStringDeep()}',
            );
            expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue,
                reason: name);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue,
                reason: name);
            if (name != 'ghost' && name != 'fit') {
              expect(data.hasFlag(ui.SemanticsFlag.isSelected), isTrue,
                  reason: name);
            }
            if (name == 'row') {
              final decoration = tester
                  .widget<AnimatedContainer>(
                    find
                        .descendant(
                            of: _key(name),
                            matching: find.byType(AnimatedContainer))
                        .first,
                  )
                  .foregroundDecoration! as BoxDecoration;
              expect(decoration.border!.top.color, palette.accent);
            } else if (name == 'document') {
              final container = tester.widget<AnimatedContainer>(
                find.descendant(
                  of: _key(name),
                  matching: find.byType(AnimatedContainer),
                ),
              );
              final decoration = container.decoration! as BoxDecoration;
              expect(decoration.border!.top.color, document.accent);
              expect(decoration.border!.top.color.a, 1);
              expect(_fill(tester, _key(name)), document.controlActive);
              expect(container.duration,
                  reduced ? Duration.zero : WorkspaceTokens.hoverDuration);
            } else if (name == 'ghost') {
              final decoration = tester
                  .widget<AnimatedContainer>(
                    find
                        .descendant(
                            of: _key(name),
                            matching: find.byType(AnimatedContainer))
                        .first,
                  )
                  .decoration! as BoxDecoration;
              expect(decoration.border!.top.color, palette.accent);
            } else {
              expect(
                  _button(tester, name)
                      .style!
                      .side!
                      .resolve({WidgetState.focused})!.color,
                  palette.accent);
            }
            expect(
                _contrast(palette.accent, palette.selectedOn(palette.canvas)),
                greaterThanOrEqualTo(3));
            await tester.sendKeyEvent(LogicalKeyboardKey.enter,
                physicalKey: PhysicalKeyboardKey.enter);
            await tester.sendKeyEvent(LogicalKeyboardKey.space,
                physicalKey: PhysicalKeyboardKey.space);
            await tester.pump();
            await tester.pump(_settle);
            expect(calls[name], 2, reason: name);
            expect(tester.getRect(_key(name)), rect);
          }
          expect(calls['danger'], isNull);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await _unmount(tester);
        }
      });

      testWidgets(
          '$mode/reduced=$reduced: legacy aliases, explicit surfaces and AF fades retain alpha and ink',
          (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _outside);
          final context =
              await _mount(tester, mode, reduced: reduced, builder: (context) {
            final palette = PremiumThemeExtension.of(context);
            final legacy = AFThemeExtension.of(context);
            Widget row(String name, Color color,
                    {bool selected = false, Color? background}) =>
                FlowyHover(
                  key: ValueKey(name),
                  resetHoverOnRebuild: false,
                  isSelected: () => selected,
                  style: HoverStyle(
                      hoverColor: color,
                      backgroundColor: background ?? Colors.transparent),
                  child: SizedBox(
                    height: 32,
                    child: Builder(
                        builder: (context) => Row(children: [
                              Icon(Icons.folder_outlined,
                                  key: ValueKey('$name-icon')),
                              Text(name,
                                  key: ValueKey('$name-label'),
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ])),
                  ),
                );
            return Theme(
              data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.copyWith(
                        bodyMedium: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(color: palette.textSecondary),
                      )),
              child: IconTheme(
                data: IconThemeData(color: palette.accent),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    row('grey', legacy.greyHover),
                    row('light-grey', legacy.lightGreyHover),
                    row('toolbar', legacy.toolbarHoverColor),
                    row('selected', legacy.greyHover, selected: true),
                    row('custom', const Color(0x084B83A4)),
                    row('surface', const Color(0x084B83A4),
                        background: palette.mutedSurface),
                    AFGhostButton.normal(
                        key: const ValueKey('af'),
                        onTap: () {},
                        builder: (_, __, ___) => const Text('AF ghost')),
                  ],
                ),
              ),
            );
          });
          final palette = PremiumThemeExtension.of(context);
          final legacy = AFThemeExtension.of(context);
          final hover = palette.subtleHover;
          expect(legacy.greyHover.a, 1,
              reason: 'Mixed editor surface roles stay opaque.');
          expect(legacy.lightGreyHover.a, 1);
          expect(_fill(tester, _key('selected')), legacy.greyHover);

          for (final name in [
            'grey',
            'light-grey',
            'toolbar',
            'custom',
            'surface',
            'af'
          ]) {
            final wash = name == 'custom' || name == 'surface'
                ? const Color(0x084B83A4)
                : hover;
            final rest = name == 'surface'
                ? palette.mutedSurface
                : wash.withValues(alpha: 0);
            final target =
                name == 'surface' ? Color.alphaBlend(wash, rest) : wash;
            expect(_fill(tester, _key(name)), rest);
            final rect = tester.getRect(_key(name));
            final labelRect =
                name == 'af' ? null : tester.getRect(_key('$name-label'));
            if (name != 'af') {
              expect(IconTheme.of(tester.element(_key('$name-icon'))).color,
                  palette.accent);
              expect(tester.widget<Text>(_key('$name-label')).style!.color,
                  palette.textSecondary);
            }
            await mouse.moveTo(tester.getCenter(_key(name)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 70));
            final mid = _fill(tester, _key(name));
            if (name == 'surface') {
              expect(mid.a, 1);
              expect(_difference(rest, mid),
                  lessThanOrEqualTo(_difference(rest, target) + 1e-6));
            } else {
              expect(mid.a, inInclusiveRange(0.0, wash.a));
              _sameRgb(mid, wash);
            }
            if (reduced) expect(mid, target);
            await tester.pump(_settle);
            expect(_fill(tester, _key(name)), target);
            expect(tester.getRect(_key(name)), rect);
            if (name != 'af') {
              expect(tester.getRect(_key('$name-label')), labelRect);
              expect(IconTheme.of(tester.element(_key('$name-icon'))).color,
                  palette.accent);
              expect(tester.widget<Text>(_key('$name-label')).style!.color,
                  palette.textSecondary);
            }
            for (final animation in tester.widgetList<AnimatedContainer>(
              find.descendant(
                  of: _key(name), matching: find.byType(AnimatedContainer)),
            )) {
              expect(animation.duration.inMilliseconds,
                  reduced ? 0 : inInclusiveRange(120, 180));
            }
            await mouse.moveTo(_outside);
            await tester.pump();
            await tester.pump(_settle);
            expect(_fill(tester, _key(name)), rest);
          }
          await mouse.moveTo(tester.getCenter(_key('selected')));
          await tester.pump();
          await tester.pump(_settle);
          expect(_fill(tester, _key('selected')), legacy.greyHover);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await _unmount(tester);
        }
      });

      testWidgets(
          '$mode/reduced=$reduced: live viewport and Fit hover once on their surface without a lift',
          (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _outside);
          final context = await _mount(tester, mode,
              reduced: reduced,
              builder: (context) => ColoredBox(
                    key: const ValueKey('control-surface'),
                    color: PremiumThemeExtension.of(context).mutedSurface,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DocumentViewportButton(
                          key: const ValueKey('viewport'),
                          icon: Icons.refresh,
                          tooltip: 'Refresh document',
                          onPressed: () {},
                        ),
                        DocumentViewportFitButton(
                          key: const ValueKey('fit'),
                          onPressed: () {},
                        ),
                        const DocumentViewportFitButton(
                          key: ValueKey('fit-disabled'),
                          onPressed: null,
                        ),
                      ],
                    ),
                  ));
          final palette = PremiumThemeExtension.of(context);
          final document = DocumentViewportStyle.of(context);
          final surface =
              tester.widget<ColoredBox>(_key('control-surface')).color;
          final style = _button(tester, 'fit').style!;
          final rest = palette.subtleHover.withValues(alpha: 0);
          expect(style.backgroundColor!.resolve({}), rest);
          expect(style.backgroundColor!.resolve({WidgetState.hovered}),
              document.controlHover);
          expect(style.backgroundColor!.resolve({WidgetState.pressed}),
              palette.subtlePressed);
          expect(style.overlayColor!.resolve({WidgetState.hovered})!.a, 0);
          expect(style.foregroundColor!.resolve({WidgetState.hovered}),
              style.foregroundColor!.resolve({}));
          expect(style.iconColor!.resolve({WidgetState.hovered}),
              style.iconColor!.resolve({}));
          expect(style.animationDuration,
              reduced ? Duration.zero : WorkspaceTokens.hoverDuration);

          for (final name in ['viewport', 'fit']) {
            Color fill() => name == 'viewport'
                ? _fill(tester, _key(name))
                : _nativeFill(tester, name);
            final control = _key(name);
            final rect = tester.getRect(control);
            final glyph = find.descendant(
              of: control,
              matching: find.byType(WorkspaceGlyph),
            );
            final ink = tester.widget<WorkspaceGlyph>(glyph).color;
            final glyphRect = tester.getRect(glyph);
            expect(fill(), rest);
            await mouse.moveTo(tester.getCenter(control));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 70));
            final mid = fill();
            // AnimatedContainer fades the viewport wash; TextButton retains
            // Flutter's native color/shape policy, rather than a second fade.
            expect(
              mid.a,
              name == 'viewport' && !reduced
                  ? inExclusiveRange(0.0, document.controlHover.a)
                  : inInclusiveRange(0.0, document.controlHover.a),
            );
            _sameRgb(mid, document.controlHover);
            if (reduced) expect(mid, document.controlHover);
            expect(tester.getRect(control), rect);
            expect(tester.getRect(glyph), glyphRect);
            expect(tester.widget<WorkspaceGlyph>(glyph).color, ink);
            await tester.pump(_settle);
            expect(fill(), document.controlHover);
            final painted = Color.alphaBlend(fill(), surface);
            expect(painted, palette.hoverOn(surface));
            expect(
                _difference(painted, surface), inExclusiveRange(0.003, 0.055));
            expect(
                _contrast(document.icon, painted), greaterThanOrEqualTo(4.5));
            expect(tester.getRect(control), rect);
            await mouse.moveTo(_outside);
            await tester.pump();
            await tester.pump(_settle);
            expect(fill(), rest);
          }
          final disabled = _button(tester, 'fit-disabled');
          expect(disabled.onPressed, isNull);
          expect(
              disabled.style!.foregroundColor!.resolve({WidgetState.disabled}),
              document.iconMuted);
          await mouse.moveTo(tester.getCenter(_key('fit-disabled')));
          await tester.pump();
          await tester.pump(_settle);
          expect(_nativeFill(tester, 'fit-disabled'), rest);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await _unmount(tester);
        }
      });
    }

    testWidgets(
        '$mode: custom aliases and live control scopes keep their alpha and selection',
        (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      const customWash = Color(0x04675443);
      const customSelected = Color(0xFFDABF92);
      try {
        await mouse.addPointer(location: _outside);
        await _mount(tester, mode, builder: (context) {
          final inherited = Theme.of(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Theme(
                data: inherited.copyWith(extensions: [
                  ...inherited.extensions.values,
                  AFThemeExtension.of(context).copyWith(greyHover: customWash),
                ]),
                child: const FlowyHover(
                  key: ValueKey('custom-alias'),
                  style: HoverStyle(hoverColor: customWash),
                  child: SizedBox(
                      width: 160, height: 32, child: Text('Custom wash')),
                ),
              ),
              Theme(
                data: inherited.copyWith(extensions: [
                  ...inherited.extensions.values,
                  PremiumThemeExtension.of(context).copyWith(
                    hoverOverlay: customWash,
                    selectedOverlay: customSelected,
                  ),
                ]),
                child: WorkspaceControlButton(
                  key: const ValueKey('custom-shared'),
                  icon: Icons.check,
                  tooltip: 'Custom selected',
                  selected: true,
                  onPressed: () {},
                ),
              ),
            ],
          );
        });
        expect(_fill(tester, _key('custom-alias')),
            customWash.withValues(alpha: 0));
        await mouse.moveTo(tester.getCenter(_key('custom-alias')));
        await tester.pump();
        await tester.pump(_settle);
        expect(_fill(tester, _key('custom-alias')), customWash);
        final style = _button(tester, 'custom-shared').style!;
        final wash = customWash.withValues(alpha: customWash.a * 0.65);
        expect(style.backgroundColor!.resolve({}), customSelected);
        expect(style.backgroundColor!.resolve({WidgetState.hovered}),
            Color.alphaBlend(wash, customSelected));
        expect(style.overlayColor!.resolve({WidgetState.hovered})!.a, 0);
        expect(_nativeFill(tester, 'custom-shared'), customSelected);
        await mouse.moveTo(tester.getCenter(_key('custom-shared')));
        await tester.pump();
        await tester.pump(_settle);
        expect(_nativeFill(tester, 'custom-shared'),
            Color.alphaBlend(wash, customSelected));
        expect(
            _difference(_nativeFill(tester, 'custom-shared'), customSelected),
            lessThan(0.055));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _unmount(tester);
      }
    });

    testWidgets('$mode: accessible navigation disables shared hover motion too',
        (tester) async {
      try {
        final context = await _mount(tester, mode,
            accessible: true,
            builder: (_) => Column(children: [
                  SidebarRow(
                      key: const ValueKey('row'),
                      label: const Text('Entry'),
                      onTap: () {}),
                  DocumentViewportButton(
                      key: const ValueKey('document'),
                      icon: Icons.refresh,
                      tooltip: 'Refresh',
                      onPressed: () {}),
                  DocumentViewportFitButton(
                    key: const ValueKey('fit'),
                    onPressed: () {},
                  ),
                  const FlowyHover(child: Text('Legacy control')),
                  AFGhostButton.normal(
                      onTap: () {},
                      builder: (_, __, ___) => const Text('AF control')),
                ]));
        expect(WorkspaceChrome.controlStyle(context).animationDuration,
            Duration.zero);
        expect(_button(tester, 'fit').style!.animationDuration, Duration.zero);
        for (final animation in tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))) {
          expect(animation.duration, Duration.zero);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });

    testWidgets(
        '$mode: page canvas overrides cannot split caption/sidebar colors',
        (tester) async {
      try {
        late Color canvas;
        late Color chrome;
        late Color sidebar;
        final context = await _mount(tester, mode,
            builder: (_) => EditorCanvasScope(
                  color: const Color(0xFF734D39),
                  child: Builder(builder: (context) {
                    canvas = EditorSurfaceStyle.canvasBackground(context);
                    chrome = EditorSurfaceStyle.chromeBackground(context);
                    sidebar = SidebarStyle.background(context);
                    return const WindowTitleBar(showCaptionButtons: false);
                  }),
                ));
        expect(canvas, const Color(0xFF734D39));
        expect(chrome, PremiumThemeExtension.of(context).sidebar);
        expect(sidebar, chrome);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));

Finder _buttonSemantics(String name) => find.descendant(
      of: _key(name),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    );

TextButton _button(WidgetTester tester, String name) =>
    tester.widget<TextButton>(
      find.descendant(of: _key(name), matching: find.byType(TextButton)),
    );

Color _nativeFill(WidgetTester tester, String name) => tester
    .widget<PhysicalShape>(
      find.descendant(of: _key(name), matching: find.byType(PhysicalShape)),
    )
    .color;

Color _fill(WidgetTester tester, Finder scope) => tester
    .widgetList<DecoratedBox>(
      find.descendant(of: scope, matching: find.byType(DecoratedBox)),
    )
    .map((widget) => widget.decoration)
    .whereType<BoxDecoration>()
    .map((decoration) => decoration.color)
    .whereType<Color>()
    .first;

void _sameRgb(Color a, Color b) {
  expect(a.r, closeTo(b.r, 1e-6));
  expect(a.g, closeTo(b.g, 1e-6));
  expect(a.b, closeTo(b.b, 1e-6));
}

double _difference(Color a, Color b) =>
    math.max((a.r - b.r).abs(), math.max((a.g - b.g).abs(), (a.b - b.b).abs()));

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

Future<BuildContext> _mount(
  WidgetTester tester,
  String mode, {
  required WidgetBuilder builder,
  bool reduced = false,
  bool accessible = false,
}) async {
  final app = mode == 'paper'
      ? AppTheme.builtins
          .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
      : AppTheme.fallback;
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance()
      .getThemeData(app, brightness, 'Ahem', builtInCodeFontFamily)
      .copyWith(platform: TargetPlatform.windows);
  final defaults = AppFlowyDefaultTheme();
  late BuildContext sample;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    themeAnimationDuration: Duration.zero,
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
          accessibleNavigation: accessible),
      child: AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
            base: mode == 'dark' ? defaults.dark() : defaults.light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: brightness),
        child: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: 640,
                    child: Builder(builder: (context) {
                      sample = context;
                      return builder(context);
                    })))),
      ),
    ),
  ));
  await tester.pump();
  return sample;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(_settle);
}
