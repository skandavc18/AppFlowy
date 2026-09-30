import 'dart:async';

import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy/workspace/application/view/local_page_store.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/widgets.dart';

/// Cover height reads and writes for a [LocalPageStore] place.
class LocalPageViewBackend extends PageIconBackendService {
  const LocalPageViewBackend(this.store);

  final LocalPageStore store;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> readView(String viewId) async =>
      FlowyResult.success(
        LocalPageStore.viewFor(viewId, await store.read(viewId)),
      );

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateView({
    required String viewId,
    required String extra,
  }) async {
    await store.write(viewId, extra);
    return FlowyResult.success(LocalPageStore.viewFor(viewId, extra));
  }

  @override
  VoidCallback listen({
    required String viewId,
    required ValueChanged<ViewPB> onView,
    required VoidCallback onUnavailable,
  }) =>
      store.listen(
        viewId,
        (extra) => onView(LocalPageStore.viewFor(viewId, extra)),
      );
}

/// The ordinary cover picker and upload, saved into a [LocalPageStore] place.
class LocalPageCoverActionsBackend extends ViewCoverActionsBackend {
  const LocalPageCoverActionsBackend(this.store);

  final LocalPageStore store;

  @override
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) async {
    final String extra;
    try {
      // Merge into what is stored now: the height may have changed meanwhile.
      extra = ViewCoverCodec.mergeCover(await store.read(view.id), cover);
    } on FormatException catch (error) {
      return FlowyResult.failure(FlowyError(msg: error.message));
    }
    await store.write(view.id, extra);
    return FlowyResult.success(null);
  }
}

/// A [LocalPageStore] place as the cover machinery needs it. The backends are
/// kept for as long as the store is, since covers compare them by identity.
@immutable
class LocalPage {
  const LocalPage({
    required this.view,
    required this.heights,
    required this.covers,
  });

  /// The stand-in view: its cover and its cover height.
  final ViewPB view;

  /// For [PageCoverLayout.backend] and `WorkspacePageHeader.coverBackend`.
  final PageCoverBackendService heights;

  /// For [ViewDecorationActions.coverBackend].
  final ViewCoverActionsBackend covers;

  PageStyleCover? get cover {
    final cover = view.cover;
    return cover == null || cover.isNone ? null : cover;
  }
}

/// Rebuilds with [pageId]'s stand-in view as it is read and changed.
class LocalPageBuilder extends StatefulWidget {
  const LocalPageBuilder({
    super.key,
    required this.pageId,
    required this.builder,
    this.store,
  });

  final String pageId;

  /// Null uses [LocalPageStore.instance].
  final LocalPageStore? store;
  final Widget Function(BuildContext context, LocalPage page) builder;

  @override
  State<LocalPageBuilder> createState() => _LocalPageBuilderState();
}

class _LocalPageBuilderState extends State<LocalPageBuilder> {
  LocalPageStore? _store;
  late PageCoverBackendService _heights;
  late ViewCoverActionsBackend _covers;
  late ViewPB _view;
  VoidCallback? _stop;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(LocalPageBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageId != widget.pageId || oldWidget.store != widget.store) {
      _stop?.call();
      _bind();
    }
  }

  void _bind() {
    final store = widget.store ?? LocalPageStore.instance;
    if (!identical(store, _store)) {
      _store = store;
      _heights = PageCoverBackendService(views: LocalPageViewBackend(store));
      _covers = LocalPageCoverActionsBackend(store);
    }
    final id = widget.pageId;
    final known = store.peek(id);
    _view = LocalPageStore.viewFor(id, known ?? '');
    _stop = store.listen(id, _adopt);
    // The first read reports through the listener above.
    if (known == null) unawaited(store.read(id));
  }

  void _adopt(String extra) {
    if (!mounted || _view.extra == extra) return;
    setState(() => _view = LocalPageStore.viewFor(widget.pageId, extra));
  }

  @override
  void dispose() {
    _stop?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        LocalPage(view: _view, heights: _heights, covers: _covers),
      );
}
