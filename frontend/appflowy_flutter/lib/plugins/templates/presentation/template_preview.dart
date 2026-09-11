import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_canvas.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/templates/built_in/built_in_templates.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows what a template would make, before it makes it.
///
/// Nothing here is a picture: a dashboard is drawn by the real board, a page
/// by the real editor and a canvas by the real canvas — all read only and all
/// against an empty view id, so none of them can write anything down.
///
/// Returns true when the person wants it.
Future<bool> showTemplatePreview(
  BuildContext context,
  WorkspaceTemplate template, {
  required String confirmLabel,
}) async {
  // A dialog is pushed above the page's own providers, so the ones a previewed
  // widget reads — a reminder list, a calendar, a page link — travel with it.
  final carried = <BlocProvider>[
    ..._carry<TabsBloc>(context),
    ..._carry<UserWorkspaceBloc>(context),
    ..._carry<ReminderBloc>(context),
  ];

  final wanted = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.34),
    builder: (_) {
      final dialog = _TemplatePreviewDialog(
        template: template,
        confirmLabel: confirmLabel,
      );
      return carried.isEmpty
          ? dialog
          : MultiBlocProvider(providers: carried, child: dialog);
    },
  );
  return wanted ?? false;
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

class _TemplatePreviewDialog extends StatefulWidget {
  const _TemplatePreviewDialog({
    required this.template,
    required this.confirmLabel,
  });

  final WorkspaceTemplate template;
  final String confirmLabel;

  @override
  State<_TemplatePreviewDialog> createState() => _TemplatePreviewDialogState();
}

class _TemplatePreviewDialogState extends State<_TemplatePreviewDialog> {
  int _part = 0;

  /// ⚠️ Deliberately empty. Binding a preview's widgets to view ids that do
  /// not exist yet would have every chart and metric reading a table the
  /// backend cannot find, i.e. a preview full of errors. Unbound, they draw
  /// their own "choose a table" card and the layout still reads correctly —
  /// and the table itself is shown as its own part beside the dashboard.
  static const TemplateContext _unbound = {};

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final template = widget.template;
    final parts = template.parts;
    final tone = palette.toneFor(template.accent);

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.all(48),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(
              template: template,
              palette: palette,
              tone: tone,
              confirmLabel: widget.confirmLabel,
              onUse: () => Navigator.of(context).pop(true),
              onClose: () => Navigator.of(context).pop(false),
            ),
            if (parts.length > 1)
              _PartSwitcher(
                parts: parts,
                palette: palette,
                selected: _part,
                onChosen: (index) => setState(() => _part = index),
              ),
            Expanded(
              child: ColoredBox(
                color: palette.canvas,
                child: _PartPreview(
                  // Keyed, so switching part builds a fresh controller rather
                  // than pouring one document into another's.
                  key: ValueKey('${template.id}-$_part'),
                  part: parts[_part],
                  created: _unbound,
                  palette: palette,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.template,
    required this.palette,
    required this.tone,
    required this.confirmLabel,
    required this.onUse,
    required this.onClose,
  });

  final WorkspaceTemplate template;
  final DashboardPalette palette;
  final DashboardTone tone;
  final String confirmLabel;
  final VoidCallback onUse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.wash(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(template.icon, size: 21, color: tone.strong),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.label(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardType.title(palette, size: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    template.description(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        DashboardType.caption(palette).copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            _Pill(
              label: confirmLabel,
              palette: palette,
              tone: tone,
              onTap: onUse,
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onClose,
              iconSize: 18,
              splashRadius: 16,
              color: palette.textMuted,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.palette,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final DashboardPalette palette;
  final DashboardTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: tone.wash(0.2),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 15, color: tone.strong),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tone.strong,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Which of a template's several parts is being looked at.
class _PartSwitcher extends StatelessWidget {
  const _PartSwitcher({
    required this.parts,
    required this.palette,
    required this.selected,
    required this.onChosen,
  });

  final List<TemplatePart> parts;
  final DashboardPalette palette;
  final int selected;
  final ValueChanged<int> onChosen;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
        child: Row(
          children: [
            for (var index = 0; index < parts.length; index++) ...[
              _Tab(
                label: parts[index].name(),
                icon: _kindOf(parts[index]).icon,
                palette: palette,
                selected: index == selected,
                onTap: () => onChosen(index),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
}

TemplateKind _kindOf(TemplatePart part) => switch (part.blueprint) {
      TemplateDashboard() => TemplateKind.dashboard,
      TemplatePage() => TemplateKind.page,
      TemplateDatabase() => TemplateKind.database,
      TemplateCanvas() => TemplateKind.canvas,
      TemplateFolder() => TemplateKind.bundle,
    };

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final DashboardPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? palette.accent : palette.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.12)
                : palette.raised,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: ink),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartPreview extends StatelessWidget {
  const _PartPreview({
    super.key,
    required this.part,
    required this.created,
    required this.palette,
  });

  final TemplatePart part;
  final TemplateContext created;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => switch (part.blueprint) {
        TemplateDashboard(build: final build) => _DashboardPreview(
            document: build(created),
            palette: palette,
          ),
        TemplateCanvas(build: final build) => _CanvasPreview(
            document: build(created),
          ),
        TemplatePage(markdown: final markdown) => _PagePreview(
            markdown: markdown(created),
            title: part.name(),
          ),
        TemplateDatabase(build: final build) => _TablePreview(
            table: build(created),
            palette: palette,
          ),
        TemplateFolder() => const SizedBox.shrink(),
      };
}

/// The real board, read only, against a view id nothing can be written to.
class _DashboardPreview extends StatefulWidget {
  const _DashboardPreview({required this.document, required this.palette});

  final DashboardDocument document;
  final DashboardPalette palette;

  @override
  State<_DashboardPreview> createState() => _DashboardPreviewState();
}

class _DashboardPreviewState extends State<_DashboardPreview> {
  late final DashboardController _controller = DashboardController(
    viewId: '',
    document: widget.document,
    mode: DashboardMode.presentation,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DashboardBoard(
        registry: DashboardSectionRegistry(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in widget.document.sections)
                DashboardSectionView(
                  key: ValueKey(section.id),
                  controller: _controller,
                  section: section,
                  palette: widget.palette,
                ),
            ],
          ),
        ),
      );
}

class _CanvasPreview extends StatefulWidget {
  const _CanvasPreview({required this.document});

  final CanvasDocument document;

  @override
  State<_CanvasPreview> createState() => _CanvasPreviewState();
}

class _CanvasPreviewState extends State<_CanvasPreview> {
  late final CanvasController _controller = CanvasController(
    viewId: '',
    document: widget.document,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CanvasBoard(
        controller: _controller,
        editable: false,
        embedded: true,
        showChrome: false,
      );
}

/// The real editor, read only. It needs a bounded height, which the dialog
/// gives it.
class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.markdown, required this.title});

  final String markdown;
  final String title;

  @override
  Widget build(BuildContext context) => PageVersionCanvas(
        viewId: '',
        versionId: 'template-preview',
        content: customMarkdownToDocument(markdown).toJson(),
        scale: 1,
        interactive: true,
        title: title,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      );
}

/// What the table will hold: its columns, typed, and the rows it starts with.
class _TablePreview extends StatelessWidget {
  const _TablePreview({required this.table, required this.palette});

  final TemplateTable table;
  final DashboardPalette palette;

  static const _minimumColumnWidth = 132.0;

  @override
  Widget build(BuildContext context) {
    final width = table.columns.length * _minimumColumnWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headings(),
                for (final row in table.rows) _row(row),
                if (table.rows.isEmpty) _row(const []),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headings() => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Row(
          children: [
            for (final column in table.columns)
              SizedBox(
                width: _minimumColumnWidth,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _glyphFor(column.type),
                        size: 13,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          column.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _row(List<String> values) => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.gridLine)),
        ),
        // ⚠️ Never `CrossAxisAlignment.stretch` here: this Row sits in a
        // scroll view, so stretch forces h=Infinity on every cell, layout
        // throws where nothing reports it, and the whole preview goes blank.
        child: Row(
          children: [
            for (var index = 0; index < table.columns.length; index++)
              SizedBox(
                width: _minimumColumnWidth,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  child: _cell(
                    table.columns[index],
                    index < values.length ? values[index] : '',
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _cell(TemplateColumn column, String value) {
    if (value.isEmpty) {
      return const SizedBox(height: 18);
    }
    if (column.options.isNotEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.textPrimary),
          ),
        ),
      );
    }
    if (column.type == FieldType.Checkbox) {
      final ticked = const {'yes', 'true', '1'}.contains(value.toLowerCase());
      return Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          ticked
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: 16,
          color: ticked ? palette.accent : palette.textMuted,
        ),
      );
    }
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
    );
  }

  static IconData _glyphFor(FieldType type) => switch (type) {
        FieldType.Number => Icons.tag_rounded,
        FieldType.DateTime => Icons.event_rounded,
        FieldType.Checkbox => Icons.check_box_outlined,
        FieldType.URL => Icons.link_rounded,
        FieldType.SingleSelect => Icons.radio_button_checked_rounded,
        FieldType.MultiSelect => Icons.style_rounded,
        _ => Icons.notes_rounded,
      };
}
