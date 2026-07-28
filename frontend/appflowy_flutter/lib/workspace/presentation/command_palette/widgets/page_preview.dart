import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/document_immersive_cover_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_text_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_thumbnail_cache.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

class PagePreview extends StatelessWidget {
  const PagePreview({
    super.key,
    required this.view,
    required this.onViewOpened,
  });
  final ViewPB view;
  final VoidCallback onViewOpened;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final backgroundColor = EditorSurfaceStyle.previewBackgroundFor(
      Theme.of(context).brightness,
      theme.surfaceColorScheme.layer02,
      isPaper: PaperTheme.isEnabled(context),
    );

    return BlocProvider(
      create: (context) => DocumentImmersiveCoverBloc(view: view)
        ..add(const DocumentImmersiveCoverEvent.initial()),
      child:
          BlocBuilder<DocumentImmersiveCoverBloc, DocumentImmersiveCoverState>(
        builder: (context, state) {
          final cover = buildCover(state, context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 20),
            child: Container(
              key: const ValueKey('page-preview-card'),
              height: double.infinity,
              width: 304,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.borderColorScheme.primary),
                boxShadow: theme.shadow.small,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cover != null) cover,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (view.icon.value.isNotEmpty || cover == null) ...[
                          SizedBox.square(
                            dimension: 24,
                            child: Center(
                              child: buildIcon(theme, view, cover != null),
                            ),
                          ),
                          const VSpace(10),
                        ],
                        buildTitle(context, view),
                      ],
                    ),
                  ),
                  const AFDivider(),
                  Expanded(
                    child: _buildPageContent(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageContent() {
    // A workspace file is stored as a document holding one attachment, so the
    // document renderer would only ever show that block's chip.
    if (view.isWorkspaceFile) {
      return _WorkspaceFilePreview(
        key: ValueKey('file-preview-${view.id}'),
        view: view,
      );
    }
    if (view.layout.isDocumentView) {
      return _DocumentPagePreview(
        key: ValueKey('document-preview-${view.id}'),
        viewId: view.id,
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

  Widget? buildCover(DocumentImmersiveCoverState state, BuildContext context) {
    final viewCover = view.cover;
    const height = 96.0;
    if (viewCover != null && !viewCover.isNone) {
      return ViewCoverImage(
        cover: viewCover,
        userProfile: context.read<UserWorkspaceBloc?>()?.state.userProfile,
        width: double.infinity,
        height: height,
      );
    }

    final cover = state.cover;
    final type = state.cover.type;
    if (type == PageStyleCoverImageType.customImage ||
        type == PageStyleCoverImageType.unsplashImage) {
      final userProfile = context.read<UserWorkspaceBloc?>()?.state.userProfile;
      if (userProfile == null) return null;

      return SizedBox(
        height: height,
        width: double.infinity,
        child: FlowyNetworkImage(
          url: cover.value,
          userProfilePB: userProfile,
        ),
      );
    }

    if (type == PageStyleCoverImageType.builtInImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
          fit: BoxFit.cover,
        ),
      );
    }

    if (type == PageStyleCoverImageType.pureColor) {
      final color = FlowyTint.fromId(cover.value)?.color(context) ??
          cover.value.tryToColor();
      return Container(
        height: height,
        width: double.infinity,
        color: color,
      );
    }

    if (type == PageStyleCoverImageType.gradientColor) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: FlowyGradientColor.fromId(cover.value).linear,
        ),
      );
    }

    if (type == PageStyleCoverImageType.localImage) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.file(
          File(cover.value),
          fit: BoxFit.cover,
        ),
      );
    }

    return null;
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
    return FlowySvg(
      view.iconData,
      size: const Size.square(20),
      color: theme.iconColorScheme.secondary,
    );
  }

  Widget buildTitle(BuildContext context, ViewPB view) {
    final theme = AppFlowyTheme.of(context);
    final titleStyle = theme.textStyle.heading4
            .enhanced(color: theme.textColorScheme.primary),
        titleHoverStyle =
            titleStyle.copyWith(decoration: TextDecoration.underline);
    return LayoutBuilder(
      builder: (context, constrains) {
        final maxWidth = constrains.maxWidth;
        String displayText = view.nameOrDefault;
        final painter = TextPainter(
          text: TextSpan(text: displayText, style: titleStyle),
          maxLines: 3,
          textDirection: TextDirection.ltr,
          ellipsis: '...     ',
        );
        painter.layout(maxWidth: maxWidth);
        if (painter.didExceedMaxLines) {
          final lines = painter.computeLineMetrics();
          final lastLine = lines.last;
          final offset = Offset(
            lastLine.left + lastLine.width,
            lines.map((e) => e.height).reduce((a, b) => a + b),
          );
          final range = painter.getPositionForOffset(offset);
          displayText = '${displayText.substring(0, range.offset)}...';
        }
        return AFBaseButton(
          borderColor: (_, __, ___, ____) => Colors.transparent,
          borderRadius: 0,
          onTap: onViewOpened,
          padding: EdgeInsets.zero,
          builder: (context, isHovering, disabled) {
            return RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: displayText,
                    style: isHovering ? titleHoverStyle : titleStyle,
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: FlowyTooltip(
                        message: LocaleKeys.settings_files_open.tr(),
                        child: FlowySvg(
                          FlowySvgs.search_open_tab_m,
                          color: theme.iconColorScheme.secondary,
                          size: const Size.square(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DocumentPagePreview extends StatefulWidget {
  const _DocumentPagePreview({
    required this.viewId,
    super.key,
  });

  final String viewId;

  @override
  State<_DocumentPagePreview> createState() => _DocumentPagePreviewState();
}

class _DocumentPagePreviewState extends State<_DocumentPagePreview> {
  static const double _canvasWidth = 520;
  static const double _lineHeight = 1.4;

  EditorState? editorState;
  bool isLoading = true;
  bool hasError = false;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDocument());
  }

  @override
  void didUpdateWidget(covariant _DocumentPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
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

    final result = await DocumentService().getDocument(
      documentId: widget.viewId,
    );
    var requestFailed = false;
    final document = result.fold(
      (data) => data.toDocument(),
      (error) {
        requestFailed = true;
        Log.warn(
          'Unable to load search preview for ${widget.viewId}: $error',
        );
        return null;
      },
    );

    if (!mounted || currentRequestId != requestId) {
      return;
    }

    if (document == null && !requestFailed) {
      Log.warn('Search preview document is invalid: ${widget.viewId}');
    }
    setState(() {
      editorState = document == null ? null : EditorState(document: document);
      hasError = document == null;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final editorState = this.editorState;
    if (hasError || editorState == null) {
      return _PreviewError(onRetry: () => unawaited(_loadDocument()));
    }

    return LayoutBuilder(
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
    );
  }
}

class _DatabasePagePreview extends StatelessWidget {
  const _DatabasePagePreview({
    required this.view,
    super.key,
  });

  static const double _canvasWidth = 720;
  static const double _canvasHeight = 960;

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final scale = constraints.maxWidth / _canvasWidth;
        final renderedHeight = _canvasHeight * scale;
        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: renderedHeight,
            child: FittedBox(
              alignment: Alignment.topLeft,
              fit: BoxFit.fill,
              child: SizedBox(
                width: _canvasWidth,
                height: _canvasHeight,
                child: FocusScope(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  child: IgnorePointer(
                    child: Provider(
                      create: (_) => const DatabasePluginWidgetBuilderSize(
                        horizontalPadding: 16,
                      ),
                      child: DatabaseTabBarView(
                        view: view,
                        shrinkWrap: false,
                        showActions: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A search preview never scrolls, so only the opening of a file is read.
const _maxFilePreviewBytes = 8 * 1024;

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
      return _FilePreviewText(path: path, fallback: _fallback);
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in rows.take(_maxRows))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        entry.isDirectory
                            ? Icons.folder_rounded
                            : fileIconForName(entry.name),
                        size: 15,
                        color: theme.iconColorScheme.secondary,
                      ),
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
    final theme = AppFlowyTheme.of(context);
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Text(
            value,
            maxLines: 18,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11.5,
              height: 17 / 11.5,
              color: theme.textColorScheme.secondary,
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
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // The card is roughly 300pt wide, so a full size decode is pure waste.
      cacheWidth: (304 * MediaQuery.devicePixelRatioOf(context)).round(),
      errorBuilder: (_, __, ___) => fallback,
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
    return FutureBuilder<File?>(
      future: poster,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return widget.fallback;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth:
                  (304 * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, __, ___) => widget.fallback,
            ),
            Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0x73000000),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
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
                borderRadius: BorderRadius.circular(6),
                child: ColoredBox(
                  color: Colors.white,
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: FolderGalleryRichTextPreview(blocks: blocks),
        );
      },
    );
  }
}

class _FilePreviewText extends StatefulWidget {
  const _FilePreviewText({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  State<_FilePreviewText> createState() => _FilePreviewTextState();
}

class _FilePreviewTextState extends State<_FilePreviewText> {
  late Future<String> head;

  @override
  void initState() {
    super.initState();
    head = _readHead();
  }

  @override
  void didUpdateWidget(covariant _FilePreviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      head = _readHead();
    }
  }

  /// Reads only the opening of the file — a search preview never scrolls.
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
    final theme = AppFlowyTheme.of(context);
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Text(
            text,
            maxLines: 24,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontFamily: 'Geist Mono',
              fontFamilyFallback: const ['RobotoMono', 'monospace'],
              fontSize: 10,
              height: 15 / 10,
              color: theme.textColorScheme.secondary,
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              fileIconForName(name),
              size: 30,
              color: theme.iconColorScheme.secondary,
            ),
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
      child: Padding(
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
