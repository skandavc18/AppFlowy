import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/email_state.dart';
import 'package:appflowy/workspace/application/collections/email/email_thread.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The message list, shared by every mailbox view.
///
/// One list serves all three readings: the density decides how tall a row is,
/// the grouping decides what breaks it up, and whether a row stands for a
/// message or a whole conversation is the caller's choice.
class EmailMessageList extends StatelessWidget {
  const EmailMessageList({
    super.key,
    required this.controller,
    required this.theme,
    required this.onOpen,
    this.threaded = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: EmailMetrics.space2,
      vertical: EmailMetrics.space2,
    ),
  });

  final EmailController controller;
  final EmailTheme theme;
  final ValueChanged<String> onOpen;

  /// Whether a row stands for a conversation rather than one message.
  final bool threaded;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rows = threaded ? _threadRows() : _messageRows();
    if (rows.isEmpty) {
      return EmailEmptyState(
        icon: Icons.mark_email_read_rounded,
        title: LocaleKeys.collections_email_noMatches.tr(),
        theme: theme,
        message: LocaleKeys.collections_email_noMatchesHint.tr(),
      );
    }

    return EmailScrollArea(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  List<Widget> _messageRows() {
    final rows = <Widget>[];
    String? heading;

    for (final message in controller.messages) {
      final next = _headingFor(message);
      if (next != null && next != heading) {
        heading = next;
        rows.add(_Heading(label: next, theme: theme));
      }
      rows.add(
        EmailRow(
          key: ValueKey(message.id),
          message: message,
          theme: theme,
          density: controller.settings.density,
          selected: controller.activeId == message.id,
          onOpen: () => onOpen(message.id),
          onToggleStar: () => controller.toggleStarred(message.id),
          onToggleRead: () => controller.toggleRead(message.id),
        ),
      );
    }
    return rows;
  }

  List<Widget> _threadRows() {
    final rows = <Widget>[];
    for (final thread in controller.threads) {
      rows.add(
        EmailThreadRow(
          key: ValueKey(thread.id),
          thread: thread,
          theme: theme,
          density: controller.settings.density,
          selected: thread.messages.any(
            (message) => message.id == controller.activeId,
          ),
          onOpen: () => onOpen(thread.representative.id),
          onToggleStar: () => controller.setStarred(
            thread.messages.map((message) => message.id).toList(),
            starred: !thread.starred,
          ),
          onToggleRead: () => controller.setRead(
            thread.messages.map((message) => message.id).toList(),
            read: thread.hasUnread,
          ),
        ),
      );
    }
    return rows;
  }

  String? _headingFor(EmailMessage message) =>
      switch (controller.settings.grouping) {
        EmailGrouping.none => null,
        EmailGrouping.sender => message.sender,
        EmailGrouping.date => _dateHeading(message.sentAt),
      };

  String? _dateHeading(DateTime? moment) {
    if (moment == null) {
      return LocaleKeys.collections_email_undated.tr();
    }
    final local = moment.toLocal();
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final day = DateTime(local.year, local.month, local.day);
    final difference = startOfToday.difference(day).inDays;

    if (difference <= 0) {
      return LocaleKeys.collections_email_today.tr();
    }
    if (difference == 1) {
      return LocaleKeys.collections_email_yesterday.tr();
    }
    if (difference < 7) {
      return LocaleKeys.collections_email_thisWeek.tr();
    }
    if (difference < 31) {
      return LocaleKeys.collections_email_thisMonth.tr();
    }
    return LocaleKeys.collections_email_older.tr();
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.label, required this.theme});

  final String label;
  final EmailTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          EmailMetrics.space2,
          EmailMetrics.space4,
          EmailMetrics.space2,
          EmailMetrics.space2,
        ),
        child: Text(label, style: theme.sectionLabel),
      );
}

/// One message in a list.
class EmailRow extends StatefulWidget {
  const EmailRow({
    super.key,
    required this.message,
    required this.theme,
    required this.density,
    required this.selected,
    required this.onOpen,
    required this.onToggleStar,
    required this.onToggleRead,
  });

  final EmailMessage message;
  final EmailTheme theme;
  final EmailDensity density;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;
  final VoidCallback onToggleRead;

  @override
  State<EmailRow> createState() => _EmailRowState();
}

class _EmailRowState extends State<EmailRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final message = widget.message;
    final unread = !message.read;
    final compact = widget.density == EmailDensity.compact;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: EmailMetrics.hover,
          curve: EmailMetrics.curve,
          height: widget.density.rowHeight,
          margin: const EdgeInsets.only(bottom: 1),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? EmailMetrics.space2 : EmailMetrics.space3,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.selected
                : _hovered
                    ? theme.hover
                    : theme.transparentAs(theme.hover),
            borderRadius: BorderRadius.circular(EmailMetrics.rowRadius),
          ),
          child: compact
              ? _buildCompact(theme, message, unread: unread)
              : _buildComfortable(theme, message, unread: unread),
        ),
      ),
    );
  }

  Widget _buildComfortable(
    EmailTheme theme,
    EmailMessage message, {
    required bool unread,
  }) =>
      Row(
        children: [
          SizedBox(
            width: EmailMetrics.unreadDot + EmailMetrics.space1,
            child: unread ? EmailUnreadDot(theme: theme) : null,
          ),
          EmailAvatar(
            name: message.sender,
            seed: message.metadata.fromAddress,
            theme: theme,
          ),
          const SizedBox(width: EmailMetrics.space3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message.sender.isEmpty
                            ? LocaleKeys.collections_email_unknownSender.tr()
                            : message.sender,
                        overflow: TextOverflow.ellipsis,
                        style: theme.sender(unread: unread),
                      ),
                    ),
                    const SizedBox(width: EmailMetrics.space2),
                    Text(
                      emailDateLabel(message.sentAt),
                      style: theme.meta,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  message.subject.isEmpty
                      ? LocaleKeys.collections_email_noSubject.tr()
                      : message.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.subject(unread: unread),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (message.metadata.hasAttachments) ...[
                      Icon(
                        Icons.attach_file_rounded,
                        size: 11,
                        color: theme.textFaint,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Expanded(
                      child: Text(
                        message.metadata.unreadable
                            ? LocaleKeys.collections_email_unreadable.tr()
                            : message.metadata.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.snippet,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _actions(theme, message),
        ],
      );

  Widget _buildCompact(
    EmailTheme theme,
    EmailMessage message, {
    required bool unread,
  }) =>
      Row(
        children: [
          SizedBox(
            width: EmailMetrics.unreadDot + EmailMetrics.space1,
            child: unread ? EmailUnreadDot(theme: theme, size: 6) : null,
          ),
          SizedBox(
            width: 148,
            child: Text(
              message.sender.isEmpty
                  ? LocaleKeys.collections_email_unknownSender.tr()
                  : message.sender,
              overflow: TextOverflow.ellipsis,
              style: theme.sender(unread: unread),
            ),
          ),
          const SizedBox(width: EmailMetrics.space3),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    message.subject.isEmpty
                        ? LocaleKeys.collections_email_noSubject.tr()
                        : message.subject,
                    overflow: TextOverflow.ellipsis,
                    style: theme.subject(unread: unread),
                  ),
                ),
                const SizedBox(width: EmailMetrics.space2),
                Flexible(
                  flex: 2,
                  child: Text(
                    message.metadata.snippet,
                    overflow: TextOverflow.ellipsis,
                    style: theme.snippet,
                  ),
                ),
              ],
            ),
          ),
          if (message.metadata.hasAttachments) ...[
            const SizedBox(width: EmailMetrics.space2),
            Icon(Icons.attach_file_rounded, size: 12, color: theme.textFaint),
          ],
          const SizedBox(width: EmailMetrics.space2),
          SizedBox(
            width: 62,
            child: Text(
              emailDateLabel(message.sentAt),
              textAlign: TextAlign.right,
              style: theme.meta,
            ),
          ),
          _actions(theme, message, compact: true),
        ],
      );

  Widget _actions(
    EmailTheme theme,
    EmailMessage message, {
    bool compact = false,
  }) {
    final starred = message.starred;
    // The star is always shown once it is set; the rest only appear under the
    // pointer, so a resting list stays quiet.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (starred || _hovered)
          EmailAction(
            icon: starred ? Icons.star_rounded : Icons.star_outline_rounded,
            tooltip: starred
                ? LocaleKeys.collections_email_unstar.tr()
                : LocaleKeys.collections_email_star.tr(),
            theme: theme,
            size: compact ? 22 : 26,
            tint: starred ? const Color(0xFFE0A400) : null,
            onPressed: widget.onToggleStar,
          ),
        if (_hovered)
          EmailAction(
            icon: message.read
                ? Icons.mark_email_unread_rounded
                : Icons.mark_email_read_rounded,
            tooltip: message.read
                ? LocaleKeys.collections_email_markUnread.tr()
                : LocaleKeys.collections_email_markRead.tr(),
            theme: theme,
            size: compact ? 22 : 26,
            onPressed: widget.onToggleRead,
          ),
      ],
    );
  }
}

/// One conversation in a list.
class EmailThreadRow extends StatefulWidget {
  const EmailThreadRow({
    super.key,
    required this.thread,
    required this.theme,
    required this.density,
    required this.selected,
    required this.onOpen,
    required this.onToggleStar,
    required this.onToggleRead,
  });

  final EmailThread thread;
  final EmailTheme theme;
  final EmailDensity density;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onToggleStar;
  final VoidCallback onToggleRead;

  @override
  State<EmailThreadRow> createState() => _EmailThreadRowState();
}

class _EmailThreadRowState extends State<EmailThreadRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final thread = widget.thread;
    final unread = thread.hasUnread;
    final compact = widget.density == EmailDensity.compact;
    final participants = thread.participants;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: EmailMetrics.hover,
          curve: EmailMetrics.curve,
          height: compact ? 36.0 : 70.0,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: EmailMetrics.space3,
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
              SizedBox(
                width: EmailMetrics.unreadDot + EmailMetrics.space1,
                child: unread ? EmailUnreadDot(theme: theme) : null,
              ),
              if (!compact) ...[
                EmailAvatar(
                  name: participants.isEmpty ? '' : participants.first,
                  seed: thread.first.metadata.fromAddress,
                  theme: theme,
                ),
                const SizedBox(width: EmailMetrics.space3),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            participants.isEmpty
                                ? LocaleKeys.collections_email_unknownSender
                                    .tr()
                                : participants.join(', '),
                            overflow: TextOverflow.ellipsis,
                            style: theme.sender(unread: unread),
                          ),
                        ),
                        if (!thread.isSingle) ...[
                          const SizedBox(width: EmailMetrics.space2),
                          EmailChip(
                            label: '${thread.length}',
                            theme: theme,
                            icon: Icons.forum_rounded,
                          ),
                        ],
                        const SizedBox(width: EmailMetrics.space2),
                        Text(
                          emailDateLabel(thread.lastSentAt),
                          style: theme.meta,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            thread.subject.isEmpty
                                ? LocaleKeys.collections_email_noSubject.tr()
                                : thread.subject,
                            overflow: TextOverflow.ellipsis,
                            style: theme.subject(unread: unread),
                          ),
                        ),
                        if (thread.hasAttachments) ...[
                          const SizedBox(width: EmailMetrics.space1 + 2),
                          Icon(
                            Icons.attach_file_rounded,
                            size: 11,
                            color: theme.textFaint,
                          ),
                        ],
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        thread.representative.metadata.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.snippet,
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thread.starred || _hovered)
                    EmailAction(
                      icon: thread.starred
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      tooltip: thread.starred
                          ? LocaleKeys.collections_email_unstar.tr()
                          : LocaleKeys.collections_email_star.tr(),
                      theme: theme,
                      size: compact ? 22 : 26,
                      tint: thread.starred ? const Color(0xFFE0A400) : null,
                      onPressed: widget.onToggleStar,
                    ),
                  if (_hovered)
                    EmailAction(
                      icon: unread
                          ? Icons.mark_email_read_rounded
                          : Icons.mark_email_unread_rounded,
                      tooltip: unread
                          ? LocaleKeys.collections_email_markRead.tr()
                          : LocaleKeys.collections_email_markUnread.tr(),
                      theme: theme,
                      size: compact ? 22 : 26,
                      onPressed: widget.onToggleRead,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
