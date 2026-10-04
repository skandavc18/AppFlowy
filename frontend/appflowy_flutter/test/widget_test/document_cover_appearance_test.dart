import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

void main() {
  setUpAll(initializeWorkspaceOverlayTests);
  for (final theme in ['light', 'dark', 'paper']) {
    for (final fit in CoverImageFit.values) {
      testWidgets(
          '$theme/$fit actual DesktopCover preserves legacy image through a height write',
          (tester) async {
        final editor = EditorState.blank();
        final node = Node(
          type: 'page',
          attributes: {
            DocumentHeaderBlockKeys.coverType: CoverType.asset.toString(),
            DocumentHeaderBlockKeys.coverDetails: 'n1',
          },
        );
        final attributes = Map<String, dynamic>.from(node.attributes);
        var view = ViewPB(id: 'legacy-cover', layout: ViewLayoutPB.Document);
        final appearance =
            CoverAppearance(fit: fit, position: CoverPosition.top);
        Widget app() => workspaceOverlayTestApp(
              appearance: theme,
              disableAnimations: true,
              child: PageCoverPresentation(
                appearance: appearance,
                alignment: appearance.alignment,
                child: SizedBox(
                  width: 600,
                  height: PageCoverHeight.decode(view.extra) ?? 200,
                  child: DesktopCover(
                    view: view,
                    editorState: editor,
                    node: node,
                    coverType: CoverType.asset,
                    coverDetails: 'n1',
                  ),
                ),
              ),
            );
        await tester.pumpWidget(app());
        await tester.pump();
        final state = tester.state(find.byType(DesktopCover));
        expect(
          (tester.widget<Image>(find.byType(Image)).image as CoverImageProvider)
              .imageProvider,
          AssetImage(PageStyleCoverImageType.builtInImagePath('n1')),
        );
        view = PageCoverHeight.applyTo(view, 313.5);
        await tester.pumpWidget(app());
        await tester.pump();
        expect(tester.state(find.byType(DesktopCover)), same(state));
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.fit, appearance.boxFit);
        expect(image.alignment, Alignment.topCenter);
        expect(node.attributes, attributes);
        expect(ViewCoverCodec.decodeCover(view.extra), isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
      });
    }

    testWidgets('$theme explicit modern none beats an old node cover',
        (tester) async {
      final editor = EditorState.blank();
      final node = Node(
        type: 'page',
        attributes: {
          DocumentHeaderBlockKeys.coverType: CoverType.asset.toString(),
          DocumentHeaderBlockKeys.coverDetails: 'n1',
        },
      );
      final view = ViewPB(
        id: 'removed-cover',
        layout: ViewLayoutPB.Document,
        extra: PageCoverHeight.merge(
          ViewCoverCodec.mergeCover('', const PageStyleCover.none()),
          200,
        ),
      );
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: theme,
          child: SizedBox(
            width: 600,
            height: 200,
            child: DesktopCover(
              view: view,
              editorState: editor,
              node: node,
              coverType: CoverType.asset,
              coverDetails: 'n1',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(node.attributes[DocumentHeaderBlockKeys.coverDetails], 'n1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    });

    testWidgets(
        '$theme modern renderer follows its supplied cover without extra fetch',
        (tester) async {
      final editor = EditorState.blank();
      final node = Node(type: 'page');
      Widget app(String value) => workspaceOverlayTestApp(
            appearance: theme,
            child: SizedBox(
              width: 600,
              height: 200,
              child: DesktopCover(
                view: ViewPB(
                  id: 'modern-cover',
                  layout: ViewLayoutPB.Document,
                  extra: ViewCoverCodec.mergeCover(
                    '',
                    PageStyleCover(
                      type: PageStyleCoverImageType.builtInImage,
                      value: value,
                    ),
                  ),
                ),
                editorState: editor,
                node: node,
                coverType: CoverType.none,
              ),
            ),
          );
      await tester.pumpWidget(app('n1'));
      await tester.pump();
      final state = tester.state(find.byType(DesktopCover));
      await tester.pumpWidget(app('n2'));
      await tester.pump();
      expect(tester.state(find.byType(DesktopCover)), same(state));
      expect(
        (tester.widget<Image>(find.byType(Image)).image as CoverImageProvider)
            .imageProvider,
        AssetImage(PageStyleCoverImageType.builtInImagePath('n2')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    });
  }
}
