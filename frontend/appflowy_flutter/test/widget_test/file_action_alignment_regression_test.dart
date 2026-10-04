import 'dart:ui' as ui;

import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/document_viewer/document_viewport.dart';
import 'package:appflowy/shared/document_viewer/document_viewport_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

void main() {
  fileControlTestSetup();
  for (final theme in fileControlAppearances) {
    for (final direction in ui.TextDirection.values) {
      for (final width in [300.0, 1000.0]) {
        for (final pdf in [false, true]) {
          testWidgets(
              '$theme/$direction/$width PDF=$pdf: fallback tools wrap on screen',
              (tester) async {
            final header = pdf
                ? _pdfToolbar()
                : DocumentViewportHeader(
                    identity: const DocumentIdentity(
                      title: 'A retained long filename.txt',
                      icon: Icons.description_rounded,
                    ),
                    keepActionsVisible: true,
                    toolbar: TextButton(
                      key: const ValueKey('fallback-toolbar-tool'),
                      onPressed: () {},
                      child: const Text('Format'),
                    ),
                    actions: [
                      for (var i = 0; i < 5; i++)
                        TextButton(
                          key: ValueKey('fallback-action-$i'),
                          onPressed: () {},
                          child: Text('Action $i'),
                        ),
                    ],
                  );
            await mountFileControls(
              tester,
              Directionality(
                textDirection: direction,
                child: Align(alignment: Alignment.topCenter, child: header),
              ),
              mode: theme,
              width: width,
              height: 900,
              textScale: 2,
              reduced: true,
              accessible: true,
            );
            final bar = tester.getRect(find.byType(DocumentViewportBar));
            final bounds = bar.deflate(DocumentViewportStyle.horizontalPadding);
            final controls = find.byWidgetPredicate(
              (w) =>
                  w is TextButton ||
                  w is IconButton ||
                  w is WorkspaceControlButton ||
                  w is PdfPageNumberField,
            );
            expect(controls, findsWidgets);
            var right = double.negativeInfinity;
            for (final element in controls.evaluate()) {
              final target =
                  find.byElementPredicate((e) => identical(e, element));
              final rect = tester.getRect(target);
              expect(rect.left, greaterThanOrEqualTo(bounds.left - .01));
              expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
              expect(rect.top, greaterThanOrEqualTo(bar.top));
              expect(rect.bottom, lessThanOrEqualTo(bar.bottom));
              expect(
                target.hitTestable(),
                findsOneWidget,
                reason:
                    'No ensureVisible or horizontal scrolling to find tools',
              );
              if (rect.right > right) right = rect.right;
            }
            // PDF groups have a 1px border and 3px padding; the action itself,
            // rather than a wide toolbar shell, must still reach that gutter.
            expect(bounds.right - right, inInclusiveRange(0, pdf ? 4.01 : .01));
            expect(tester.takeException(), isNull);
            await unmountFileControls(tester);
          });
        }
      }
    }
  }
  for (final theme in fileControlAppearances) {
    for (final width in [300.0, 800.0, 1200.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final direction in ui.TextDirection.values) {
          testWidgets(
              '$theme/$width/$scale/$direction: native file actions reach physical right gutter',
              (tester) async {
            final file = MemoryCodeFile('print("unchanged")');
            final backend = FileControlBackend(
              fileControlView(
                'alignment',
                'A long localized filename — source.py',
                file.path,
              ),
              file,
            );
            await mountFileControls(
              tester,
              Directionality(
                textDirection: direction,
                child: backend.viewer(editable: false),
              ),
              mode: theme,
              width: width,
              height: 900,
              textScale: scale,
              reduced: true,
            );
            await tester.binding.setSurfaceSize(Size(width + 64, 1000));
            await settleFileControls(tester);
            final band =
                find.byKey(const ValueKey('workspace-file-toolbar-scroll'));
            expect(
              tester
                  .widget<FileActionBand>(find.byType(FileActionBand))
                  .responsive,
              isTrue,
            );
            expectFileToolsBesideOrBelowTitle(
              tester,
              beside: width == 300
                  ? false
                  : scale == 1
                      ? true
                      : null,
            );
            final nativeButtons = find.descendant(
              of: band,
              matching: find.byWidgetPredicate(
                (w) => w is TextButton || w is IconButton,
              ),
            );
            expect(nativeButtons, findsWidgets);
            final bounds = tester.getRect(band);
            final runs = <double, double>{};
            for (final element in nativeButtons.evaluate()) {
              final target = find.byElementPredicate(
                (candidate) => identical(element, candidate),
              );
              final rect = tester.getRect(target);
              expect(rect.left, greaterThanOrEqualTo(bounds.left - .01));
              expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
              final run = rect.center.dy.roundToDouble();
              runs.update(
                run,
                (right) => right > rect.right ? right : rect.right,
                ifAbsent: () => rect.right,
              );
            }
            final pane = tester
                .getRect(find.byKey(const ValueKey('workspace-file-canvas')));
            expect(
              bounds.right,
              closeTo(pane.right - WorkspaceTokens.pageInset(width), .01),
            );
            // The actual controls, not an allocated 620px shell, end at the
            // toolbar's intentional 4/6px inner padding.
            expect(
              runs.values.reduce((a, b) => a > b ? a : b),
              closeTo(
                bounds.right - (fileToolsOfferedWidth(tester) < 520 ? 4 : 6),
                .01,
              ),
            );
            expect(
              find.byKey(const ValueKey('workspace-file-rename')),
              findsNothing,
            );
            expect(file.reads, 1);
            expect(file.writes, 0);
            expect(tester.takeException(), isNull);
            await unmountFileControls(tester);
          });
        }
      }
    }
  }
}

PdfPreviewToolbar _pdfToolbar() => PdfPreviewToolbar(
      title: 'Original.pdf',
      currentPage: 1,
      pageCount: 40,
      zoom: 1,
      ready: true,
      showThumbnails: false,
      showOutline: false,
      searchVisible: false,
      isFullscreen: false,
      onToggleThumbnails: () {},
      onToggleOutline: () {},
      onPreviousPage: () {},
      onNextPage: () {},
      onPageSubmitted: (_) {},
      onZoomOut: () {},
      onZoomIn: () {},
      onFitWidth: () {},
      onFitPage: () {},
      onToggleSearch: () {},
      onRotate: () {},
      onDownload: () {},
      onPrint: () {},
      onFullscreen: () {},
      overflow:
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
    );
