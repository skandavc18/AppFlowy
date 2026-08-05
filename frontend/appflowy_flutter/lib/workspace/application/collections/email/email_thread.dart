import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:flutter/foundation.dart';

/// A conversation: the messages that answer one another, oldest first.
@immutable
class EmailThread {
  const EmailThread({
    required this.id,
    required this.subject,
    required this.messages,
  });

  /// The identifier of the message the conversation hangs off.
  final String id;

  /// The subject with any `Re:`/`Fwd:` prefixes taken off.
  final String subject;

  /// Oldest first, so a conversation reads downwards like a transcript.
  final List<EmailMessage> messages;

  int get length => messages.length;

  bool get isSingle => messages.length == 1;

  EmailMessage get first => messages.first;

  EmailMessage get last => messages.last;

  /// The moment the conversation was last added to, which is how a mailbox
  /// orders conversations rather than by when they began.
  DateTime? get lastSentAt {
    DateTime? latest;
    for (final message in messages) {
      final sentAt = message.sentAt;
      if (sentAt != null && (latest == null || sentAt.isAfter(latest))) {
        latest = sentAt;
      }
    }
    return latest;
  }

  bool get hasUnread => messages.any((message) => !message.read);

  int get unreadCount => messages.where((message) => !message.read).length;

  bool get starred => messages.any((message) => message.starred);

  bool get hasAttachments =>
      messages.any((message) => message.metadata.hasAttachments);

  /// Everyone who has spoken, in the order they first did.
  List<String> get participants {
    final seen = <String>{};
    final names = <String>[];
    for (final message in messages) {
      final sender = message.sender;
      if (sender.isNotEmpty && seen.add(sender.toLowerCase())) {
        names.add(sender);
      }
    }
    return names;
  }

  /// The message to show when the conversation is collapsed: the first unread
  /// one, because that is what the reader has not seen, else the newest.
  EmailMessage get representative {
    for (final message in messages) {
      if (!message.read) {
        return message;
      }
    }
    return last;
  }
}

/// Gathers messages into conversations.
///
/// Threading follows the identifiers RFC 5322 already carries — `Message-ID`,
/// `In-Reply-To` and `References` — so a conversation is a fact about the mail
/// rather than a guess. Messages whose ancestry is missing, which is common in
/// an exported mailbox, fall back to a normalised subject so a reply still
/// lands beside what it answers.
List<EmailThread> buildEmailThreads(List<EmailMessage> messages) {
  if (messages.isEmpty) {
    return const <EmailThread>[];
  }

  final byMessageId = <String, EmailMessage>{};
  for (final message in messages) {
    final id = message.metadata.messageId;
    if (id != null && id.isNotEmpty) {
      byMessageId.putIfAbsent(id, () => message);
    }
  }

  // Union-find over view ids: each message starts alone and is joined to
  // whatever it answers.
  final parent = <String, String>{
    for (final message in messages) message.id: message.id,
  };

  String find(String id) {
    var root = id;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    // Flatten the path so repeated lookups stay cheap.
    var walk = id;
    while (parent[walk] != root) {
      final next = parent[walk]!;
      parent[walk] = root;
      walk = next;
    }
    return root;
  }

  void union(String a, String b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) {
      parent[rootB] = rootA;
    }
  }

  for (final message in messages) {
    for (final reference in message.metadata.references) {
      final other = byMessageId[reference];
      if (other != null) {
        union(other.id, message.id);
      }
    }
    final replyTo = message.metadata.inReplyTo;
    if (replyTo != null) {
      final other = byMessageId[replyTo];
      if (other != null) {
        union(other.id, message.id);
      }
    }
  }

  // Only messages that carry no ancestry at all fall back to the subject; a
  // threaded message must not be dragged into another conversation by a
  // coincidence of wording.
  final orphansBySubject = <String, String>{};
  for (final message in messages) {
    if (message.metadata.references.isNotEmpty ||
        message.metadata.inReplyTo != null) {
      continue;
    }
    final subject = normalizeEmailSubject(message.subject);
    if (subject.isEmpty) {
      continue;
    }
    final existing = orphansBySubject[subject];
    if (existing == null) {
      orphansBySubject[subject] = message.id;
    } else {
      union(existing, message.id);
    }
  }

  final grouped = <String, List<EmailMessage>>{};
  for (final message in messages) {
    grouped.putIfAbsent(find(message.id), () => <EmailMessage>[]).add(message);
  }

  final threads = <EmailThread>[];
  for (final entry in grouped.entries) {
    final conversation = entry.value..sort(compareEmailBySentAt);
    threads.add(
      EmailThread(
        id: entry.key,
        subject: normalizeEmailSubject(conversation.first.subject),
        messages: List<EmailMessage>.unmodifiable(conversation),
      ),
    );
  }

  threads.sort((a, b) {
    final left = a.lastSentAt;
    final right = b.lastSentAt;
    if (left == null && right == null) {
      return a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  });

  return threads;
}

/// Oldest first, with undated messages last so they never lead a thread.
int compareEmailBySentAt(EmailMessage a, EmailMessage b) {
  final left = a.sentAt;
  final right = b.sentAt;
  if (left == null && right == null) {
    return a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
}

final _replyPrefix = RegExp(
  r'^\s*(?:(?:re|aw|sv|vs|fw|fwd|antw|res|odp|tr)\s*(?:\[\d+\])?\s*:\s*)+',
  caseSensitive: false,
);

/// Strips the reply and forward markers a subject collects as it travels.
String normalizeEmailSubject(String subject) {
  var value = subject.trim();
  while (true) {
    final stripped = value.replaceFirst(_replyPrefix, '');
    if (stripped == value) {
      break;
    }
    value = stripped.trim();
  }
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
