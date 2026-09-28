import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_controls.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_controls.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_theme.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/mind_map/mind_map_canvas.dart';
import 'package:appflowy/shared/mind_map/mind_map_controller.dart';
import 'package:appflowy/shared/mind_map/mind_map_model.dart';
import 'package:appflowy/shared/mind_map/mind_map_theme.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart'
    show settleVividIconPictures, vividIconTestTheme;

const _appearances = ['light', 'dark', 'paper'];
const _styleCycle = [
  DefaultIconStyle.monochrome,
  DefaultIconStyle.vivid,
  DefaultIconStyle.monochrome,
];
const _chosenInk = Color(0xFFE0A400);
const _inheritedInk = Color(0xFF8F4779);
const _repoIdentities = [
  (Icons.balance_rounded, 'scales'),
  (Icons.commit_rounded, 'commit'),
  (Icons.data_array_rounded, 'brackets'),
];
const _emailIdentities = [
  (Icons.file_download_outlined, 'download'),
  (Icons.segment_rounded, 'rows'),
  (Icons.view_headline_rounded, 'rows'),
  (Icons.all_inbox_rounded, 'inboxes'),
];

void main() {
  setUp(WorkspaceGlyphs.clearUnknownMappings);

  for (final appearance in _appearances) {
    testWidgets('$appearance map/table buttons keep native focus and hit areas',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final semantics = tester.ensureSemantics();
      final calls = <String>[];
      late MapPalette map;
      late TableViewPalette table;
      var builds = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) {
                builds++;
                map = mapPaletteOf(context);
                table = tableViewPaletteOf(context);
                return Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MapControlButton(
                      key: const ValueKey('map'),
                      icon: Icons.zoom_in_rounded,
                      tooltip: 'Zoom in',
                      palette: map,
                      selected: true,
                      onPressed: () => calls.add('map'),
                    ),
                    MapControlButton(
                      key: const ValueKey('map-disabled'),
                      icon: Icons.zoom_out_rounded,
                      tooltip: 'Zoom out',
                      palette: map,
                    ),
                    TableViewButton(
                      key: const ValueKey('table'),
                      icon: Icons.filter_alt_rounded,
                      tooltip: 'Filter',
                      palette: table,
                      active: true,
                      onTap: () => calls.add('table'),
                    ),
                    TableViewAction(
                      key: const ValueKey('table-action'),
                      label: 'Add row',
                      icon: Icons.add_rounded,
                      palette: table,
                      onTap: () => calls.add('add'),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        _expectAppearance(tester, appearance);
        final mapButton = _native(_key('map'), IconButton);
        final disabled = _native(_key('map-disabled'), IconButton);
        final tableButton = _native(_key('table'), IconButton);
        final controls = [
          mapButton,
          disabled,
          tableButton,
          _key('table-action')
        ];
        final elements = controls.map(tester.element).toList();
        final bounds = controls.map(tester.getRect).toList();
        final actionState = tester.state(_key('table-action'));
        final hostBuilds = builds;
        await _focusWithTab(tester, mapButton);
        final focus = FocusManager.instance.primaryFocus;

        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, _key('map'), 'zoom-in', style,
              size: 17.5, ink: map.accent);
          _expectGlyph(tester, _key('map-disabled'), 'zoom-out', style,
              size: 17.5,
              ink: map.textMuted.withValues(alpha: 0.5),
              preserveInk: true);
          _expectGlyph(tester, _key('table'), 'filter', style,
              size: 17, ink: table.accent);
          _expectGlyph(tester, _key('table-action'), 'plus', style,
              size: 15, ink: table.accent);
          for (var i = 0; i < controls.length; i++) {
            expect(tester.element(controls[i]), same(elements[i]));
            expect(tester.getRect(controls[i]), bounds[i]);
          }
          expect(tester.getSize(_key('map')), const Size.square(34));
          expect(tester.getSize(_key('table')), const Size.square(34));
          expect(tester.state(_key('table-action')), same(actionState));
          expect(builds, hostBuilds);
          expect(FocusManager.instance.primaryFocus, same(focus));
          expect(_data(tester, mapButton).hasFlag(ui.SemanticsFlag.isFocused),
              isTrue);
          _expectNativeButton(tester, mapButton, enabled: true);
          _expectNativeButton(tester, disabled, enabled: false);
          _expectNativeButton(tester, tableButton, enabled: true);
          expect(_data(tester, mapButton).tooltip, 'Zoom in');
          expect(_data(tester, disabled).tooltip, 'Zoom out');
          expect(_data(tester, tableButton).tooltip, 'Filter');
          expect(tester.widget<IconButton>(mapButton).isSelected, isTrue);
          expect(tester.widget<IconButton>(tableButton).isSelected, isTrue);
          expect(tester.widget<IconButton>(disabled).onPressed, isNull);
          expect(map.isPaper, appearance == 'paper');
          expect(table.isPaper, appearance == 'paper');
          expect(calls, isEmpty);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.space,
            physicalKey: PhysicalKeyboardKey.space);
        await tester.pump();
        await tester.tap(disabled);
        await tester.tap(tableButton);
        await tester.tap(_key('table-action'));
        await tester.pump();
        expect(calls, ['map', 'table', 'add']);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        styles.dispose();
      }
    });

    testWidgets('$appearance map search retains draft, selection and callbacks',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final changes = <String>[];
      final submissions = <String>[];
      late MapPalette palette;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            StatefulBuilder(
              builder: (context, setState) {
                palette = mapPaletteOf(context);
                return AppMapSearchField(
                  key: const ValueKey('map-search'),
                  palette: palette,
                  // No place picker means no geocoder or network startup.
                  onSubmitted: submissions.add,
                  onChanged: (value) {
                    changes.add(value);
                    setState(() {});
                  },
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        _expectAppearance(tester, appearance);
        final search = find.byType(TextField);
        await tester.enterText(search, 'Oxford');
        await tester.pump();
        final editableFinder = find.byType(EditableText);
        final editable = tester.widget<EditableText>(editableFinder);
        const selection = TextSelection(baseOffset: 1, extentOffset: 4);
        editable.controller.selection = selection;
        await tester.pump();
        final state = tester.state(editableFinder);
        final rect = tester.getRect(search);
        final clear = _glyph(_key('map-search'), 'x');
        final clearElement = tester.element(clear);

        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, _key('map-search'), 'magnifying-glass', style,
              size: 16, ink: palette.textMuted);
          _expectGlyph(tester, _key('map-search'), 'x', style,
              size: 15, ink: palette.textMuted);
          expect(tester.state(editableFinder), same(state));
          expect(tester.element(clear), same(clearElement));
          expect(tester.getRect(search), rect);
          expect(editable.controller.text, 'Oxford');
          expect(editable.controller.selection, selection);
          expect(editable.focusNode.hasFocus, isTrue);
          expect(changes, ['Oxford']);
          expect(submissions, isEmpty);
        }
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(submissions, ['Oxford']);
        expect(clear.hitTestable(), findsOneWidget);
        await tester.tap(clear);
        await tester.pump();
        expect(changes, ['Oxford', '']);
        expect(submissions, ['Oxford', '']);
        expect(editable.controller.text, isEmpty);
        expect(tester.state(editableFinder), same(state));
        expect(clear, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance image controls keep named geometry and transforms',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final busy = ValueNotifier(false);
      final calls = <String>[];
      late ImageEditorPalette palette;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) {
                palette = ImageEditorPalette.of(context);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ImageEditorIconButton(
                      key: const ValueKey('actual'),
                      icon: Icons.crop_free_rounded,
                      tooltip: 'Actual size',
                      palette: palette,
                      dimension: 28,
                      iconSize: 16,
                      onPressed: () => calls.add('actual'),
                    ),
                    ImageEditorIconButton(
                      key: const ValueKey('fit'),
                      icon: Icons.fit_screen_rounded,
                      tooltip: 'Fit to screen',
                      palette: palette,
                      dimension: 28,
                      iconSize: 16,
                      onPressed: () => calls.add('fit'),
                    ),
                    ImageEditorIconButton(
                      key: const ValueKey('rotate'),
                      icon: Icons.rotate_90_degrees_ccw_rounded,
                      tooltip: 'Rotate left',
                      palette: palette,
                      onPressed: () => calls.add('rotate'),
                    ),
                    // The image page rotates this entire control for vertical
                    // flipping. The shared glyph migration must not undo it.
                    Transform.rotate(
                      key: const ValueKey('flip-transform'),
                      angle: math.pi / 2,
                      child: ImageEditorIconButton(
                        key: const ValueKey('flip'),
                        icon: Icons.flip_rounded,
                        tooltip: 'Flip vertically',
                        palette: palette,
                        dimension: 36,
                        iconSize: 19,
                        isActive: true,
                        onPressed: () => calls.add('flip'),
                      ),
                    ),
                    ImageEditorIconButton(
                      key: const ValueKey('image-disabled'),
                      icon: Icons.crop_free_rounded,
                      tooltip: 'Actual size unavailable',
                      palette: palette,
                    ),
                    ImageEditorTextButton(
                      key: const ValueKey('text-disabled'),
                      label: 'Export unavailable',
                      icon: Icons.ios_share_rounded,
                      palette: palette,
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: busy,
                      builder: (_, value, __) => ImageEditorTextButton(
                        key: const ValueKey('export'),
                        label: 'Export',
                        icon: Icons.ios_share_rounded,
                        palette: palette,
                        filled: true,
                        busy: value,
                        onPressed: () => calls.add('export'),
                      ),
                    ),
                    ImageEditorChip(
                      key: const ValueKey('crop-chip'),
                      label: 'Crop',
                      icon: Icons.crop_rounded,
                      selected: true,
                      palette: palette,
                      onPressed: () => calls.add('chip'),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        _expectAppearance(tester, appearance);
        const keys = [
          'actual',
          'fit',
          'rotate',
          'flip',
          'image-disabled',
          'text-disabled',
          'export',
          'crop-chip',
        ];
        final states = {for (final key in keys) key: tester.state(_key(key))};
        final bounds = {for (final key in keys) key: tester.getRect(_key(key))};
        final transform = tester.widget<Transform>(_key('flip-transform'));
        final matrix = List<double>.of(transform.transform.storage);
        final tooltip = tester.widget<Tooltip>(
          find.descendant(of: _key('actual'), matching: find.byType(Tooltip)),
        );
        expect(tooltip.message, 'Actual size');
        expect(tooltip.waitDuration, const Duration(milliseconds: 400));

        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, _key('actual'), 'actual-size', style,
              size: 16, ink: palette.textSecondary);
          _expectGlyph(tester, _key('fit'), 'fit-page', style,
              size: 16, ink: palette.textSecondary);
          _expectGlyph(tester, _key('rotate'), 'rotate-ccw', style,
              size: 18, ink: palette.textSecondary);
          _expectGlyph(tester, _key('flip'), 'flip-horizontal', style,
              size: 19, ink: palette.textPrimary);
          _expectGlyph(tester, _key('image-disabled'), 'actual-size', style,
              size: 18, ink: palette.textMuted, preserveInk: true);
          _expectGlyph(tester, _key('text-disabled'), 'share', style,
              size: 15, ink: palette.textMuted, preserveInk: true);
          _expectGlyph(tester, _key('export'), 'share', style,
              size: 15, ink: palette.onAccent);
          _expectGlyph(tester, _key('crop-chip'), 'crop', style,
              size: 15, ink: palette.textPrimary);
          for (final key in keys) {
            expect(tester.state(_key(key)), same(states[key]));
            expect(tester.getRect(_key(key)), bounds[key]);
          }
          expect(tester.getSize(_key('actual')), const Size.square(28));
          expect(tester.getSize(_key('flip')), const Size.square(36));
          expect(tester.getSize(_key('crop-chip')).height, 30);
          expect(tester.getSize(_key('export')).height, 32);
          expect(
              tester
                  .widget<Transform>(_key('flip-transform'))
                  .transform
                  .storage,
              matrix);
          expect(tester.widget<Transform>(_key('flip-transform')).alignment,
              Alignment.center);
          expect(calls, isEmpty);
        }
        for (final key in [
          'actual',
          'fit',
          'rotate',
          'flip',
          'export',
          'crop-chip'
        ]) {
          expect(_key(key).hitTestable(), findsOneWidget);
          await tester.tap(_key(key));
        }
        await tester.tap(_key('image-disabled'));
        await tester.tap(_key('text-disabled'));
        await tester.pump();
        expect(calls, ['actual', 'fit', 'rotate', 'flip', 'export', 'chip']);
        busy.value = true;
        await tester.pump();
        final indicator = find.descendant(
          of: _key('export'),
          matching: find.byType(CircularProgressIndicator),
        );
        expect(indicator, findsOneWidget);
        expect(_glyph(_key('export'), 'share'), findsNothing);
        expect(
            tester
                .widget<CircularProgressIndicator>(indicator)
                .valueColor!
                .value,
            palette.textMuted);
        await tester.tap(_key('export'));
        await tester.pump();
        expect(calls, ['actual', 'fit', 'rotate', 'flip', 'export', 'chip']);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        busy.dispose();
        styles.dispose();
      }
    });

    testWidgets('$appearance collection aliases retain meanings and state ink',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final semantics = tester.ensureSemantics();
      final calls = <String>[];
      late BookReaderPalette book;
      late RepoTheme repo;
      late EmailTheme email;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) {
                book = BookReaderPalette.of(context, BookReaderTheme.workspace);
                repo = RepoTheme.of(context,
                    CollectionPalette.of(context, CollectionKind.repository));
                email = emailThemeOf(context);
                return SizedBox(
                  width: 620,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      BookControlButton(
                        key: const ValueKey('book'),
                        icon: Icons.remove_done_rounded,
                        tooltip: 'Mark unfinished',
                        palette: book,
                        selected: true,
                        onPressed: () => calls.add('book'),
                      ),
                      BookControlButton(
                        key: const ValueKey('book-disabled'),
                        icon: Icons.remove_done_rounded,
                        tooltip: 'Mark unfinished unavailable',
                        palette: book,
                      ),
                      for (final (icon, name) in _repoIdentities)
                        RepoGlyphIcon(
                          key: ValueKey('repo-$name'),
                          glyph: RepoGlyph(icon, repo.iconRest),
                        ),
                      const RepoGlyphIcon(
                        key: ValueKey('repo-muted'),
                        glyph: RepoGlyph(Icons.commit_rounded, Colors.blue),
                        muted: _chosenInk,
                      ),
                      RepoAction(
                        key: const ValueKey('repo-action'),
                        theme: repo,
                        icon: Icons.segment_rounded,
                        trailingIcon: Icons.expand_more_rounded,
                        tooltip: 'Group repository',
                        onPressed: () => calls.add('repo'),
                      ),
                      RepoAction(
                        key: const ValueKey('repo-disabled'),
                        theme: repo,
                        icon: Icons.segment_rounded,
                        trailingIcon: Icons.expand_more_rounded,
                        tooltip: 'Group repository unavailable',
                      ),
                      for (var i = 0; i < _emailIdentities.length; i++)
                        EmailAction(
                          key: ValueKey('email-$i'),
                          icon: _emailIdentities[i].$1,
                          tooltip: 'Email action $i',
                          theme: email,
                          active: i == 3,
                          onPressed: () => calls.add('email-$i'),
                        ),
                      EmailAction(
                        key: const ValueKey('email-disabled'),
                        icon: Icons.all_inbox_rounded,
                        tooltip: 'All inboxes unavailable',
                        theme: email,
                      ),
                      EmailAction(
                        key: const ValueKey('email-tint'),
                        icon: Icons.star_rounded,
                        tooltip: 'Starred',
                        theme: email,
                        tint: _chosenInk,
                        onPressed: () => calls.add('star'),
                      ),
                      EmailChip(
                        key: const ValueKey('status'),
                        label: 'Reading mail',
                        icon: Icons.hourglass_empty_rounded,
                        theme: email,
                      ),
                      EmailChip(
                        key: const ValueKey('status-tone'),
                        label: 'Syncing',
                        icon: Icons.sync_rounded,
                        theme: email,
                        tone: _chosenInk,
                      ),
                      EmailChip(
                        key: const ValueKey('chip-action'),
                        label: 'Download',
                        icon: Icons.file_download_outlined,
                        theme: email,
                        onTap: () => calls.add('chip'),
                      ),
                      EmailChip(
                        key: const ValueKey('chip-tone'),
                        label: 'Chosen label color',
                        icon: Icons.label_rounded,
                        theme: email,
                        tone: _chosenInk,
                        onTap: () => calls.add('tone'),
                      ),
                      WorkspaceGlyphScope(
                        color: _inheritedInk,
                        role: WorkspaceGlyphRole.preserveInk,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BookControlButton(
                              key: const ValueKey('book-scoped'),
                              icon: Icons.remove_done_rounded,
                              tooltip: 'Scoped book',
                              palette: book,
                              onPressed: () {},
                            ),
                            RepoAction(
                              key: const ValueKey('repo-scoped'),
                              theme: repo,
                              icon: Icons.segment_rounded,
                              tooltip: 'Scoped repository',
                              onPressed: () {},
                            ),
                            EmailAction(
                              key: const ValueKey('email-scoped'),
                              icon: Icons.all_inbox_rounded,
                              tooltip: 'Scoped email',
                              theme: email,
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        _expectAppearance(tester, appearance);
        final nativeButtons = find.byType(TextButton);
        final elements = nativeButtons.evaluate().toList();
        final bounds = elements
            .map((element) => tester.getRect(find.byWidget(element.widget)))
            .toList();
        final bookButton = _native(_key('book'), TextButton);
        await _focusWithTab(tester, bookButton);
        final focus = FocusManager.instance.primaryFocus;

        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, _key('book'), 'check-off', style,
              size: 16, ink: book.inkMuted);
          expect(
              tester
                  .widget<WorkspaceGlyph>(_glyph(_key('book'), 'check-off'))
                  .icon,
              Icons.remove_done_rounded);
          _expectGlyph(tester, _key('book-disabled'), 'check-off', style,
              size: 16,
              ink: book.inkMuted.withValues(alpha: 0.45),
              preserveInk: true);
          for (final (icon, name) in _repoIdentities) {
            final parent = _key('repo-$name');
            _expectGlyph(tester, parent, name, style,
                size: 15,
                ink: workspaceGlyphInk(tester.element(parent)),
                slot: const Size(RepoMetrics.iconSlot, RepoMetrics.iconSize));
            expect(
                tester.widget<WorkspaceGlyph>(_glyph(parent, name)).icon, icon);
          }
          _expectGlyph(tester, _key('repo-muted'), 'commit', style,
              size: 15,
              ink: _chosenInk,
              preserveInk: true,
              slot: const Size(RepoMetrics.iconSlot, RepoMetrics.iconSize));
          for (final (key, disabled) in [
            ('repo-action', false),
            ('repo-disabled', true)
          ]) {
            final ink = repo.textSoft.withValues(alpha: disabled ? 0.45 : 1);
            _expectGlyph(tester, _key(key), 'rows', style,
                size: 16, ink: ink, preserveInk: disabled);
            _expectGlyph(tester, _key(key), 'caret-down', style,
                size: 14, ink: ink, preserveInk: disabled);
            expect(
                tester.widget<WorkspaceGlyph>(_glyph(_key(key), 'rows')).icon,
                Icons.segment_rounded);
          }
          for (var i = 0; i < _emailIdentities.length; i++) {
            final (icon, name) = _emailIdentities[i];
            final parent = _key('email-$i');
            _expectGlyph(tester, parent, name, style,
                size: 16, ink: email.textSoft);
            expect(
                tester.widget<WorkspaceGlyph>(_glyph(parent, name)).icon, icon);
          }
          _expectGlyph(tester, _key('email-disabled'), 'inboxes', style,
              size: 16,
              ink: email.textSoft.withValues(alpha: 0.45),
              preserveInk: true);
          _expectGlyph(tester, _key('email-tint'), 'star', style,
              size: 16, ink: _chosenInk, preserveInk: true);
          _expectGlyph(tester, _key('status'), 'hourglass', style,
              size: 11, ink: email.textSoft, preserveInk: true);
          _expectGlyph(tester, _key('status-tone'), 'refresh', style,
              size: 11, ink: _chosenInk, preserveInk: true);
          _expectGlyph(tester, _key('chip-action'), 'download', style,
              size: 11, ink: email.textSoft);
          _expectGlyph(tester, _key('chip-tone'), 'tag', style,
              size: 11, ink: _chosenInk, preserveInk: true);
          for (final (key, name) in [
            ('book-scoped', 'check-off'),
            ('repo-scoped', 'rows'),
            ('email-scoped', 'inboxes'),
          ]) {
            _expectGlyph(tester, _key(key), name, style,
                size: 16, ink: _inheritedInk, preserveInk: true);
          }
          expect(nativeButtons.evaluate().toList(), elements);
          for (var i = 0; i < elements.length; i++) {
            expect(
                tester.getRect(find.byWidget(elements[i].widget)), bounds[i]);
          }
          expect(FocusManager.instance.primaryFocus, same(focus));
          expect(_data(tester, bookButton).label, 'Mark unfinished');
          expect(_data(tester, bookButton).hasFlag(ui.SemanticsFlag.isSelected),
              isTrue);
          expect(_data(tester, bookButton).hasFlag(ui.SemanticsFlag.isFocused),
              isTrue);
          for (final key in [
            'book-disabled',
            'repo-disabled',
            'email-disabled'
          ]) {
            final button = _native(_key(key), TextButton);
            _expectNativeButton(tester, button, enabled: false);
            expect(tester.widget<TextButton>(button).onPressed, isNull);
            await tester.tap(button);
          }
          expect(calls, isEmpty);
        }
        for (final key in [
          'book',
          'repo-action',
          'email-3',
          'email-tint',
          'chip-action',
          'chip-tone'
        ]) {
          await tester.tap(_key(key));
        }
        await tester.pump();
        expect(calls, ['book', 'repo', 'email-3', 'star', 'chip', 'tone']);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        styles.dispose();
      }
    });

    testWidgets(
        '$appearance mind-map fit, delete and color controls retain roles',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final transform = ValueNotifier(Matrix4.identity()..scale(1.5));
      const document = MindMapDocument(
        root: MindMapNode(id: 'root', text: 'Root', children: [
          MindMapNode(id: 'branch', text: 'Branch', colorIndex: 2, children: [
            MindMapNode(id: 'leaf', text: 'Leaf'),
          ]),
        ]),
      );
      final controller = MindMapController(document: document);
      final calls = <String>[];
      late MindMapPalette palette;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) {
                palette = MindMapPalette.of(context);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MindMapViewportControls(
                      key: const ValueKey('viewport'),
                      palette: palette,
                      scale: 1.5,
                      transform: transform,
                      onZoomIn: () {
                        calls.add('in');
                        transform.value = Matrix4.identity()..scale(2.0);
                      },
                      onZoomOut: () => calls.add('out'),
                      onFit: () => calls.add('fit'),
                      onCentre: () => calls.add('centre'),
                      onReset: () => calls.add('reset'),
                      onFullscreen: () => calls.add('fullscreen'),
                    ),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (_, __) {
                        final node = controller.document.find('branch') ??
                            controller.document.root;
                        return MindMapNodeToolbar(
                          key: const ValueKey('node-toolbar'),
                          controller: controller,
                          palette: palette,
                          node: node,
                          isRoot: node.id == 'root',
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        _expectAppearance(tester, appearance);
        final fit = find.byTooltip('Fit to screen');
        final fitElement = tester.element(fit);
        final fitBounds = tester.getRect(fit);
        final original = controller.document.toJson();
        final originalMatrix = List<double>.of(transform.value.storage);
        final chosenSwatch = find.descendant(
          of: _key('node-toolbar'),
          matching: find.byWidgetPredicate((widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 13 &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  palette.branchAt(2)),
        );
        expect(chosenSwatch, findsOneWidget);
        final swatchElement = tester.element(chosenSwatch);

        for (final style in _styleCycle) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, _key('viewport'), 'fit-page', style,
              size: 15, ink: palette.textMuted);
          _expectGlyph(tester, _key('viewport'), 'target', style,
              size: 15, ink: palette.textMuted);
          _expectGlyph(tester, _key('viewport'), 'fullscreen', style,
              size: 15, ink: palette.textMuted);
          _expectGlyph(tester, _key('node-toolbar'), 'pen', style,
              size: 15, ink: palette.textMuted);
          _expectGlyph(tester, _key('node-toolbar'), 'trash', style,
              size: 15,
              ink: palette.isDark
                  ? const Color(0xFFE58B8B)
                  : const Color(0xFFC0554F),
              preserveInk: true);
          expect(tester.element(fit), same(fitElement));
          expect(tester.getRect(fit), fitBounds);
          expect(fitBounds.size, const Size.square(26));
          expect(tester.element(chosenSwatch), same(swatchElement));
          expect(controller.document.toJson(), original);
          expect(transform.value.storage, originalMatrix);
          expect(find.text('150%'), findsOneWidget);
          expect(calls, isEmpty);
        }
        for (final tooltip in [
          'Zoom in',
          'Zoom out',
          'Centre',
          'Fit to screen',
          'Fullscreen'
        ]) {
          await tester.tap(find.byTooltip(tooltip));
        }
        await tester.pump();
        expect(find.text('200%'), findsOneWidget);
        await tester.tap(find.text('200%'));
        expect(calls, ['in', 'out', 'centre', 'fit', 'fullscreen', 'reset']);
        await tester.tap(find.byTooltip('Rename  ·  F2'));
        expect(controller.editingId, 'branch');
        controller.endEditing();
        await tester.tap(find.byTooltip('Add child  ·  Tab'));
        expect(controller.document.nodeCount, document.nodeCount + 1);
        expect(
            controller.document.parentOf(controller.editingId!)!.id, 'branch');
        controller.endEditing();
        await tester.pump();
        await tester.tap(find.byTooltip('Colour'));
        await settleVividIconPictures(tester);
        styles.value = DefaultIconStyle.vivid;
        await settleVividIconPictures(tester);
        final swatches = find.byType(PopupMenuItem<int>);
        _expectGlyph(tester, swatches, 'paint-off', DefaultIconStyle.vivid,
            size: 11, ink: palette.textMuted, preserveInk: true);
        await tester.tap(_glyph(swatches, 'paint-off'));
        await tester.pumpAndSettle();
        expect(controller.document.find('branch')!.colorIndex, isNull);
        await tester.tap(find.byTooltip('Delete  ·  Del'));
        await tester.pump();
        expect(controller.document.find('branch'), isNull);
        expect(controller.document.nodeCount, 1);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        transform.dispose();
        styles.dispose();
      }
    });
  }
}

Widget _app(String appearance, ValueNotifier<DefaultIconStyle> styles,
        Widget child) =>
    MaterialApp(
      theme: vividIconTestTheme(appearance),
      themeAnimationDuration: Duration.zero,
      home: DefaultIconStyleScope(
        styles: styles,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void _expectAppearance(WidgetTester tester, String appearance) {
  final context = tester.element(find.byType(Scaffold));
  expect(PaperTheme.isEnabled(context), appearance == 'paper');
  expect(Theme.of(context).brightness,
      appearance == 'dark' ? Brightness.dark : Brightness.light);
}

Finder _key(String name) => find.byKey(ValueKey(name));

Finder _native(Finder parent, Type type) =>
    find.descendant(of: parent, matching: find.byType(type));

Finder _glyph(Finder parent, String name) => find.descendant(
      of: parent,
      matching: find.byWidgetPredicate(
          (widget) => widget is WorkspaceGlyph && widget.name == name),
    );

SemanticsData _data(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  expect(node.attached, isTrue);
  return node.getSemanticsData();
}

void _expectNativeButton(WidgetTester tester, Finder button,
    {required bool enabled}) {
  expect(button, findsOneWidget);
  final data = _data(tester, button);
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.hasEnabledState), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(data.hasAction(ui.SemanticsAction.tap), enabled);
}

Future<void> _focusWithTab(WidgetTester tester, Finder button) async {
  for (var i = 0;
      i < 8 && !_data(tester, button).hasFlag(ui.SemanticsFlag.isFocused);
      i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab,
        physicalKey: PhysicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_data(tester, button).hasFlag(ui.SemanticsFlag.isFocused), isTrue);
}

void _expectGlyph(
  WidgetTester tester,
  Finder parent,
  String name,
  DefaultIconStyle style, {
  required double size,
  required Color ink,
  bool preserveInk = false,
  Size? slot,
}) {
  final finder = _glyph(parent, name);
  expect(finder, findsOneWidget, reason: 'The real control must expose $name.');
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  final context = tester.element(finder);
  final scope = WorkspaceGlyphScope.maybeOf(context);
  expect(
      glyph.role == WorkspaceGlyphRole.preserveInk ||
          scope?.role == WorkspaceGlyphRole.preserveInk,
      preserveInk);
  expect(glyph.size, size);
  expect(tester.getSize(finder), slot ?? Size.square(size));
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: finder, matching: find.byType(SvgPicture)),
  );
  final vivid = style == DefaultIconStyle.vivid && !preserveInk;
  final source = vivid
      ? vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!
      : defaultIconSvg(name)!;
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
      loader,
      SvgStringLoader(source,
          theme: loader.theme, colorMapper: loader.colorMapper));
  expect(picture.colorFilter,
      vivid ? null : ColorFilter.mode(ink, BlendMode.srcIn));
  expect(picture.width, size);
  expect(picture.height, size);
  expect(picture.excludeFromSemantics, isTrue);
  expect(
      find.descendant(of: finder, matching: find.byType(Icon)), findsNothing);
}
