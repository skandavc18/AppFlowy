import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_body.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_rail.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows one remembered state at reading size, with the way back to the page.
///
/// Returns the version somebody asked to restore, or null when the popup was
/// only read. Restoring is done by the caller, which owns the editor.
Future<PageVersion?> showPageVersionPreview(
  BuildContext context, {
  required List<PageVersion> versions,
  required PageVersion selected,
  required String pageName,
  bool editable = true,
}) {
  // A dialog is pushed above the page's own providers, so the ones the page
  // reads have to travel with it — a row page asks for the workspace, and an
  // embedded block opens a page through the tabs.
  final carried = <BlocProvider>[
    ..._carry<TabsBloc>(context),
    ..._carry<UserWorkspaceBloc>(context),
  ];

  return showDialog<PageVersion>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.34),
    builder: (_) {
      final dialog = _PageVersionPreviewDialog(
        versions: versions,
        selected: selected,
        pageName: pageName,
        editable: editable,
      );
      return carried.isEmpty
          ? dialog
          : MultiBlocProvider(providers: carried, child: dialog);
    },
  );
}

/// Hands a bloc down to the dialog, when the page has one to give.
List<BlocProvider<T>> _carry<T extends StateStreamableSource<Object?>>(
  BuildContext context,
) {
  try {
    return [BlocProvider<T>.value(value: context.read<T>())];
  } on ProviderNotFoundException {
    return const [];
  }
}

class _PageVersionPreviewDialog extends StatefulWidget {
  const _PageVersionPreviewDialog({
    required this.versions,
    required this.selected,
    required this.pageName,
    required this.editable,
  });

  final List<PageVersion> versions;
  final PageVersion selected;
  final String pageName;
  final bool editable;

  @override
  State<_PageVersionPreviewDialog> createState() =>
      _PageVersionPreviewDialogState();
}

class _PageVersionPreviewDialogState extends State<_PageVersionPreviewDialog> {
  late int _index = widget.versions.indexWhere(
    (version) => version.id == widget.selected.id,
  );

  PageVersion get _version =>
      widget.versions[_index.clamp(0, widget.versions.length - 1)];

  bool get _hasNewer => _index > 0;

  bool get _hasOlder => _index < widget.versions.length - 1;

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final media = MediaQuery.of(context);
    final width = (media.size.width * 0.62).clamp(420.0, 980.0);
    final height = (media.size.height - media.viewInsets.vertical - 120)
        .clamp(320.0, 860.0);

    return Dialog(
      backgroundColor: palette.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _older,
          const SingleActivator(LogicalKeyboardKey.arrowRight): _newer,
        },
        child: Focus(
          autofocus: true,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(palette),
                Expanded(child: _buildStage(palette)),
                _buildFooter(palette),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(TableViewPalette palette) {
    final version = _version;
    final title = version.name.isNotEmpty
        ? version.name
        : version.pageName.isNotEmpty
            ? version.pageName
            : widget.pageName;
    final words = pageVersionDetail(version);
    final when = pageVersionMoment(version.createdAt, now: DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border(
          bottom: BorderSide(color: palette.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            pageVersionKindIcon(version.kind),
            size: 18,
            color: palette.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty
                      ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
                      : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$when · ${pageVersionKindLabel(version.kind)} · $words',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: palette.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _hasOlder ? _older : null,
            iconSize: 18,
            tooltip: LocaleKeys.pageVersions_older.tr(),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            onPressed: _hasNewer ? _newer : null,
            iconSize: 18,
            tooltip: LocaleKeys.pageVersions_newer.tr(),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 18,
            tooltip: LocaleKeys.button_close.tr(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(TableViewPalette palette) {
    final version = _version;
    return ColoredBox(
      color: palette.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
        child: PageVersionBody(
          key: ValueKey(version.id),
          version: version,
          interactive: true,
        ),
      ),
    );
  }

  Widget _buildFooter(TableViewPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border(
          top: BorderSide(color: palette.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              LocaleKeys.pageVersions_restoreHint.tr(),
              maxLines: 2,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleKeys.button_close.tr()),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: widget.editable
                ? () => Navigator.of(context).pop(_version)
                : null,
            icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
            label: Text(LocaleKeys.pageVersions_restore.tr()),
          ),
        ],
      ),
    );
  }

  void _older() {
    if (_hasOlder) {
      setState(() => _index++);
    }
  }

  void _newer() {
    if (_hasNewer) {
      setState(() => _index--);
    }
  }
}
