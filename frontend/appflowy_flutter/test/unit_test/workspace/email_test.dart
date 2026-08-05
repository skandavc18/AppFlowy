import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/email_state.dart';
import 'package:appflowy/workspace/application/collections/email/email_thread.dart';
import 'package:appflowy/workspace/application/collections/email/mime_header.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _messageView({
  required String id,
  String name = 'message.eml',
  EmailMetadata? metadata,
}) =>
    ViewPB()
      ..id = id
      ..name = name
      ..extra = (metadata ?? const EmailMetadata()).mergeIntoExtra(
        const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          mimeType: emailMimeType,
          storageUrl: 'C:/mail/message.eml',
        ).mergeIntoExtra(''),
      );

EmailMessage _message({
  required String id,
  String subject = '',
  String from = 'Ada Lovelace',
  String address = 'ada@example.org',
  DateTime? sentAt,
  String? messageId,
  String? inReplyTo,
  List<String> references = const <String>[],
  bool read = false,
  bool starred = false,
  int attachments = 0,
  List<String> labels = const <String>[],
}) {
  final metadata = EmailMetadata(
    subject: subject,
    fromName: from,
    fromAddress: address,
    sentAt: sentAt,
    messageId: messageId,
    inReplyTo: inReplyTo,
    references: references,
    attachmentCount: attachments,
    read: read,
    starred: starred,
    labels: labels,
    indexedAt: DateTime(2026),
  );
  return EmailMessage(
    view: _messageView(id: id, metadata: metadata),
    metadata: metadata,
  );
}

Uint8List _bytes(String text) => Uint8List.fromList(latin1.encode(text));

void main() {
  group('the headers a message wears', () {
    test('a folded header is read back as one line', () {
      final headers = MimeHeaders.parse(
        'Subject: the quick brown fox\n'
        '\tjumps over the lazy dog\n'
        'From: ada@example.org',
      );

      expect(
        headers.value('subject'),
        'the quick brown fox jumps over the lazy dog',
      );
      expect(headers.value('from'), 'ada@example.org');
    });

    test('a header is found whatever case it was written in', () {
      final headers = MimeHeaders.parse('MIME-Version: 1.0\nX-Mailer: nine');

      expect(headers.value('mime-version'), '1.0');
      expect(headers.value('X-MAILER'), 'nine');
      expect(headers.value('absent'), isNull);
    });

    test('encoded words are decoded, base64 and quoted-printable alike', () {
      expect(
        decodeEncodedWords('=?utf-8?B?w6l0w6k=?='),
        'été',
      );
      expect(
        decodeEncodedWords('=?utf-8?Q?caf=C3=A9?='),
        'café',
      );
      expect(
        decodeEncodedWords('=?iso-8859-1?Q?a_b?='),
        'a b',
      );
    });

    test('adjacent encoded words join without the space between them', () {
      expect(
        decodeEncodedWords('=?utf-8?Q?one?= =?utf-8?Q?two?='),
        'onetwo',
      );
      expect(
        decodeEncodedWords('plain =?utf-8?Q?word?= tail'),
        'plain word tail',
      );
    });

    test('text that is not an encoded word is left exactly as it was', () {
      expect(decodeEncodedWords('a normal subject'), 'a normal subject');
      expect(decodeEncodedWords('2 =? 3'), '2 =? 3');
    });

    test('a field value is split from its parameters', () {
      final value = parseFieldValue('multipart/mixed; boundary="=-=-="');

      expect(value.value, 'multipart/mixed');
      expect(value.parameter('boundary'), '=-=-=');
    });

    test('a parameter split across continuations is put back together', () {
      final value = parseFieldValue(
        'attachment; filename*0="a very "; filename*1="long name.pdf"',
      );

      expect(value.parameter('filename'), 'a very long name.pdf');
    });
  });

  group('the addresses a message names', () {
    test('a display name and an address are told apart', () {
      final addresses = parseAddressList('Ada Lovelace <ada@example.org>');

      expect(addresses, hasLength(1));
      expect(addresses.first.name, 'Ada Lovelace');
      expect(addresses.first.address, 'ada@example.org');
      expect(addresses.first.domain, 'example.org');
    });

    test('a comma inside a quoted name does not split the list', () {
      final addresses = parseAddressList(
        '"Lovelace, Ada" <ada@example.org>, grace@example.org',
      );

      expect(addresses, hasLength(2));
      expect(addresses.first.name, 'Lovelace, Ada');
      expect(addresses.last.address, 'grace@example.org');
      expect(addresses.last.display, 'grace@example.org');
    });

    test('a group with no addresses in it yields none', () {
      expect(parseAddressList('undisclosed-recipients:;'), isEmpty);
      expect(parseAddressList(''), isEmpty);
      expect(parseAddressList(null), isEmpty);
    });
  });

  group('the date a message carries', () {
    test('an offset is taken off so two zones can be compared', () {
      final date = parseMailDate('Tue, 4 Aug 2026 12:30:00 +0530');

      expect(date, isNotNull);
      expect(date!.isUtc, isTrue);
      expect(date, DateTime.utc(2026, 8, 4, 7));
    });

    test('the day name and a trailing comment are both optional', () {
      expect(
        parseMailDate('4 Aug 2026 07:00:00 +0000'),
        DateTime.utc(2026, 8, 4, 7),
      );
      expect(
        parseMailDate('Tue, 4 Aug 2026 07:00:00 GMT (UTC)'),
        DateTime.utc(2026, 8, 4, 7),
      );
    });

    test('a date nobody can read is reported as missing, not guessed', () {
      expect(parseMailDate('sometime last week'), isNull);
      expect(parseMailDate(''), isNull);
      expect(parseMailDate(null), isNull);
    });
  });

  group('reading a whole message', () {
    test('a plain message gives up its headers and its body', () {
      final message = parseMimeMessage(
        _bytes(
          'From: Ada Lovelace <ada@example.org>\r\n'
          'To: Grace Hopper <grace@example.org>\r\n'
          'Subject: On the engine\r\n'
          'Date: Tue, 4 Aug 2026 12:30:00 +0000\r\n'
          'Message-ID: <one@example.org>\r\n'
          '\r\n'
          'The engine weaves algebraic patterns.\r\n',
        ),
      );

      expect(message.subject, 'On the engine');
      expect(message.from?.name, 'Ada Lovelace');
      expect(message.to.single.address, 'grace@example.org');
      expect(message.messageId, 'one@example.org');
      expect(message.date, DateTime.utc(2026, 8, 4, 12, 30));
      expect(message.plainBody, contains('algebraic patterns'));
      expect(message.attachments, isEmpty);
    });

    test('a multipart message keeps the text and the html apart', () {
      final message = parseMimeMessage(
        _bytes(
          'Subject: Two ways to read\r\n'
          'Content-Type: multipart/alternative; boundary="frontier"\r\n'
          '\r\n'
          'This preamble is not a part.\r\n'
          '--frontier\r\n'
          'Content-Type: text/plain; charset="utf-8"\r\n'
          '\r\n'
          'the plain one\r\n'
          '--frontier\r\n'
          'Content-Type: text/html; charset="utf-8"\r\n'
          '\r\n'
          '<p>the marked up one</p>\r\n'
          '--frontier--\r\n',
        ),
      );

      expect(message.plainBody?.trim(), 'the plain one');
      expect(message.htmlBody?.trim(), '<p>the marked up one</p>');
      expect(message.root.isMultipart, isTrue);
      expect(message.root.children, hasLength(2));
    });

    test('a quoted-printable body is decoded with its charset', () {
      final message = parseMimeMessage(
        _bytes(
          'Content-Type: text/plain; charset="utf-8"\r\n'
          'Content-Transfer-Encoding: quoted-printable\r\n'
          '\r\n'
          'caf=C3=A9 and a soft=\r\n'
          ' break\r\n',
        ),
      );

      expect(message.plainBody, contains('café'));
      expect(message.plainBody, contains('soft break'));
    });

    test('a base64 body is decoded', () {
      final message = parseMimeMessage(
        _bytes(
          'Content-Type: text/plain; charset="utf-8"\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          '\r\n'
          '${base64.encode(utf8.encode('hidden in plain sight'))}\r\n',
        ),
      );

      expect(message.plainBody, 'hidden in plain sight');
    });

    test('a named part is offered as an attachment', () {
      final message = parseMimeMessage(
        _bytes(
          'Content-Type: multipart/mixed; boundary="edge"\r\n'
          '\r\n'
          '--edge\r\n'
          'Content-Type: text/plain\r\n'
          '\r\n'
          'see attached\r\n'
          '--edge\r\n'
          'Content-Type: application/pdf; name="report.pdf"\r\n'
          'Content-Disposition: attachment; filename="report.pdf"\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          '\r\n'
          '${base64.encode(<int>[1, 2, 3, 4])}\r\n'
          '--edge--\r\n',
        ),
      );

      expect(message.attachments, hasLength(1));
      expect(message.attachments.single.filename, 'report.pdf');
      expect(message.attachments.single.size, 4);
      expect(message.plainBody?.trim(), 'see attached');
    });

    test('an mbox archive is taken apart into its messages', () {
      final archive = _bytes(
        'From ada@example.org Tue Aug 04 12:00:00 2026\r\n'
        'Subject: first\r\n'
        '\r\n'
        'one\r\n'
        '>From the body, not a separator\r\n'
        'From ada@example.org Tue Aug 04 13:00:00 2026\r\n'
        'Subject: second\r\n'
        '\r\n'
        'two\r\n',
      );

      expect(looksLikeMboxArchive(archive), isTrue);

      final messages = splitMboxArchive(archive);
      expect(messages, hasLength(2));
      expect(parseMimeMessage(messages.first).subject, 'first');
      expect(
        parseMimeMessage(messages.first).plainBody,
        contains('From the body'),
      );
      expect(parseMimeMessage(messages.last).subject, 'second');
    });

    test('a single message is not mistaken for an archive', () {
      expect(looksLikeMboxArchive(_bytes('Subject: alone\n\nbody')), isFalse);
    });
  });

  group('the summary a message leaves behind', () {
    test('the envelope survives a round trip through the view extra', () {
      final metadata = EmailMetadata(
        subject: 'On the engine',
        fromName: 'Ada Lovelace',
        fromAddress: 'ada@example.org',
        to: const ['Grace Hopper'],
        sentAt: DateTime.utc(2026, 8, 4, 12),
        messageId: 'one@example.org',
        references: const ['zero@example.org'],
        snippet: 'The engine weaves',
        attachmentCount: 2,
        read: true,
        starred: true,
        labels: const ['work'],
        indexedAt: DateTime.utc(2026, 8, 5),
      );

      final restored = EmailMetadata.fromExtra(metadata.mergeIntoExtra(''));

      expect(restored, isNotNull);
      expect(restored!.subject, 'On the engine');
      expect(restored.fromAddress, 'ada@example.org');
      expect(restored.to, ['Grace Hopper']);
      expect(restored.sentAt, DateTime.utc(2026, 8, 4, 12));
      expect(restored.references, ['zero@example.org']);
      expect(restored.attachmentCount, 2);
      expect(restored.read, isTrue);
      expect(restored.starred, isTrue);
      expect(restored.labels, ['work']);
      expect(restored.isIndexed, isTrue);
    });

    test('the envelope leaves the workspace file metadata alone', () {
      final extra = EmailMetadata.newExtra(storageUrl: 'C:/mail/one.eml');
      final view = ViewPB()
        ..id = 'one'
        ..extra = extra;

      expect(view.isWorkspaceFile, isTrue);
      expect(view.workspaceItem?.mimeType, emailMimeType);
      expect(EmailMetadata.fromExtra(extra), isNotNull);
    });

    test('a file that was never read still belongs in the mailbox', () {
      final view = ViewPB()
        ..id = 'one'
        ..name = 'exported.eml'
        ..extra = const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: 'C:/mail/exported.eml',
        ).mergeIntoExtra('');

      final message = EmailMessage.fromView(view);
      expect(message, isNotNull);
      expect(message!.metadata.isIndexed, isFalse);
    });

    test('a folder in the mailbox is not a message', () {
      final view = ViewPB()
        ..id = 'folder'
        ..name = 'Archive'
        ..extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');

      expect(EmailMessage.fromView(view), isNull);
    });

    test('a summary is taken off a parsed message', () {
      final parsed = parseMimeMessage(
        _bytes(
          'From: Ada Lovelace <ada@example.org>\r\n'
          'Subject: On the engine\r\n'
          'Date: Tue, 4 Aug 2026 12:00:00 +0000\r\n'
          'Message-ID: <one@example.org>\r\n'
          '\r\n'
          'The engine weaves algebraic patterns.\r\n',
        ),
      );

      final metadata = EmailMetadata.fromMime(parsed, sizeBytes: 512);

      expect(metadata.subject, 'On the engine');
      expect(metadata.fromName, 'Ada Lovelace');
      expect(metadata.snippet, contains('algebraic'));
      expect(metadata.sizeBytes, 512);
      expect(metadata.isIndexed, isTrue);
    });

    test('a snippet is one line, without the quoted reply', () {
      expect(
        emailSnippetOfText('hello\n> you said this\nthere'),
        'hello there',
      );
      expect(emailSnippetOfText('a' * 300).length, 241);
    });

    test('initials are drawn from whatever the sender is called', () {
      expect(emailInitials('Ada Lovelace'), 'AL');
      expect(emailInitials('ada'), 'AD');
      expect(emailInitials('ada.lovelace@example.org'), 'AL');
      expect(emailInitials(''), '?');
    });
  });

  group('the conversations a mailbox forms', () {
    test('a reply joins the message it answers', () {
      final threads = buildEmailThreads([
        _message(
          id: 'a',
          subject: 'On the engine',
          messageId: 'one@example.org',
          sentAt: DateTime.utc(2026, 8, 4, 10),
        ),
        _message(
          id: 'b',
          subject: 'Re: On the engine',
          messageId: 'two@example.org',
          inReplyTo: 'one@example.org',
          sentAt: DateTime.utc(2026, 8, 4, 11),
        ),
      ]);

      expect(threads, hasLength(1));
      expect(threads.single.length, 2);
      expect(threads.single.subject, 'On the engine');
      expect(threads.single.first.id, 'a');
      expect(threads.single.last.id, 'b');
    });

    test('a chain is joined through references, not just the direct reply', () {
      final threads = buildEmailThreads([
        _message(id: 'a', messageId: 'one@x', sentAt: DateTime.utc(2026)),
        _message(
          id: 'c',
          messageId: 'three@x',
          references: const ['one@x', 'two@x'],
          sentAt: DateTime.utc(2026, 1, 3),
        ),
      ]);

      expect(threads, hasLength(1));
      expect(threads.single.length, 2);
    });

    test('two messages sharing a subject but no ancestry still gather', () {
      final threads = buildEmailThreads([
        _message(id: 'a', subject: 'Lunch', sentAt: DateTime.utc(2026)),
        _message(id: 'b', subject: 'RE: Lunch', sentAt: DateTime.utc(2026, 2)),
      ]);

      expect(threads, hasLength(1));
      expect(threads.single.subject, 'Lunch');
    });

    test('a threaded message is not dragged off by a coincidence of wording',
        () {
      final threads = buildEmailThreads([
        _message(id: 'a', subject: 'Lunch', messageId: 'one@x'),
        _message(
          id: 'b',
          subject: 'Lunch',
          messageId: 'two@x',
          inReplyTo: 'other@x',
        ),
      ]);

      expect(threads, hasLength(2));
    });

    test('conversations are ordered by their newest message', () {
      final threads = buildEmailThreads([
        _message(
          id: 'old',
          subject: 'Older thread',
          sentAt: DateTime.utc(2026),
        ),
        _message(
          id: 'new',
          subject: 'Newer thread',
          sentAt: DateTime.utc(2026, 6),
        ),
      ]);

      expect(threads.first.subject, 'Newer thread');
      expect(threads.last.subject, 'Older thread');
    });

    test('a conversation reports what it holds', () {
      final threads = buildEmailThreads([
        _message(
          id: 'a',
          subject: 'Plans',
          messageId: 'one@x',
          from: 'Ada',
          read: true,
          sentAt: DateTime.utc(2026),
        ),
        _message(
          id: 'b',
          subject: 'Re: Plans',
          messageId: 'two@x',
          inReplyTo: 'one@x',
          from: 'Grace',
          starred: true,
          attachments: 1,
          sentAt: DateTime.utc(2026, 1, 2),
        ),
      ]);

      final thread = threads.single;
      expect(thread.participants, ['Ada', 'Grace']);
      expect(thread.hasUnread, isTrue);
      expect(thread.unreadCount, 1);
      expect(thread.starred, isTrue);
      expect(thread.hasAttachments, isTrue);
      expect(thread.lastSentAt, DateTime.utc(2026, 1, 2));
      expect(thread.representative.id, 'b');
    });

    test('reply and forward markers are stripped from a subject', () {
      expect(normalizeEmailSubject('Re: Fwd: RE: Lunch'), 'Lunch');
      expect(normalizeEmailSubject('AW: Mittagessen'), 'Mittagessen');
      expect(normalizeEmailSubject('Re[2]: Lunch'), 'Lunch');
      expect(normalizeEmailSubject('Research notes'), 'Research notes');
    });
  });

  group('what the mailbox shows', () {
    late EmailController controller;

    setUp(() {
      controller = EmailController(
        persistDebounce: const Duration(days: 1),
      );
    });

    tearDown(() => controller.dispose());

    test('only the files that are messages are taken in', () {
      final folder = ViewPB()
        ..id = 'folder'
        ..name = 'Archive'
        ..extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');

      controller.setViews([
        ..._orderedViews(),
        folder,
      ]);

      expect(controller.all, hasLength(3));
      expect(controller.stats.total, 3);
    });

    test('the unread filter keeps only what has not been read', () {
      controller.setViews(_orderedViews());
      controller.setFilter(EmailFilter.unread);

      expect(controller.messages, hasLength(2));
      expect(controller.messages.every((message) => !message.read), isTrue);
    });

    test('a search reads the subject, the sender and the snippet', () {
      controller.setViews(_orderedViews());

      controller.search('grace');
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.sender, 'Grace Hopper');

      controller.search('engine');
      expect(controller.messages, hasLength(1));

      controller.search('');
      expect(controller.messages, hasLength(3));
    });

    test('sorting runs newest first, and can be turned round', () {
      controller.setViews(_orderedViews());

      expect(controller.messages.first.id, 'c');

      controller.setSort(EmailSort.oldest);
      expect(controller.messages.first.id, 'a');

      controller.setSort(EmailSort.sender);
      expect(controller.messages.first.sender, 'Ada Lovelace');
    });

    test('narrowing to a correspondent shows only their messages', () {
      controller.setViews(_orderedViews());

      controller.setActiveSender('Grace Hopper');
      expect(controller.messages, hasLength(1));

      controller.clearNarrowing();
      expect(controller.messages, hasLength(3));
    });

    test('marking read is answered here before the backend hears of it', () {
      controller.setViews(_orderedViews());
      expect(controller.stats.unread, 2);

      controller.setRead(['a'], read: true);
      expect(controller.stats.unread, 1);

      controller.toggleRead('a');
      expect(controller.stats.unread, 2);
    });

    test('starring is remembered on the message', () {
      controller.setViews(_orderedViews());

      controller.toggleStarred('a');
      expect(controller.stats.starred, 1);
      expect(controller.all.first.starred, isTrue);
    });

    test('the correspondents are counted for the rail', () {
      controller.setViews(_orderedViews());

      final senders = controller.senders;
      expect(senders.first.value, 'Ada Lovelace');
      expect(senders.first.count, 2);
      expect(senders.last.value, 'Grace Hopper');
    });

    test('what the reader chose is written down and read back', () {
      controller
        ..setSort(EmailSort.oldest)
        ..setDensity(EmailDensity.compact)
        ..setFilter(EmailFilter.starred)
        ..setShowReadingPane(show: false);

      final restored = EmailState.fromJson(controller.state.toJson());

      expect(restored.settings.sort, EmailSort.oldest);
      expect(restored.settings.density, EmailDensity.compact);
      expect(restored.settings.filter, EmailFilter.starred);
      expect(restored.settings.showReadingPane, isFalse);
    });

    test('a mailbox with nothing in it says so rather than failing', () {
      controller.setViews(const <ViewPB>[]);

      expect(controller.isEmpty, isTrue);
      expect(controller.messages, isEmpty);
      expect(controller.threads, isEmpty);
      expect(controller.stats.total, 0);
      expect(controller.stats.indexProgress, 1);
    });

    test('the same views twice do not rebuild the mailbox', () {
      final views = _orderedViews();
      controller.setViews(views);

      var notified = 0;
      controller.addListener(() => notified += 1);
      controller.setViews(views);

      expect(notified, 0);
    });

    test('selecting a message remembers it', () {
      controller
        ..setViews(_orderedViews())
        ..select('b');

      expect(controller.activeId, 'b');
      expect(controller.activeMessage?.id, 'b');
      expect(controller.state.toJson()['message'], 'b');
    });
  });
}

List<ViewPB> _orderedViews() => [
      _message(
        id: 'a',
        subject: 'On the engine',
        sentAt: DateTime.utc(2026, 8),
      ).view,
      _message(
        id: 'b',
        subject: 'Compilers',
        from: 'Grace Hopper',
        address: 'grace@example.org',
        sentAt: DateTime.utc(2026, 8, 2),
        read: true,
      ).view,
      _message(
        id: 'c',
        subject: 'Notes',
        sentAt: DateTime.utc(2026, 8, 3),
      ).view,
    ];
