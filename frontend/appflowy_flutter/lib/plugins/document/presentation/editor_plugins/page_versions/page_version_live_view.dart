import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_row_opener.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_canvas.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_gallery_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_row_view.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A remembered page, at the size it would be read at.
///
/// Each shape is drawn by the widget that draws the real thing: a page by the
/// editor, a file by the file viewer, a folder by the gallery its cards come
/// from, and a table by the grid — which is the only one that has to be put
/// back into a database first, since a grid cannot read a list of strings.
class PageVersionLiveView extends StatefulWidget {
  const PageVersionLiveView({
    super.key,
    required this.version,
    required this.payload,
    this.interactive = false,
  });

  final PageVersion version;
  final PageVersionPayload payload;

  /// Whether the reader may scroll through it.
  final bool interactive;

  @override
  State<PageVersionLiveView> createState() => _PageVersionLiveViewState();
}

class _PageVersionLiveViewState extends State<PageVersionLiveView> {
  Plugin? _plugin;
  ViewPB? _staged;
  PageVersionRow? _row;
  File? _file;
  bool _ready = false;
  bool _held = false;

  PageVersionShape get _shape => widget.payload.shape;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _plugin?.dispose();
    if (_held) {
      unawaited(PageVersionStage.instance.release(widget.version.id));
    }
    super.dispose();
  }

  Future<void> _open() async {
    switch (_shape) {
      case PageVersionShape.file:
        _file = await PageVersionStore.instance.contentFile(
          widget.version.viewId,
          widget.version.id,
          widget.payload.file?.extension ?? '',
        );
      case PageVersionShape.database:
        await _stageTable();
      case PageVersionShape.board:
        _openBoard();
      default:
        break;
    }
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  /// A canvas and a dashboard keep everything in `extra`, so a made-up view
  /// carrying that draws the whole thing without reading anything else.
  ///
  /// ⚠️ The id is deliberately NOT the page's own: a preview must never be
  /// able to write back over the page it is a record of.
  void _openBoard() {
    final view = ViewPB(
      id: 'page-version-${widget.version.id}',
      name: widget.payload.settings.name,
      layout: ViewLayoutPB.Document,
      extra: widget.payload.settings.extra,
    );
    _plugin = view.plugin()..init();
  }

  Future<void> _stageTable() async {
    if (widget.payload.table?.columns.isEmpty ?? true) {
      return;
    }
    _held = true;
    final view = await PageVersionStage.instance.mount(
      widget.version.id,
      widget.payload,
    );
    if (!mounted || view == null) {
      return;
    }
    _staged = view;
    // ⚠️ A plugin only hands out its blocs after init(), and it must be made
    // once — building one per frame would open a bloc per frame.
    _plugin = view.plugin()..init();
  }

  /// Shows the row a reader clicked, as it was, inside this preview.
  ///
  /// ⚠️ The staged table has rows of its own with fresh ids, so the click is
  /// matched back by POSITION — and what is drawn is the STORED row, never the
  /// staged one, which is a throwaway copy with a page the reader never wrote.
  Future<void> _openStagedRow(String rowId) async {
    final staged = _staged;
    final table = widget.payload.table;
    if (staged == null || table == null) {
      return;
    }
    final rows = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB()..value = staged.id,
    ).send().fold<RepeatedRowTextPB?>((rows) => rows, (_) => null);
    if (!mounted || rows == null) {
      return;
    }
    final index = rows.rows.indexWhere((row) => row.rowId == rowId);
    if (index < 0 || index >= table.rows.length) {
      return;
    }
    setState(() => _row = table.rows[index]);
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    if (row != null) {
      return PageVersionRowView(
        version: widget.version,
        payload: PageVersionPayload(
          shape: PageVersionShape.row,
          settings: widget.payload.settings,
          document: row.document,
          table: PageVersionTable(
            columns: widget.payload.table?.columns ?? const [],
            rows: [row],
          ),
        ),
        interactive: widget.interactive,
        onBack: () => setState(() => _row = null),
      );
    }

    if (_shape == PageVersionShape.document) {
      return PageVersionCanvas(
        viewId: widget.version.viewId,
        versionId: widget.version.id,
        title: widget.version.pageName,
        scale: 1,
        interactive: widget.interactive,
      );
    }

    if (!_ready) {
      return const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }

    return switch (_shape) {
      PageVersionShape.file => _fileView(),
      PageVersionShape.container => PageVersionGalleryView(
          children: widget.payload.children ?? const [],
          onOpen: _openChild,
        ),
      PageVersionShape.row => PageVersionRowView(
          version: widget.version,
          payload: widget.payload,
          interactive: widget.interactive,
        ),
      PageVersionShape.database || PageVersionShape.board => _pluginView(),
      _ => const SizedBox.shrink(),
    };
  }

  /// A folder version keeps what was in it, not what each of those held, so
  /// its items open the page itself rather than a record of it.
  void _openChild(PageVersionChild child) {
    if (child.id.isEmpty) {
      return;
    }
    unawaited(_openPage(child.id));
  }

  Future<void> _openPage(String viewId) async {
    final view = await PageVersionService.instance.readView(viewId);
    if (!mounted) {
      return;
    }
    if (view == null) {
      showToastNotification(
        message: LocaleKeys.pageVersions_childGone.tr(),
        type: ToastificationType.warning,
      );
      return;
    }
    unawaited(Navigator.of(context).maybePop());
    getIt<TabsBloc>().add(
      TabsEvent.openPlugin(plugin: view.plugin(), view: view),
    );
  }

  Widget _fileView() {
    final file = _file;
    if (file == null) {
      return _note(LocaleKeys.pageVersions_fileNotKept.tr());
    }
    return WorkspaceFileView(
      key: ValueKey(file.path),
      view: pageVersionFileView(widget.payload, file.path),
    );
  }

  Widget _pluginView() {
    final plugin = _plugin;
    if (plugin == null) {
      return _note(LocaleKeys.pageVersions_unavailable.tr());
    }
    final builder = plugin.widgetBuilder;
    return FocusScope(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      // A row clicked in here is a record, so it opens inside this preview
      // rather than in a dialog of the live table's own.
      child: Provider<DatabaseRowOpener?>.value(
        value: DatabaseRowOpener(
          (rowId) => unawaited(_openStagedRow(rowId)),
        ),
        child: Padding(
          padding: builder.contentPadding,
          child: builder.buildWidget(
            context: PluginContext(),
            shrinkWrap: false,
          ),
        ),
      ),
    );
  }

  Widget _note(String message) {
    final palette = tableViewPaletteOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: palette.textMuted),
        ),
      ),
    );
  }
}

/// The view a remembered file would have had, pointing at the stored copy.
ViewPB pageVersionFileView(PageVersionPayload payload, String path) {
  final file = payload.file;
  return ViewPB(
    id: 'page-version-file',
    name: file?.name ?? payload.settings.name,
    layout: ViewLayoutPB.Document,
    extra: WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.binary,
      storageUrl: path,
      size: file?.bytes ?? 0,
    ).mergeIntoExtra(payload.settings.extra),
  );
}
