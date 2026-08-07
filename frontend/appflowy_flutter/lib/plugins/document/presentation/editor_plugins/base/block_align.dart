import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_equation_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/video/video_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/material.dart';

/// The value stored under [blockComponentAlign] for a justified block.
///
/// The editor package's own align mixin only knows left/center/right, so a
/// justified block reports no box alignment and is expressed through
/// [TextAlign] instead.
const blockComponentAlignJustify = 'justify';

const blockComponentAlignLeft = 'left';
const blockComponentAlignCenter = 'center';
const blockComponentAlignRight = 'right';

/// Blocks that are centred on the page until somebody aligns them by hand.
const _centredBlockTypes = <String>{
  ImageBlockKeys.type,
  CodeBlockKeys.type,
  MathEquationBlockKeys.type,
  PagePreviewBlockKeys.type,
  FolderExplorerBlockKeys.type,
};

/// Where a block sits when it carries no align attribute of its own.
///
/// The align menu ticks whatever this returns, so a block component must lay
/// itself out with [blockEmbedAlignment] rather than a default of its own —
/// otherwise the menu claims an alignment the block is not using.
Alignment defaultBlockAlignment(Node node) {
  if (_centredBlockTypes.contains(node.type)) {
    return Alignment.center;
  }
  if (node.type == FileBlockKeys.type) {
    return fileBlockShowsPreview(node)
        ? Alignment.center
        : Alignment.centerLeft;
  }
  if (node.type == LinkPreviewBlockKeys.type ||
      node.type == VideoBlockKeys.type) {
    return node.attributes[LinkEmbedKeys.previewType] == LinkEmbedKeys.embed
        ? Alignment.center
        : Alignment.centerLeft;
  }
  return Alignment.centerLeft;
}

/// [defaultBlockAlignment] expressed as the attribute value that produces it.
String defaultBlockAlignKey(Node node) {
  final alignment = defaultBlockAlignment(node);
  if (alignment == Alignment.center) {
    return blockComponentAlignCenter;
  }
  if (alignment == Alignment.centerRight) {
    return blockComponentAlignRight;
  }
  return blockComponentAlignLeft;
}

/// Whether a file block renders a preview frame rather than the compact chip.
///
/// It mirrors the branches `FileBlockComponentState.build` chooses between.
bool fileBlockShowsPreview(Node node) {
  final url = node.attributes[FileBlockKeys.url] as String?;
  if (url == null || url.isEmpty) {
    return false;
  }
  if (isYoutubeVideoUrl(url)) {
    return true;
  }
  final name = node.attributes[FileBlockKeys.name] as String?;
  if (fileMediaKind(name, url) != null) {
    return true;
  }
  return node.attributes[FileBlockKeys.displayMode] == 'preview' &&
      name != null &&
      supportsEmbeddedFilePreview(name);
}

/// The box alignment an embedded block (image, file, chart, database…) should
/// be laid out with, read from the block's own align attribute.
Alignment blockEmbedAlignment(Node node) =>
    switch (node.attributes[blockComponentAlign] as String?) {
      blockComponentAlignLeft => Alignment.centerLeft,
      blockComponentAlignCenter => Alignment.center,
      blockComponentAlignRight => Alignment.centerRight,
      _ => defaultBlockAlignment(node),
    };

/// The text alignment a block with text should be set in.
///
/// Only justification is answered here: the editor package's align mixin
/// already turns left/center/right into a box alignment and a matching
/// [TextAlign], and it reports nothing for a justified block.
TextAlign blockTextAlign(Node node, {TextAlign fallback = TextAlign.start}) =>
    node.attributes[blockComponentAlign] == blockComponentAlignJustify
        ? TextAlign.justify
        : fallback;
