import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_entry_viewer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;

const _copyKey = ValueKey('media-copy');
const _shareKey = ValueKey('media-share');
const _referenceKey = ValueKey('shared-control-reference');
const _fade = Duration(milliseconds: 140);
const _finishFade = Duration(milliseconds: 141);
const _fileKinds = <(String?, String)>[
  ('report.PDF', 'file-pdf'),
  ('report.docx', 'file-doc'),
  ('budget.XLSX', 'file-xls'),
  ('slides.pptx', 'file-ppt'),
  ('bundle.tar.gz', 'file-zip'),
  ('source.py', 'file-code'),
  ('data.csv', 'file-csv'),
  ('README.md', 'file-markdown'),
  ('index.html', 'file-html'),
  ('records.json', 'file-json'),
  ('analysis.ipynb', 'file-notebook'),
  ('notes.txt', 'file-text'),
  ('song.mp3', 'music-note'),
  ('clip.mp4', 'film-strip'),
  ('image.png', 'image'),
  ('unknown.extension', 'file'),
  (null, 'file'),
];

void main() {
  fileControlTestSetup();

  for (final mode in fileControlAppearances) {
    for (final reduced in [false, true]) {
      testWidgets(
        '$mode/reduced=$reduced: media controls share native workspace chrome',
        (tester) async {
          final styles = ValueNotifier(DefaultIconStyle.monochrome);
          final actions = _Actions();
          final semantics = tester.ensureSemantics();
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: const Offset(1080, 880));
            await _mount(
              tester,
              styles,
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buttons(actions),
                    const SizedBox(width: 8),
                    WorkspaceControlButton(
                      key: _referenceKey,
                      icon: Icons.copy_rounded,
                      tooltip: 'Reference control',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              mode: mode,
              reduced: reduced,
            );
            final reference = tester.widget<TextButton>(
              find.descendant(
                of: find.byKey(_referenceKey),
                matching: find.byType(TextButton),
              ),
            );
            final state = tester.state(find.byType(MediaActionButtons));
            final element = tester.element(find.byKey(_copyKey));
            final bounds = tester.getRect(find.byKey(_copyKey));
            final context = tester.element(find.byKey(_copyKey));
            final shared = WorkspaceChrome.controlStyle(context);
            expect(
              reference.style!.shape!.resolve({}),
              shared.shape!.resolve({}),
            );
            for (final key in [_copyKey, _shareKey]) {
              final style = _button(tester, key).style!;
              expect(tester.getSize(find.byKey(key)), const Size.square(28));
              expect(style.minimumSize!.resolve({}), const Size.square(28));
              expect(style.maximumSize!.resolve({}), const Size.square(28));
              expect(style.padding!.resolve({}), EdgeInsets.zero);
              expect(
                style.shape!.resolve({}),
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              );
              expect(
                style.shape!.resolve({}),
                reference.style!.shape!.resolve({}),
              );
              expect(style.splashFactory, NoSplash.splashFactory);
              expect(style.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
              expect(style.animationDuration, shared.animationDuration);
              for (final states in <Set<WidgetState>>[
                {},
                {WidgetState.hovered},
                {WidgetState.focused},
                {WidgetState.pressed},
                {WidgetState.hovered, WidgetState.focused},
                {WidgetState.disabled, WidgetState.hovered},
                {WidgetState.disabled, WidgetState.focused},
              ]) {
                expect(
                  style.backgroundColor!.resolve(states),
                  reference.style!.backgroundColor!.resolve(states),
                );
                expect(
                  style.side!.resolve(states),
                  shared.side!.resolve(states),
                );
                expect(
                  style.overlayColor!.resolve(states),
                  shared.overlayColor!.resolve(states),
                );
              }
              _expectNativeSemantics(tester, key);
            }
            if (mode == 'paper') {
              final decoration = tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('media-action-surface')),
                  )
                  .decoration as BoxDecoration;
              expect(PaperTheme.isEnabled(context), isTrue);
              expect(decoration.color, PaperTheme.popupBackground);
              expect(decoration.color, isNot(Colors.white));
            }

            // Resolve the shared style through the actual native hover/focus
            // paths, not just through a synthetic set of WidgetStates.
            await mouse.moveTo(tester.getCenter(find.byKey(_copyKey)));
            await _settleNativeStyle(tester, shared);
            expect(
              _buttonMaterial(tester, _copyKey).color,
              shared.backgroundColor!.resolve({WidgetState.hovered}),
            );
            await mouse.moveTo(const Offset(1080, 880));
            _button(tester, _copyKey).focusNode!.requestFocus();
            await _settleNativeStyle(tester, shared);
            expect(
              _buttonMaterial(tester, _copyKey).color,
              shared.backgroundColor!.resolve({WidgetState.focused}),
            );
            for (final style in DefaultIconStyle.values) {
              styles.value = style;
              await tester.pump();
              _expectArtwork(
                tester,
                _glyphIn(find.byKey(_copyKey)),
                'copy',
                style,
              );
              _expectArtwork(
                tester,
                _glyphIn(find.byKey(_shareKey)),
                'share',
                style,
              );
              expect(tester.element(find.byKey(_copyKey)), same(element));
              expect(tester.getRect(find.byKey(_copyKey)), bounds);
              expect(_button(tester, _copyKey).focusNode!.hasFocus, isTrue);
            }
            expect(tester.state(find.byType(MediaActionButtons)), same(state));
            expect(
              find.descendant(
                of: find.byType(MediaActionButtons),
                matching: find.byType(Icon),
              ),
              findsNothing,
            );
            expect(actions.calls, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await _unmount(tester);
            semantics.dispose();
            styles.dispose();
          }
        },
      );
    }

    for (final onDarkSurface in [false, true]) {
      testWidgets(
        '$mode/onDark=$onDarkSurface: status ink, native role, focus and deadline survive style changes',
        (tester) async {
          final styles = ValueNotifier(DefaultIconStyle.vivid);
          final actions = _Actions();
          final semantics = tester.ensureSemantics();
          try {
            await _mount(
              tester,
              styles,
              Center(child: _buttons(actions, onDarkSurface: onDarkSurface)),
              mode: mode,
              reduced: true,
            );
            final button = _button(tester, _copyKey);
            final focus = button.focusNode!;
            final element = tester.element(find.byKey(_copyKey));
            final context = tester.element(find.byKey(_copyKey));
            final palette = PremiumThemeExtension.of(context);
            final ink = onDarkSurface ? Colors.white : palette.textSecondary;
            final success = onDarkSurface ? Colors.white : palette.accent;
            final error = onDarkSurface
                ? Colors.white
                : Theme.of(context).colorScheme.error;
            final side = onDarkSurface ? 32.0 : 28.0;
            expect(tester.getSize(find.byKey(_copyKey)), Size.square(side));
            expect(button.style!.animationDuration, Duration.zero);
            if (onDarkSurface) {
              expect(
                button.style!.shape!.resolve({}),
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              );
              expect(
                button.style!.side!.resolve({WidgetState.focused})!.color,
                Colors.white,
              );
              expect(
                button.style!.backgroundColor!.resolve({WidgetState.hovered}),
                Colors.white.withValues(alpha: 0.1),
              );
              expect(
                button.style!.backgroundColor!.resolve({WidgetState.pressed}),
                Colors.white.withValues(alpha: 0.12),
              );
              for (final key in [_copyKey, _shareKey]) {
                _expectArtwork(
                  tester,
                  _glyphIn(find.byKey(key)),
                  key == _copyKey ? 'copy' : 'share',
                  styles.value,
                  ink: Colors.white,
                  preserveInk: true,
                );
              }
            }
            focus.requestFocus();
            await tester.pump();
            await tester.pump();
            final staleCopy = button.onPressed!;
            final staleShare = _button(tester, _shareKey).onPressed!;
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(
              actions.calls,
              hasLength(1),
              reason: 'Native Enter activates Copy',
            );
            staleCopy();
            staleShare();
            expect(actions.calls, hasLength(1));
            expect(actions.calls.single.action, 'copy');
            for (final key in [_copyKey, _shareKey]) {
              expect(_button(tester, key).onPressed, isNull);
              _expectNativeSemantics(tester, key, enabled: false);
            }
            final progress = tester.widget<CircularProgressIndicator>(
              find.descendant(
                of: find.byKey(const ValueKey('media-copy-progress')),
                matching: find.byType(CircularProgressIndicator),
              ),
            );
            expect(progress.value, 0.65);
            expect(progress.color, ink.withValues(alpha: 0.65));
            for (final style in DefaultIconStyle.values) {
              styles.value = style;
              await tester.pump();
              _expectArtwork(
                tester,
                _glyphIn(find.byKey(_shareKey)),
                'share',
                style,
                ink: ink.withValues(alpha: 0.4),
                preserveInk: true,
              );
            }
            final deadline = tester.binding.clock.now().add(
                  const Duration(milliseconds: 1600),
                );
            actions.calls.single.completion.complete();
            await tester.pump();
            await tester.pump();
            expect(_button(tester, _copyKey).tooltip, 'Copied');
            _expectNativeSemantics(tester, _copyKey, liveRegion: true);
            _expectArtwork(
              tester,
              _glyphIn(find.byKey(_copyKey)),
              'check',
              styles.value,
              ink: success,
              preserveInk: true,
            );
            expect(focus.hasFocus, isTrue);
            expect(tester.element(find.byKey(_copyKey)), same(element));
            styles.value = DefaultIconStyle.monochrome;
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 1599));
            expect(_button(tester, _copyKey).tooltip, 'Copied');
            await tester.pump(const Duration(milliseconds: 1));
            expect(tester.binding.clock.now(), deadline);
            expect(_button(tester, _copyKey).tooltip, 'Copy');
            _expectNativeSemantics(tester, _copyKey);

            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            await tester.pump();
            expect(_button(tester, _shareKey).focusNode!.hasFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pump();
            expect(actions.calls.last.action, 'share');
            expect(
              actions.calls.last.origin,
              tester.getRect(find.byKey(_shareKey)),
            );
            actions.calls.last.completion.completeError(
              StateError('private-fixture-error-not-for-display'),
            );
            await tester.pump();
            await tester.pump();
            styles.value = DefaultIconStyle.vivid;
            await tester.pump();
            _expectNativeSemantics(tester, _shareKey, liveRegion: true);
            _expectArtwork(
              tester,
              _glyphIn(find.byKey(_shareKey)),
              'warning',
              styles.value,
              ink: error,
              preserveInk: true,
            );
            expect(
              _button(tester, _shareKey).tooltip,
              isNot(contains('private-fixture')),
            );
            expect(find.byKey(const ValueKey('media-copied')), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await _unmount(tester);
            actions.completePending();
            await tester.pump();
            semantics.dispose();
            styles.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets('$mode: hidden media keeps hover and native Tab reveal',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final actions = _Actions();
      final before = FocusNode();
      final semantics = tester.ensureSemantics();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(1080, 880));
        await _mount(
          tester,
          styles,
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  autofocus: true,
                  focusNode: before,
                  onPressed: () {},
                  child: const Text('Before'),
                ),
                MediaHoverRegion(
                  builder: (context, visible) => SizedBox(
                    key: const ValueKey('media-hover-host'),
                    width: 180,
                    height: 100,
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: MediaActionReveal(
                          visible: visible,
                          child: _buttons(actions),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          mode: mode,
          reduced: true,
        );
        final state = tester.state(find.byType(MediaActionButtons));
        expect(before.hasFocus, isTrue);
        expect(find.byKey(_copyKey).hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('media-hover-host'))),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
        _expectNativeSemantics(tester, _copyKey);
        await mouse.moveTo(const Offset(1080, 880));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(_copyKey).hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        styles.value = DefaultIconStyle.vivid;
        await tester.pump();
        expect(find.semantics.byLabel('Copy'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        expect(_button(tester, _copyKey).focusNode!.hasFocus, isTrue);
        expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
        _expectNativeSemantics(tester, _copyKey);
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        expect(actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _unmount(tester);
        before.dispose();
        semantics.dispose();
        styles.dispose();
      }
    });

    testWidgets(
        '$mode: file identity uses classified monochrome and vivid artwork',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      try {
        await _mount(
          tester,
          styles,
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _fileKinds.length; i++)
                  FileIdentityGlyph(
                    key: ValueKey('file-identity-$i'),
                    icon: EmojiIconData.none(),
                    name: _fileKinds[i].$1,
                  ),
              ],
            ),
          ),
          mode: mode,
        );
        final elements = [
          for (var i = 0; i < _fileKinds.length; i++)
            tester.element(find.byKey(ValueKey('file-identity-$i'))),
        ];
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (var i = 0; i < _fileKinds.length; i++) {
            final identity = find.byKey(ValueKey('file-identity-$i'));
            expect(tester.element(identity), same(elements[i]));
            _expectArtwork(tester, _glyphIn(identity), _fileKinds[i].$2, style);
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        styles.dispose();
      }
    });

    testWidgets(
        '$mode: explicit emoji, library and upload identities bypass defaults',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final choices = [
        EmojiIconData.emoji('📚'),
        IconsData('appflowy_default_collections', 'book', '4283665274')
            .toEmojiIconData(),
        IconsData('appflowy_vivid_essentials', 'rocket', null)
            .toEmojiIconData(),
        IconsData('phosphor_bold_office', 'book', '4283665274')
            .toEmojiIconData(),
        EmojiIconData.custom(r'C:\synthetic-fixture\chosen.svg'),
        EmojiIconData.custom('https://example.invalid/chosen.png'),
      ];
      final snapshots = [
        for (final choice in choices) choice.toViewIcon().writeToBuffer(),
      ];
      try {
        await _mount(
          tester,
          styles,
          const SizedBox(key: ValueKey('identity-context')),
          mode: mode,
        );
        final context =
            tester.element(find.byKey(const ValueKey('identity-context')));
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await tester.pump();
          for (var i = 0; i < choices.length; i++) {
            // Inspect the real fallback decision without fetching or decoding
            // a chosen upload; that renderer is explicitly outside this change.
            final rendered = FileIdentityGlyph(
              icon: choices[i],
              name: 'must-not-replace-the-choice.xlsx',
              size: 24,
              color: Colors.red,
            ).build(context);
            expect(rendered, isA<RawEmojiIconWidget>());
            final chosen = rendered as RawEmojiIconWidget;
            expect(chosen.emoji, same(choices[i]));
            expect(chosen.emojiSize, 24);
            expect(choices[i].toViewIcon().writeToBuffer(), snapshots[i]);
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        styles.dispose();
      }
    });

    for (final name in ['records.json', 'payload.unknown']) {
      testWidgets(
          '$mode/$name: archive entry identity and fallback use file artwork',
          (tester) async {
        final styles = ValueNotifier(DefaultIconStyle.monochrome);
        final file = MemoryCodeFile('{"value":1}', path: '/fixture/$name');
        final glyphName = name.endsWith('.json') ? 'file-json' : 'file';
        var closes = 0;
        try {
          await _mount(
            tester,
            styles,
            ArchiveEntryViewer(
              file: file,
              name: name,
              path: 'folder/$name',
              archiveName: 'bundle.zip',
              editable: false,
              metadata: const {},
              onMetadataChanged: (_) {},
              onClose: () => closes++,
            ),
            mode: mode,
          );
          final entry = tester.element(find.byType(ArchiveEntryViewer));
          for (final style in DefaultIconStyle.values) {
            styles.value = style;
            await settleVividIconPictures(tester);
            _expectArtwork(tester, _fileGlyph(glyphName, 16), glyphName, style);
            if (glyphName == 'file') {
              _expectArtwork(tester, _fileGlyph('file', 34), 'file', style);
              expect(
                find.text('AppFlowy has no viewer for this file type yet.'),
                findsOneWidget,
              );
            }
            expect(
              tester.element(find.byType(ArchiveEntryViewer)),
              same(entry),
            );
          }
          expect(file.reads, glyphName == 'file' ? 0 : 1);
          expect(file.writes, 0);
          expect(closes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
          styles.dispose();
        }
      });
    }

    testWidgets(
        '$mode: empty archive header and fallback keep natural default ink',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final search = TextEditingController();
      final focus = FocusNode();
      try {
        await _mount(
          tester,
          styles,
          ArchiveGallery(
            entries: const [],
            previewCache: FolderGalleryPreviewCache(),
            selectedPath: null,
            renamingPath: null,
            editable: false,
            onSelect: (_) {},
            onOpen: (_) {},
            onRenameRequested: (_) {},
            onRenameSubmitted: (_, __) async => false,
            onRenameCancelled: () {},
            onMore: (_, __) {},
            header: ArchiveGalleryHeader(
              title: 'bundle.zip',
              breadcrumbs: const [''],
              rootLabel: 'bundle.zip',
              subtitle: 'Empty archive',
              searchController: search,
              searchFocusNode: focus,
              searching: false,
              onSearchChanged: (_) {},
              onSearchDismissed: () {},
              onSearchRequested: () {},
              onNavigate: (_) {},
              editable: false,
              busy: false,
              onAddFiles: () {},
              onNewFolder: () {},
              onRefresh: () {},
            ),
          ),
          mode: mode,
        );
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (final size in [20.0, 28.0]) {
            final glyph = _fileGlyph('file-zip', size);
            expect(tester.widget<WorkspaceGlyph>(glyph).color, isNull);
            _expectArtwork(tester, glyph, 'file-zip', style);
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        search.dispose();
        focus.dispose();
        styles.dispose();
      }
    });

    testWidgets(
        '$mode: archive unpacking progress uses the entry file classification',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('shared-file-action-style-'),
      ))!;
      try {
        final bytes = utf8.encode('{"value":1}');
        final archive = (await tester.runAsync(
          () => File('${temporary.path}/bundle.zip').writeAsBytes(
            ZipEncoder().encode(
              Archive()
                ..addFile(ArchiveFile('records.json', bytes.length, bytes)),
            )!,
          ),
        ))!;
        await _mount(
          tester,
          styles,
          ArchiveExplorer(
            file: archive,
            name: 'bundle.zip',
            editable: false,
            embedded: false,
          ),
          mode: mode,
        );
        await _drainArchiveIO(
          tester,
          () =>
              find.byType(ArchiveGallery).evaluate().isNotEmpty &&
              tester
                      .widget<ArchiveGallery>(find.byType(ArchiveGallery))
                      .entries
                      .length ==
                  1,
        );
        final gallery =
            tester.widget<ArchiveGallery>(find.byType(ArchiveGallery));
        // Activate the real gallery callback, then pause real IO while checking
        // its intermediate stage. No private State or extraction seam is used.
        gallery.onOpen(gallery.entries.single);
        await tester.pump();
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(ArchiveEntryViewer), findsNothing);
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await tester.pump();
          _expectArtwork(
            tester,
            _fileGlyph('file-json', 26),
            'file-json',
            style,
          );
        }
        await _drainArchiveIO(
          tester,
          () => find.byType(SelectableText).evaluate().isNotEmpty,
        );
        expect(find.byType(ArchiveEntryViewer), findsOneWidget);
        _expectArtwork(
          tester,
          _fileGlyph('file-json', 16),
          'file-json',
          styles.value,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        await tester.runAsync(() => temporary.delete(recursive: true));
        styles.dispose();
      }
    });
  }

  testWidgets(
      'accessible navigation keeps intrinsic 2x media controls visible and still',
      (tester) async {
    final styles = ValueNotifier(DefaultIconStyle.vivid);
    final actions = _Actions();
    final semantics = tester.ensureSemantics();
    try {
      await _mount(
        tester,
        styles,
        Center(
          child: SizedBox(
            width: 60,
            child: IntrinsicHeight(
              child: MediaActionReveal(
                visible: false,
                child: MediaActionButtons(
                  source: _source(),
                  actions: actions,
                  decorated: false,
                ),
              ),
            ),
          ),
        ),
        mode: 'paper',
        accessible: true,
        textScale: 2,
      );
      final reveal = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('media-action-reveal')),
      );
      expect(reveal.opacity, 1);
      expect(reveal.duration, Duration.zero);
      expect(
        tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
        Duration.zero,
      );
      expect(
        tester.getSize(find.byType(MediaActionButtons)),
        const Size(60, 28),
      );
      final bounds = tester.getRect(find.byType(MediaActionButtons));
      for (final key in [_copyKey, _shareKey]) {
        expect(find.byKey(key).hitTestable(), findsOneWidget);
        expect(tester.getSize(find.byKey(key)), const Size.square(28));
        expect(_button(tester, key).style!.animationDuration, Duration.zero);
        _expectNativeSemantics(tester, key);
      }
      await tester.tap(find.byKey(_shareKey));
      await tester.pump();
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0.65,
      );
      actions.calls.single.completion.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byType(MediaActionButtons)), bounds);
      _expectNativeSemantics(tester, _shareKey);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      actions.completePending();
      await tester.pump();
      semantics.dispose();
      styles.dispose();
    }
  });

  testWidgets(
      'style updates retain the 140ms feedback fade and 1600ms lifetime',
      (tester) async {
    final styles = ValueNotifier(DefaultIconStyle.monochrome);
    final actions = _Actions();
    try {
      await _mount(tester, styles, Center(child: _buttons(actions)));
      final element = tester.element(find.byKey(_copyKey));
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      actions.calls.single.completion.complete();
      final deadline =
          tester.binding.clock.now().add(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(_badgeOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 70));
      final opacity = _badgeOpacity(tester);
      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));
      styles.value = DefaultIconStyle.vivid;
      await tester.pump();
      expect(_badgeOpacity(tester), opacity);
      await tester.pump(const Duration(milliseconds: 70));
      expect(_badgeOpacity(tester), 1);
      expect(tester.element(find.byKey(_copyKey)), same(element));
      for (final switcher in tester
          .widgetList<AnimatedSwitcher>(find.byType(AnimatedSwitcher))) {
        expect(switcher.duration, _fade);
      }
      await tester.pump(
        deadline.difference(tester.binding.clock.now()) -
            const Duration(milliseconds: 1),
      );
      expect(_button(tester, _copyKey).tooltip, 'Copied');
      await tester.pump(const Duration(milliseconds: 1));
      expect(_button(tester, _copyKey).tooltip, 'Copy');
      await tester.pump(_finishFade);
      expect(find.byKey(const ValueKey('media-copied')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      actions.completePending();
      await tester.pump();
      styles.dispose();
    }
  });

  testWidgets('style changes do not release a rebound source/service lock',
      (tester) async {
    final styles = ValueNotifier(DefaultIconStyle.monochrome);
    final first = _Actions();
    final second = _Actions();
    var actions = first;
    var source = _source('first.txt');
    late StateSetter update;
    try {
      await _mount(
        tester,
        styles,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Center(
              child: MediaActionButtons(source: source, actions: actions),
            );
          },
        ),
        reduced: true,
      );
      final state = tester.state(find.byType(MediaActionButtons));
      final staleCopy = _button(tester, _copyKey).onPressed!;
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      update(() {
        actions = second;
        source = _source('second.txt');
      });
      styles.value = DefaultIconStyle.vivid;
      await tester.pump();
      staleCopy();
      expect(first.calls, hasLength(1));
      expect(second.calls, isEmpty);
      expect(_button(tester, _shareKey).onPressed, isNull);
      first.calls.single.completion.complete();
      await tester.pump();
      await tester.pump();
      expect(_button(tester, _copyKey).tooltip, 'Copy');
      expect(find.byKey(const ValueKey('media-copied')), findsNothing);
      staleCopy();
      expect(second.calls, isEmpty);
      await tester.tap(find.byKey(_shareKey));
      await tester.pump();
      expect(second.calls.single.source, same(source));
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      await _unmount(tester);
      second.calls.single.completion
          .completeError(StateError('Late fixture failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      first.completePending();
      second.completePending();
      await tester.pump();
      styles.dispose();
    }
  });
}

MediaActionSource _source([String name = 'fixture.txt']) => MediaActionSource(
      source: '/synthetic-fixture/$name',
      name: name,
    );

Widget _buttons(_Actions actions, {bool onDarkSurface = false}) =>
    MediaActionButtons(
      source: _source(),
      actions: actions,
      decorated: !onDarkSurface,
      buttonSize: onDarkSurface ? 32 : 28,
      onDarkSurface: onDarkSurface,
    );

Future<void> _mount(
  WidgetTester tester,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child, {
  String mode = 'light',
  bool reduced = false,
  bool accessible = false,
  double textScale = 1,
}) =>
    mountFileControls(
      tester,
      DefaultIconStyleScope(styles: styles, child: child),
      mode: mode,
      reduced: reduced,
      accessible: accessible,
      textScale: textScale,
    );

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

Material _buttonMaterial(WidgetTester tester, Key key) =>
    tester.widget<Material>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Material))
          .first,
    );

Future<void> _settleNativeStyle(WidgetTester tester, ButtonStyle style) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(
    (style.animationDuration ?? Duration.zero) +
        const Duration(milliseconds: 1),
  );
}

void _expectNativeSemantics(
  WidgetTester tester,
  Key key, {
  bool enabled = true,
  bool liveRegion = false,
}) {
  final node = tester.getSemantics(find.byKey(key));
  final label = _button(tester, key).tooltip!;
  expect(node.attached, isTrue);
  expect(find.semantics.byLabel(label).evaluate(), contains(same(node)));
  expect(node.label, label);
  expect(node.tooltip, isEmpty);
  expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(node.hasFlag(ui.SemanticsFlag.hasEnabledState), isTrue);
  expect(node.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(node.hasFlag(ui.SemanticsFlag.isLiveRegion), liveRegion);
  expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), enabled);
}

Finder _glyphIn(Finder parent) => find.descendant(
      of: parent,
      matching: find.byType(WorkspaceGlyph),
    );

Finder _fileGlyph(String name, double size) => find.byWidgetPredicate(
      (widget) =>
          widget is WorkspaceGlyph &&
          widget.name == name &&
          widget.size == size,
    );

void _expectArtwork(
  WidgetTester tester,
  Finder finder,
  String name,
  DefaultIconStyle style, {
  Color? ink,
  bool preserveInk = false,
}) {
  expect(finder, findsOneWidget);
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  expect(glyph.name, name);
  if (preserveInk) expect(glyph.role, WorkspaceGlyphRole.preserveInk);
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: finder, matching: find.byType(SvgPicture)),
  );
  final vivid = style == DefaultIconStyle.vivid && !preserveInk
      ? WorkspaceGlyphs.vividNameFor(name)
      : null;
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      (vivid == null ? defaultIconSvg(name) : vividIconSvg(vivid))!,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
  final context = tester.element(finder);
  expect(
    picture.colorFilter,
    vivid == null
        ? ColorFilter.mode(
            style == DefaultIconStyle.vivid && !preserveInk
                ? workspaceGlyphAccent(context)
                : ink ?? glyph.color ?? workspaceGlyphInk(context),
            BlendMode.srcIn,
          )
        : null,
  );
  expect(tester.getSize(finder), Size.square(glyph.size));
}

double _badgeOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('media-copied')),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

Future<void> _drainArchiveIO(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(
    ready(),
    isTrue,
    reason: 'The bounded local archive fixture must finish',
  );
}

/// No native clipboard, share sheet, credential or network implementation.
class _Actions extends Fake implements MediaActionService {
  final calls = <_Call>[];

  @override
  Future<void> copy(MediaActionSource source) => _start('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _start('share', source, sharePositionOrigin);

  Future<void> _start(String action, MediaActionSource source, Rect? origin) {
    final call = _Call(action, source, origin);
    calls.add(call);
    return call.completion.future;
  }

  void completePending() {
    for (final call in calls) {
      if (!call.completion.isCompleted) call.completion.complete();
    }
  }
}

class _Call {
  _Call(this.action, this.source, this.origin);

  final String action;
  final MediaActionSource source;
  final Rect? origin;
  final completion = Completer<void>();
}
