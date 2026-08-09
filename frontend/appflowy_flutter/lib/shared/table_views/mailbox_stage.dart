import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/widgets/row/row_document.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/table_views/mailbox_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A table read the way a mail client reads a mailbox.
///
/// The same rows a grid lists become a column of arrivals: who it is from, what
/// it is about, when it came, and the opening of whatever was written on it.
/// Choosing one opens it beside the list rather than in a window of its own.
class MailboxStage extends StatefulWidget {
  const MailboxStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.onOpenRow,
    this.onAddRow,
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final MailboxSpec spec;
  final ValueChanged<MailboxSpec> onSpecChanged;
  final String? title;

  final ValueChanged<String>? onOpenRow;
  final Future<String?> Function()? onAddRow;

  final EdgeInsets padding;

  @override
  State<MailboxStage> createState() => MailboxStageState();
}

class MailboxStageState extends State<MailboxStage> {
  /// The list keeps its own width so the reader beside it is what grows.
  static const _listWidth = 380.0;

  /// Below this there is no room for two panes, so the reader takes over.
  static const _twoPaneWidth = 880.0;

  late final TableRowSource _source = TableRowSource(viewId: widget.viewId);
  final ScrollController _scroll = ScrollController();
  final GlobalKey<TableViewHeaderState> _header =
      GlobalKey<TableViewHeaderState>();

  TableQuery _query = const TableQuery();
  List<TableRowCard> _visible = const [];
  Set<String> _matches = const {};
  String _openId = '';

  /// A row that names nobody was written here, so it is signed with the name on
  /// the profile rather than left as a stranger.
  String _profileName = '';
  UserListener? _profileListener;

  @override
  void initState() {
    super.initState();
    _source
      ..updateSpec(widget.spec.readSpec)
      ..addListener(_onSourceChanged);
    unawaited(_source.load());
    unawaited(_readProfile());
  }

  @override
  void didUpdateWidget(MailboxStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) {
      _source.updateSpec(widget.spec.readSpec);
      setState(_refine);
    }
  }

  @override
  void dispose() {
    unawaited(_profileListener?.stop());
    _profileListener = null;
    _source.removeListener(_onSourceChanged);
    _source.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _readProfile() async {
    final result = await UserBackendService.getCurrentUserProfile();
    result.fold(
      (profile) {
        _watchProfile(profile);
        _setProfileName(profile.name);
      },
      (error) => Log.error(error),
    );
  }

  /// Follows a rename made in settings, so the list never signs itself with a
  /// name the person has already replaced.
  void _watchProfile(UserProfilePB profile) {
    if (!mounted || _profileListener != null) {
      return;
    }
    _profileListener = UserListener(userProfile: profile)
      ..start(
        onProfileUpdated: (result) => result.fold(
          (updated) => _setProfileName(updated.name),
          (error) => Log.error(error),
        ),
      );
  }

  void _setProfileName(String name) {
    final next = name.trim();
    if (!mounted || _profileName == next) {
      return;
    }
    setState(() => _profileName = next);
  }

  /// Reads the table again — the host calls this when a row changes.
  void reload() => _source.invalidate();

  /// Reads the pages again as well, for when somebody asks outright.
  void _readAgain() {
    RowPageText.forget();
    reload();
  }

  void _onSourceChanged() {
    if (mounted) {
      setState(_refine);
    }
  }

  void _refine() {
    var cards = applyTableQuery(_source.cards, _query);
    // A mailbox with no order of its own reads newest first.
    if (!_query.isSorting) {
      cards = [...cards]..sort((a, b) {
          final left = _dateOf(a);
          final right = _dateOf(b);
          if (left == null && right == null) {
            return 0;
          }
          if (left == null) {
            return 1;
          }
          if (right == null) {
            return -1;
          }
          return right.compareTo(left);
        });
    }
    _visible = cards;
    _matches = tableMatchesOf(_visible, _query.search);
    if (_visible.every((card) => card.rowId != _openId)) {
      _openId = _visible.isEmpty ? '' : _visible.first.rowId;
    }
  }

  void _setQuery(TableQuery query) => setState(() {
        _query = query;
        _refine();
      });

  DateTime? _dateOf(TableRowCard card) {
    final column = widget.spec.dateColumn;
    if (column.isNotEmpty) {
      final value = card.propertyOf(column)?.value ?? '';
      final parsed = parseTableDate(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return card.lastModified;
  }

  String _senderOf(TableRowCard card) {
    final column = widget.spec.senderColumn;
    if (column.isNotEmpty) {
      final named = card.propertyOf(column)?.value.trim() ?? '';
      return named.isEmpty ? _profileName : named;
    }
    for (final property in card.properties) {
      if (property.kind == TablePropertyKind.person && !property.isEmpty) {
        return property.value.trim();
      }
    }
    return _profileName;
  }

  String _snippetColumnOf(TableRowCard card) {
    final column = widget.spec.snippetColumn;
    if (column.isEmpty) {
      return '';
    }
    return card.propertyOf(column)?.value.trim() ?? '';
  }

  TableRowCard? get _open {
    for (final card in _visible) {
      if (card.rowId == _openId) {
        return card;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _header.currentState?.openSearch(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _header.currentState?.openSearch(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _header.currentState?.closeSearch(),
      },
      child: Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(palette),
            const SizedBox(height: TableViewMetrics.space3),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TableViewPalette palette) => TableViewHeader(
        key: _header,
        palette: palette,
        title: widget.title?.trim().isNotEmpty == true
            ? widget.title!
            : LocaleKeys.mailbox_name.tr(),
        subtitle: LocaleKeys.mailbox_rowCount
            .tr(namedArgs: {'count': '${_visible.length}'}),
        columns: _source.fields,
        query: _query,
        onQueryChanged: _setQuery,
        valuesOf: (fieldId) => tableValuesOf(_source.cards, fieldId),
        onAdd: widget.onAddRow == null ? null : _addRow,
        optionsBuilder: _options,
        actions: [
          TableViewButton(
            palette: palette,
            icon: widget.spec.density == MailboxDensity.comfortable
                ? Icons.density_medium_rounded
                : Icons.density_small_rounded,
            tooltip: LocaleKeys.mailbox_density.tr(),
            onTap: () => widget.onSpecChanged(
              widget.spec.copyWith(
                density: widget.spec.density == MailboxDensity.comfortable
                    ? MailboxDensity.compact
                    : MailboxDensity.comfortable,
              ),
            ),
          ),
          const SizedBox(width: TableViewMetrics.controlGap),
          TableViewButton(
            palette: palette,
            icon: Icons.vertical_split_rounded,
            tooltip: LocaleKeys.mailbox_readingPane.tr(),
            active: widget.spec.showReader,
            onTap: () => widget.onSpecChanged(
              widget.spec.copyWith(showReader: !widget.spec.showReader),
            ),
          ),
        ],
      );

  Widget _buildBody(TableViewPalette palette) {
    if (_source.isLoading && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.mark_email_unread_rounded,
        message: LocaleKeys.tableViews_loading.tr(),
      );
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.mark_email_unread_rounded,
        message: LocaleKeys.tableViews_couldNotRead.tr(),
        detail: error,
        actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
        onAction: reload,
      );
    }
    if (_visible.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.mark_email_unread_rounded,
        message: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatch.tr()
            : LocaleKeys.mailbox_empty.tr(),
        detail: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatchDetail.tr()
            : LocaleKeys.mailbox_emptyDetail.tr(),
        actionLabel: _query.isFiltering
            ? LocaleKeys.tableViews_clearFilter.tr()
            : LocaleKeys.mailbox_addFirst.tr(),
        onAction: _query.isFiltering
            ? () =>
                _setQuery(_query.copyWith(filterColumn: '', filterValue: ''))
            : (widget.onAddRow == null ? null : _addRow),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane =
            widget.spec.showReader && constraints.maxWidth >= _twoPaneWidth;
        if (!twoPane) {
          return _buildList(palette, expanded: true);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: _listWidth, child: _buildList(palette)),
            const SizedBox(width: TableViewMetrics.space3),
            Expanded(child: _buildReader(palette)),
          ],
        );
      },
    );
  }

  Widget _buildList(TableViewPalette palette, {bool expanded = false}) {
    final sections = _sections();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        boxShadow: palette.cardShadow(prominence: 0.6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        child: Scrollbar(
          controller: _scroll,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(
              vertical: TableViewMetrics.space2,
            ),
            itemCount: sections.length,
            itemBuilder: (context, at) =>
                _buildSection(palette, sections[at], wide: expanded),
          ),
        ),
      ),
    );
  }

  /// The list broken into the headings a mailbox reads by.
  List<({String label, List<TableRowCard> rows})> _sections() {
    if (_query.isGrouping) {
      return groupTableRows(
        _visible,
        _query.groupColumn,
        ungrouped: LocaleKeys.tableViews_ungrouped.tr(),
      ).map((group) => (label: group.label, rows: group.rows)).toList();
    }
    if (!widget.spec.groupByDate) {
      return [(label: '', rows: _visible)];
    }
    return groupMailboxRows(_visible, dateOf: _dateOf)
        .map((section) => (label: _bandLabel(section.band), rows: section.rows))
        .toList();
  }

  String _bandLabel(MailboxBand band) => switch (band) {
        MailboxBand.today => LocaleKeys.mailbox_today.tr(),
        MailboxBand.yesterday => LocaleKeys.mailbox_yesterday.tr(),
        MailboxBand.thisWeek => LocaleKeys.mailbox_thisWeek.tr(),
        MailboxBand.thisMonth => LocaleKeys.mailbox_thisMonth.tr(),
        MailboxBand.earlier => LocaleKeys.mailbox_earlier.tr(),
        MailboxBand.undated => LocaleKeys.mailbox_undated.tr(),
      };

  Widget _buildSection(
    TableViewPalette palette,
    ({String label, List<TableRowCard> rows}) section, {
    required bool wide,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TableViewMetrics.space4,
                TableViewMetrics.space3,
                TableViewMetrics.space4,
                TableViewMetrics.space1,
              ),
              child: TableGroupHeading(
                palette: palette,
                label: section.label,
                count: section.rows.length,
              ),
            ),
          for (final card in section.rows)
            _MailboxRow(
              key: ValueKey(card.rowId),
              card: card,
              palette: palette,
              sender: _senderOf(card),
              snippet: _snippetColumnOf(card),
              when: _dateOf(card),
              density: widget.spec.density,
              selected: !wide && card.rowId == _openId,
              highlighted: !_query.isSearching || _matches.contains(card.rowId),
              onTap: () => _choose(card, openPage: wide),
              onOpen: widget.onOpenRow == null
                  ? null
                  : () => widget.onOpenRow!(card.rowId),
              onContextMenu: (position) => _showRowMenu(card, position),
            ),
        ],
      );

  /// A click reads the row beside the list; with no room for a reader it opens
  /// the row itself rather than doing nothing.
  void _choose(TableRowCard card, {required bool openPage}) {
    if (openPage) {
      widget.onOpenRow?.call(card.rowId);
      return;
    }
    setState(() => _openId = card.rowId);
  }

  Widget _buildReader(TableViewPalette palette) {
    final card = _open;
    if (card == null) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.drafts_rounded,
        message: LocaleKeys.mailbox_nothingOpen.tr(),
        detail: LocaleKeys.mailbox_nothingOpenDetail.tr(),
      );
    }
    return _MailboxReader(
      key: ValueKey(card.rowId),
      viewId: widget.viewId,
      card: card,
      palette: palette,
      sender: _senderOf(card),
      when: _dateOf(card),
      editing: widget.spec.editPage,
      onEditingChanged: (editing) => widget.onSpecChanged(
        widget.spec.copyWith(editPage: editing),
      ),
      onOpen:
          widget.onOpenRow == null ? null : () => widget.onOpenRow!(card.rowId),
    );
  }

  void _addRow() {
    final add = widget.onAddRow;
    if (add == null) {
      return;
    }
    unawaited(add());
  }

  Future<void> _showRowMenu(TableRowCard card, Offset position) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuHeader(
          card.title.isEmpty ? LocaleKeys.mailbox_noSubject.tr() : card.title,
        ),
        AppMenuItem(
          label: LocaleKeys.mailbox_openRow.tr(),
          icon: Icons.open_in_full_rounded,
          enabled: widget.onOpenRow != null,
          onSelected: () => widget.onOpenRow?.call(card.rowId),
        ),
        AppMenuItem(
          label: LocaleKeys.mailbox_readHere.tr(),
          icon: Icons.chrome_reader_mode_rounded,
          onSelected: () => setState(() => _openId = card.rowId),
        ),
      ],
    );
  }

  List<AppMenuEntry> _options() => [
        AppMenuHeader(LocaleKeys.tableViews_options.tr()),
        AppMenuItem(
          label: LocaleKeys.mailbox_readingPane.tr(),
          icon: Icons.vertical_split_rounded,
          selected: widget.spec.showReader,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(showReader: !widget.spec.showReader),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.mailbox_groupByDate.tr(),
          icon: Icons.event_note_rounded,
          selected: widget.spec.groupByDate,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(groupByDate: !widget.spec.groupByDate),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.mailbox_editPage.tr(),
          icon: Icons.edit_note_rounded,
          selected: widget.spec.editPage,
          enabled: widget.spec.showReader,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(editPage: !widget.spec.editPage),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.mailbox_comfortable.tr(),
          icon: Icons.density_medium_rounded,
          selected: widget.spec.density == MailboxDensity.comfortable,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(density: MailboxDensity.comfortable),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.mailbox_compact.tr(),
          icon: Icons.density_small_rounded,
          selected: widget.spec.density == MailboxDensity.compact,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(density: MailboxDensity.compact),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.tableViews_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: _readAgain,
        ),
      ];
}

/// One arrival in the list.
class _MailboxRow extends StatefulWidget {
  const _MailboxRow({
    super.key,
    required this.card,
    required this.palette,
    required this.sender,
    required this.snippet,
    required this.when,
    required this.density,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    this.onOpen,
    this.onContextMenu,
  });

  final TableRowCard card;
  final TableViewPalette palette;
  final String sender;
  final String snippet;
  final DateTime? when;
  final MailboxDensity density;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback? onOpen;
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  State<_MailboxRow> createState() => _MailboxRowState();
}

class _MailboxRowState extends State<_MailboxRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final card = widget.card;
    final subject = card.title.trim().isEmpty
        ? LocaleKeys.mailbox_noSubject.tr()
        : card.title;
    final sender = widget.sender.isEmpty
        ? LocaleKeys.mailbox_unknownSender.tr()
        : widget.sender;

    final background = widget.selected
        ? palette.accent.withValues(alpha: palette.isDark ? 0.18 : 0.11)
        : _hovered
            ? palette.hover
            : palette.hover.withValues(alpha: 0);

    return Opacity(
      opacity: widget.highlighted ? 1 : 0.42,
      child: MouseRegion(
        opaque: false,
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTap: widget.onOpen,
          onSecondaryTapUp: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          child: AnimatedContainer(
            duration: TableViewMetrics.hover,
            margin: const EdgeInsets.symmetric(
              horizontal: TableViewMetrics.space2,
              vertical: 1,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: TableViewMetrics.space3,
              vertical: TableViewMetrics.space2,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius:
                  BorderRadius.circular(TableViewMetrics.controlRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                  label: card.icon ?? sender,
                  isEmoji: card.icon != null,
                  colour: palette.swatchFor(
                    card.accent.isNotEmpty ? card.accent : sender,
                  ),
                  size: widget.density.showsSnippet ? 34 : 26,
                ),
                const SizedBox(width: TableViewMetrics.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: TableViewMetrics.space2),
                          Text(
                            mailboxDateLabel(widget.when),
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: palette.textSecondary,
                        ),
                      ),
                      if (widget.density.showsSnippet) ...[
                        const SizedBox(height: 3),
                        _Snippet(
                          card: card,
                          palette: palette,
                          written: widget.snippet,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered != hovered && mounted) {
      setState(() => _hovered = hovered);
    }
  }
}

/// The second line: a chosen column when there is one, otherwise the opening
/// of the row's own page.
class _Snippet extends StatelessWidget {
  const _Snippet({
    required this.card,
    required this.palette,
    required this.written,
  });

  final TableRowCard card;
  final TableViewPalette palette;
  final String written;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      height: 1.35,
      color: palette.textMuted,
    );
    if (written.isNotEmpty) {
      return Text(
        written,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return RowPageTextView(
      documentId: card.documentId,
      builder: (context, text) => Text(
        _oneLine(text ?? ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// The open row, read — and written on — beside the list.
class _MailboxReader extends StatelessWidget {
  const _MailboxReader({
    super.key,
    required this.viewId,
    required this.card,
    required this.palette,
    required this.sender,
    required this.when,
    required this.editing,
    required this.onEditingChanged,
    this.onOpen,
  });

  final String viewId;
  final TableRowCard card;
  final TableViewPalette palette;
  final String sender;
  final DateTime? when;

  /// Whether the page below the envelope is the row's own, open for writing.
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final subject = card.title.trim().isEmpty
        ? LocaleKeys.mailbox_noSubject.tr()
        : card.title;
    final from =
        sender.isEmpty ? LocaleKeys.mailbox_unknownSender.tr() : sender;
    final properties = card.filled;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        boxShadow: palette.cardShadow(prominence: 0.6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final head = Padding(
              padding: const EdgeInsets.fromLTRB(
                TableViewMetrics.space5,
                TableViewMetrics.space5,
                TableViewMetrics.space5,
                TableViewMetrics.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          subject,
                          style: TextStyle(
                            fontSize: 19,
                            height: 1.28,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: TableViewMetrics.space3),
                      TableViewButton(
                        palette: palette,
                        icon: Icons.edit_note_rounded,
                        tooltip: LocaleKeys.mailbox_editPage.tr(),
                        active: editing,
                        onTap: () => onEditingChanged(!editing),
                      ),
                      if (onOpen != null) ...[
                        const SizedBox(width: TableViewMetrics.controlGap),
                        TableViewButton(
                          palette: palette,
                          icon: Icons.open_in_full_rounded,
                          tooltip: LocaleKeys.mailbox_openRow.tr(),
                          onTap: onOpen!,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: TableViewMetrics.space4),
                  Row(
                    children: [
                      _Avatar(
                        label: card.icon ?? from,
                        isEmoji: card.icon != null,
                        colour: palette.swatchFor(
                          card.accent.isNotEmpty ? card.accent : from,
                        ),
                        size: 34,
                      ),
                      const SizedBox(width: TableViewMetrics.space3),
                      Expanded(
                        child: Text(
                          from,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: TableViewMetrics.space3),
                      Text(
                        mailboxFullDateLabel(when),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (properties.isNotEmpty) ...[
                    const SizedBox(height: TableViewMetrics.space4),
                    Wrap(
                      spacing: TableViewMetrics.space5,
                      runSpacing: TableViewMetrics.space3,
                      children: [
                        for (final property in properties)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: TablePropertyView(
                              property: property,
                              palette: palette,
                              live: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The envelope keeps to its own share, so a row carrying a
                // dozen properties cannot squeeze the page out of the pane.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.hasBoundedHeight
                        ? constraints.maxHeight * 0.5
                        : double.infinity,
                  ),
                  child: SingleChildScrollView(child: head),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      // The page brings its own measure, and its + and ::
                      // handles need the margin the pane would otherwise take.
                      editing ? 0 : TableViewMetrics.space5,
                      0,
                      editing ? 0 : TableViewMetrics.space5,
                      editing ? 0 : TableViewMetrics.space6,
                    ),
                    child: editing
                        ? _MailboxPage(
                            viewId: viewId,
                            rowId: card.rowId,
                            documentId: card.documentId,
                          )
                        : RowPagePreview(
                            documentId: card.documentId,
                            scale: 1,
                            interactive: true,
                            emptyBuilder: (context) => Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                LocaleKeys.mailbox_pageEmpty.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.textMuted,
                                ),
                              ),
                            ),
                            textBuilder: (context, text) =>
                                SingleChildScrollView(
                              child: SelectableText(
                                text ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.62,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The open row's own page, opened for writing.
///
/// The reader otherwise shows a copy of the page taken when it was last read;
/// this is the page itself, so what is typed here is what the row keeps. A row
/// whose page has never been written on has none yet — [RowDocument] makes it.
class _MailboxPage extends StatefulWidget {
  const _MailboxPage({
    required this.viewId,
    required this.rowId,
    required this.documentId,
  });

  final String viewId;
  final String rowId;
  final String documentId;

  @override
  State<_MailboxPage> createState() => _MailboxPageState();
}

class _MailboxPageState extends State<_MailboxPage> {
  @override
  void dispose() {
    // The list and the reading pane are both showing what this page said when
    // it was last read, so they have to read it again. A page made during the
    // visit had no id to forget, which is what forgetting all of them covers.
    final documentId = widget.documentId;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => RowPageText.forget(documentId.isEmpty ? null : documentId),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RowDocument(
        viewId: widget.viewId,
        rowId: widget.rowId,
        // The pane is a box of its own, so the page scrolls inside it rather
        // than growing past it.
        shrinkWrap: false,
        contentInset: TableViewMetrics.space5,
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.isEmoji,
    required this.colour,
    required this.size,
  });

  final String label;
  final bool isEmoji;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Text(
          isEmoji ? label : tableInitialsOf(label),
          style: TextStyle(
            fontSize: isEmoji ? size * 0.5 : size * 0.38,
            fontWeight: FontWeight.w600,
            color: colour,
          ),
        ),
      );
}

/// A date the way a mailbox writes it: a time today, a weekday this week, a
/// date after that.
String mailboxDateLabel(DateTime? when, {DateTime? now}) {
  if (when == null) {
    return '';
  }
  final local = when.toLocal();
  final today = now?.toLocal() ?? DateTime.now();
  final sameDay = local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  if (sameDay) {
    return DateFormat.jm().format(local);
  }
  if (today.difference(local).inDays < 7 && local.isBefore(today)) {
    return DateFormat.E().format(local);
  }
  if (local.year == today.year) {
    return DateFormat.MMMd().format(local);
  }
  return DateFormat.yMMMd().format(local);
}

String mailboxFullDateLabel(DateTime? when) {
  if (when == null) {
    return '';
  }
  final local = when.toLocal();
  return '${DateFormat.yMMMMd().format(local)} · ${DateFormat.jm().format(local)}';
}

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
