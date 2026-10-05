import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_preview.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_preview_face.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_preview.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/deferred_code_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_text_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_thumbnail_cache.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_preview/view_preview_scope.dart';
import 'package:appflowy/workspace/presentation/widgets/view_preview/view_preview_table.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';

import 'search_layout.dart';
import 'content_search_widgets.dart';

class PagePreview extends StatelessWidget {
  const PagePreview({
    super.key,
    required this.view,
    required this.onViewOpened,
    this.query,
    this.matchingSnippet,
    this.contentSearch = false,
  });
  final ViewPB view;
  final VoidCallback onViewOpened;
  final String? query;
  final String? matchingSnippet;
  final bool contentSearch;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    if (contentSearch) {
      // Only already-authorized text enters this path. Do not mount the normal
      // cover/editor/database/file previews: they can read or fetch again.
      return CommandPalettePreviewSurface(
        key: const ValueKey('page-preview-card'),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildIcon(theme, view, false),
              const HSpace(WorkspaceTokens.space3),
              Expanded(child: buildTitle(context, view)),
            ],
          ),
        ),
        child: SearchMatchContext(
          query: query ?? '',
          snippet: matchingSnippet ?? '',
        ),
      );
    }
    // A dashboard's preview is its whole page, cover included.
    final cover = _dashboardOf(view) == null ? _buildCover(context) : null;
    return CommandPalettePreviewSurface(
      key: const ValueKey('page-preview-card'),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (view.icon.value.isNotEmpty || cover == null) ...[
                  SizedBox.square(
                    dimension: 28,
                    child: Center(
                      child: buildIcon(theme, view, cover != null),
                    ),
                  ),
                  const HSpace(WorkspaceTokens.space3),
                ],
                Expanded(child: buildTitle(context, view)),
              ],
            ),
            if (cover != null)
              Padding(
                padding: const EdgeInsets.only(top: WorkspaceTokens.space4),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(WorkspaceTokens.cardRadius),
                  child: cover,
                ),
              ),
          ],
        ),
      ),
      child: _buildPageContent(context),
    );
  }

  static DashboardMetadata? _dashboardOf(ViewPB view) =>
      view.layout == ViewLayoutPB.Document ? view.dashboard : null;

  Widget _buildPageContent(BuildContext context) {
    // A saved link is stored as a file with no bytes; what it has to show is
    // what was learned about its page.
    final link = view.bookmark;
    if (link != null) {
      return Padding(
        key: ValueKey('bookmark-preview-${view.id}'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WorkspaceTokens.cardRadius),
          child: BookmarkPreviewFace(
            entry: BookmarkEntry(view: view, metadata: link),
          ),
        ),
      );
    }
    // A workspace file is stored as a document holding one attachment, so the
    // document renderer would only ever show that block's chip.
    if (view.isWorkspaceFile) {
      return _WorkspaceFilePreview(
        key: ValueKey('file-preview-${view.id}'),
        view: view,
      );
    }
    // A dashboard and a canvas are document pages whose whole content lives in
    // the view's own settings; their document holds nothing to preview.
    final document = view.layout == ViewLayoutPB.Document;
    final dashboard = _dashboardOf(view);
    if (dashboard != null) {
      final palette = WorkspacePalette.of(context);
      final radius = BorderRadius.circular(WorkspaceTokens.cardRadius);
      // The page drawn small, as one card lined up with the title above.
      return Padding(
        key: ValueKey('dashboard-preview-${view.id}'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: palette.border),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: DashboardLivePreview(
              document: dashboard.document,
              view: view,
              userProfile:
                  context.read<UserWorkspaceBloc?>()?.state.userProfile,
            ),
          ),
        ),
      );
    }
    final canvas = document ? view.canvas : null;
    if (canvas != null) {
      return CanvasLivePreview(
        key: ValueKey('canvas-preview-${view.id}'),
        document: canvas.document,
      );
    }
    // A folder (the workspace itself included) or a collection is what it
    // holds; its own document has nothing to show.
    if (view.isWorkspaceFolder || view.isCollection) {
      return Padding(
        key: ValueKey('folder-preview-${view.id}'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WorkspaceTokens.cardRadius),
          child: FolderGalleryCollectionArtwork(
            item: WorkspaceExplorerItem.fromView(view),
            view: view,
          ),
        ),
      );
    }
    if (view.layout.isDocumentView) {
      return _DocumentPagePreview(
        key: ValueKey('document-preview-${view.id}'),
        view: view,
      );
    }
    if (view.layout.isDatabaseView) {
      return _DatabasePagePreview(
        key: ValueKey('database-preview-${view.id}'),
        view: view,
      );
    }
    return const _PreviewError();
  }

  /// The page's own saved cover, exactly as its gallery card shows it.
  Widget? _buildCover(BuildContext context) {
    final cover = view.cover;
    if (cover == null || cover.isNone) return null;
    return ViewCoverImage(
      cover: cover,
      userProfile: context.read<UserWorkspaceBloc?>()?.state.userProfile,
      width: double.infinity,
      height: 96,
    );
  }

  Widget buildIcon(AppFlowyThemeData theme, ViewPB view, bool hasCover) {
    final hasIcon = view.icon.value.isNotEmpty;
    if (!hasIcon && hasCover) return const SizedBox.shrink();
    if (hasIcon) {
      return RawEmojiIconWidget(
        emoji: view.icon.toEmojiIconData(),
        emojiSize: 16.0,
        lineHeight: 20 / 16,
      );
    }
    if (view.isWorkspaceItem) {
      return WorkspaceItemIcon.fromView(view: view, size: 20);
    }
    return WorkspaceGlyph.svg(
      view.iconData,
      size: 20,
      color: theme.iconColorScheme.secondary,
    );
  }

  Widget buildTitle(BuildContext context, ViewPB view) {
    final palette = WorkspacePalette.of(context);
    return Tooltip(
      message: '${view.nameOrDefault} · ${LocaleKeys.settings_files_open.tr()}',
      child: TextButton(
        onPressed: onViewOpened,
        style: TextButton.styleFrom(
          foregroundColor: palette.primaryText,
          alignment: AlignmentDirectional.centerStart,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
          ),
        ).copyWith(
          animationDuration:
              WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                view.nameOrDefault,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.section,
                ),
              ),
            ),
            const HSpace(WorkspaceTokens.space2),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: WorkspaceGlyph(
                Icons.open_in_new_rounded,
                size: 16,
                color: palette.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentPagePreview extends StatefulWidget {
  const _DocumentPagePreview({
    required this.view,
    super.key,
  });

  final ViewPB view;

  @override
  State<_DocumentPagePreview> createState() => _DocumentPagePreviewState();
}

class _DocumentPagePreviewState extends State<_DocumentPagePreview> {
  static const double _canvasWidth = 520;
  static const double _lineHeight = 1.4;

  EditorState? editorState;
  DocumentDataPB? data;
  List<FolderGalleryPreviewBlock>? textBlocks;
  bool isLoading = true;
  bool hasError = false;
  bool blank = false;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDocument());
  }

  @override
  void didUpdateWidget(covariant _DocumentPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id) {
      unawaited(_loadDocument());
    }
  }

  @override
  void dispose() {
    requestId++;
    editorState?.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    final currentRequestId = ++requestId;
    final previousEditorState = editorState;
    editorState = null;
    previousEditorState?.dispose();

    if (mounted && !isLoading) {
      setState(() {
        isLoading = true;
        hasError = false;
      });
    }

    final viewId = widget.view.id;
    // The host's reader when it has one: the palette reads every preview
    // through the same reader as its search.
    final reads = ViewPreviewScope.maybeOf(context);
    DocumentDataPB? data;
    try {
      data = await (reads ?? ViewPreviewReads.native()).document(viewId);
    } on Object catch (error) {
      Log.warn('Unable to load search preview for $viewId: $error');
    }
    final document = data?.toDocument();

    if (!mounted || currentRequestId != requestId) {
      return;
    }

    if (data == null) {
      Log.warn('Unable to load search preview for $viewId');
    } else if (document == null) {
      Log.warn('Search preview document is invalid: $viewId');
    }
    setState(() {
      this.data = document == null ? null : data;
      textBlocks = null;
      editorState = document == null ? null : EditorState(document: document);
      blank = document != null && _isBlank(document);
      hasError = document == null;
      isLoading = false;
    });
  }

  static const _textTypes = {
    ParagraphBlockKeys.type,
    HeadingBlockKeys.type,
    BulletedListBlockKeys.type,
    NumberedListBlockKeys.type,
    TodoListBlockKeys.type,
    QuoteBlockKeys.type,
  };

  /// Nothing but empty lines of text: a page nobody has written in yet.
  static bool _isBlank(Document document) => document.root.children.every(
        (node) =>
            _textTypes.contains(node.type) &&
            node.children.isEmpty &&
            (node.delta?.toPlainText().trim().isEmpty ?? true),
      );

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _PreviewFadeIn(
        key: ValueKey('document-preview-loading'),
        delay: _spinnerDelay,
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final editorState = this.editorState;
    if (hasError || editorState == null) {
      return _PreviewFadeIn(
        key: const ValueKey('document-preview-error'),
        child: _PreviewError(onRetry: () => unawaited(_loadDocument())),
      );
    }
    if (blank) {
      return _PreviewFadeIn(
        child: BoardPreviewEmptyNote(
          key: const ValueKey('document-preview-empty'),
          icon: Icons.article_rounded,
          message: LocaleKeys.viewLibrary_emptyPage.tr(),
        ),
      );
    }

    // The miniature editor needs the app's appearance. A host without it
    // still shows what the page says, as its gallery card does.
    final data = this.data;
    if (data != null &&
        (context.read<AppearanceSettingsCubit?>() == null ||
            context.read<DocumentAppearanceCubit?>() == null)) {
      final blocks = textBlocks ??= FolderGalleryPreviewParser.parse(
        view: widget.view,
        item: WorkspaceExplorerItem.fromView(widget.view),
        document: data,
      ).blocks;
      return _PreviewFadeIn(
        key: const ValueKey('document-preview-ready'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: FolderGalleryRichTextPreview(blocks: blocks),
        ),
      );
    }

    return _PreviewFadeIn(
      key: const ValueKey('document-preview-ready'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }

          final scale = constraints.maxWidth / _canvasWidth;
          final canvasHeight = constraints.maxHeight / scale;
          final styleCustomizer = EditorStyleCustomizer(
            context: context,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            width: _canvasWidth,
            editorState: editorState,
          );
          final baseEditorStyle = styleCustomizer.style();
          final editorStyle = baseEditorStyle.copyWith(
            cursorColor: Colors.transparent,
            cursorWidth: 0,
            textStyleConfiguration: baseEditorStyle.textStyleConfiguration
                .copyWith(lineHeight: _lineHeight),
          );
          final blockBuilders = buildBlockComponentBuilders(
            context: context,
            editorState: editorState,
            styleCustomizer: styleCustomizer,
            editable: false,
            customPadding: (node) => node.type == HeadingBlockKeys.type
                ? const EdgeInsets.only(top: 6, bottom: 2)
                : EdgeInsets.zero,
            alwaysDistributeSimpleTableColumnWidths: true,
          );

          return ClipRect(
            child: FittedBox(
              key: const ValueKey('document-preview-canvas'),
              alignment: Alignment.topLeft,
              fit: BoxFit.fill,
              child: SizedBox(
                width: _canvasWidth,
                height: canvasHeight,
                child: AppFlowyEditor(
                  editorState: editorState,
                  editorStyle: editorStyle,
                  blockComponentBuilders: blockBuilders,
                  contextMenuItems: const [],
                  disableSelectionService: true,
                  disableKeyboardService: true,
                  disableAutoScroll: true,
                  editable: false,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A table's preview, drawn by the same renderer as its gallery card.
class _DatabasePagePreview extends StatefulWidget {
  const _DatabasePagePreview({
    required this.view,
    super.key,
  });

  final ViewPB view;

  @override
  State<_DatabasePagePreview> createState() => _DatabasePagePreviewState();
}

class _DatabasePagePreviewState extends State<_DatabasePagePreview> {
  /// Only for a host without a [ViewPreviewScope]; dropped with this preview.
  ViewPreviewReads? _ownReads;
  late Future<FolderGalleryPreview> _table = _read();

  Future<FolderGalleryPreview> _read({bool reload = false}) {
    final reads = ViewPreviewScope.maybeOf(context) ??
        (_ownReads ??= ViewPreviewReads.native());
    return reads.table(widget.view, reload: reload);
  }

  @override
  void didUpdateWidget(covariant _DatabasePagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id) {
      _table = _read();
    }
  }

  @override
  void dispose() {
    _ownReads?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FolderGalleryPreview>(
      future: _table,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PreviewFadeIn(
            key: ValueKey('database-preview-loading'),
            delay: _spinnerDelay,
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final preview = snapshot.data;
        final database = preview?.database;
        if (snapshot.hasError ||
            preview == null ||
            preview.unavailable ||
            database == null ||
            (database.totalRowCount > 0 &&
                (database.columns.isEmpty || database.rows.isEmpty))) {
          return _PreviewFadeIn(
            key: const ValueKey('database-preview-error'),
            child: _PreviewError(
              onRetry: () => setState(() => _table = _read(reload: true)),
            ),
          );
        }
        if (database.rows.isEmpty) {
          return _PreviewFadeIn(
            child: BoardPreviewEmptyNote(
              key: const ValueKey('database-preview-empty'),
              icon: Icons.table_chart_rounded,
              message: LocaleKeys.viewLibrary_emptyTable.tr(),
            ),
          );
        }
        return _PreviewFadeIn(
          key: const ValueKey('database-preview-ready'),
          child: ViewPreviewTable(
            snapshot: database,
            surface: WorkspacePalette.of(context).elevatedSurface,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          ),
        );
      },
    );
  }
}

/// Read only the opening of a file; the excerpt can scroll in a short window.
const _maxFilePreviewBytes = 8 * 1024;

/// A load quicker than this never shows its spinner at all.
const _spinnerDelay = Duration(milliseconds: 240);

/// Loaded preview content eases in rather than popping into place.
class _PreviewFadeIn extends StatefulWidget {
  const _PreviewFadeIn({super.key, required this.child, this.delay});

  final Widget child;
  final Duration? delay;

  @override
  State<_PreviewFadeIn> createState() => _PreviewFadeInState();
}

class _PreviewFadeInState extends State<_PreviewFadeIn>
    with SingleTickerProviderStateMixin {
  static const _fade = WorkspaceTokens.transitionDuration;

  late final Duration _delay = widget.delay ?? Duration.zero;
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _delay + _fade);
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delay.inMicroseconds / (_delay + _fade).inMicroseconds,
      1,
      curve: AppFlowyMotion.enterCurve,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.value > 0 || _controller.isAnimating) return;
    if (WorkspaceTokens.motion(context, _fade) == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _progress.value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - _progress.value)),
            child: child,
          ),
        ),
      );
}

/// The preview of a standalone file: a picture, the first page of a PDF, the
/// head of a text file, or a card naming what the attachment is.
class _WorkspaceFilePreview extends StatelessWidget {
  const _WorkspaceFilePreview({super.key, required this.view});

  final ViewPB view;

  String get _name => view.name.isEmpty ? 'Untitled' : view.name;

  /// Only files inside AppFlowy's own storage can be read straight away; a
  /// cloud object would need an authenticated download.
  String? get _localPath {
    final source = view.workspaceItem?.storageUrl;
    if (source == null || source.isEmpty) {
      return null;
    }
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase() ?? '';
    return scheme == 'http' || scheme == 'https' ? null : source;
  }

  @override
  Widget build(BuildContext context) {
    final path = _localPath;
    if (path == null) {
      return _WorkspaceFileCard(name: _name, view: view);
    }

    final lower = _name.toLowerCase();
    if (imgExtensionRegex.hasMatch(lower)) {
      return _FilePreviewImage(path: path, fallback: _fallback);
    }
    if (videoExtensionRegex.hasMatch(lower)) {
      return _FilePreviewVideo(path: path, fallback: _fallback);
    }

    final kind = filePreviewKindFromName(_name);
    if (kind == FilePreviewKind.pdf) {
      return _FilePreviewPdfPage(path: path, fallback: _fallback);
    }
    if (kind == FilePreviewKind.markdown) {
      return _FilePreviewMarkdown(path: path, fallback: _fallback);
    }
    if (kind == FilePreviewKind.archive) {
      return _FilePreviewArchive(
        path: path,
        name: _name,
        fallback: _fallback,
        empty: _emptyCard('This archive is empty'),
      );
    }
    if (isOfficeFile(_name)) {
      return _FilePreviewOfficeDocument(
        path: path,
        name: _name,
        fallback: _fallback,
        empty: _emptyCard('This document is empty'),
      );
    }
    if (kind != null) {
      return FilePreviewExcerpt(
        path: path,
        fallback: _fallback,
        language: searchPreviewCodeLanguage(view, _name),
      );
    }
    return _fallback;
  }

  Widget get _fallback => _WorkspaceFileCard(name: _name, view: view);

  Widget _emptyCard(String note) =>
      _WorkspaceFileCard(name: _name, view: view, note: note);
}

/// The largest package a search preview will unpack.
///
/// The popup has to answer while the pointer is still moving, so a big
/// archive shows its card rather than holding the list up.
const int _maxPreviewArchiveBytes = 24 * 1024 * 1024;

/// Opens a package for a preview, or returns null when it is too big.
///
/// [format] is passed for the containers whose extension does not name one:
/// every Office document is a zip called `.docx`, `.xlsx` or `.pptx`.
Future<ArchiveDocument?> _readPreviewArchive(
  String path,
  String name, {
  ArchiveFormat? format,
}) async {
  final file = File(path);
  if (await file.length() > _maxPreviewArchiveBytes) {
    return null;
  }
  return ArchiveDocument.read(file, name: name, format: format);
}

/// What an archive holds, listed the way a file manager would.
class _FilePreviewArchive extends StatefulWidget {
  const _FilePreviewArchive({
    required this.path,
    required this.name,
    required this.fallback,
    required this.empty,
  });

  final String path;
  final String name;
  final Widget fallback;
  final Widget empty;

  @override
  State<_FilePreviewArchive> createState() => _FilePreviewArchiveState();
}

class _FilePreviewArchiveState extends State<_FilePreviewArchive> {
  static const _maxRows = 12;

  late Future<List<ArchiveEntry>?> entries = _read();

  @override
  void didUpdateWidget(covariant _FilePreviewArchive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      entries = _read();
    }
  }

  Future<List<ArchiveEntry>?> _read() async {
    final document = await _readPreviewArchive(widget.path, widget.name);
    return document?.childrenOf('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return FutureBuilder<List<ArchiveEntry>?>(
      future: entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.fallback;
        }
        final rows = snapshot.data;
        if (rows == null) {
          return snapshot.connectionState == ConnectionState.done
              ? widget.fallback
              : const SizedBox.shrink();
        }
        if (rows.isEmpty) {
          return widget.empty;
        }
        return _PreviewFadeIn(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in rows.take(_maxRows))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        entry.isDirectory
                            ? const WorkspaceGlyph(
                                Icons.folder_rounded,
                                size: 15,
                              )
                            : WorkspaceGlyph.file(entry.name, size: 15),
                        const HSpace(8),
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyle.caption.standard(
                              color: theme.textColorScheme.primary,
                            ),
                          ),
                        ),
                        if (!entry.isDirectory) ...[
                          const HSpace(8),
                          Text(
                            _readableSize(entry.size),
                            style: theme.textStyle.caption.standard(
                              color: theme.textColorScheme.tertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (rows.length > _maxRows)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${rows.length - _maxRows} more',
                      style: theme.textStyle.caption.standard(
                        color: theme.textColorScheme.tertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The words inside an Office package, read straight out of its XML.
class _FilePreviewOfficeDocument extends StatefulWidget {
  const _FilePreviewOfficeDocument({
    required this.path,
    required this.name,
    required this.fallback,
    required this.empty,
  });

  final String path;
  final String name;
  final Widget fallback;
  final Widget empty;

  @override
  State<_FilePreviewOfficeDocument> createState() =>
      _FilePreviewOfficeDocumentState();
}

class _FilePreviewOfficeDocumentState
    extends State<_FilePreviewOfficeDocument> {
  late Future<String?> text = _read();

  @override
  void didUpdateWidget(covariant _FilePreviewOfficeDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      text = _read();
    }
  }

  /// The text of the document, an empty string when it holds none, and null
  /// when the package could not be unpacked at all.
  Future<String?> _read() async {
    final document = await _readPreviewArchive(
      widget.path,
      widget.name,
      // Office packages are zips; their extension never says so.
      format: ArchiveFormat.zip,
    );
    if (document == null) {
      return null;
    }
    return extractOfficeDocumentText(document, widget.name) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: text,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.fallback;
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final value = snapshot.data;
        if (value == null) {
          return widget.fallback;
        }
        if (value.trim().isEmpty) {
          return widget.empty;
        }
        return _PreviewFadeIn(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Text(
              value,
              maxLines: 18,
              overflow: TextOverflow.fade,
              style: WorkspaceTypography.style(context, WorkspaceTextRole.body),
            ),
          ),
        );
      },
    );
  }
}

class _FilePreviewImage extends StatelessWidget {
  const _FilePreviewImage({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Image.file(
        File(path),
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        cacheWidth:
            (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                .clamp(1.0, 1600.0)
                .round(),
        errorBuilder: (_, __, ___) => fallback,
        frameBuilder: (context, child, frame, synchronous) => synchronous
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: WorkspaceTokens.motion(
                  context,
                  WorkspaceTokens.transitionDuration,
                ),
                curve: WorkspaceTokens.curve,
                child: child,
              ),
      ),
    );
  }
}

/// A clip's poster frame with a play badge, so a video reads as a video.
class _FilePreviewVideo extends StatefulWidget {
  const _FilePreviewVideo({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  State<_FilePreviewVideo> createState() => _FilePreviewVideoState();
}

class _FilePreviewVideoState extends State<_FilePreviewVideo> {
  late Future<File?> poster;

  @override
  void initState() {
    super.initState();
    poster = VideoThumbnailCache.instance.thumbnailFor(widget.path);
  }

  @override
  void didUpdateWidget(covariant _FilePreviewVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      poster = VideoThumbnailCache.instance.thumbnailFor(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return FutureBuilder<File?>(
      future: poster,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PreviewFadeIn(
            key: ValueKey('video-preview-loading'),
            delay: _spinnerDelay,
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return widget.fallback;
        }
        return _PreviewFadeIn(
          key: const ValueKey('video-preview-ready'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                file,
                fit: BoxFit.contain,
                cacheWidth:
                    (304 * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (_, __, ___) => widget.fallback,
              ),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.elevatedSurface.withValues(alpha: 0.94),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 26,
                      color: palette.primaryText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilePreviewPdfPage extends StatelessWidget {
  const _FilePreviewPdfPage({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: PdfDocumentViewBuilder(
        documentRef: PdfDocumentRefFile(path),
        builder: (context, document) {
          if (document == null) {
            return const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (document.pages.isEmpty) {
            return fallback;
          }
          final page = document.pages.first;
          return Align(
            alignment: Alignment.topCenter,
            child: AspectRatio(
              aspectRatio: page.width / page.height,
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(WorkspaceTokens.controlRadius),
                child: ColoredBox(
                  color: WorkspacePalette.of(context).surface,
                  child: PdfPageView(
                    document: document,
                    pageNumber: 1,
                    maximumDpi: 144,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Markdown reads as markdown, not as its source.
class _FilePreviewMarkdown extends StatefulWidget {
  const _FilePreviewMarkdown({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  State<_FilePreviewMarkdown> createState() => _FilePreviewMarkdownState();
}

class _FilePreviewMarkdownState extends State<_FilePreviewMarkdown> {
  late Future<String> source = _read();

  @override
  void didUpdateWidget(covariant _FilePreviewMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      source = _read();
    }
  }

  Future<String> _read() async {
    final handle = await File(widget.path).open();
    try {
      final bytes = await handle.read(_maxFilePreviewBytes);
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } finally {
      await handle.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: source,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.fallback;
        }
        final text = snapshot.data;
        if (text == null) {
          return const SizedBox.shrink();
        }
        if (text.trim().isEmpty) {
          return widget.fallback;
        }
        final blocks = parseMarkdownPreviewBlocks(text, maximumBlocks: 24);
        if (blocks.isEmpty) {
          return widget.fallback;
        }
        // This renderer owns a non-shrink-wrapped list and needs the bounded
        // preview height. Do not place it in another vertical scroll view.
        return _PreviewFadeIn(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: FolderGalleryRichTextPreview(blocks: blocks),
          ),
        );
      },
    );
  }
}

/// The grammar a code file's excerpt is coloured with: the one its viewer was
/// last set to, otherwise the one its name implies. Null for anything else.
String? searchPreviewCodeLanguage(ViewPB view, String name) {
  if (filePreviewKindFromName(name) != FilePreviewKind.code) return null;
  final stored = WorkspaceFilePreviewCodec.decode(view.extra)['code_language'];
  return stored is String ? stored : codeLanguageForName(name);
}

/// The head of a text file, coloured like its viewer when it is source code.
class FilePreviewExcerpt extends StatefulWidget {
  const FilePreviewExcerpt({
    super.key,
    required this.path,
    required this.fallback,
    this.language,
  });

  final String path;
  final Widget fallback;

  /// Source code is coloured the way its own viewer colours it.
  final String? language;

  @override
  State<FilePreviewExcerpt> createState() => _FilePreviewExcerptState();
}

class _FilePreviewExcerptState extends State<FilePreviewExcerpt> {
  late Future<String> head;

  @override
  void initState() {
    super.initState();
    head = _readHead();
  }

  @override
  void didUpdateWidget(covariant FilePreviewExcerpt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      head = _readHead();
    }
  }

  /// Reads only the opening of the file, regardless of the preview's height.
  Future<String> _readHead() async {
    final handle = await File(widget.path).open();
    try {
      final bytes = await handle.read(_maxFilePreviewBytes);
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } finally {
      await handle.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: head,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.fallback;
        }
        final text = snapshot.data;
        if (text == null) {
          return const SizedBox.shrink();
        }
        if (text.trim().isEmpty) {
          return widget.fallback;
        }
        final style =
            WorkspaceTypography.style(context, WorkspaceTextRole.metadata)
                .copyWith(
          fontFamily: 'Geist Mono',
          fontFamilyFallback: const ['RobotoMono', 'monospace'],
          height: 1.5,
          color: WorkspacePalette.of(context).primaryText,
        );
        Widget excerpt(TextSpan span) => Text.rich(
              span,
              maxLines: 24,
              overflow: TextOverflow.fade,
            );
        final language = widget.language;
        return _PreviewFadeIn(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: language == null
                ? excerpt(TextSpan(text: text, style: style))
                // Shown plain at once, then coloured off the UI thread.
                : DeferredCodeHighlight(
                    code: text,
                    language: language,
                    brightness: Theme.of(context).brightness,
                    isPaper: PaperTheme.isEnabled(context),
                    style: style,
                    builder: (_, span) => excerpt(span),
                  ),
          ),
        );
      },
    );
  }
}

/// Named the way the file manager would: a big glyph, the type and the size.
class _WorkspaceFileCard extends StatelessWidget {
  const _WorkspaceFileCard({
    required this.name,
    required this.view,
    this.note,
  });

  final String name;
  final ViewPB view;

  /// An extra line under the type, for a file that turned out to hold
  /// nothing worth previewing.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final metadata = view.workspaceItem;
    final extension = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : LocaleKeys.document_menuName.tr();
    final size = metadata?.size;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph.file(name, size: 30),
            const VSpace(10),
            Text(
              size == null ? extension : '$extension · ${_readableSize(size)}',
              textAlign: TextAlign.center,
              style: theme.textStyle.caption.standard(
                color: theme.textColorScheme.secondary,
              ),
            ),
            if (note case final note?) ...[
              const VSpace(6),
              Text(
                note,
                textAlign: TextAlign.center,
                style: theme.textStyle.caption.standard(
                  color: theme.textColorScheme.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _readableSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              FlowySvgs.something_wrong_warning_m,
              color: theme.iconColorScheme.secondary,
              size: const Size.square(24),
            ),
            const VSpace(8),
            Text(
              LocaleKeys.search_somethingWentWrong.tr(),
              textAlign: TextAlign.center,
              style: theme.textStyle.body.enhanced(
                color: theme.textColorScheme.secondary,
              ),
            ),
            if (onRetry != null) ...[
              const VSpace(8),
              TextButton(
                onPressed: onRetry,
                child: Text(LocaleKeys.button_tryAgain.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
