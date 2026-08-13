import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';

/// Creating a dashboard, and turning a page into one.
///
/// A dashboard is a document view wearing the dashboard envelope, so both of
/// these are one `updateView` — nothing is copied, nothing is lost, and a
/// dashboard can be turned back into an ordinary page.
abstract final class DashboardService {
  /// Create a dashboard under [parentViewId].
  static Future<ViewPB?> create({
    required String parentViewId,
    String? name,
    ViewSectionPB? section,
    DashboardDocument? document,
  }) async {
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: name ?? LocaleKeys.dashboard_defaultName.tr(),
      section: section,
      extra: DashboardMetadata.newExtra(document: document),
    );
    return created.fold((view) => view, (_) => null);
  }

  /// Turn an existing page into a dashboard, keeping its cover, its icon and
  /// anything else already marked on it.
  ///
  /// The page's own body is untouched — it is still there if the dashboard is
  /// turned back off.
  static Future<bool> convert(ViewPB view) async {
    if (view.layout != ViewLayoutPB.Document || view.isDashboard) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: DashboardMetadata(document: DashboardDocument.blank())
          .mergeIntoExtra(view.extra),
    );
    return result.fold((_) => true, (_) => false);
  }

  /// Turn a dashboard back into an ordinary page.
  ///
  /// The arrangement is deliberately thrown away rather than kept invisibly:
  /// a page that silently remembers a dashboard nobody can see is worse than
  /// one that starts again.
  static Future<bool> revert(ViewPB view) async {
    if (!view.isDashboard) {
      return false;
    }
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: DashboardMetadata.removeFromExtra(view.extra),
    );
    return result.fold((_) => true, (_) => false);
  }
}
