import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';

/// Which library a gallery shows. Only the meaning of "when" differs:
/// last viewed, favorited, or (for every page in the Library) last edited.
enum ViewLibrary { recents, favorites, all }

/// What kind of page a view is, in words a reader uses.
String viewGalleryKindLabel(ViewPB view) {
  if (view.isCollection) return LocaleKeys.viewLibrary_kind_collection.tr();
  if (view.isWorkspaceFolder) return LocaleKeys.viewLibrary_kind_folder.tr();
  if (view.isWorkspaceFile) return LocaleKeys.viewLibrary_kind_file.tr();
  if (view.isDashboard) return LocaleKeys.viewLibrary_kind_dashboard.tr();
  if (view.isCanvas) return LocaleKeys.viewLibrary_kind_canvas.tr();
  return switch (view.layout) {
    ViewLayoutPB.Grid => LocaleKeys.viewLibrary_kind_table.tr(),
    ViewLayoutPB.Board => LocaleKeys.viewLibrary_kind_board.tr(),
    ViewLayoutPB.Calendar => LocaleKeys.viewLibrary_kind_calendar.tr(),
    ViewLayoutPB.Chat => LocaleKeys.viewLibrary_kind_chat.tr(),
    _ => LocaleKeys.viewLibrary_kind_page.tr(),
  };
}

String viewGalleryPeriodLabel(ViewGalleryPeriod period) => switch (period) {
      ViewGalleryPeriod.today => LocaleKeys.viewLibrary_period_today.tr(),
      ViewGalleryPeriod.yesterday =>
        LocaleKeys.viewLibrary_period_yesterday.tr(),
      ViewGalleryPeriod.thisWeek => LocaleKeys.viewLibrary_period_thisWeek.tr(),
      ViewGalleryPeriod.thisMonth =>
        LocaleKeys.viewLibrary_period_thisMonth.tr(),
      ViewGalleryPeriod.earlier => LocaleKeys.viewLibrary_period_earlier.tr(),
    };

/// "just now", "5m ago", "3h ago", "2d ago", then a plain date.
String viewGalleryAgo(DateTime at, DateTime now) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return LocaleKeys.viewLibrary_justNow.tr();
  if (gap.inHours < 1) {
    return LocaleKeys.viewLibrary_minutesAgo.tr(args: ['${gap.inMinutes}']);
  }
  if (gap.inDays < 1) {
    return LocaleKeys.viewLibrary_hoursAgo.tr(args: ['${gap.inHours}']);
  }
  if (gap.inDays < 7) {
    return LocaleKeys.viewLibrary_daysAgo.tr(args: ['${gap.inDays}']);
  }
  return DateFormat.yMMMd().format(at);
}

DateTime? _seconds(Int64 value) {
  final seconds = value.toInt();
  return seconds <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

/// The readable facts of every page in one library at one moment.
class ViewGalleryFacts {
  const ViewGalleryFacts({
    required this.library,
    required this.now,
    required this.locationOf,
  });

  final ViewLibrary library;
  final DateTime now;
  final String Function(ViewPB view) locationOf;

  String get whenLabel => switch (library) {
        ViewLibrary.recents => LocaleKeys.viewLibrary_column_viewed.tr(),
        ViewLibrary.favorites => LocaleKeys.viewLibrary_column_favorited.tr(),
        ViewLibrary.all => LocaleKeys.viewLibrary_column_edited.tr(),
      };

  DateTime? timeOf(ViewGalleryEntry entry, String column) => switch (column) {
        ViewGalleryColumns.when => entry.at,
        ViewGalleryColumns.edited => _seconds(entry.view.lastEdited),
        ViewGalleryColumns.created => _seconds(entry.view.createTime),
        _ => null,
      };

  String valueOf(ViewGalleryEntry entry, String column) {
    if (ViewGalleryColumns.isTime(column)) {
      final at = timeOf(entry, column);
      return at == null
          ? ''
          : viewGalleryPeriodLabel(viewGalleryPeriodOf(at, now));
    }
    return switch (column) {
      ViewGalleryColumns.name => entry.view.nameOrDefault,
      ViewGalleryColumns.kind => viewGalleryKindLabel(entry.view),
      ViewGalleryColumns.location => locationOf(entry.view),
      ViewGalleryColumns.pinned =>
        entry.pinned ? LocaleKeys.viewLibrary_column_pinned.tr() : '',
      _ => '',
    };
  }

  /// The quiet line under a title: "Viewed 5m ago" or "Favorited 2d ago".
  String captionOf(ViewGalleryEntry entry) {
    final at = entry.at;
    if (at != null) {
      final ago = viewGalleryAgo(at, now);
      return switch (library) {
        ViewLibrary.recents => LocaleKeys.viewLibrary_viewedAgo.tr(args: [ago]),
        ViewLibrary.favorites =>
          LocaleKeys.viewLibrary_favoritedAgo.tr(args: [ago]),
        ViewLibrary.all => LocaleKeys.viewLibrary_editedAgo.tr(args: [ago]),
      };
    }
    final edited = _seconds(entry.view.lastEdited);
    return edited == null
        ? ''
        : LocaleKeys.viewLibrary_editedAgo
            .tr(args: [viewGalleryAgo(edited, now)]);
  }

  /// "Page · Projects": what it is and where it lives.
  String detailsOf(ViewGalleryEntry entry) => [
        viewGalleryKindLabel(entry.view),
        locationOf(entry.view),
      ].where((part) => part.trim().isNotEmpty).join(' · ');
}
