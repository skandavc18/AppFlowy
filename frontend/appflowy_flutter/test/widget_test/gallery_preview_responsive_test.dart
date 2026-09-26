import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _cardSize = Size(218, 250);
const _longFileName =
    'Collected research notes and supplementary materials.archives';
// At 2x text this exceeds the compact footer beside the pinned/favorite badges.
const _longTypeLabel = 'ARCHIVES';
const _previewStageKey = ValueKey('folder-gallery-preview-stage');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  group('FolderGalleryCard compact file preview', () {
    for (final appearance in ['light', 'dark', 'paper']) {
      for (final withMetadata in [false, true]) {
        testWidgets(
            '$appearance: 2x text fits loading and loaded cards '
            '${withMetadata ? 'with' : 'without'} metadata', (tester) async {
          final preview = Completer<FolderGalleryPreview>();
          await _pumpCard(tester, preview.future, appearance: appearance);

          expect(
            tester.takeException(),
            isNull,
            reason: 'The pending skeleton must fit the bounded card.',
          );
          expect(preview.isCompleted, isFalse);
          final previewStage = find.byKey(_previewStageKey);
          expect(previewStage, findsOneWidget);
          final previewStageElement = tester.element(previewStage);
          final skeleton = find.descendant(
            of: previewStage,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_GalleryCardSkeleton',
              description: 'gallery loading skeleton',
            ),
          );
          expect(skeleton, findsOneWidget);
          expect(find.text(_longTypeLabel), findsNothing);
          final card = find.byType(FolderGalleryCard);
          final cardState = tester.state(card);
          final cardBounds = tester.getRect(card);
          expect(cardBounds.size, _cardSize);
          _expectInside(tester.getRect(previewStage), cardBounds);
          final context = tester.element(card);
          expect(PaperTheme.isEnabled(context), appearance == 'paper');
          expect(
            Theme.of(context).brightness,
            appearance == 'dark' ? Brightness.dark : Brightness.light,
          );
          expect(MediaQuery.textScalerOf(context).scale(14), 28);
          _expectTitleFits(tester, cardBounds);

          // Only the public card and an in-memory file preview are involved:
          // no registry, repository, preview loader, native media or file I/O.
          preview.complete(
            FolderGalleryPreview(
              kind: FolderGalleryPreviewKind.file,
              blocks: const [],
              wordCount: withMetadata ? 1200 : 0,
              readingMinutes: withMetadata ? 6 : 0,
              tags: const [],
              fileTypeLabel: _longTypeLabel,
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Resolving the preview must not overflow the footer.',
          );
          await tester.pumpAndSettle();

          expect(previewStage, findsOneWidget);
          expect(tester.element(previewStage), same(previewStageElement));
          expect(skeleton, findsNothing);
          expect(
            find.descendant(
              of: previewStage,
              matching: find.text(_longTypeLabel),
            ),
            findsNothing,
          );
          final glyph = tester.widget<WorkspaceGlyph>(
            find.descendant(
              of: previewStage,
              matching: find.byType(WorkspaceGlyph),
            ),
          );
          expect(glyph.name, 'file');
          expect(glyph.size, 64);
          expect(tester.state(card), same(cardState));
          expect(tester.getRect(card), cardBounds);
          // Metadata now shares the card's height; the retained preview slot
          // must remain nonempty and inside the same outer bounds.
          _expectInside(tester.getRect(previewStage), cardBounds);
          _expectTitleFits(tester, cardBounds);

          // Type belongs in the real metadata, not on a fabricated file sheet.
          final typeLabel = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == _longTypeLabel &&
                widget.maxLines == 1,
          );
          expect(typeLabel, findsOneWidget);
          expect(
            tester.widget<Text>(typeLabel).overflow,
            TextOverflow.ellipsis,
          );
          expect(
            tester.renderObject<RenderParagraph>(typeLabel).didExceedMaxLines,
            isTrue,
          );
          _expectInside(tester.getRect(typeLabel), cardBounds);
          expect(
            tester.getRect(find.text(_longFileName)).bottom,
            lessThanOrEqualTo(tester.getRect(typeLabel).top),
          );
          for (final icon in [Icons.push_pin_rounded, Icons.star_rounded]) {
            final badge = find.byIcon(icon);
            expect(badge, findsOneWidget);
            _expectInside(tester.getRect(badge), cardBounds);
          }
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          expect(cardState.mounted, isFalse);
          expect(tester.takeException(), isNull);
          expect(tester.binding.transientCallbackCount, 0);
        });
      }
    }
  });
}

void _expectTitleFits(WidgetTester tester, Rect cardBounds) {
  final title = find.text(_longFileName);
  expect(title, findsOneWidget);
  expect(tester.widget<Text>(title).maxLines, 2);
  expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
  expect(
    tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
    isTrue,
  );
  _expectInside(tester.getRect(title), cardBounds);
}

void _expectInside(Rect child, Rect parent) {
  expect(child.width, greaterThan(0));
  expect(child.height, greaterThan(0));
  expect(child.left, greaterThanOrEqualTo(parent.left));
  expect(child.top, greaterThanOrEqualTo(parent.top));
  expect(child.right, lessThanOrEqualTo(parent.right));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom));
}

Future<void> _pumpCard(
  WidgetTester tester,
  Future<FolderGalleryPreview> preview, {
  required String appearance,
}) async {
  final brightness = appearance == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final view = ViewPB(
    id: 'responsive-file',
    parentViewId: 'folder',
    name: _longFileName,
    layout: ViewLayoutPB.Document,
    extra: jsonEncode({ViewExtKeys.isPinnedKey: true}),
    isFavorite: true,
  );
  expect(view.isPinned, isTrue);
  const item = WorkspaceExplorerItem(
    id: 'responsive-file',
    parentId: 'folder',
    name: _longFileName,
    kind: WorkspaceExplorerItemKind.file,
    metadata: null,
    hasChildren: false,
    lastEdited: null,
  );

  await tester.pumpWidget(
    WidgetTestApp(
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: Center(
              child: SizedBox(
                width: _cardSize.width,
                height: _cardSize.height,
                child: FolderGalleryCard(
                  item: item,
                  view: view,
                  preview: preview,
                  userProfile: null,
                  selected: false,
                  editing: false,
                  onTap: () {},
                  onRename: () {},
                  onRenameSubmitted: (_) async => true,
                  onRenameCancelled: () {},
                  onMore: (_) {},
                  onContextMenu: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Settle the finite card entrance, leaving the preview future unresolved.
  await tester.pumpAndSettle();
}
