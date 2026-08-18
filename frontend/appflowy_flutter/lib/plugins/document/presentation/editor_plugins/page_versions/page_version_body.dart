import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_canvas.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_card_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_gallery_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_live_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_rail.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One remembered state, drawn as whatever it is.
///
/// A page is rendered as a page, a file through the viewer that file type
/// already has, a folder as the listing it was, a table as its rows. Nothing
/// here is a mock-up of the real thing — every shape reuses what the
/// application already draws.
class PageVersionBody extends StatefulWidget {
  const PageVersionBody({
    super.key,
    required this.version,
    this.compact = false,
    this.interactive = false,
  });

  final PageVersion version;

  /// A thumbnail rather than a reading surface.
  final bool compact;

  final bool interactive;

  @override
  State<PageVersionBody> createState() => _PageVersionBodyState();
}

class _PageVersionBodyState extends State<PageVersionBody> {
  PageVersionPayload? _payload;
  bool _read = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PageVersionBody old) {
    super.didUpdateWidget(old);
    if (old.version.id != widget.version.id) {
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  void _load() {
    final request = ++_request;
    _read = false;
    _payload = null;
    unawaited(
      PageVersionService.instance
          .readPayload(widget.version.viewId, widget.version.id)
          .then((payload) {
        if (!mounted || request != _request) {
          return;
        }
        setState(() {
          _read = true;
          _payload = payload;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);

    // A row's thumbnail is the page behind it, the same as any other page.
    if (widget.compact &&
        (widget.version.shape == PageVersionShape.document ||
            widget.version.shape == PageVersionShape.row)) {
      return PageVersionCanvas(
        viewId: widget.version.viewId,
        versionId: widget.version.id,
        placeholder: _Fallback(palette: palette, version: widget.version),
      );
    }

    if (!_read) {
      return const SizedBox.shrink();
    }
    final payload = _payload;
    if (payload == null) {
      return _Fallback(palette: palette, version: widget.version);
    }

    if (widget.version.shape == PageVersionShape.settings) {
      return _SettingsBody(payload: payload, palette: palette);
    }

    // The page as it was, drawn by the widget that draws the page itself —
    // unless there is nothing to draw it from, which reads better as a note.
    if (!widget.compact && _hasPage(payload)) {
      return PageVersionLiveView(
        version: widget.version,
        payload: payload,
        interactive: widget.interactive,
      );
    }

    return switch (widget.version.shape) {
      PageVersionShape.file => _FileBody(
          version: widget.version,
          payload: payload,
          palette: palette,
          compact: widget.compact,
        ),
      PageVersionShape.container => _ChildrenBody(
          payload: payload,
          palette: palette,
          compact: widget.compact,
        ),
      _ => PageVersionCardPreview(payload: payload),
    };
  }

  /// Whether there is enough stored to draw the page itself.
  bool _hasPage(PageVersionPayload payload) => switch (payload.shape) {
        PageVersionShape.file => payload.file?.stored ?? false,
        PageVersionShape.container => (payload.children ?? const []).isNotEmpty,
        PageVersionShape.database => payload.table?.isEmpty == false,
        _ => true,
      };
}

/// What a version was, when there is nothing of it left to draw.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.palette, required this.version});

  final TableViewPalette palette;
  final PageVersion version;

  @override
  Widget build(BuildContext context) {
    if (version.excerpt.isNotEmpty) {
      return _Excerpt(palette: palette, version: version);
    }
    return _Placard(
      palette: palette,
      icon: pageVersionKindIcon(version.kind),
      title: version.pageName.isEmpty ? version.name : version.pageName,
      subtitle: pageVersionDetail(version),
    );
  }
}

class _Excerpt extends StatelessWidget {
  const _Excerpt({required this.palette, required this.version});

  final TableViewPalette palette;
  final PageVersion version;

  @override
  Widget build(BuildContext context) {
    if (version.excerpt.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      version.excerpt,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 9, height: 1.5, color: palette.textMuted),
    );
  }
}

class _FileBody extends StatefulWidget {
  const _FileBody({
    required this.version,
    required this.payload,
    required this.palette,
    required this.compact,
  });

  final PageVersion version;
  final PageVersionPayload payload;
  final TableViewPalette palette;
  final bool compact;

  @override
  State<_FileBody> createState() => _FileBodyState();
}

class _FileBodyState extends State<_FileBody> {
  File? _file;
  bool _read = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final file = await PageVersionStore.instance.contentFile(
      widget.version.viewId,
      widget.version.id,
      widget.payload.file?.extension ?? '',
    );
    if (mounted) {
      setState(() {
        _read = true;
        _file = file;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final name = widget.payload.file?.name ?? '';
    final file = _file;

    if (!_read) {
      return const SizedBox.shrink();
    }

    if (file == null) {
      final stored = widget.payload.file?.stored ?? true;
      return _Placard(
        palette: palette,
        icon: fileIconForName(name),
        title: name,
        subtitle: stored
            ? LocaleKeys.pageVersions_unavailable.tr()
            : LocaleKeys.pageVersions_fileNotKept.tr(),
      );
    }

    if (widget.compact) {
      // The rail shows what a folder card shows, drawn by the same preview.
      return PageVersionCardPreview(
        payload: widget.payload,
        filePath: file.path,
      );
    }

    // A picture is its own preview.
    if (imgExtensionRegex.hasMatch(name.toLowerCase())) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _card(palette, name),
      );
    }

    final mediaKind = fileMediaKind(name, file.path);
    if (mediaKind != null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: mediaKind == FileMediaKind.audio ? 560 : 1180,
          ),
          child: FileMediaPlayer(url: file.path, name: name, kind: mediaKind),
        ),
      );
    }

    final kind = filePreviewKindFromName(name);
    if (kind == null) {
      return _card(palette, name);
    }

    // A stored copy is read only — a version is a record, not a place to work.
    if (kind == FilePreviewKind.pdf) {
      return PdfPreview(
        key: ValueKey(file.path),
        file: file,
        name: name,
        metadata: const {},
        onMetadataChanged: (_) {},
        editable: false,
        bare: true,
      );
    }

    if (kind == FilePreviewKind.archive) {
      return ArchiveExplorer(
        key: ValueKey(file.path),
        file: file,
        name: name,
        editable: false,
      );
    }

    return FilePreview(
      key: ValueKey(file.path),
      file: file,
      name: name,
      kind: kind,
      metadata: const {},
      onMetadataChanged: (_) {},
      editable: false,
      bare: true,
    );
  }

  Widget _card(TableViewPalette palette, String name) => _Placard(
        palette: palette,
        icon: fileIconForName(name),
        title: name,
        subtitle: _bytesLabel(widget.payload.file?.bytes ?? 0),
      );
}

class _ChildrenBody extends StatelessWidget {
  const _ChildrenBody({
    required this.payload,
    required this.palette,
    required this.compact,
  });

  final PageVersionPayload payload;
  final TableViewPalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final children = payload.children ?? const <PageVersionChild>[];
    final link = payload.link;

    if (compact) {
      return PageVersionCardPreview(payload: payload);
    }

    if (children.isEmpty) {
      return _Placard(
        palette: palette,
        icon: link == null ? Icons.folder_open_rounded : Icons.cloud_rounded,
        title:
            link?.name.isNotEmpty ?? false ? link!.name : payload.settings.name,
        subtitle: link == null
            ? LocaleKeys.pageVersions_emptyFolder.tr()
            : link.listed
                ? LocaleKeys.pageVersions_linkedEmpty.tr()
                : LocaleKeys.pageVersions_linkedNotRead.tr(),
      );
    }

    return PageVersionGalleryView(children: children);
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.payload, required this.palette});

  final PageVersionPayload payload;
  final TableViewPalette palette;

  @override
  Widget build(BuildContext context) {
    return _Placard(
      palette: palette,
      icon: Icons.tune_rounded,
      title: payload.settings.name,
      subtitle: LocaleKeys.pageVersions_settingsOnly.tr(),
    );
  }
}

class _Placard extends StatelessWidget {
  const _Placard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final TableViewPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 160;
        return Center(
          child: Padding(
            padding: EdgeInsets.all(tight ? 6 : 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: tight ? 16 : 26, color: palette.textMuted),
                SizedBox(height: tight ? 4 : 10),
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: tight ? 8.5 : 13,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
                    ),
                  ),
                SizedBox(height: tight ? 2 : 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tight ? 7.5 : 11.5,
                    color: palette.textMuted,
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

String _bytesLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
