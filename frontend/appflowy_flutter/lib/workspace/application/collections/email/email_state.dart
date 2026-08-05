import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:flutter/foundation.dart';

/// How a mailbox is ordered.
enum EmailSort {
  newest,
  oldest,
  sender,
  subject,
  size;

  static EmailSort fromValue(Object? value) {
    for (final sort in EmailSort.values) {
      if (sort.name == value) {
        return sort;
      }
    }
    return EmailSort.newest;
  }
}

/// Which messages a mailbox is showing.
enum EmailFilter {
  all,
  unread,
  starred,
  attachments;

  static EmailFilter fromValue(Object? value) {
    for (final filter in EmailFilter.values) {
      if (filter.name == value) {
        return filter;
      }
    }
    return EmailFilter.all;
  }
}

/// How much room a row is given.
enum EmailDensity {
  comfortable,
  compact;

  static EmailDensity fromValue(Object? value) {
    for (final density in EmailDensity.values) {
      if (density.name == value) {
        return density;
      }
    }
    return EmailDensity.comfortable;
  }

  double get rowHeight => this == EmailDensity.compact ? 32.0 : 66.0;
}

/// What a list is broken into.
enum EmailGrouping {
  none,
  date,
  sender;

  static EmailGrouping fromValue(Object? value) {
    for (final grouping in EmailGrouping.values) {
      if (grouping.name == value) {
        return grouping;
      }
    }
    return EmailGrouping.date;
  }
}

/// The choices a reader makes about a mailbox, kept between visits.
@immutable
class EmailSettings {
  const EmailSettings({
    this.sort = EmailSort.newest,
    this.filter = EmailFilter.all,
    this.density = EmailDensity.comfortable,
    this.grouping = EmailGrouping.date,
    this.showReadingPane = true,
    this.syncMinutes = 0,
  });

  final EmailSort sort;
  final EmailFilter filter;
  final EmailDensity density;
  final EmailGrouping grouping;

  /// Whether the three-pane view keeps a reading pane beside the list.
  final bool showReadingPane;

  /// How often the mailbox fetches on its own, in minutes. Zero is off.
  final int syncMinutes;

  bool get syncsOnItsOwn => syncMinutes > 0;

  EmailSettings copyWith({
    EmailSort? sort,
    EmailFilter? filter,
    EmailDensity? density,
    EmailGrouping? grouping,
    bool? showReadingPane,
    int? syncMinutes,
  }) =>
      EmailSettings(
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
        density: density ?? this.density,
        grouping: grouping ?? this.grouping,
        showReadingPane: showReadingPane ?? this.showReadingPane,
        syncMinutes: syncMinutes ?? this.syncMinutes,
      );

  Map<String, Object?> toJson() => {
        if (sort != EmailSort.newest) 'sort': sort.name,
        if (filter != EmailFilter.all) 'filter': filter.name,
        if (density != EmailDensity.comfortable) 'density': density.name,
        if (grouping != EmailGrouping.date) 'grouping': grouping.name,
        if (!showReadingPane) 'reading_pane': false,
        if (syncMinutes > 0) 'sync_minutes': syncMinutes,
      };

  static EmailSettings fromJson(Map<String, dynamic> values) => EmailSettings(
        sort: EmailSort.fromValue(values['sort']),
        filter: EmailFilter.fromValue(values['filter']),
        density: EmailDensity.fromValue(values['density']),
        grouping: EmailGrouping.fromValue(values['grouping']),
        showReadingPane: values['reading_pane'] != false,
        syncMinutes:
            values['sync_minutes'] is int ? values['sync_minutes'] as int : 0,
      );
}

/// How often a mailbox may fetch on its own.
const emailSyncIntervals = <int>[0, 5, 15, 30, 60];

/// Everything a mailbox remembers.
@immutable
class EmailState {
  const EmailState({
    this.settings = const EmailSettings(),
    this.activeLabel,
    this.activeSender,
    this.activeMessageId,
    this.account,
  });

  final EmailSettings settings;

  /// The label rail selection, when one is narrowed to.
  final String? activeLabel;

  /// The correspondent the mailbox is narrowed to.
  final String? activeSender;

  /// The message last open in the reading pane.
  final String? activeMessageId;

  /// The server this mailbox is joined to, if any. The password is not here:
  /// it lives in the secret store, because this is written into the view's
  /// `extra` in the clear.
  final MailAccount? account;

  EmailState copyWith({
    EmailSettings? settings,
    String? activeLabel,
    String? activeSender,
    String? activeMessageId,
    MailAccount? account,
    bool clearLabel = false,
    bool clearSender = false,
    bool clearMessage = false,
    bool clearAccount = false,
  }) =>
      EmailState(
        settings: settings ?? this.settings,
        activeLabel: clearLabel ? null : activeLabel ?? this.activeLabel,
        activeSender: clearSender ? null : activeSender ?? this.activeSender,
        activeMessageId:
            clearMessage ? null : activeMessageId ?? this.activeMessageId,
        account: clearAccount ? null : account ?? this.account,
      );

  Map<String, Object?> toJson() => {
        'settings': settings.toJson(),
        if (activeLabel != null) 'label': activeLabel,
        if (activeSender != null) 'sender': activeSender,
        if (activeMessageId != null) 'message': activeMessageId,
        if (account != null) 'account': account!.toJson(),
      };

  static EmailState fromJson(Map<String, dynamic> values) => EmailState(
        settings: values['settings'] is Map
            ? EmailSettings.fromJson(
                Map<String, dynamic>.from(values['settings'] as Map),
              )
            : const EmailSettings(),
        activeLabel: _string(values['label']),
        activeSender: _string(values['sender']),
        activeMessageId: _string(values['message']),
        account: values['account'] is Map
            ? MailAccount.fromJson(
                Map<String, dynamic>.from(values['account'] as Map),
              )
            : null,
      );

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// One entry of the mailbox rail: a correspondent or a label, and how many
/// messages sit behind it.
@immutable
class EmailFacet {
  const EmailFacet({
    required this.value,
    required this.count,
    this.unread = 0,
  });

  final String value;
  final int count;
  final int unread;
}

/// What the mailbox holds, for the header to report.
@immutable
class EmailStats {
  const EmailStats({
    this.total = 0,
    this.unread = 0,
    this.starred = 0,
    this.withAttachments = 0,
    this.threads = 0,
    this.indexed = 0,
    this.unreadable = 0,
  });

  final int total;
  final int unread;
  final int starred;
  final int withAttachments;
  final int threads;

  /// How many messages have been read off disk, so progress can be shown while
  /// a freshly imported mailbox is still being taken in.
  final int indexed;

  final int unreadable;

  bool get isIndexing => indexed < total;

  double get indexProgress => total == 0 ? 1 : indexed / total;
}
