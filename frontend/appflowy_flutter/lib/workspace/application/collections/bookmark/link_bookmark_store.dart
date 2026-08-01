import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:path/path.dart' as p;

/// Where a link that lives in a document keeps what has been said about it.
///
/// A bookmark inside a library is a workspace view, so the folder backend
/// stores its notes and tags. A link written into a page is not a view, and
/// it still deserves the same reading surface — so its envelope is kept beside
/// the offline copy the reader already writes for that address.
class LinkBookmarkStore {
  const LinkBookmarkStore({this.snapshots});

  static const fileName = 'bookmark.json';

  final BookmarkSnapshotStore? snapshots;

  BookmarkSnapshotStore get _snapshots =>
      snapshots ?? BookmarkSnapshotStore.instance;

  /// An identifier for [url] that survives a restart.
  static String idFor(String url) => 'link::${url.hashCode}';

  Future<File> _fileFor(String url) async {
    final directory = await _snapshots.directoryFor(url);
    return File(p.join(directory.path, fileName));
  }

  /// Reads the saved link at [url], or a fresh one if it has never been read.
  Future<ViewPB> load(String url, {String? title}) async {
    final view = ViewPB()
      ..id = idFor(url)
      ..name = title?.trim().isNotEmpty == true
          ? title!.trim()
          : (bookmarkHost(url) ?? untitledBookmarkName)
      ..layout = ViewLayoutPB.Document
      ..extra = BookmarkMetadata.newExtra(url);
    try {
      final file = await _fileFor(url);
      if (!file.existsSync()) {
        return view;
      }
      final record = jsonDecode(await file.readAsString());
      if (record is! Map) {
        return view;
      }
      final name = record['name'];
      final extra = record['extra'];
      if (name is String && name.isNotEmpty) {
        view.name = name;
      }
      if (extra is String && extra.isNotEmpty) {
        view.extra = extra;
      }
    } on Object catch (error) {
      Log.warn('Could not read the saved link for $url: $error');
    }
    return view;
  }

  Future<void> save(String url, ViewPB view) async {
    try {
      final file = await _fileFor(url);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'name': view.name, 'extra': view.extra}),
      );
    } on Object catch (error) {
      Log.warn('Could not keep the saved link for $url: $error');
    }
  }
}

/// Persists a document link's bookmark envelope on disk instead of the folder
/// backend, so the reader behaves identically without creating a view.
class LinkBookmarkService extends BookmarkService {
  const LinkBookmarkService({
    required this.url,
    this.store = const LinkBookmarkStore(),
  });

  final String url;
  final LinkBookmarkStore store;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required BookmarkMetadata metadata,
  }) async {
    final next = ViewPB()
      ..mergeFromMessage(view)
      ..extra = metadata.mergeIntoExtra(view.extra);
    await store.save(url, next);
    return FlowyResult.success(next);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    final view = await store.load(url)
      ..name = name;
    await store.save(url, view);
    return FlowyResult.success(view);
  }

  @override
  Future<FlowyResult<void, FlowyError>> delete(List<String> viewIds) async =>
      FlowyResult.success(null);
}
