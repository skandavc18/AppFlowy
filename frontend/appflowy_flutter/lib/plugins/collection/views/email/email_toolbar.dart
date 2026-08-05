import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_account_dialog.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:appflowy/workspace/application/collections/email/email_state.dart';
import 'package:appflowy/workspace/application/collections/email/mail_sync.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

String emailFilterLabel(EmailFilter filter) => switch (filter) {
      EmailFilter.all => LocaleKeys.collections_email_filterAll.tr(),
      EmailFilter.unread => LocaleKeys.collections_email_filterUnread.tr(),
      EmailFilter.starred => LocaleKeys.collections_email_filterStarred.tr(),
      EmailFilter.attachments =>
        LocaleKeys.collections_email_filterAttachments.tr(),
    };

String emailSortLabel(EmailSort sort) => switch (sort) {
      EmailSort.newest => LocaleKeys.collections_email_sortNewest.tr(),
      EmailSort.oldest => LocaleKeys.collections_email_sortOldest.tr(),
      EmailSort.sender => LocaleKeys.collections_email_sortSender.tr(),
      EmailSort.subject => LocaleKeys.collections_email_sortSubject.tr(),
      EmailSort.size => LocaleKeys.collections_email_sortSize.tr(),
    };

String emailDensityLabel(EmailDensity density) => switch (density) {
      EmailDensity.comfortable =>
        LocaleKeys.collections_email_densityComfortable.tr(),
      EmailDensity.compact => LocaleKeys.collections_email_densityCompact.tr(),
    };

String emailGroupingLabel(EmailGrouping grouping) => switch (grouping) {
      EmailGrouping.none => LocaleKeys.collections_email_groupNone.tr(),
      EmailGrouping.date => LocaleKeys.collections_email_groupDate.tr(),
      EmailGrouping.sender => LocaleKeys.collections_email_groupSender.tr(),
    };

String emailSyncIntervalLabel(int minutes) => minutes == 0
    ? LocaleKeys.collections_email_autoSyncOff.tr()
    : LocaleKeys.collections_email_autoSyncEvery.tr(args: ['$minutes']);

/// The strip above every mailbox view: what is showing, and what it is
/// ordered by.
class EmailToolbar extends StatelessWidget {
  const EmailToolbar({
    super.key,
    required this.controller,
    required this.theme,
    required this.searchController,
    this.trailing = const <Widget>[],
    this.showGrouping = true,
  });

  final EmailController controller;
  final EmailTheme theme;
  final TextEditingController searchController;
  final List<Widget> trailing;
  final bool showGrouping;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    return SizedBox(
      height: EmailMetrics.toolbarHeight,
      child: Row(
        children: [
          for (final filter in EmailFilter.values) ...[
            EmailAction(
              icon: _filterIcon(filter),
              tooltip: emailFilterLabel(filter),
              theme: theme,
              label: emailFilterLabel(filter),
              active: controller.settings.filter == filter,
              onPressed: () => controller.setFilter(filter),
            ),
            const SizedBox(width: EmailMetrics.space1),
          ],
          const EmailGap(size: EmailMetrics.space2),
          if (stats.unread > 0)
            EmailChip(
              label: LocaleKeys.collections_email_unreadCount
                  .tr(args: ['${stats.unread}']),
              theme: theme,
              tone: theme.accent,
            ),
          if (stats.isIndexing) ...[
            const SizedBox(width: EmailMetrics.space2),
            EmailChip(
              label: LocaleKeys.collections_email_reading.tr(
                args: ['${stats.indexed}', '${stats.total}'],
              ),
              theme: theme,
              icon: Icons.hourglass_empty_rounded,
            ),
          ],
          if (controller.isSyncing) ...[
            const SizedBox(width: EmailMetrics.space2),
            EmailChip(
              label: _syncLabel(controller.syncProgress),
              theme: theme,
              icon: Icons.sync_rounded,
              tone: theme.accent,
            ),
          ],
          const Spacer(),
          EmailSearchField(
            controller: searchController,
            theme: theme,
            hintText: LocaleKeys.collections_email_searchHint.tr(),
            onChanged: controller.search,
            width: 226,
          ),
          const SizedBox(width: EmailMetrics.space2),
          EmailAction(
            icon: Icons.swap_vert_rounded,
            tooltip: LocaleKeys.collections_email_sort.tr(),
            theme: theme,
            onPressed: () => _showSorts(context),
          ),
          if (showGrouping)
            EmailAction(
              icon: Icons.segment_rounded,
              tooltip: LocaleKeys.collections_email_group.tr(),
              theme: theme,
              onPressed: () => _showGroups(context),
            ),
          EmailAction(
            icon: Icons.density_medium_rounded,
            tooltip: LocaleKeys.collections_email_density.tr(),
            theme: theme,
            onPressed: () => _showDensity(context),
          ),
          EmailAction(
            icon: controller.isConnected
                ? Icons.sync_rounded
                : Icons.cloud_off_rounded,
            tooltip: controller.isConnected
                ? LocaleKeys.collections_email_syncNow.tr()
                : LocaleKeys.collections_email_connect.tr(),
            theme: theme,
            active: controller.isSyncing,
            onPressed: controller.isSyncing
                ? null
                : () => syncMailWithFeedback(context, controller: controller),
          ),
          EmailAction(
            icon: Icons.settings_rounded,
            tooltip: LocaleKeys.collections_email_mailboxSettings.tr(),
            theme: theme,
            onPressed: () => _showMailbox(context),
          ),
          ...trailing,
        ],
      ),
    );
  }

  IconData _filterIcon(EmailFilter filter) => switch (filter) {
        EmailFilter.all => Icons.all_inbox_rounded,
        EmailFilter.unread => Icons.mark_email_unread_rounded,
        EmailFilter.starred => Icons.star_rounded,
        EmailFilter.attachments => Icons.attach_file_rounded,
      };

  static String _syncLabel(MailSyncProgress? progress) =>
      switch (progress?.stage) {
        MailSyncStage.connecting =>
          LocaleKeys.collections_email_syncConnecting.tr(),
        MailSyncStage.signingIn =>
          LocaleKeys.collections_email_syncSigningIn.tr(),
        MailSyncStage.searching =>
          LocaleKeys.collections_email_syncSearching.tr(),
        MailSyncStage.fetching => LocaleKeys.collections_email_syncFetching.tr(
            args: ['${progress!.fetched}', '${progress.total}'],
          ),
        _ => LocaleKeys.collections_email_syncNow.tr(),
      };

  Future<void> _showSorts(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_email_sort.tr()),
          for (final sort in EmailSort.values)
            AppMenuItem(
              label: emailSortLabel(sort),
              selected: controller.settings.sort == sort,
              onSelected: () => controller.setSort(sort),
            ),
        ],
      );

  Future<void> _showGroups(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_email_group.tr()),
          for (final grouping in EmailGrouping.values)
            AppMenuItem(
              label: emailGroupingLabel(grouping),
              selected: controller.settings.grouping == grouping,
              onSelected: () => controller.setGrouping(grouping),
            ),
        ],
      );

  Future<void> _showDensity(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_email_density.tr()),
          for (final density in EmailDensity.values)
            AppMenuItem(
              label: emailDensityLabel(density),
              selected: controller.settings.density == density,
              onSelected: () => controller.setDensity(density),
            ),
        ],
      );

  Future<void> _showMailbox(BuildContext context) => showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuHeader(LocaleKeys.collections_email_mailboxSettings.tr()),
          AppMenuItem(
            label: controller.isConnected
                ? LocaleKeys.collections_email_mailboxSettings.tr()
                : LocaleKeys.collections_email_connect.tr(),
            icon: Icons.cloud_sync_rounded,
            onSelected: () =>
                showMailAccountDialog(context, controller: controller),
          ),
          const AppMenuSeparator(),
          AppMenuHeader(LocaleKeys.collections_email_autoSync.tr()),
          for (final minutes in emailSyncIntervals)
            AppMenuItem(
              label: emailSyncIntervalLabel(minutes),
              selected: controller.settings.syncMinutes == minutes,
              onSelected: () => controller.setSyncMinutes(minutes),
            ),
        ],
      );
}

/// The rail down the side of the three-pane view: the correspondents the
/// mailbox holds, and how much of each is unread.
class EmailSenderRail extends StatelessWidget {
  const EmailSenderRail({
    super.key,
    required this.controller,
    required this.theme,
  });

  final EmailController controller;
  final EmailTheme theme;

  @override
  Widget build(BuildContext context) {
    final senders = controller.senders;
    final stats = controller.stats;
    return EmailPanel(
      padding: const EdgeInsets.fromLTRB(
        EmailMetrics.space2,
        EmailMetrics.space3,
        EmailMetrics.space2,
        EmailMetrics.space3,
      ),
      child: EmailScrollArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EmailMetrics.space2,
                0,
                EmailMetrics.space2,
                EmailMetrics.space2,
              ),
              child: Text(
                LocaleKeys.collections_email_mailbox.tr(),
                style: theme.sectionLabel,
              ),
            ),
            _RailRow(
              theme: theme,
              icon: Icons.all_inbox_rounded,
              label: LocaleKeys.collections_email_allMail.tr(),
              count: stats.total,
              unread: stats.unread,
              selected: controller.state.activeSender == null,
              onTap: () => controller.setActiveSender(null),
            ),
            _RailRow(
              theme: theme,
              icon: Icons.star_rounded,
              label: LocaleKeys.collections_email_filterStarred.tr(),
              count: stats.starred,
              unread: 0,
              selected: controller.settings.filter == EmailFilter.starred,
              onTap: () => controller.setFilter(
                controller.settings.filter == EmailFilter.starred
                    ? EmailFilter.all
                    : EmailFilter.starred,
              ),
            ),
            _RailRow(
              theme: theme,
              icon: Icons.attach_file_rounded,
              label: LocaleKeys.collections_email_filterAttachments.tr(),
              count: stats.withAttachments,
              unread: 0,
              selected: controller.settings.filter == EmailFilter.attachments,
              onTap: () => controller.setFilter(
                controller.settings.filter == EmailFilter.attachments
                    ? EmailFilter.all
                    : EmailFilter.attachments,
              ),
            ),
            if (senders.isNotEmpty) ...[
              const SizedBox(height: EmailMetrics.space4),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  EmailMetrics.space2,
                  0,
                  EmailMetrics.space2,
                  EmailMetrics.space2,
                ),
                child: Text(
                  LocaleKeys.collections_email_correspondents.tr(),
                  style: theme.sectionLabel,
                ),
              ),
              for (final sender in senders.take(40))
                _RailRow(
                  theme: theme,
                  label: sender.value,
                  count: sender.count,
                  unread: sender.unread,
                  selected: controller.state.activeSender == sender.value,
                  avatarSeed: sender.value,
                  onTap: () => controller.setActiveSender(
                    controller.state.activeSender == sender.value
                        ? null
                        : sender.value,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailRow extends StatefulWidget {
  const _RailRow({
    required this.theme,
    required this.label,
    required this.count,
    required this.unread,
    required this.selected,
    required this.onTap,
    this.icon,
    this.avatarSeed,
  });

  final EmailTheme theme;
  final String label;
  final int count;
  final int unread;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? avatarSeed;

  @override
  State<_RailRow> createState() => _RailRowState();
}

class _RailRowState extends State<_RailRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final unread = widget.unread > 0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: EmailMetrics.hover,
          curve: EmailMetrics.curve,
          height: 30,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: EmailMetrics.space2,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.selected
                : _hovered
                    ? theme.hover
                    : theme.transparentAs(theme.hover),
            borderRadius: BorderRadius.circular(EmailMetrics.rowRadius),
          ),
          child: Row(
            children: [
              if (widget.icon != null)
                Icon(
                  widget.icon,
                  size: 15,
                  color: widget.selected ? theme.accent : theme.iconRest,
                )
              else if (widget.avatarSeed != null)
                EmailAvatar(
                  name: widget.label,
                  seed: widget.avatarSeed!,
                  theme: theme,
                  size: 18,
                ),
              const SizedBox(width: EmailMetrics.space2),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.face(
                    fontSize: EmailMetrics.metaSize + 1,
                    color: widget.selected
                        ? theme.accent
                        : unread
                            ? theme.textStrong
                            : theme.textBody,
                    axis: unread || widget.selected ? 620 : 545,
                    weight: unread || widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: EmailMetrics.space1),
              Text(
                '${unread ? widget.unread : widget.count}',
                style: theme.face(
                  fontSize: EmailMetrics.metaSize - 0.5,
                  color: unread ? theme.accent : theme.textFaint,
                  axis: unread ? 640 : 545,
                  weight: unread ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
