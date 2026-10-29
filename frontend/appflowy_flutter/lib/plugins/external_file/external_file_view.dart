import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/external_file/external_file_access.dart';
import 'package:appflowy/plugins/external_file/external_file_kind.dart';
import 'package:appflowy/plugins/external_file/external_file_plugin.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Kinds whose source AppFlowy can save back to the file. A PDF, archive or
/// notebook stays read-only here.
const _editableKinds = {
  FilePreviewKind.markdown,
  FilePreviewKind.html,
  FilePreviewKind.text,
  FilePreviewKind.code,
};

/// What is known about an opened file before its content is read.
class ExternalFileTarget {
  const ExternalFileTarget({required this.kind, required this.editable});

  /// Null when AppFlowy has no viewer for the file.
  final FilePreviewKind? kind;

  /// Whether edits can be saved to the file.
  final bool editable;
}

Future<ExternalFileTarget> resolveExternalFile(File file) async {
  final type = await FileSystemEntity.type(file.path);
  if (type == FileSystemEntityType.notFound) {
    throw FileSystemException('The file no longer exists.', file.path);
  }
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('This is not a file.', file.path);
  }
  final kind = await externalFilePreviewKind(file);
  final editable = kind != null &&
      _editableKinds.contains(kind) &&
      await canWriteExternalFile(file);
  return ExternalFileTarget(kind: kind, editable: editable);
}

/// Shows a file from disk in a tab with the viewer a workspace file of the
/// same type gets. Markup opens as a preview; editing it is a choice, and
/// saves go straight back to the file.
class ExternalFileView extends StatefulWidget {
  const ExternalFileView({super.key, required this.plugin});

  final ExternalFilePlugin plugin;

  @override
  State<ExternalFileView> createState() => _ExternalFileViewState();
}

class _ExternalFileViewState extends State<ExternalFileView> {
  late Future<ExternalFileTarget> _target;

  ExternalFilePlugin get _plugin => widget.plugin;

  File get _file => File(_plugin.path);

  @override
  void initState() {
    super.initState();
    _resolve();
    _plugin.revision.addListener(_onReopened);
  }

  @override
  void didUpdateWidget(covariant ExternalFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.plugin, widget.plugin)) {
      oldWidget.plugin.revision.removeListener(_onReopened);
      widget.plugin.revision.addListener(_onReopened);
      _resolve();
    }
  }

  @override
  void dispose() {
    _plugin.revision.removeListener(_onReopened);
    super.dispose();
  }

  void _resolve() => _target = resolveExternalFile(_file);

  /// Opening the file again re-reads it. A pending edit is saved first, when
  /// the old preview goes away, so it is not lost to the re-read.
  void _onReopened() {
    if (mounted) setState(_resolve);
  }

  void _setMetadata(Map<String, dynamic> value) {
    if (!mounted) return;
    setState(() => _plugin.metadata = Map.of(value));
  }

  void _toggleSourceEditing() {
    final editing = _plugin.metadata[filePreviewEditModeKey] == true;
    _setMetadata({..._plugin.metadata, filePreviewEditModeKey: !editing});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canvas = EditorSurfaceStyle.canvasBackgroundFor(
      theme.brightness,
      theme.scaffoldBackgroundColor,
      isPaper: PaperTheme.isEnabled(context),
    );
    return ColoredBox(
      color: canvas,
      child: FutureBuilder<ExternalFileTarget>(
        // A re-opened file must not show the last read while it resolves.
        key: ObjectKey(_target),
        future: _target,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ExternalFileMessage(
              icon: Icons.error_outline_rounded,
              title: 'This file could not be opened',
              message: _describeError(snapshot.error!),
              action: TextButton(
                style: WorkspaceChrome.controlStyle(context),
                onPressed: () => setState(_resolve),
                child: const Text('Try again'),
              ),
            );
          }
          final target = snapshot.requireData;
          final kind = target.kind;
          if (kind == null) {
            return _ExternalFileMessage(
              icon: fileIconForName(_plugin.name),
              title: _plugin.name,
              message: 'AppFlowy has no viewer for this file type yet.',
            );
          }
          final metadata = _plugin.metadata;
          return LayoutBuilder(
            builder: (context, constraints) => FilePreview(
              file: _file,
              name: _plugin.name,
              kind: kind,
              metadata: metadata,
              onMetadataChanged: _setMetadata,
              editable: target.editable,
              height: constraints.maxHeight,
              framed: false,
              toolbarTrailing: kind.supportsSourceEditing && target.editable
                  ? _SourceModeToggle(
                      editing: metadata[filePreviewEditModeKey] == true,
                      onPressed: _toggleSourceEditing,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  static String _describeError(Object error) {
    if (error is FileSystemException) {
      final path = error.path;
      return path == null || path.isEmpty
          ? error.message
          : '${error.message}\n$path';
    }
    return error.toString();
  }
}

/// Switches markup between its rendered preview and the source editor.
class _SourceModeToggle extends StatelessWidget {
  const _SourceModeToggle({required this.editing, required this.onPressed});

  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: editing ? 'Show preview' : 'Edit source',
      child: TextButton.icon(
        onPressed: onPressed,
        style: WorkspaceChrome.controlStyle(context),
        icon: WorkspaceGlyph(
          editing ? Icons.visibility_rounded : Icons.edit_rounded,
          size: 16,
        ),
        label: Text(editing ? 'Preview' : 'Edit'),
      ),
    );
  }
}

class _ExternalFileMessage extends StatelessWidget {
  const _ExternalFileMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ViewerCard(
            color: theme.fillColorScheme.content,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 34, color: theme.iconColorScheme.secondary),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.textColorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: theme.textColorScheme.secondary,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 18),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
