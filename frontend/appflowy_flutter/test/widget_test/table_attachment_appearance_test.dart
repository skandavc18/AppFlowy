import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/media_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller_builder.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/application/field/type_option/type_option_data_parser.dart';
import 'package:appflowy/plugins/database/grid/application/row/row_detail_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/desktop_grid_media_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_row_detail/desktop_row_detail_media_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/media.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/media_cell_editor.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/file_viewer/attachment_file_viewer.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reorderables/reorderables.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'test_asset_bundle.dart';

const _host = ValueKey('real-media-cell-host');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _fileIcons = {
  'Quarterly report.PDF': Icons.picture_as_pdf_rounded,
  'Proposal.docx': Icons.text_snippet_rounded,
  'Budget.xlsx': Icons.table_chart_rounded,
  'Presentation.pptx': Icons.slideshow_rounded,
  'Backup.zip': Icons.folder_zip_rounded,
  'Interview.mp3': Icons.audiotrack_rounded,
  'Recording.mp4': Icons.movie_rounded,
  'Analysis.py': Icons.code_rounded,
  'Notes.txt': Icons.description_rounded,
  'Unknown.unrecognized': Icons.insert_drive_file_rounded,
};

enum _Skin { grid, rowDetail }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File blue;
  late File red;
  late bool fontFetching;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    temporary = await Directory.systemTemp.createTemp('table_attachments_');
    blue = await File('${temporary.path}/blue.png').writeAsBytes(
      await _png(256, 512, const Color(0xFF143CDC)),
    );
    red = await File('${temporary.path}/red #1 100%.PNG').writeAsBytes(
      await _png(512, 256, const Color(0xFFDC2414)),
    );
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
    await temporary.delete(recursive: true);
  });

  test('file glyphs reuse page helpers without rewriting frozen protobufs', () {
    for (final entry in _fileIcons.entries) {
      for (final type in [MediaFileTypePB.Other, MediaFileTypePB.Link]) {
        final file = _file(name: entry.key, type: type);
        final saved = file.writeToBuffer();
        file.freeze();
        expect(file.displayName, entry.key);
        final isLinkFallback = type == MediaFileTypePB.Link &&
            entry.value == Icons.insert_drive_file_rounded;
        expect(
          file.displayIcon,
          isLinkFallback ? Icons.link_rounded : entry.value,
        );
        if (!isLinkFallback) {
          expect(file.displayIcon, fileIconForName(entry.key));
        }
        expect(file.isImage, isFalse);
        expect(file.fileType, type);
        expect(file.writeToBuffer(), orderedEquals(saved));
      }
    }
  });

  test('URI suffixes are decoded, queries ignored and literal names retained',
      () {
    for (final entry in [
      (
        'https://assets.example.invalid/Budget%20%231%20%25100.PDF'
            '?signature=do-not-display#preview',
        'Budget #1 %100.PDF',
        Icons.picture_as_pdf_rounded,
      ),
      (
        'file:///C:/synthetic/Presentation%20one%2Epptx',
        'Presentation one.pptx',
        Icons.slideshow_rounded,
      ),
      (
        r'C:\synthetic\Budget #1 100%.xlsx',
        'Budget #1 100%.xlsx',
        Icons.table_chart_rounded,
      ),
      (
        'https://assets.example.invalid/download?name=leak.pdf#photo.JPG',
        'download',
        Icons.insert_drive_file_rounded,
      ),
    ]) {
      final file = _file(name: '  ', url: entry.$1);
      final before = file.writeToBuffer();
      file.freeze();
      expect(file.displayName, entry.$2);
      expect(file.displayIcon, entry.$3);
      expect(file.writeToBuffer(), orderedEquals(before));
    }
    expect(
      _file(name: 'Literal%20name.pdf').displayName,
      'Literal%20name.pdf',
    );
    expect(
      _file(name: 'Friendly title', url: 'https://example.invalid/file.xlsx')
          .displayIcon,
      Icons.table_chart_rounded,
    );
    for (final source in [
      '',
      'data:text/plain,secret.pdf',
      'https://[invalid',
    ]) {
      expect(_file(name: '', url: source).displayName, isNotEmpty);
      expect(
        _file(name: '', url: source).displayIcon,
        Icons.insert_drive_file_rounded,
      );
    }
  });

  test('saved MIME-derived categories win over misleading image filenames', () {
    for (final entry in {
      'application/pdf': Icons.description_rounded,
      'text/plain': Icons.description_rounded,
      'audio/mpeg': Icons.audiotrack_rounded,
      'video/mp4': Icons.movie_rounded,
      'application/zip': Icons.folder_zip_rounded,
    }.entries) {
      final type = inferFileType('misleading.JPG', mimeType: entry.key)
          .toMediaFileTypePB();
      final file = _file(name: 'misleading.JPG', type: type);
      final saved = file.writeToBuffer();
      file.freeze();
      expect(file.isImage, isFalse);
      expect(file.displayIcon, entry.value);
      expect(file.writeToBuffer(), orderedEquals(saved));
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final skin in _Skin.values) {
      _case('$mode $skin: named typed files fit 40/80/250px at 2x text',
          (tester, boundary) async {
        final fixture = _Fixture(skin, []);
        try {
          for (final width in [40.0, 80.0, 250.0]) {
            fixture.controller.width = width;
            for (final upload in [
              FileUploadTypePB.CloudFile,
              FileUploadTypePB.NetworkFile,
              FileUploadTypePB.LocalFile,
            ]) {
              for (final entry in _fileIcons.entries) {
                final file = _file(name: entry.key, upload: upload);
                final saved = file.writeToBuffer();
                file.freeze();
                fixture.controller.replaceFiles([file]);
                await _pump(tester, fixture.cell(), mode, textScale: 2);
                expect(find.byType(MediaFileLabel), findsOneWidget);
                expect(tester.widget<Text>(_name(file.id)).data, file.name);
                expect(
                  tester.widget<Icon>(_icon(file.id)).icon,
                  entry.value,
                  reason: '${entry.key}, $upload, $width',
                );
                final label = tester.widget<Text>(_name(file.id));
                expect(label.maxLines, 1);
                expect(label.overflow, TextOverflow.ellipsis);
                expect(find.byTooltip(file.name), findsWidgets);
                final bounds = tester.getRect(find.byKey(_host));
                final chip = tester.getRect(_surface(file.id));
                expect(chip.left, greaterThanOrEqualTo(bounds.left));
                expect(chip.right, lessThanOrEqualTo(bounds.right + 0.01));
                final glyph = tester.getRect(_icon(file.id));
                expect(glyph.width, greaterThanOrEqualTo(12));
                expect(glyph.left, greaterThanOrEqualTo(chip.left));
                expect(glyph.right, lessThanOrEqualTo(chip.right + 0.01));
                _expectPalette(tester, file.id, mode);
                _expectNoFilePreview();
                expect(find.byType(AFImage), findsNothing);
                expect(file.writeToBuffer(), orderedEquals(saved));
                expect(fixture.backend.mediaEvents, isEmpty);
                expect(fixture.backend.rowEvents, isEmpty);
                expect(boundary.http.requests, isEmpty);
                expect(tester.takeException(), isNull);
              }
            }
          }
        } finally {
          await fixture.dispose(tester);
        }
      });

      _case('$mode $skin: ellipsis retains a full native hover tooltip',
          (tester, boundary) async {
        const fullName = 'Quarterly report with a deliberately long filename '
            'and the original revision details.PDF';
        final file = _file(name: fullName);
        final fixture = _Fixture(skin, [file], width: 80);
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _pump(tester, fixture.cell(), mode, textScale: 2);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: _name(file.id),
              matching: find.byType(RichText),
            ),
          );
          expect(paragraph.didExceedMaxLines, isTrue);
          final rect = tester.getRect(_surface(file.id));
          final before =
              find.text(fullName, findRichText: true).evaluate().length;
          await mouse.moveTo(tester.getCenter(_name(file.id)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();
          expect(
            find.text(fullName, findRichText: true).evaluate().length,
            greaterThan(before),
          );
          expect(tester.getRect(_surface(file.id)), rect);
          expect(fixture.ancestorTaps, 0);
          expect(fixture.backend.mediaEvents, isEmpty);
          expect(boundary.launcher.urls, isEmpty);
          _expectNoFilePreview();
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      });

      for (final legacy in [MediaFileTypePB.Other, MediaFileTypePB.Link]) {
        _case('$mode $skin: two decoded photos and cached reorder with $legacy',
            (tester, _) async {
          final files = [
            _file(
              id: 'blue',
              name: 'First.png',
              url: blue.path,
              type: MediaFileTypePB.Image,
              upload: FileUploadTypePB.LocalFile,
            ),
            _file(id: 'document', name: 'Notes.pdf'),
            _file(
              id: 'red',
              name: 'Legacy photo',
              url: red.uri.toString(),
              type: legacy,
              upload: FileUploadTypePB.LocalFile,
            ),
          ];
          final original = files.map((file) => file.writeToBuffer()).toList();
          final fixture = _Fixture(skin, files, width: 520);
          ui.Image? cached;
          try {
            await _pump(tester, fixture.cell(), mode, dpr: 2);
            await _finishImages(tester);
            expect(find.byType(AFImage), findsNWidgets(2));
            expect(find.byType(MediaFileLabel), findsOneWidget);
            await _expectPixel(tester, 'blue', red: false);
            await _expectPixel(tester, 'red', red: true);
            final imageState = tester.state(_image('red'));
            cached = _raw(tester, 'red').image!.clone();
            for (final id in ['blue', 'red']) {
              final thumbnail =
                  tester.widget<MediaFileThumbnail>(_thumbnail(id));
              final renderer = tester.widget<AFImage>(
                find.descendant(
                  of: _thumbnail(id),
                  matching: find.byType(AFImage),
                ),
              );
              expect(renderer.cacheWidth, (thumbnail.size.width * 2).ceil());
              expect(renderer.cacheHeight, isNull);
              expect(_raw(tester, id).image!.width, renderer.cacheWidth);
              expect(_raw(tester, id).fit, BoxFit.cover);
            }

            final updated = original.map(MediaFilePB.fromBuffer).toList();
            updated[1].name = 'Renamed notes.pdf';
            fixture.controller.replaceFiles(updated);
            await tester.pumpAndSettle();
            expect(tester.state(_image('red')), same(imageState));
            expect(find.text('Renamed notes.pdf'), findsOneWidget);
            fixture.controller.replaceFiles(updated.reversed.toList());
            await tester.pumpAndSettle();
            // Reorderables may remount index-keyed drag targets. The pixels
            // must still come from the cached decode, not a blank/new image.
            expect(_raw(tester, 'red').image!.isCloneOf(cached), isTrue);
            expect(
              tester.getTopLeft(_thumbnail('red')).dx,
              lessThan(tester.getTopLeft(_thumbnail('blue')).dx),
            );
            await _expectPixel(tester, 'blue', red: false);
            await _expectPixel(tester, 'red', red: true);
            expect(files.map((file) => file.writeToBuffer()), original);
            expect(fixture.backend.mediaEvents, isEmpty);
          } finally {
            cached?.dispose();
            await fixture.dispose(tester);
          }
        });
      }
    }

    _case('$mode: non-image +N footer fits narrow rows and expands in order',
        (tester, _) async {
      for (final width in [40.0, 80.0, 250.0]) {
        final files = List.generate(
          5,
          (index) => _file(id: 'file-$index', name: 'Document $index.pdf'),
        );
        final fixture = _Fixture(_Skin.rowDetail, files, width: width);
        try {
          await _pump(tester, fixture.cell(), mode, textScale: 2);
          final wrap =
              tester.widget<ReorderableWrap>(find.byType(ReorderableWrap));
          expect(wrap.children, hasLength(1));
          final counter =
              find.text(LocaleKeys.grid_media_extraCount.tr(args: ['4']));
          expect(counter, findsOneWidget);
          final cell = tester.getRect(find.byKey(_host));
          final paragraph = tester.renderObject<RenderBox>(counter);
          final count = MatrixUtils.transformRect(
            paragraph.getTransformTo(null),
            Offset.zero & paragraph.size,
          );
          expect(count.left, greaterThanOrEqualTo(cell.left - 0.01));
          expect(count.right, lessThanOrEqualTo(cell.right + 0.01));
          expect(find.semantics.byLabel(files[1].name), findsNothing);
          expect(fixture.backend.mediaEvents, isEmpty);
          await tester.tap(counter);
          await tester.pumpAndSettle();
          final expanded =
              tester.widget<ReorderableWrap>(find.byType(ReorderableWrap));
          expect(expanded.children, hasLength(5));
          expect(expanded.footer, isNull);
          expect(fixture.bloc.state.showAllFiles, isTrue);
          expect(
            fixture.bloc.state.files.map((file) => file.id),
            files.map((file) => file.id),
          );
          expect(fixture.backend.mediaEvents, isEmpty);
          expect(fixture.ancestorTaps, 0);
          expect(find.byType(AttachmentFileViewer), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      }
    });

    _case('$mode: wrapping grid keeps all filenames and intrinsic dimensions',
        (tester, _) async {
      final files = [
        _file(id: 'a', name: 'Budget.xlsx'),
        _file(id: 'b', name: 'Slides.pptx'),
        _file(id: 'c', name: 'Source.py'),
      ];
      final fixture = _Fixture(_Skin.grid, files, width: 80, wrap: true);
      try {
        await _pump(tester, fixture.cell(), mode, textScale: 2);
        expect(find.byType(IntrinsicHeight), findsOneWidget);
        expect(find.byType(MediaFileLabel), findsNWidgets(3));
        expect(
          find.descendant(
            of: find.byKey(_host),
            matching: find.byType(LayoutBuilder),
          ),
          findsNothing,
        );
        expect(
          tester.getTopLeft(_surface('a')).dy,
          lessThan(tester.getTopLeft(_surface('b')).dy),
        );
        expect(
          tester.getTopLeft(_surface('b')).dy,
          lessThan(tester.getTopLeft(_surface('c')).dy),
        );
        final box = tester.renderObject<RenderBox>(find.byKey(_host));
        for (final dimension in [
          box.getMinIntrinsicHeight(80),
          box.getMaxIntrinsicHeight(80),
          box.getMinIntrinsicWidth(160),
          box.getMaxIntrinsicWidth(160),
        ]) {
          expect(dimension.isFinite, isTrue);
          expect(dimension, greaterThanOrEqualTo(0));
        }
        expect(fixture.backend.mediaEvents, isEmpty);
        _expectNoFilePreview();
      } finally {
        await fixture.dispose(tester);
      }
    });

    _case(
        '$mode: editor typed icons retain inert hidden actions and current targets',
        (tester, boundary) async {
      final file = _file(name: 'First proposal.docx');
      final fixture = _Fixture(_Skin.grid, [file]);
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _pump(
          tester,
          fixture.editor(boundary.actions),
          mode,
          textScale: 2,
        );
        final buttons = tester.state(find.byType(MediaActionButtons));
        expect(find.byIcon(Icons.text_snippet_rounded), findsOneWidget);
        expect(find.byTooltip(file.name), findsOneWidget);
        expect(find.byKey(_copy).hitTestable(), findsNothing);
        expect(find.byKey(_share).hitTestable(), findsNothing);
        await tester.tapAt(tester.getCenter(find.byKey(_copy)));
        await tester.pump();
        expect(boundary.actions.calls, isEmpty);
        expect(find.byType(AttachmentFileViewer), findsNothing);
        await mouse.moveTo(tester.getCenter(find.byType(RenderMedia)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 141));
        expect(find.byKey(_copy).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(_copy));
        await tester.pumpAndSettle();
        expect(boundary.actions.calls.single.$1, 'copy');
        expect(boundary.actions.calls.single.$2.name, file.name);
        expect(boundary.actions.calls.single.$2.source, file.url);

        final replacement = _file(
          name: 'Updated budget.xlsx',
          url: 'https://assets.example.invalid/current-file',
          upload: FileUploadTypePB.NetworkFile,
        );
        fixture.controller.replaceFiles([replacement]);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.table_chart_rounded), findsOneWidget);
        expect(tester.state(find.byType(MediaActionButtons)), same(buttons));
        expect(
          tester
              .widget<MediaActionButtons>(find.byType(MediaActionButtons))
              .source
              .source,
          replacement.url,
        );
        await mouse.moveTo(tester.getCenter(find.byType(RenderMedia)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 141));
        await tester.tap(find.byKey(_share));
        await tester.pumpAndSettle();
        final shared = boundary.actions.calls.last;
        expect(shared.$1, 'share');
        expect(shared.$2.source, replacement.url);
        expect(shared.$2.name, replacement.name);
        expect(shared.$2.httpHeaders, isEmpty);
        expect(find.byType(AttachmentFileViewer), findsNothing);
        expect(fixture.backend.mediaEvents, isEmpty);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  for (final skin in _Skin.values) {
    _case('$skin: blank name displays URI basename, never signed parameters',
        (tester, _) async {
      final file = _file(
        name: '',
        url: 'https://assets.example.invalid/Notes%20%231%20%25100.PDF'
            '?signature=do-not-display#secret-fragment',
      );
      final fixture = _Fixture(skin, [file]);
      try {
        await _pump(tester, fixture.cell(), 'paper');
        expect(tester.widget<Text>(_name(file.id)).data, 'Notes #1 %100.PDF');
        expect(find.byTooltip('Notes #1 %100.PDF'), findsWidgets);
        expect(
          find.textContaining('do-not-display', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('secret-fragment', findRichText: true),
          findsNothing,
        );
        expect(
          tester.widget<Icon>(_icon(file.id)).icon,
          Icons.picture_as_pdf_rounded,
        );
        fixture.controller.replaceFiles([_file(name: '', url: '')]);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(_name(file.id)).data,
          LocaleKeys.document_plugins_file_name.tr(),
        );
        expect(
          tester.widget<Icon>(_icon(file.id)).icon,
          Icons.insert_drive_file_rounded,
        );
        expect(fixture.backend.mediaEvents, isEmpty);
      } finally {
        await fixture.dispose(tester);
      }
    });

    _case(
        '$skin: clicking a named PDF opens that attachment without a row action',
        (tester, _) async {
      // No profile: the real viewer must fail closed, before materialization.
      final files = [
        _file(id: 'one', name: 'First.pdf'),
        _file(id: 'two', name: 'Selected.pdf'),
      ];
      final fixture = _Fixture(skin, files, width: 460);
      try {
        await _pump(tester, fixture.cell(), 'dark');
        await tester.tap(_name('two'));
        await tester.pumpAndSettle();
        final viewer = tester
            .widget<AttachmentFileViewer>(find.byType(AttachmentFileViewer));
        expect(viewer.file.id, 'two');
        expect(viewer.file.url, files.last.url);
        expect(viewer.userProfile, isNull);
        expect(find.byType(MaterializedFileBuilder), findsNothing);
        expect(find.byType(InteractiveImageViewer), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        expect(fixture.backend.mediaEvents, isEmpty);
        expect(fixture.ancestorTaps, 0);
        expect(fixture.ancestorDeletes, 0);
        expect(fixture.bloc.state.files.map((file) => file.id), ['one', 'two']);
      } finally {
        await fixture.dispose(tester);
      }
    });

    _case('$skin: genuine links keep the browser route and link glyph',
        (tester, boundary) async {
      final file = _file(
        name: 'A web article',
        url: 'https://example.invalid/read/index.html?keep=original#section',
        type: MediaFileTypePB.Link,
        upload: FileUploadTypePB.NetworkFile,
      );
      final fixture = _Fixture(skin, [file]);
      try {
        await _pump(tester, fixture.cell(), 'light');
        expect(tester.widget<Icon>(_icon(file.id)).icon, Icons.link_rounded);
        await tester.tap(_name(file.id));
        await tester.pumpAndSettle();
        expect(boundary.launcher.urls, [file.url]);
        expect(find.byType(AttachmentFileViewer), findsNothing);
        expect(find.byType(InteractiveImageViewer), findsNothing);
        expect(fixture.backend.mediaEvents, isEmpty);
        expect(fixture.ancestorTaps, 0);
      } finally {
        await fixture.dispose(tester);
      }
    });

    _case('$skin: image click and delete callback retain the same ID snapshot',
        (tester, _) async {
      final files = [
        _file(id: 'first', name: 'First.PNG'),
        _file(id: 'document', name: 'Document.pdf'),
        _file(id: 'second', name: 'Second.JFIF', type: MediaFileTypePB.Link),
      ];
      final fixture = _Fixture(skin, files, width: 520);
      try {
        await _pump(tester, fixture.cell(), 'paper');
        await tester.tap(_thumbnail('second'));
        await tester.pumpAndSettle();
        final viewer = tester.widget<InteractiveImageViewer>(
          find.byType(InteractiveImageViewer),
        );
        final provider = viewer.imageProvider as MediaFileImageProvider;
        expect(provider.files.map((file) => file.id), ['first', 'second']);
        expect(provider.initialIndex, 1);
        expect(provider.getImageName(1), 'Second.JFIF');
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        expect(fixture.backend.mediaEvents, isEmpty);
        fixture.controller.replaceFiles(files.reversed.toList());
        await tester.pumpAndSettle();
        provider.onDeleteImage!(1);
        expect(
          fixture.backend.mediaEvents.single,
          const MediaCellEvent.removeFile(fileId: 'second'),
        );
        await tester.runAsync(fixture.bloc.close);
        provider.onDeleteImage!(0);
        expect(fixture.backend.mediaEvents, hasLength(1));
        expect(fixture.ancestorTaps, 0);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  _case(
      'row-detail image menu still sets the selected cover, not the file order',
      (tester, _) async {
    final file = _file(id: 'cover', name: 'Legacy cover.JPG');
    final fixture = _Fixture(_Skin.rowDetail, [file]);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _pump(tester, fixture.cell(), 'paper');
      await mouse.moveTo(tester.getCenter(_thumbnail(file.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FlowyIconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LocaleKeys.grid_media_setAsCover.tr()));
      await tester.pumpAndSettle();
      final cover = fixture.backend.rowEvents.single.maybeWhen(
        setCover: (cover) => cover,
        orElse: () => null,
      );
      expect(cover, isNotNull);
      expect(cover!.data, file.url);
      expect(cover.uploadType, file.uploadType);
      expect(cover.coverType, CoverTypePB.FileCover);
      expect(fixture.bloc.state.files.single.id, file.id);
      expect(fixture.backend.mediaEvents, isEmpty);
      expect(find.byType(InteractiveImageViewer), findsNothing);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });
}

MediaFilePB _file({
  String id = 'attachment',
  String name = 'Attachment.bin',
  String? url,
  MediaFileTypePB type = MediaFileTypePB.Other,
  FileUploadTypePB upload = FileUploadTypePB.CloudFile,
}) =>
    MediaFilePB(
      id: id,
      name: name,
      url: url ?? 'https://assets.example.invalid/$id?not-a-name=photo.JPG',
      fileType: type,
      uploadType: upload,
    );

/// Real bloc initialization, subscriptions, field options and state updates;
/// only persistence is intercepted. There is no SDK initialization or profile
/// read, and column styles come from the same ValueListenable API as in the app.
class _Fixture {
  _Fixture(
    this.kind,
    List<MediaFilePB> files, {
    double width = 250,
    bool wrap = false,
  }) : controller = _MemoryMediaController(files, width: width, wrap: wrap) {
    bloc = _MediaBloc(controller, backend);
    rowBloc = _RowBloc(backend);
    skin = kind == _Skin.grid
        ? GridMediaCellSkin(styleListenable: styles)
        : DekstopRowDetailMediaCellSkin();
  }

  final _Skin kind;
  final _MemoryMediaController controller;
  final backend = _Backend();
  final styles = ValueNotifier(const PropertyStyles());
  final notifier = CellContainerNotifier();
  final popover = PopoverController();
  late final _MediaBloc bloc;
  late final _RowBloc rowBloc;
  late final IEditableMediaCellSkin skin;
  int ancestorTaps = 0;
  int ancestorDeletes = 0;

  Widget cell() {
    Widget content = MultiBlocProvider(
      providers: [
        BlocProvider<MediaCellBloc>.value(value: bloc),
        BlocProvider<RowDetailBloc>.value(value: rowBloc),
      ],
      child: Builder(
        builder: (context) => skin.build(context, notifier, popover, bloc),
      ),
    );
    if (kind == _Skin.grid) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 0, height: 48),
            Expanded(child: Center(child: content)),
          ],
        ),
      );
    }
    return SizedBox(
      key: _host,
      width: controller.width,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.delete ||
                  event.logicalKey == LogicalKeyboardKey.backspace)) {
            ancestorDeletes++;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ancestorTaps++,
          child: content,
        ),
      ),
    );
  }

  Widget editor(MediaActionService actions) =>
      BlocProvider<MediaCellBloc>.value(
        value: bloc,
        child: SizedBox(
          width: 250,
          height: 340,
          child: MediaCellEditor(actions: actions),
        ),
      );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    if (!bloc.isClosed) await tester.runAsync(bloc.close);
    await tester.runAsync(rowBloc.close);
    popover.close();
    skin.dispose();
    notifier.dispose();
    styles.dispose();
  }
}

class _MemoryMediaController extends Fake implements MediaCellController {
  _MemoryMediaController(
    List<MediaFilePB> files, {
    required this.width,
    required this.wrap,
  }) : _data = MediaCellDataPB(files: files);

  MediaCellDataPB _data;
  double width;
  final bool wrap;
  VoidCallback? _listener;

  @override
  String get viewId => 'synthetic-attachment-view';
  @override
  String get fieldId => 'synthetic-attachment-field';
  @override
  String get rowId => 'synthetic-attachment-row';
  @override
  FieldInfo get fieldInfo => FieldInfo.initial(
        FieldPB(
          id: fieldId,
          name: 'Files',
          fieldType: FieldType.Media,
          typeOptionData:
              MediaTypeOptionPB(hideFileNames: true).writeToBuffer(),
        ),
      ).copyWith(
        fieldSettings: FieldSettingsPB(
          fieldId: fieldId,
          width: width.toInt(),
          wrapCellContent: wrap,
        ),
      );
  @override
  MediaCellDataPB getCellData({bool loadIfNotExist = true}) => _data;
  @override
  T getTypeOption<T>(TypeOptionParser parser) =>
      parser.fromBuffer(fieldInfo.field.typeOptionData) as T;
  @override
  VoidCallback? addListener({
    required void Function(MediaCellDataPB?) onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
  }) {
    _listener = () => onCellChanged(_data);
    return _listener;
  }

  @override
  void removeListener({
    required VoidCallback onCellChanged,
    void Function(FieldInfo)? onFieldChanged,
    VoidCallback? onRowMetaChanged,
  }) =>
      _listener = null;

  void replaceFiles(List<MediaFilePB> files) {
    _data = MediaCellDataPB(files: files);
    _listener?.call();
  }

  @override
  Future<void> dispose() async => _listener = null;
}

class _Backend {
  final mediaEvents = <MediaCellEvent>[];
  final rowEvents = <RowDetailEvent>[];
}

class _MediaBloc extends MediaCellBloc {
  _MediaBloc(MediaCellController controller, this.backend)
      : super(cellController: controller);
  final _Backend backend;

  @override
  void add(MediaCellEvent event) {
    final inMemory = event.maybeWhen(
      didUpdateCell: (_) => true,
      didUpdateField: (_) => true,
      toggleShowAllFiles: () => true,
      orElse: () => false,
    );
    if (inMemory) {
      super.add(event);
    } else {
      // Capture writes (and an accidental initial/profile read) instead of FFI.
      backend.mediaEvents.add(event);
    }
  }
}

class _RowBloc extends Cubit<RowDetailState> implements RowDetailBloc {
  _RowBloc(this.backend) : super(RowDetailState.initial(RowMetaPB()));
  final _Backend backend;
  @override
  void add(RowDetailEvent event) => backend.rowEvents.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Actions extends Fake implements MediaActionService {
  final calls = <(String, MediaActionSource)>[];
  @override
  Future<void> copy(MediaActionSource source) async =>
      calls.add(('copy', source));
  @override
  Future<void> share(
    MediaActionSource source, {
    Rect? sharePositionOrigin,
  }) async =>
      calls.add(('share', source));
}

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }
}

class _NoHttp extends Fake implements HttpClient {
  final requests = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    throw StateError('Attachment appearance must not fetch file bytes');
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => getUrl(url);
  @override
  void close({bool force = false}) {}
}

class _Boundaries {
  final http = _NoHttp();
  final launcher = _Launcher();
  final actions = _Actions();
}

void _case(String name, Future<void> Function(WidgetTester, _Boundaries) body) {
  testWidgets(
    name,
    (tester) async {
      final boundary = _Boundaries();
      final previousLauncher = UrlLauncherPlatform.instance;
      final previousImageClient = debugNetworkImageHttpClientProvider;
      final semantics = tester.ensureSemantics();
      UrlLauncherPlatform.instance = boundary.launcher;
      debugNetworkImageHttpClientProvider = () => boundary.http;
      try {
        await HttpOverrides.runZoned(
          () => body(tester, boundary),
          createHttpClient: (_) => boundary.http,
        );
        expect(boundary.http.requests, isEmpty);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
        UrlLauncherPlatform.instance = previousLauncher;
        debugNetworkImageHttpClientProvider = previousImageClient;
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Finder _surface(String id) => find.byKey(ValueKey('media-attachment-$id'));
Finder _name(String id) => find.byKey(ValueKey('media-attachment-name-$id'));
Finder _icon(String id) => find.byKey(ValueKey('media-file-icon-$id'));
Finder _thumbnail(String id) => find.byWidgetPredicate(
      (widget) => widget is MediaFileThumbnail && widget.file.id == id,
    );
Finder _image(String id) =>
    find.descendant(of: _thumbnail(id), matching: find.byType(Image));
RawImage _raw(WidgetTester tester, String id) => tester.widget<RawImage>(
      find.descendant(of: _thumbnail(id), matching: find.byType(RawImage)),
    );

void _expectNoFilePreview() {
  expect(find.byType(MaterializedFileBuilder), findsNothing);
  expect(find.byType(FilePreview), findsNothing);
  expect(find.byType(FileMediaPlayer), findsNothing);
  expect(find.byType(OfficeDocumentView), findsNothing);
}

void _expectPalette(WidgetTester tester, String id, String mode) {
  final context = tester.element(_surface(id));
  final theme = Theme.of(context);
  final palette = PremiumThemeExtension.of(context);
  final surface = tester.widget<Material>(_surface(id));
  expect(
    surface.color,
    EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.surface,
      isPaper: PaperTheme.isEnabled(context),
    ),
  );
  expect(tester.widget<Text>(_name(id)).style!.color, palette.textPrimary);
  final ink = tester.widget<InkWell>(
    find.descendant(of: _surface(id), matching: find.byType(InkWell)),
  );
  expect(ink.hoverColor, palette.hoverOverlay);
  expect(ink.onTap, isNotNull);
  if (mode == 'paper') {
    expect(surface.color, PaperTheme.editorPreviewBackground);
    expect(surface.color!.r, greaterThan(surface.color!.b));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  String mode, {
  double textScale = 1,
  double dpr = 1,
}) async {
  final theme = DesktopAppearance().getThemeData(
    mode == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    mode == 'dark' ? Brightness.dark : Brightness.light,
    'DM Sans',
    builtInCodeFontFamily,
  );
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
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
          builder: (context, child) => AppFlowyTheme(
            data: appTheme,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                devicePixelRatio: dpr,
              ),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(padding: const EdgeInsets.all(24), child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finishImages(WidgetTester tester) async {
  final images = tester
      .widgetList<Image>(
        find.descendant(of: find.byType(AFImage), matching: find.byType(Image)),
      )
      .toList();
  var completed = 0;
  final listeners = <(ImageStream, ImageStreamListener)>[];
  for (final image in images) {
    var finished = false;
    void finish() {
      if (!finished) completed++;
      finished = true;
    }

    final stream = image.image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        finish();
      },
      onError: (Object error, StackTrace? stack) => finish(),
    );
    stream.addListener(listener);
    listeners.add((stream, listener));
  }
  try {
    for (var attempt = 0;
        completed < images.length && attempt < 200;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(completed, images.length);
  } finally {
    for (final (stream, listener) in listeners) {
      stream.removeListener(listener);
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _expectPixel(
  WidgetTester tester,
  String id, {
  required bool red,
}) async {
  final image = _raw(tester, id).image;
  expect(image, isNotNull, reason: '$id must contain decoded pixels');
  final data = await tester.runAsync(() => image!.toByteData());
  final offset = ((image!.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  expect(data!.getUint8(offset + (red ? 0 : 2)), greaterThan(180));
  expect(data.getUint8(offset + (red ? 2 : 0)), lessThan(80));
}

Future<List<int>> _png(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
