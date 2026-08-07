import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_equation_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Node _file({
  String? url,
  String? name,
  String displayMode = 'preview',
  String? align,
}) =>
    Node(
      type: FileBlockKeys.type,
      attributes: {
        if (url != null) FileBlockKeys.url: url,
        if (name != null) FileBlockKeys.name: name,
        FileBlockKeys.displayMode: displayMode,
        if (align != null) blockComponentAlign: align,
      },
    );

void main() {
  group('default block alignment', () {
    test('text starts against the leading edge', () {
      expect(
        defaultBlockAlignment(paragraphNode()),
        Alignment.centerLeft,
      );
    });

    test('a picture and an equation are centred', () {
      expect(
        defaultBlockAlignment(Node(type: ImageBlockKeys.type)),
        Alignment.center,
      );
      expect(
        defaultBlockAlignment(Node(type: MathEquationBlockKeys.type)),
        Alignment.center,
      );
      expect(
        defaultBlockAlignment(Node(type: PagePreviewBlockKeys.type)),
        Alignment.center,
      );
    });

    test('a file preview is centred but the compact chip is not', () {
      expect(
        defaultBlockAlignment(
          _file(url: 'file:///docs/report.pdf', name: 'report.pdf'),
        ),
        Alignment.center,
      );
      expect(
        defaultBlockAlignment(
          _file(url: 'file:///docs/notes.bin', name: 'notes.bin'),
        ),
        Alignment.centerLeft,
      );
      expect(defaultBlockAlignment(_file()), Alignment.centerLeft);
    });

    test('a link renders as a card until it is embedded', () {
      expect(
        defaultBlockAlignment(Node(type: LinkPreviewBlockKeys.type)),
        Alignment.centerLeft,
      );
      expect(
        defaultBlockAlignment(linkEmbedNode(url: 'https://example.com')),
        Alignment.center,
      );
    });

    test('a chosen alignment wins over the default', () {
      final centred = _file(
        url: 'file:///docs/notes.bin',
        name: 'notes.bin',
        align: blockComponentAlignCenter,
      );
      expect(blockEmbedAlignment(centred), Alignment.center);
      expect(
        blockEmbedAlignment(
          _file(url: 'file:///docs/report.pdf', name: 'report.pdf'),
        ),
        Alignment.center,
      );
    });

    test('the key the menu ticks matches the layout', () {
      expect(defaultBlockAlignKey(paragraphNode()), blockComponentAlignLeft);
      expect(
        defaultBlockAlignKey(
          _file(url: 'file:///docs/report.pdf', name: 'report.pdf'),
        ),
        blockComponentAlignCenter,
      );
    });
  });

  group('justification', () {
    test('only a justified block changes the text alignment', () {
      expect(blockTextAlign(paragraphNode()), TextAlign.start);
      expect(
        blockTextAlign(
          paragraphNode()
            ..updateAttributes({
              blockComponentAlign: blockComponentAlignCenter,
            }),
        ),
        TextAlign.start,
      );
      expect(
        blockTextAlign(
          paragraphNode()
            ..updateAttributes({
              blockComponentAlign: blockComponentAlignJustify,
            }),
        ),
        TextAlign.justify,
      );
    });
  });
}
