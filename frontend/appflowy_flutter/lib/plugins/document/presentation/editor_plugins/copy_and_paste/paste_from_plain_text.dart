import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/paste_as/paste_as_menu.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/shared/patterns/common_patterns.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:universal_platform/universal_platform.dart';

extension PasteFromPlainText on EditorState {
  Future<void> pastePlainText(String plainText) async {
    await deleteSelectionIfNeeded();
    final nodes = plainText
        .split('\n')
        .map(
          (e) => e
            ..replaceAll(r'\r', '')
            ..trimRight(),
        )
        .map((e) => Delta()..insert(e))
        .map((e) => paragraphNode(delta: e))
        .toList();
    if (nodes.isEmpty) {
      return;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await pasteMultiLineNodes(nodes.toList());
    }
  }

  Future<void> pasteText(String plainText) async {
    if (await pasteHtmlIfAvailable(plainText)) {
      return;
    }

    await deleteSelectionIfNeeded();

    /// try to parse the plain text as markdown
    final nodes = customMarkdownToDocument(plainText).root.children;
    if (nodes.isEmpty) {
      /// if the markdown parser failed, fallback to the plain text parser
      await pastePlainText(plainText);
      return;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
      checkToShowPasteAsMenu(nodes.first);
    } else {
      await pasteMultiLineNodes(nodes.toList());
    }
  }

  Future<bool> pasteHtmlIfAvailable(String plainText) async {
    final selection = this.selection;
    if (selection == null ||
        !selection.isSingle ||
        selection.isCollapsed ||
        !hrefRegex.hasMatch(plainText)) {
      return false;
    }

    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return false;
    }

    final transaction = this.transaction;
    transaction.formatText(node, selection.startIndex, selection.length, {
      AppFlowyRichTextKeys.href: plainText,
    });
    await apply(transaction);
    checkToShowPasteAsMenu(node);
    return true;
  }

  void checkToShowPasteAsMenu(Node node) {
    if (selection == null || !selection!.isCollapsed) return;
    if (UniversalPlatform.isMobile) return;
    final link = pastedLinkOf(node);
    if (link != null) {
      final context = document.root.context;
      if (context != null && context.mounted) {
        PasteAsMenuService(context: context, editorState: this).show(
          link.href,
          length: link.text.length,
        );
      }
    }
  }
}

/// The one link [node] holds, as the words it shows and the address it
/// points at, or null when the node holds anything else.
///
/// The two differ when a browser copies an address together with its page's
/// title, or when markdown names a link: the address is what an embed shows,
/// and the words are what the paste left before the caret.
({String text, String href})? pastedLinkOf(Node node) {
  final delta = node.delta;
  if (delta == null) return null;
  final inserts = delta.whereType<TextInsert>().toList();
  if (inserts.length != 1) return null;
  final href = inserts.first.attributes?.href;
  if (href == null || href.isEmpty) return null;
  return (text: inserts.first.text, href: href);
}
