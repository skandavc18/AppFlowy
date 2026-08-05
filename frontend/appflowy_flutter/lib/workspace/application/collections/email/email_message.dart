import 'dart:convert';

import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// What a stored message is: an `.eml` file, the format every mail client can
/// export and none of them owns.
const emailMimeType = 'message/rfc822';

const untitledMessageName = 'Untitled message';

/// The header summary and the reader's own marks, carried on the message's
/// child view.
///
/// A mailbox has to list hundreds of messages at once, and opening every file
/// to do it would be unbearable — so the facts a list needs are cached here
/// when the message is first read, and the file itself is only opened when
/// somebody actually reads the message.
@immutable
class EmailMetadata {
  const EmailMetadata({
    this.subject = '',
    this.fromName = '',
    this.fromAddress = '',
    this.to = const <String>[],
    this.cc = const <String>[],
    this.sentAt,
    this.messageId,
    this.inReplyTo,
    this.references = const <String>[],
    this.snippet = '',
    this.attachmentCount = 0,
    this.sizeBytes,
    this.read = false,
    this.starred = false,
    this.labels = const <String>[],
    this.indexedAt,
    this.unreadable = false,
  });

  static const envelopeKey = 'appflowy_email';
  static const currentVersion = 1;

  final String subject;
  final String fromName;
  final String fromAddress;

  /// Display strings rather than parsed addresses: a list only ever shows them.
  final List<String> to;
  final List<String> cc;

  final DateTime? sentAt;

  final String? messageId;
  final String? inReplyTo;
  final List<String> references;

  /// The opening of the body, so a list can show a second line.
  final String snippet;

  final int attachmentCount;
  final int? sizeBytes;

  final bool read;
  final bool starred;
  final List<String> labels;

  /// When the summary was taken off the file, so a changed file can be reread.
  final DateTime? indexedAt;

  /// Set when the file could not be read as a message, so the interface can
  /// say so rather than showing a blank row for ever.
  final bool unreadable;

  bool get isIndexed => indexedAt != null;

  bool get hasAttachments => attachmentCount > 0;

  /// Who the message is from, falling back to the address and then to nothing.
  String get senderDisplay => fromName.isNotEmpty ? fromName : fromAddress;

  /// The subject to show, falling back to the file's own name.
  String displaySubject(String viewName) {
    if (subject.trim().isNotEmpty) {
      return subject.trim();
    }
    if (viewName.trim().isNotEmpty && viewName != untitledMessageName) {
      return viewName;
    }
    return '';
  }

  EmailMetadata copyWith({
    String? subject,
    String? fromName,
    String? fromAddress,
    List<String>? to,
    List<String>? cc,
    DateTime? sentAt,
    String? messageId,
    String? inReplyTo,
    List<String>? references,
    String? snippet,
    int? attachmentCount,
    int? sizeBytes,
    bool? read,
    bool? starred,
    List<String>? labels,
    DateTime? indexedAt,
    bool? unreadable,
  }) =>
      EmailMetadata(
        subject: subject ?? this.subject,
        fromName: fromName ?? this.fromName,
        fromAddress: fromAddress ?? this.fromAddress,
        to: to ?? this.to,
        cc: cc ?? this.cc,
        sentAt: sentAt ?? this.sentAt,
        messageId: messageId ?? this.messageId,
        inReplyTo: inReplyTo ?? this.inReplyTo,
        references: references ?? this.references,
        snippet: snippet ?? this.snippet,
        attachmentCount: attachmentCount ?? this.attachmentCount,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        read: read ?? this.read,
        starred: starred ?? this.starred,
        labels: labels ?? this.labels,
        indexedAt: indexedAt ?? this.indexedAt,
        unreadable: unreadable ?? this.unreadable,
      );

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        if (subject.isNotEmpty) 'subject': subject,
        if (fromName.isNotEmpty) 'from_name': fromName,
        if (fromAddress.isNotEmpty) 'from_address': fromAddress,
        if (to.isNotEmpty) 'to': to,
        if (cc.isNotEmpty) 'cc': cc,
        if (sentAt != null) 'sent_at': sentAt!.millisecondsSinceEpoch,
        if (messageId != null) 'message_id': messageId,
        if (inReplyTo != null) 'in_reply_to': inReplyTo,
        if (references.isNotEmpty) 'references': references,
        if (snippet.isNotEmpty) 'snippet': snippet,
        if (attachmentCount > 0) 'attachments': attachmentCount,
        if (sizeBytes != null) 'size': sizeBytes,
        if (read) 'read': true,
        if (starred) 'starred': true,
        if (labels.isNotEmpty) 'labels': labels,
        if (indexedAt != null) 'indexed_at': indexedAt!.millisecondsSinceEpoch,
        if (unreadable) 'unreadable': true,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static EmailMetadata? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }

    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return null;
    }

    return EmailMetadata(
      subject: _string(values['subject']) ?? '',
      fromName: _string(values['from_name']) ?? '',
      fromAddress: _string(values['from_address']) ?? '',
      to: _strings(values['to']),
      cc: _strings(values['cc']),
      sentAt: _date(values['sent_at']),
      messageId: _string(values['message_id']),
      inReplyTo: _string(values['in_reply_to']),
      references: _strings(values['references']),
      snippet: _string(values['snippet']) ?? '',
      attachmentCount:
          values['attachments'] is int ? values['attachments'] as int : 0,
      sizeBytes: values['size'] is int ? values['size'] as int : null,
      read: values['read'] == true,
      starred: values['starred'] == true,
      labels: _strings(values['labels']),
      indexedAt: _date(values['indexed_at']),
      unreadable: values['unreadable'] == true,
    );
  }

  /// The summary a parsed message leaves behind.
  static EmailMetadata fromMime(
    MimeMessage message, {
    int? sizeBytes,
    DateTime? indexedAt,
  }) {
    final sender = message.from;
    return EmailMetadata(
      subject: message.subject,
      fromName: sender?.name ?? '',
      fromAddress: sender?.address ?? '',
      to: message.to.map((address) => address.display).toList(),
      cc: message.cc.map((address) => address.display).toList(),
      sentAt: message.date,
      messageId: message.messageId,
      inReplyTo: message.inReplyTo,
      references: message.references,
      snippet: emailSnippetOf(message),
      attachmentCount: message.attachments.length,
      sizeBytes: sizeBytes,
      indexedAt: indexedAt ?? DateTime.now(),
    );
  }

  /// The `extra` payload of a stored message: a workspace file that also
  /// declares itself a piece of mail.
  static String newExtra({String? storageUrl, int? size}) =>
      const EmailMetadata().mergeIntoExtra(
        WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          mimeType: emailMimeType,
          storageUrl: storageUrl,
          size: size,
        ).mergeIntoExtra(''),
      );

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _date(Object? value) => value is int
      ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
      : null;

  static List<String> _strings(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    final items = <String>[];
    for (final entry in value) {
      if (entry is String && entry.trim().isNotEmpty) {
        items.add(entry.trim());
      }
    }
    return items;
  }
}

/// A message as the mailbox sees it: its view, its cached summary, and the
/// parsed body once somebody has opened it.
@immutable
class EmailMessage {
  const EmailMessage({
    required this.view,
    required this.metadata,
    this.body,
  });

  final ViewPB view;
  final EmailMetadata metadata;

  /// Only present for a message that has actually been opened.
  final MimeMessage? body;

  String get id => view.id;

  String get subject => metadata.displaySubject(view.name);

  String get sender => metadata.senderDisplay;

  DateTime? get sentAt => metadata.sentAt;

  bool get read => metadata.read;

  bool get starred => metadata.starred;

  /// Where the `.eml` lives on disk, when it is a local file.
  String? get storageUrl {
    final url = view.workspaceItem?.storageUrl;
    return url == null || url.isEmpty ? null : url;
  }

  EmailMessage withMetadata(EmailMetadata metadata) => EmailMessage(
        view: ViewPB()
          ..mergeFromMessage(view)
          ..extra = metadata.mergeIntoExtra(view.extra),
        metadata: metadata,
        body: body,
      );

  EmailMessage withBody(MimeMessage body) =>
      EmailMessage(view: view, metadata: metadata, body: body);

  /// Reads the summary a child view is carrying, if it is a message at all.
  static EmailMessage? fromView(ViewPB view) {
    if (view.isWorkspaceFolder) {
      return null;
    }
    final metadata = EmailMetadata.fromExtra(view.extra);
    if (metadata != null) {
      return EmailMessage(view: view, metadata: metadata);
    }
    // A file dropped in before it was ever read still belongs in the mailbox.
    return looksLikeMessageFile(view)
        ? EmailMessage(view: view, metadata: const EmailMetadata())
        : null;
  }
}

/// Whether a child view is a file the mailbox should try to read.
bool looksLikeMessageFile(ViewPB view) {
  final item = view.workspaceItem;
  if (item == null || item.kind != WorkspaceItemKind.file) {
    return false;
  }
  if (item.mimeType == emailMimeType) {
    return true;
  }
  return looksLikeMessageFileName(view.name);
}

/// Whether a file's name says it holds mail.
bool looksLikeMessageFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.eml') || lower.endsWith('.mbox');
}

/// The opening of a message, collapsed onto one line.
String emailSnippetOf(MimeMessage message, {int limit = 240}) {
  final plain = message.plainBody;
  final source = plain != null && plain.trim().isNotEmpty
      ? plain
      : _textFromHtml(message.htmlBody ?? '');
  return emailSnippetOfText(source, limit: limit);
}

/// The same, for text that has already been pulled out of a message.
String emailSnippetOfText(String source, {int limit = 240}) {
  final collapsed = source
      .replaceAll(RegExp(r'^\s*>.*$', multiLine: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (collapsed.length <= limit) {
    return collapsed;
  }
  return '${collapsed.substring(0, limit).trimRight()}…';
}

String _textFromHtml(String html) {
  if (html.isEmpty) {
    return '';
  }
  return html
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>'), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp('</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp('<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

/// The initials to draw when a sender has no picture, which is always.
String emailInitials(String display) {
  final cleaned = display.trim();
  if (cleaned.isEmpty) {
    return '?';
  }
  final words = cleaned
      .split(RegExp(r'[\s._-]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return cleaned.substring(0, 1).toUpperCase();
  }
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${words.first.substring(0, 1)}${words[1].substring(0, 1)}'
      .toUpperCase();
}

/// A stable hue for a sender, so the same correspondent keeps one colour.
double emailSenderHue(String seed) {
  if (seed.isEmpty) {
    return 210;
  }
  var hash = 0x811c9dc5;
  for (final unit in seed.toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return (hash % 360).toDouble();
}

/// Names a stored message after its subject, which is what a folder listing
/// has to read.
String emailFileNameFor(Uint8List bytes) {
  String subject;
  try {
    subject = parseMimeMessage(bytes).subject;
  } catch (_) {
    subject = '';
  }

  final cleaned = subject
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) {
    return '$untitledMessageName.eml';
  }
  final capped =
      cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
  return '$capped.eml';
}
