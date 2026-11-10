import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/app_bar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../file_preview_kind.dart';
import '../materialized_file_builder.dart';
import 'office_document_view.dart';
import 'office_embedded_view.dart';
import 'office_panel.dart';
import 'office_platform.dart';

/// Whether tapping an attachment named [name] opens it in AppFlowy's office
/// editor instead of another app: Android builds carry the editor, and use
/// the same notion of an office file as the desktop.
bool opensOfficeFileInApp(String? name) =>
    officeRunsOnAndroid && name != null && isOfficeFile(name);

/// Opens [source] in the office editor, full screen under a mobile app bar.
///
/// [fallbackBuilder] renders the file when no editor can, as embedded
/// previews do for delimited text.
Future<void> showOfficeEditorPage(
  BuildContext context, {
  required String source,
  required String name,
  required bool editable,
  Map<String, String> httpHeaders = const {},
  Widget Function(BuildContext context, File file)? fallbackBuilder,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => OfficeEditorPage(
        source: source,
        name: name,
        editable: editable,
        httpHeaders: httpHeaders,
        fallbackBuilder: fallbackBuilder,
      ),
    ),
  );
}

/// An office file on a page of its own, for screens too small to edit it
/// inside a document.
class OfficeEditorPage extends StatelessWidget {
  const OfficeEditorPage({
    super.key,
    required this.source,
    required this.name,
    required this.editable,
    this.httpHeaders = const {},
    this.fallbackBuilder,
    this.loader = materializeMediaFile,
    this.documentBuilder,
  });

  final String source;
  final String name;
  final bool editable;
  final Map<String, String> httpHeaders;
  final Widget Function(BuildContext context, File file)? fallbackBuilder;
  final MaterializedFileLoader loader;

  /// Stands in for the editor in tests, which cannot host a WebView.
  @visibleForTesting
  final Widget Function(BuildContext context, File file)? documentBuilder;

  @override
  Widget build(BuildContext context) {
    final background = EditorSurfaceStyle.canvasBackground(context);
    return MaterializedFileBuilder(
      source: source,
      name: name,
      httpHeaders: httpHeaders,
      loader: loader,
      builder: (context, snapshot) {
        final file = snapshot.hasError ? null : snapshot.data;
        return Scaffold(
          backgroundColor: background,
          appBar: FlowyAppBar(
            title: FlowyText(
              name,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: background,
            actions: [
              if (file != null) _OpenWithAnotherApp(file: file),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildBody(context, snapshot),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<File> snapshot) {
    final error = snapshot.error;
    if (error != null) {
      return _OfficePageFailure(
        message: switch (error) {
          FileSystemException(:final message) => message,
          HttpException(:final message) => message,
          _ => 'AppFlowy could not load this file.',
        },
      );
    }
    final file = snapshot.data;
    if (file == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final fallback = fallbackBuilder;
    return documentBuilder?.call(context, file) ??
        OfficeDocumentView(
          key: ValueKey('office_page_${file.path}'),
          file: file,
          name: name,
          source: source,
          editable: editable,
          fallbackBuilder:
              fallback == null ? null : (context) => fallback(context, file),
        );
  }
}

class _OpenWithAnotherApp extends StatelessWidget {
  const _OpenWithAnotherApp({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Open with another app',
      icon: const Icon(Icons.open_in_new_rounded, size: 20),
      onPressed: () => unawaited(_open(context)),
    );
  }

  Future<void> _open(BuildContext context) async {
    // The other app reads the file, so edits still in the editor go first.
    final session =
        EmbeddedOfficeEditor.forCurrentPlatform()?.host.editingSessionFor(file);
    await session?.flush();
    if (context.mounted) {
      await afLaunchUrlString(file.path, context: context);
    }
  }
}

class _OfficePageFailure extends StatelessWidget {
  const _OfficePageFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: OfficePanelCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 34,
                  color: theme.iconColorScheme.secondary,
                ),
                const SizedBox(height: 14),
                Text(
                  'This file could not be opened',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
const kOfficeFileLaunchCardKey = ValueKey('office_file_launch_card');

/// An office file shown as a preview in a document on a phone: a card that
/// opens the file full screen, where the editor has room.
class OfficeFileLaunchCard extends StatelessWidget {
  const OfficeFileLaunchCard({
    super.key,
    required this.name,
    required this.onOpen,
    this.icon,
  });

  final String name;
  final VoidCallback onOpen;

  /// The attachment's own icon; the type's glyph otherwise.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border, width: 0.8),
      ),
      child: InkWell(
        key: kOfficeFileLaunchCardKey,
        onTap: onOpen,
        child: Padding(
          // The block's own menu button sits in the top right corner.
          padding: const EdgeInsets.fromLTRB(12, 12, 40, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: icon ??
                    Icon(
                      fileIconForName(name),
                      size: 22,
                      color: palette.accent,
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FlowyText(
                      name,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: palette.textPrimary,
                    ),
                    const SizedBox(height: 2),
                    FlowyText(
                      '${_officeKindLabel(name)} · Tap to open',
                      fontSize: 12.5,
                      overflow: TextOverflow.ellipsis,
                      color: palette.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _officeKindLabel(String name) =>
    switch (p.extension(name).replaceFirst('.', '').toLowerCase()) {
      'xls' || 'xlsx' || 'ods' || 'csv' || 'tsv' => 'Spreadsheet',
      'ppt' || 'pptx' || 'odp' => 'Presentation',
      _ => 'Document',
    };
