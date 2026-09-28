import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/shared/find_replace/surface_find_highlight.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

/// Identity of the view used to produce a displayed thumbnail. Capture scalar
/// values, not a mutable protobuf or a copied source name from dashboard config.
typedef FolderGalleryFindViewToken = (String, int, String, String, String);

FolderGalleryFindViewToken folderGalleryFindViewToken(ViewPB view) => (
      view.id,
      view.layout.value,
      view.name,
      view.extra,
      view.lastEdited.toString(),
    );

/// Renderer-owned, already-loaded preview. This is not a request to load its
/// target, nor permission to index every block in [preview]. Only mounted
/// [FolderGalleryFindText] descendants lend their native paragraphs to Find.
/// Covers, loading/error faces, identity captions and footer titles are outside
/// this boundary. The consumer must authorize this exact view/snapshot first.
class FolderGalleryFindScope extends InheritedWidget {
  FolderGalleryFindScope({
    super.key,
    required ViewPB view,
    required this.preview,
    required super.child,
  }) : viewToken = folderGalleryFindViewToken(view);

  final FolderGalleryFindViewToken viewToken;
  final FolderGalleryPreview preview;
  Object get snapshotToken => (viewToken, preview);

  @override
  InheritedElement createElement() => _FolderGalleryFindElement(this);

  @override
  bool updateShouldNotify(FolderGalleryFindScope oldWidget) =>
      snapshotToken != oldWidget.snapshotToken;
}

/// A typed displayed body value, never a toolbar, count, icon or URL field.
/// [text] is the exact string handed to the real Text/RichText renderer, not
/// an export of the full target. Find verifies it against the native paragraph.
class FolderGalleryFindText extends SingleChildRenderObjectWidget {
  const FolderGalleryFindText({
    super.key,
    required this.text,
    required super.child,
    this.enabled = true,
    this.contentStart = 0,
  });

  final String text;
  final bool enabled;

  /// Native UTF-16 prefix occupied by a decorative glyph rather than content.
  final int contentStart;

  @override
  RenderFolderGalleryFindText createRenderObject(BuildContext context) =>
      RenderFolderGalleryFindText(text, enabled, contentStart);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFolderGalleryFindText renderObject,
  ) {
    renderObject
      ..text = text
      ..enabled = enabled
      ..contentStart = contentStart;
  }
}

class RenderFolderGalleryFindText extends RenderProxyBox {
  RenderFolderGalleryFindText(this.text, this.enabled, this.contentStart);
  String text;
  bool enabled;
  int contentStart;
}

class _FolderGalleryFindElement extends InheritedElement {
  _FolderGalleryFindElement(FolderGalleryFindScope super.widget);

  RenderSurfaceFindHighlight? _owner;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _owner = findAncestorRenderObjectOfType<RenderSurfaceFindHighlight>();
    _owner?.contentChanged();
  }

  @override
  void update(covariant FolderGalleryFindScope newWidget) {
    final previous = widget as FolderGalleryFindScope;
    super.update(newWidget);
    if (previous.snapshotToken != newWidget.snapshotToken)
      _owner?.contentChanged();
  }

  @override
  void unmount() {
    _owner?.contentChanged();
    _owner = null;
    super.unmount();
  }
}
