import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/dashboard_widget/dashboard_widget_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// One thing `/` can put into a page, offered somewhere that is not a page.
@immutable
class PageBlockEntry {
  const PageBlockEntry({required this.item, required this.metadata});

  final SelectionMenuItem item;
  final SlashMenuItemMetadata metadata;

  String get name => item.name;

  String? get description => metadata.description;

  SlashMenuSection get section => metadata.section;

  /// Matched the way `/` matches: on the name and the entry's keywords.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return item.allKeywords.any(
      (keyword) => keyword.toLowerCase().contains(needle),
    );
  }

  /// The entry's icon, drawn the way `/` draws it, in [ink].
  Widget icon(EditorState editorState, Color ink) =>
      item.icon(editorState, false, pageBlockIconStyle(ink));
}

/// Everything `/` offers that is worth placing on its own — on a dashboard or
/// a canvas — read from the very list `/` shows.
///
/// So an entry added to `/` tomorrow, built in or by an extension, is offered
/// here too with nothing else to change. Left out are entries that only mean
/// something in a page's flow of text ([SlashMenuItemMetadata.pageOnly]),
/// dashboard widgets (they are offered as themselves), and blocks a dashboard
/// widget already is (its `pageBlock`), which would otherwise appear twice.
List<PageBlockEntry> pageBlockCatalog() {
  final twins = {
    for (final definition in DashboardWidgetRegistry.offered())
      if (definition.pageBlock != null) definition.pageBlock!,
  };
  final seen = <String>{};
  final entries = <PageBlockEntry>[];
  // Without a page there is nothing to create views beneath, so the entries
  // that would (a new grid, a new canvas) are simply not built.
  for (final item in slashMenuItemsBuilder()) {
    final metadata = slashMenuMetadataFor(item);
    if (metadata == null ||
        metadata.pageOnly ||
        metadata.section == SlashMenuSection.widgets ||
        metadata.blockType == DashboardWidgetBlockKeys.type ||
        twins.contains(metadata.blockType)) {
      continue;
    }
    // Some sections are assembled from more than one list; offer each once.
    if (!seen.add('${metadata.section.name}/${item.name}')) continue;
    entries.add(PageBlockEntry(item: item, metadata: metadata));
  }
  return entries;
}

/// What running a `/` entry away from a page came to.
@immutable
class PageBlockRun {
  const PageBlockRun({this.document, this.asked = false});

  /// What the entry inserted, as a document of its own; null when nothing.
  final Map<String, Object?>? document;

  /// The entry asked something first — a picker, a dialog.
  final bool asked;

  /// It asked and came back empty-handed: somebody said no, which is not a
  /// failure worth reporting.
  bool get dismissed => document == null && asked;
}

/// What [entry] puts into a page, as a document of its own.
///
/// The entry runs exactly as `/` runs it, in a scratch page holding only the
/// typed slash, so whatever it inserts is what a page would have received —
/// including entries that ask a question first. The document is null when it
/// inserted nothing that can stand on its own.
Future<PageBlockRun> runPageBlockEntry(
  PageBlockEntry entry,
  BuildContext context, {
  Duration patience = const Duration(minutes: 5),
  Duration grace = const Duration(milliseconds: 600),
}) async {
  final editorState = EditorState(
    document: Document(
      root: pageNode(children: [paragraphNode(text: '/')]),
    ),
  )..selection = Selection.collapsed(Position(path: [0], offset: 1));
  final route = ModalRoute.of(context);
  var asked = false;
  try {
    entry.item.handler(editorState, _ScratchMenuService(), context);
    // Most entries insert at once. One that asks something first — a picker,
    // a dialog — inserts once it is answered, so wait while it is asking and
    // a moment after, but never on an entry that simply inserted nothing.
    final deadline = DateTime.now().add(patience);
    var quietSince = DateTime.now();
    while (!_holdsBlocks(editorState.document) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (route != null && route.isActive && !route.isCurrent) {
        asked = true;
        quietSince = DateTime.now();
        continue;
      }
      if (DateTime.now().difference(quietSince) > grace) break;
    }
    if (!_holdsBlocks(editorState.document)) {
      return PageBlockRun(asked: asked);
    }
    return PageBlockRun(document: _trimmed(editorState.document), asked: asked);
  } on Object {
    return PageBlockRun(asked: asked);
  } finally {
    editorState.dispose();
  }
}

/// Whether [document] holds more than empty lines of text.
bool _holdsBlocks(Document document) => document.root.children.any(
      (node) =>
          node.type != ParagraphBlockKeys.type ||
          (node.delta?.isNotEmpty ?? false) ||
          node.children.isNotEmpty,
    );

/// [document] without the empty lines around what was inserted.
Map<String, Object?> _trimmed(Document document) {
  final children = document.root.children.toList();
  bool empty(Node node) =>
      node.type == ParagraphBlockKeys.type &&
      (node.delta?.isEmpty ?? true) &&
      node.children.isEmpty;
  var start = 0;
  var end = children.length;
  while (start < end && empty(children[start])) {
    start++;
  }
  while (end > start && empty(children[end - 1])) {
    end--;
  }
  final kept = Document(
    root: pageNode(
      children: [
        for (final node in children.sublist(start, end)) node.deepCopy(),
      ],
    ),
  );
  return Map<String, Object?>.from(kept.toJson());
}

/// A `/` entry's icon colours, all in one [ink].
SelectionMenuStyle pageBlockIconStyle(Color ink) => SelectionMenuStyle(
      selectionMenuBackgroundColor: Colors.transparent,
      selectionMenuItemTextColor: ink,
      selectionMenuItemIconColor: ink,
      selectionMenuItemSelectedTextColor: ink,
      selectionMenuItemSelectedIconColor: ink,
      selectionMenuItemSelectedColor: Colors.transparent,
      selectionMenuUnselectedLabelColor: ink,
      selectionMenuDividerColor: Colors.transparent,
      selectionMenuLinkBorderColor: ink,
      selectionMenuInvalidLinkColor: ink,
      selectionMenuButtonColor: ink,
      selectionMenuButtonTextColor: ink,
      selectionMenuButtonIconColor: ink,
      selectionMenuButtonBorderColor: ink,
      selectionMenuTabIndicatorColor: ink,
    );

/// `/` without a menu on screen: there is nothing to dismiss or position.
class _ScratchMenuService implements SelectionMenuService {
  @override
  Offset get offset => Offset.zero;

  @override
  Alignment get alignment => Alignment.topLeft;

  @override
  SelectionMenuStyle get style => SelectionMenuStyle.light;

  @override
  Future<void> show() async {}

  @override
  void dismiss() {}

  @override
  (double? left, double? top, double? right, double? bottom) getPosition() =>
      (0, 0, null, null);
}
