import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';

import 'archive_explorer.dart';

/// Shows one entry of an archive with the viewer its file type already has.
///
/// The entry has been extracted to [file], so every renderer — the PDF reader,
/// the media player, the picture stage, the source editor — works on it
/// unchanged. Anything those renderers write to [file] is copied back into the
/// archive by the explorer that owns this viewer.
class ArchiveEntryViewer extends StatelessWidget {
  const ArchiveEntryViewer({
    super.key,
    required this.file,
    required this.name,
    required this.path,
    required this.archiveName,
    required this.editable,
    required this.metadata,
    required this.onMetadataChanged,
    required this.onClose,
  });

  /// The extracted working copy on disk.
  final File file;

  /// The entry's own name.
  final String name;

  /// Where the entry lives inside the archive.
  final String path;

  final String archiveName;

  final bool editable;

  final Map<String, dynamic> metadata;

  final ValueChanged<Map<String, dynamic>> onMetadataChanged;

  final VoidCallback onClose;

  bool get _isImage => imgExtensionRegex.hasMatch(name.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBar(context, palette),
        Expanded(child: _buildContent(context, palette)),
      ],
    );
  }

  Widget _buildBar(BuildContext context, FolderExplorerPalette palette) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        child: Row(
          children: [
            Tooltip(
              message: 'Back to $archiveName',
              waitDuration: const Duration(milliseconds: 450),
              child: IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                color: palette.textSecondary,
                hoverColor: palette.hover,
                splashRadius: 16,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 30),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 6),
            Icon(fileIconForName(name), size: 16, color: palette.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    '$archiveName  ·  $path',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                  ),
                ],
              ),
            ),
            if (_supportsSourceEditing)
              _SourceModeToggle(
                editing: metadata[filePreviewEditModeKey] == true,
                onPressed: () => onMetadataChanged({
                  ...metadata,
                  filePreviewEditModeKey:
                      metadata[filePreviewEditModeKey] != true,
                }),
              ),
          ],
        ),
      ),
    );
  }

  bool get _supportsSourceEditing =>
      editable &&
      (filePreviewKindFromName(name)?.supportsSourceEditing ?? false);

  /// The renderer to fall back on when no Office editor is reachable.
  ///
  /// Only formats AppFlowy can read unaided have one; a .docx has nothing to
  /// fall back to and keeps the Office panel.
  WidgetBuilder? _builtInFallbackFor(String name) {
    final kind = filePreviewKindFromName(name);
    if (kind == null) {
      return null;
    }
    return (context) => LayoutBuilder(
          builder: (context, constraints) => FilePreview(
            file: file,
            name: name,
            kind: kind,
            metadata: metadata,
            onMetadataChanged: onMetadataChanged,
            editable: editable,
            height: constraints.maxHeight,
          ),
        );
  }

  Widget _buildContent(BuildContext context, FolderExplorerPalette palette) {
    final mediaKind = fileMediaKind(name, file.path);
    if (mediaKind != null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: mediaKind == FileMediaKind.audio ? 560 : 1180,
          ),
          child: FileMediaPlayer(
            url: file.path,
            name: name,
            kind: mediaKind,
          ),
        ),
      );
    }

    if (_isImage) {
      return _ArchiveImageStage(file: file);
    }

    if (isOfficeFile(name)) {
      return OfficeDocumentView(
        file: file,
        name: name,
        source: file.path,
        editable: editable,
        fallbackBuilder: _builtInFallbackFor(name),
      );
    }

    final kind = filePreviewKindFromName(name);
    if (kind == null) {
      return _ArchiveUnsupportedEntry(name: name, file: file);
    }

    if (kind == FilePreviewKind.archive) {
      // An archive inside an archive opens as its own wall of cards.
      return ArchiveExplorer(
        file: file,
        name: name,
        editable: editable,
        embedded: false,
      );
    }

    if (kind == FilePreviewKind.pdf) {
      return PdfPreview(
        file: file,
        name: name,
        metadata: metadata,
        onMetadataChanged: onMetadataChanged,
        editable: editable,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => FilePreview(
        file: file,
        name: name,
        kind: kind,
        metadata: metadata,
        onMetadataChanged: onMetadataChanged,
        editable: editable,
        height: constraints.maxHeight,
      ),
    );
  }
}

/// Switches a markup entry between its rendered preview and the editor.
class _SourceModeToggle extends StatelessWidget {
  const _SourceModeToggle({required this.editing, required this.onPressed});

  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Tooltip(
      message: editing ? 'Show preview' : 'Edit source',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                editing ? Icons.visibility_outlined : Icons.edit_outlined,
                size: 15,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                editing ? 'Preview' : 'Edit',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveImageStage extends StatelessWidget {
  const _ArchiveImageStage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return ClipRect(
      child: InteractiveViewer(
        minScale: 0.4,
        maxScale: 8,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            // The card hugs the picture rather than filling the pane, so
            // nothing sits behind a photograph but the page.
            child: ViewerCard(
              reactsToPointer: false,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Image.file(
                  file,
                  errorBuilder: (context, error, stackTrace) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'This picture could not be decoded.',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveUnsupportedEntry extends StatelessWidget {
  const _ArchiveUnsupportedEntry({required this.name, required this.file});

  final String name;
  final File file;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIconForName(name), size: 34, color: palette.textMuted),
            const SizedBox(height: 12),
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'AppFlowy has no viewer for this file type yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () =>
                  unawaited(afLaunchUrlString(file.uri.toString())),
              child: const Text('Open with system app'),
            ),
          ],
        ),
      ),
    );
  }
}
