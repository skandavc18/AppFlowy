import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';

/// Making, unmaking and copying a canvas. One place, so the envelope is never
/// written by hand anywhere else.
abstract final class CanvasService {
  static Future<ViewPB?> create({
    required String parentViewId,
    String? name,
    ViewSectionPB? section,
    CanvasDocument? document,
  }) async {
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: name ?? LocaleKeys.canvas_defaultName.tr(),
      section: section,
      extra: CanvasMetadata.newExtra(document: document),
    );
    return created.fold((view) => view, (_) => null);
  }

  /// Turn an ordinary page into a canvas. The page's own document is left
  /// alone: reverting brings it back exactly as it was.
  static Future<bool> convert(ViewPB view) async {
    if (view.layout != ViewLayoutPB.Document || view.isCanvas) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: CanvasMetadata(document: CanvasDocument.blank())
          .mergeIntoExtra(view.extra),
    );
    return result.fold((_) => true, (_) => false);
  }

  static Future<bool> revert(ViewPB view) async {
    if (!view.isCanvas) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: CanvasMetadata.removeFromExtra(view.extra),
    );
    return result.fold((_) => true, (_) => false);
  }

  /// Read a canvas without opening it — what an embedded canvas and a canvas
  /// card both need.
  static Future<CanvasDocument?> read(String viewId) async {
    if (viewId.isEmpty) {
      return null;
    }
    final result = await ViewBackendService.getView(viewId);
    return result.fold((view) => view.canvas?.document, (_) => null);
  }
}
