import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/imap_client.dart';
import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in IMAP server: it answers scripted replies so the client can be
/// driven end to end without a real mailbox anywhere.
class _FakeServer {
  _FakeServer(this._script);

  final List<String> _script;
  final List<String> received = <String>[];
  late final ServerSocket _server;

  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((socket) {
      socket.write('* OK fake server ready\r\n');
      var index = 0;
      socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) {
          return;
        }
        received.add(line);
        final tag = line.split(' ').first;
        if (index < _script.length) {
          socket.write(_script[index++].replaceAll('%TAG%', tag));
        }
        if (line.toUpperCase().contains('LOGOUT')) {
          socket.close();
        }
      });
    });
  }

  Future<void> stop() => _server.close();
}

void main() {
  group('the mailbox a reader connects to', () {
    test('a provider brings its own server settings', () {
      final account = MailAccount.forProvider(MailProvider.custom).withProvider(
        MailProvider.gmail,
      );

      expect(account.host, 'imap.gmail.com');
      expect(account.port, 993);
      expect(account.useSsl, isTrue);
      expect(account.provider.needsAppPassword, isTrue);
      expect(account.provider.appPasswordUrl, isNotNull);
    });

    test('a local bridge is plain and on its own port', () {
      final account = MailAccount.forProvider(MailProvider.proton);

      expect(account.port, 1143);
      expect(account.useSsl, isFalse);
    });

    test('an account survives a round trip, without any secret in it', () {
      final account = MailAccount.forProvider(MailProvider.fastmail).copyWith(
        username: 'ada@fastmail.com',
        mailbox: 'Archive',
        lastUid: 4210,
        uidValidity: 99,
        lastSyncAt: DateTime.utc(2026, 8, 5),
      );

      final json = account.toJson();
      expect(json.toString(), isNot(contains('password')));
      expect(json.toString(), isNot(contains('secret')));

      final restored = MailAccount.fromJson(Map<String, dynamic>.from(json));
      expect(restored, isNotNull);
      expect(restored!.username, 'ada@fastmail.com');
      expect(restored.mailbox, 'Archive');
      expect(restored.lastUid, 4210);
      expect(restored.uidValidity, 99);
      expect(restored.lastSyncAt, DateTime.utc(2026, 8, 5));
      expect(restored.host, 'imap.fastmail.com');
    });

    test('an account with nothing in it is not configured', () {
      expect(MailAccount.forProvider(MailProvider.gmail).isConfigured, isFalse);
      expect(MailAccount.fromJson(<String, dynamic>{}), isNull);
    });
  });

  group('where the password is kept', () {
    late MailSecretStore store;

    setUp(() => store = MailSecretStore());

    test('a secret is available for the session that wrote it', () async {
      await store.write('acc-1', 'hunter2', remember: false);

      expect(await store.read('acc-1'), 'hunter2');
      expect(await store.has('acc-1'), isTrue);
    });

    test('forgetting an account takes the secret with it', () async {
      await store.write('acc-1', 'hunter2', remember: false);
      await store.forget('acc-1');

      expect(await store.read('acc-1'), isNull);
    });

    test('one account cannot read another account\'s secret', () async {
      await store.write('acc-1', 'hunter2', remember: false);

      expect(await store.read('acc-2'), isNull);
    });

    test('a machine that cannot seal a secret says so', () {
      // Windows can; everything else has to ask again next time, and the
      // interface reads that off this flag rather than pretending.
      expect(store.canPersist, Platform.isWindows);
      expect(store.isSessionOnly, !Platform.isWindows);
    });
  });

  group('talking to a server', () {
    late _FakeServer server;

    tearDown(() => server.stop());

    Future<ImapClient> connect(List<String> script) async {
      server = _FakeServer(script);
      await server.start();
      return ImapClient.connect(
        host: '127.0.0.1',
        port: server.port,
        secure: false,
      );
    }

    test('the greeting is read before anything is asked', () async {
      final client = await connect(['%TAG% OK CAPABILITY done\r\n']);
      addTearDown(client.destroy);

      expect(client, isNotNull);
    });

    test('capabilities are read back', () async {
      final client = await connect([
        '* CAPABILITY IMAP4rev1 IDLE AUTH=XOAUTH2\r\n%TAG% OK done\r\n',
      ]);
      addTearDown(client.destroy);

      final capabilities = await client.capability();
      expect(capabilities, contains('imap4rev1'));
      expect(client.supportsOAuth, isTrue);
    });

    test('a refused sign in is reported as an auth failure, not a crash',
        () async {
      final client = await connect([
        '%TAG% NO [AUTHENTICATIONFAILED] Invalid credentials\r\n',
      ]);
      addTearDown(client.destroy);

      await expectLater(
        client.login('ada@example.org', 'wrong'),
        throwsA(
          isA<ImapException>().having(
            (error) => error.isAuthFailure,
            'isAuthFailure',
            isTrue,
          ),
        ),
      );
    });

    test('the password never appears in the error a failure reports', () async {
      final client = await connect(['%TAG% NO Invalid credentials\r\n']);
      addTearDown(client.destroy);

      try {
        await client.login('ada@example.org', 'super-secret-token');
        fail('the sign in should have been refused');
      } on ImapException catch (error) {
        expect(error.message, isNot(contains('super-secret-token')));
        expect(error.message, contains('Invalid credentials'));
      }
    });

    test('a line break in a password is refused before it is sent', () async {
      final client = await connect(['%TAG% OK done\r\n']);
      addTearDown(client.destroy);

      await expectLater(
        client.login('ada@example.org', 'bad\r\nA002 DELETE "INBOX"'),
        throwsA(isA<ImapException>()),
      );
      expect(server.received, isEmpty);
    });

    test('an opened mailbox reports its generation and its size', () async {
      final client = await connect([
        '* 42 EXISTS\r\n'
            '* OK [UIDVALIDITY 1234567] UIDs valid\r\n'
            '* OK [UIDNEXT 900] Predicted next UID\r\n'
            '%TAG% OK [READ-ONLY] EXAMINE completed\r\n',
      ]);
      addTearDown(client.destroy);

      final selection = await client.select('INBOX');
      expect(selection.exists, 42);
      expect(selection.uidValidity, 1234567);
      expect(selection.uidNext, 900);
      // A sync must never alter the server, so the mailbox is only examined.
      expect(server.received.single, contains('EXAMINE'));
    });

    test('a search returns the uids past the watermark only', () async {
      final client = await connect(['* SEARCH 10 11 12\r\n%TAG% OK done\r\n']);
      addTearDown(client.destroy);

      final uids = await client.searchUids(afterUid: 10);
      expect(uids, [11, 12]);
      expect(server.received.single, contains('UID 11:*'));
    });

    test('a search by date asks in the form the protocol wants', () async {
      final client = await connect(['* SEARCH\r\n%TAG% OK done\r\n']);
      addTearDown(client.destroy);

      await client.searchUids(since: DateTime.utc(2026, 8, 4));
      expect(server.received.single, contains('SINCE 04-Aug-2026'));
    });

    test('a fetched message comes back whole, newlines and all', () async {
      const message = 'Subject: On the engine\r\n'
          '\r\n'
          'The engine weaves algebraic patterns.\r\n'
          'It does not originate anything.\r\n';
      final client = await connect([
        '* 12 FETCH (UID 345 BODY[] {${message.length}}\r\n'
            '$message'
            ')\r\n'
            '%TAG% OK done\r\n',
      ]);
      addTearDown(client.destroy);

      final bytes = await client.fetchMessage(345);
      expect(bytes, isNotNull);
      expect(bytes!.length, message.length);

      // The point of the literal: a body full of newlines survives intact.
      final parsed = parseMimeMessage(bytes);
      expect(parsed.subject, 'On the engine');
      expect(parsed.plainBody, contains('does not originate'));
    });

    test('the mailbox list is read, quoted names and flags alike', () async {
      final client = await connect([
        '* LIST (\\HasNoChildren) "/" "INBOX"\r\n'
            '* LIST (\\Noselect \\HasChildren) "/" "[Gmail]"\r\n'
            '* LIST (\\HasNoChildren \\All) "/" "[Gmail]/All Mail"\r\n'
            '%TAG% OK done\r\n',
      ]);
      addTearDown(client.destroy);

      final mailboxes = await client.listMailboxes();
      expect(mailboxes.map((mailbox) => mailbox.name), [
        'INBOX',
        '[Gmail]',
        '[Gmail]/All Mail',
      ]);
      expect(mailboxes[1].isSelectable, isFalse);
      expect(mailboxes[2].displayName, 'All Mail');
    });

    test(
      'a server that says nothing does not hang for ever',
      () async {
        server = _FakeServer(const <String>[]);
        await server.start();
        final client = await ImapClient.connect(
          host: '127.0.0.1',
          port: server.port,
          secure: false,
        );
        addTearDown(client.destroy);

        await expectLater(
          client.select('INBOX').timeout(const Duration(seconds: 45)),
          throwsA(isA<ImapException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('naming what was fetched', () {
    test('a message is filed under its subject', () {
      final bytes = Uint8List.fromList(
        latin1.encode('Subject: Quarterly report\r\n\r\nbody'),
      );

      expect(emailFileNameFor(bytes), 'Quarterly report.eml');
    });

    test('a subject that would break a path is cleaned up', () {
      final bytes = Uint8List.fromList(
        latin1.encode('Subject: Re: a/b\\c:d*e?f\r\n\r\nbody'),
      );

      final name = emailFileNameFor(bytes);
      expect(name.endsWith('.eml'), isTrue);
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, isNot(contains(':')));
      // The reply marker belongs in the name: it is what the sender wrote.
      expect(name, startsWith('Re'));
    });

    test('a message with no subject still gets a name', () {
      final bytes = Uint8List.fromList(latin1.encode('From: a@b\r\n\r\nbody'));

      expect(emailFileNameFor(bytes), endsWith('.eml'));
    });
  });
}
