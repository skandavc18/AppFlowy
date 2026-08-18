import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_canvas.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One remembered row: what it held, and what was written on it.
///
/// A row reached through its table and a row reached through its own page are
/// the same thing, so both are drawn by this — the properties above, the page
/// below, the way the row page itself is laid out.
class PageVersionRowView extends StatelessWidget {
  const PageVersionRowView({
    super.key,
    required this.version,
    required this.payload,
    this.interactive = false,
    this.onBack,
  });

  final PageVersion version;
  final PageVersionPayload payload;
  final bool interactive;

  /// Set when the row was opened from the table it belongs to.
  final VoidCallback? onBack;

  /// A row is named by its first column, the way the table names it.
  String get _title {
    final table = payload.table;
    final row = table?.rows.firstOrNull;
    if (table == null || row == null) {
      return version.pageName;
    }
    for (final column in table.columns) {
      final value = row.cells[column.id] ?? '';
      if (value.trim().isNotEmpty) {
        return value;
      }
    }
    return LocaleKeys.menuAppHeader_defaultNewPageName.tr();
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final table = payload.table;
    final row = table?.rows.firstOrNull;

    return ListView(
      physics: interactive ? null : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 32),
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(
                version.pageName.isEmpty
                    ? LocaleKeys.pageVersions_title.tr()
                    : version.pageName,
              ),
            ),
          ),
        Text(
          _title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 20),
        if (row != null && table != null)
          for (final column in table.columns)
            _Property(
              column: column,
              value: row.cells[column.id] ?? '',
              palette: palette,
            ),
        const SizedBox(height: 12),
        Divider(height: 1, color: palette.border.withValues(alpha: 0.4)),
        const SizedBox(height: 16),
        // A row reached through its table carries its page in the table's
        // version; a row reached through its own page has one of its own in
        // the store. The canvas takes what it is given and falls back to what
        // was written down, so both ways in draw the same page — and a row
        // that was never written on says so rather than showing a blank.
        //
        // The editor needs a bounded height, and a row's page is read at the
        // measure the row page itself sets.
        SizedBox(
          height: 460,
          child: PageVersionCanvas(
            viewId: version.viewId,
            versionId: version.id,
            content: payload.document,
            scale: 1,
            interactive: interactive,
            placeholder: Text(
              LocaleKeys.pageVersions_rowNoPage.tr(),
              style: TextStyle(fontSize: 13, color: palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

class _Property extends StatelessWidget {
  const _Property({
    required this.column,
    required this.value,
    required this.palette,
  });

  final PageVersionColumn column;
  final String value;
  final TableViewPalette palette;

  @override
  Widget build(BuildContext context) {
    final field = FieldPB(
      id: column.id,
      name: column.name,
      fieldType: FieldType.valueOf(column.fieldType) ?? FieldType.RichText,
      isPrimary: column.isPrimary,
    );
    final kind = classifyTableProperty(field: field, value: value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                column.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: value.trim().isEmpty
                ? Text(
                    LocaleKeys.pageVersions_rowEmptyCell.tr(),
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TablePropertyView(
                      property: TableProperty(
                        fieldId: column.id,
                        name: column.name,
                        value: value,
                        kind: kind,
                        fraction: kind == TablePropertyKind.progress
                            ? tableFractionOf(field: field, value: value)
                            : null,
                        rating: kind == TablePropertyKind.rating
                            ? tableRatingOf(value)
                            : null,
                      ),
                      palette: palette,
                      showLabel: false,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
