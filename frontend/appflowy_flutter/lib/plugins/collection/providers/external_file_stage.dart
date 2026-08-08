import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens one external object with the viewer AppFlowy already has for it.
///
/// This is the rule the whole integration turns on: a OneDrive PDF opens in the
/// PDF viewer, a Box markdown file in the markdown viewer, a Drive picture in
/// the image viewer. There is no separate viewer for any service, because a
/// file is a file once its bytes are on disk.
Future<void> showExternalFile(
  BuildContext context, {
  required ProviderController controller,
  required ProviderNode node,
  List<ProviderNode> siblings = const <ProviderNode>[],
}) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: node.name,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondary) => _ExternalFileViewer(
        controller: controller,
        node: node,
        siblings: siblings.where((sibling) => !sibling.isFolder).toList(),
      ),
      transitionBuilder: (context, animation, secondary, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );

class _ExternalFileViewer extends StatefulWidget {
  const _ExternalFileViewer({
    required this.controller,
    required this.node,
    required this.siblings,
  });

  final ProviderController controller;
  final ProviderNode node;
  final List<ProviderNode> siblings;

  @override
  State<_ExternalFileViewer> createState() => _ExternalFileViewerState();
}

class _ExternalFileViewerState extends State<_ExternalFileViewer> {
  late ProviderNode node;
  String? path;
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    node = widget.node;
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      failed = false;
      path = null;
    });
    final resolved = await widget.controller.materialize(node);
    if (!mounted) {
      return;
    }
    setState(() {
      path = resolved;
      loading = false;
      failed = resolved == null;
    });
  }

  int get _index =>
      widget.siblings.indexWhere((sibling) => sibling.id == node.id);

  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index >= 0 && _index < widget.siblings.length - 1;

  void _step(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.siblings.length) {
      return;
    }
    setState(() => node = widget.siblings[next]);
    unawaited(_fetch());
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextIntent(),
      },
      child: Actions(
        actions: {
          _PreviousIntent: CallbackAction<_PreviousIntent>(
            onInvoke: (_) => _hasPrevious ? _step(-1) : null,
          ),
          _NextIntent: CallbackAction<_NextIntent>(
            onInvoke: (_) => _hasNext ? _step(1) : null,
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Padding(
              padding: const EdgeInsets.all(44),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: palette.background,
                  child: Column(
                    children: [
                      _header(palette),
                      Expanded(child: _body(palette)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(FolderExplorerPalette palette) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              onPressed: _hasPrevious ? () => _step(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: palette.textSecondary,
              splashRadius: 16,
            ),
            IconButton(
              onPressed: _hasNext ? () => _step(1) : null,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: palette.textSecondary,
              splashRadius: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13.5,
                  fontVariations: const [FontVariation.weight(580)],
                ),
              ),
            ),
            if ((node.webUrl ?? '').isNotEmpty)
              Tooltip(
                message: LocaleKeys.providers_openInSource.tr(),
                child: IconButton(
                  onPressed: () => unawaited(
                    launchUrl(
                      Uri.parse(node.webUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  color: palette.textSecondary,
                  splashRadius: 16,
                ),
              ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 18),
              color: palette.textSecondary,
              splashRadius: 16,
            ),
          ],
        ),
      );

  Widget _body(FolderExplorerPalette palette) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (failed || path == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 26, color: palette.textMuted),
            const SizedBox(height: 12),
            Text(
              LocaleKeys.providers_cannotOpen.tr(),
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => unawaited(_fetch()),
              child: Text(LocaleKeys.providers_tryAgain.tr()),
            ),
          ],
        ),
      );
    }

    return externalFileRenderer(node: node, path: path!, palette: palette);
  }
}

/// Picks the renderer for one materialised object.
///
/// Shared with the page embed, so an embedded Drive PDF and a Drive PDF opened
/// from a collection are literally the same viewer.
Widget externalFileRenderer({
  required ProviderNode node,
  required String path,
  required FolderExplorerPalette palette,
  bool bare = true,
}) {
  final file = File(path);
  // A service names a file whatever a person typed, and every viewer picks
  // itself from the name, so the declared type supplies the extension.
  final name = providerFileNameFor(node);

  if (imgExtensionRegex.hasMatch(name) || node.kind == ProviderNodeKind.image) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            file,
            fit: BoxFit.scaleDown,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_rounded,
              size: 28,
              color: palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  if (node.kind == ProviderNodeKind.video ||
      node.kind == ProviderNodeKind.audio) {
    return Center(
      child: FileMediaPlayer(
        key: ValueKey('external-media-${node.id}'),
        url: path,
        name: name,
        kind: node.kind == ProviderNodeKind.video
            ? FileMediaKind.video
            : FileMediaKind.audio,
      ),
    );
  }

  final kind = filePreviewKindFromName(name);
  if (kind == FilePreviewKind.pdf) {
    return PdfPreview(
      key: ValueKey('external-pdf-${node.id}'),
      file: file,
      name: name,
      bare: bare,
      editable: false,
      metadata: const {},
      onMetadataChanged: (_) {},
    );
  }
  if (isOfficeFile(name)) {
    return OfficeDocumentView(
      key: ValueKey('external-office-${node.id}'),
      file: file,
      name: name,
      source: path,
      editable: false,
      fallbackBuilder: (context) => _Unsupported(node: node, palette: palette),
    );
  }
  if (kind == null) {
    return _Unsupported(node: node, palette: palette);
  }
  return FilePreview(
    key: ValueKey('external-file-${node.id}'),
    file: file,
    name: name,
    kind: kind,
    bare: bare,
    editable: false,
    metadata: const {},
    onMetadataChanged: (_) {},
  );
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.node, required this.palette});

  final ProviderNode node;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_rounded,
              size: 30,
              color: palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              node.name,
              style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text(
              LocaleKeys.providers_noViewer.tr(),
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
}

class _PreviousIntent extends Intent {
  const _PreviousIntent();
}

class _NextIntent extends Intent {
  const _NextIntent();
}
