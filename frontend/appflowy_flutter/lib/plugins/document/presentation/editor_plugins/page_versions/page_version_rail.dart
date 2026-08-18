import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_body.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The words a version row is described with.
///
/// PURE, so "3 minutes ago" can be tested without a clock or a widget tree.
String pageVersionMoment(DateTime when, {required DateTime now}) {
  final elapsed = now.toUtc().difference(when.toUtc());
  if (elapsed.inSeconds < 60) {
    return LocaleKeys.pageVersions_justNow.tr();
  }
  if (elapsed.inMinutes < 60) {
    return LocaleKeys.pageVersions_minutesAgo.tr(
      args: ['${elapsed.inMinutes}'],
    );
  }
  if (elapsed.inHours < 24) {
    return LocaleKeys.pageVersions_hoursAgo.tr(args: ['${elapsed.inHours}']);
  }
  if (elapsed.inDays < 7) {
    return LocaleKeys.pageVersions_daysAgo.tr(args: ['${elapsed.inDays}']);
  }
  return DateFormat.yMMMd().add_jm().format(when.toLocal());
}

String pageVersionKindLabel(PageVersionKind kind) => switch (kind) {
      PageVersionKind.automatic => LocaleKeys.pageVersions_kindAutomatic.tr(),
      PageVersionKind.manual => LocaleKeys.pageVersions_kindNamed.tr(),
      PageVersionKind.restorePoint =>
        LocaleKeys.pageVersions_kindRestorePoint.tr(),
    };

IconData pageVersionKindIcon(PageVersionKind kind) => switch (kind) {
      PageVersionKind.automatic => Icons.history_rounded,
      PageVersionKind.manual => Icons.bookmark_rounded,
      PageVersionKind.restorePoint => Icons.settings_backup_restore_rounded,
    };

/// What a version row says it holds — words for a page, rows for a table,
/// items for a folder, a size for a file.
String pageVersionDetail(PageVersion version) => switch (version.shape) {
      PageVersionShape.document =>
        LocaleKeys.pageVersions_wordCount.tr(args: ['${version.wordCount}']),
      PageVersionShape.database =>
        LocaleKeys.pageVersions_rowCount.tr(args: ['${version.blockCount}']),
      PageVersionShape.container =>
        LocaleKeys.pageVersions_itemCount.tr(args: ['${version.blockCount}']),
      PageVersionShape.file => pageVersionBytesLabel(version.characterCount),
      PageVersionShape.row =>
        LocaleKeys.pageVersions_wordCount.tr(args: ['${version.wordCount}']),
      PageVersionShape.board ||
      PageVersionShape.settings =>
        LocaleKeys.pageVersions_settingsOnly.tr(),
    };

String pageVersionBytesLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Sizes the version rail and its cards are built from.
abstract final class PageVersionMetrics {
  static const double railWidth = 268;
  static const double thumbnailHeight = 112;
  static const double cardRadius = 12;
  static const double gap = 10;
  static const Duration hover = Duration(milliseconds: 160);
}

/// A page's previous states, listed down the right of the page.
///
/// Opened from the page's own three-dot menu; the two are siblings, so they
/// meet at [PageVersionPanel] rather than through the widget tree.
class PageVersionRail extends StatefulWidget {
  const PageVersionRail({
    super.key,
    required this.viewId,
    required this.onPreview,
    required this.onRestore,
    required this.onCaptureNow,
    required this.onClose,
    this.editable = true,
  });

  final String viewId;

  /// Opens the popup that shows one version at full size.
  final ValueChanged<PageVersion> onPreview;

  final ValueChanged<PageVersion> onRestore;

  /// Remembers the page as it stands, by name.
  final VoidCallback onCaptureNow;

  final VoidCallback onClose;

  final bool editable;

  @override
  State<PageVersionRail> createState() => _PageVersionRailState();
}

class _PageVersionRailState extends State<PageVersionRail> {
  final PageVersionStore _store = PageVersionStore.instance;

  List<PageVersion>? _versions;

  @override
  void initState() {
    super.initState();
    _store.revision.addListener(_onStoreChanged);
    unawaited(_read());
  }

  @override
  void didUpdateWidget(PageVersionRail old) {
    super.didUpdateWidget(old);
    if (old.viewId != widget.viewId) {
      _versions = null;
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    _store.revision.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (_store.lastChanged == widget.viewId) {
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final versions = await _store.read(widget.viewId);
    if (mounted) {
      setState(() => _versions = versions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final versions = _versions;

    return Container(
      width: PageVersionMetrics.railWidth,
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(
          left: BorderSide(
            color: palette.border.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, palette, versions?.length ?? 0),
          Expanded(
            child: versions == null
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                  )
                : versions.isEmpty
                    ? _buildEmpty(context, palette)
                    : _buildList(context, palette, versions),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    TableViewPalette palette,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.pageVersions_title.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  count == 0
                      ? LocaleKeys.pageVersions_noneYet.tr()
                      : LocaleKeys.pageVersions_countLabel.tr(
                          args: ['$count'],
                        ),
                  style: TextStyle(fontSize: 11.5, color: palette.textMuted),
                ),
              ],
            ),
          ),
          if (widget.editable)
            IconButton(
              onPressed: widget.onCaptureNow,
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              tooltip: LocaleKeys.pageVersions_saveNow.tr(),
              icon: Icon(
                Icons.bookmark_add_outlined,
                color: palette.textSecondary,
              ),
            ),
          IconButton(
            onPressed: widget.onClose,
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            tooltip: LocaleKeys.button_close.tr(),
            icon: Icon(Icons.close_rounded, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, TableViewPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 26, color: palette.textMuted),
          const SizedBox(height: 10),
          Text(
            LocaleKeys.pageVersions_emptyTitle.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LocaleKeys.pageVersions_emptyHint.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    TableViewPalette palette,
    List<PageVersion> versions,
  ) {
    final now = DateTime.now();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: versions.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: PageVersionMetrics.gap),
      itemBuilder: (context, index) => _VersionCard(
        version: versions[index],
        palette: palette,
        now: now,
        isCurrentStart: index == 0,
        editable: widget.editable,
        onOpen: () => widget.onPreview(versions[index]),
        onRestore: () => widget.onRestore(versions[index]),
        onRename: () => unawaited(_rename(versions[index])),
        onDiscard: () => unawaited(
          PageVersionService.instance
              .discard(widget.viewId, versions[index].id),
        ),
      ),
    );
  }

  Future<void> _rename(PageVersion version) async {
    final name = await showPageVersionNameDialog(
      context,
      initialName: version.name,
    );
    if (name == null) {
      return;
    }
    await PageVersionService.instance.rename(widget.viewId, version.id, name);
  }
}

class _VersionCard extends StatefulWidget {
  const _VersionCard({
    required this.version,
    required this.palette,
    required this.now,
    required this.isCurrentStart,
    required this.editable,
    required this.onOpen,
    required this.onRestore,
    required this.onRename,
    required this.onDiscard,
  });

  final PageVersion version;
  final TableViewPalette palette;
  final DateTime now;

  /// The newest version, which is what the page most recently looked like.
  final bool isCurrentStart;

  final bool editable;
  final VoidCallback onOpen;
  final VoidCallback onRestore;
  final VoidCallback onRename;
  final VoidCallback onDiscard;

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final version = widget.version;

    return MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapDown: (details) => unawaited(
          showPageVersionMenu(
            context: context,
            globalPosition: details.globalPosition,
            editable: widget.editable,
            onPreview: widget.onOpen,
            onRestore: widget.onRestore,
            onRename: widget.onRename,
            onDiscard: widget.onDiscard,
          ),
        ),
        child: AnimatedContainer(
          duration: PageVersionMetrics.hover,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _hovered ? palette.raised : palette.surface,
            borderRadius: BorderRadius.circular(
              PageVersionMetrics.cardRadius,
            ),
            boxShadow: palette.cardShadow(prominence: _hovered ? 0.9 : 0.45),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildThumbnail(palette, version),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            version.name.isNotEmpty
                                ? version.name
                                : pageVersionMoment(
                                    version.createdAt,
                                    now: widget.now,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                pageVersionKindIcon(version.kind),
                                size: 11,
                                color: palette.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  version.name.isNotEmpty
                                      ? pageVersionMoment(
                                          version.createdAt,
                                          now: widget.now,
                                        )
                                      : pageVersionDetail(version),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      duration: PageVersionMetrics.hover,
                      opacity: _hovered ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_hovered,
                        child: Builder(
                          builder: (buttonContext) => IconButton(
                            onPressed: () => unawaited(
                              showPageVersionMenuForWidget(
                                context: buttonContext,
                                editable: widget.editable,
                                onPreview: widget.onOpen,
                                onRestore: widget.onRestore,
                                onRename: widget.onRename,
                                onDiscard: widget.onDiscard,
                              ),
                            ),
                            iconSize: 15,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildThumbnail(TableViewPalette palette, PageVersion version) {
    // Every shape but a page brings its own surface, drawn by the gallery.
    final isPage = version.shape == PageVersionShape.document;
    return Stack(
      children: [
        Container(
          height: PageVersionMetrics.thumbnailHeight,
          color: isPage
              ? palette.isDark
                  ? palette.sunken
                  : Colors.white.withValues(alpha: palette.isPaper ? 0.5 : 0.9)
              : null,
          padding:
              isPage ? const EdgeInsets.fromLTRB(8, 8, 8, 0) : EdgeInsets.zero,
          child: PageVersionBody(version: version, compact: true),
        ),
        if (widget.isCurrentStart)
          Positioned(
            top: 6,
            right: 6,
            child: _Badge(
              palette: palette,
              label: LocaleKeys.pageVersions_latest.tr(),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.palette, required this.label});

  final TableViewPalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: palette.accent,
        ),
      ),
    );
  }
}
