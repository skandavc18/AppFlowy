import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/email_html.dart';
import 'package:appflowy/workspace/application/collections/email/email_state.dart';
import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _palette = EmailHtmlPalette(
  brightness: Brightness.light,
  background: Color(0xFFFFFFFF),
  text: Color(0xFF1F2329),
  muted: Color(0xFF8A8F98),
  link: Color(0xFF2C6BED),
  rule: Color(0xFFE3E5E8),
  quote: Color(0xFFD5D8DC),
  scrollbar: Color(0x668A8F98),
);

MimeMessage _message(String raw) =>
    parseMimeMessage(Uint8List.fromList(latin1.encode(raw)));

EmailHtmlDocument _render(String raw, {bool allowRemote = false}) =>
    buildEmailHtmlDocument(
      _message(raw),
      palette: _palette,
      allowRemoteContent: allowRemote,
    );

void main() {
  group('printing a message', () {
    test('the words and the markup both survive', () {
      final document = _render(
        'Content-Type: text/html; charset="utf-8"\r\n'
        '\r\n'
        '<p>Hello <b>Ada</b></p><table><tr><td>cell</td></tr></table>',
      );

      expect(document.html, contains('<b>Ada</b>'));
      expect(document.html, contains('<table>'));
      expect(document.isPlainText, isFalse);
    });

    test('a message with no markup is dressed as text, not left bare', () {
      final document = _render(
        'Subject: plain\r\n\r\nline one\nline two\n> quoted reply\n',
      );

      expect(document.isPlainText, isTrue);
      expect(document.html, contains('line one'));
      expect(document.html, contains('af-quote'));
    });

    test('text is escaped rather than becoming markup', () {
      final document = _render(
        'Subject: plain\r\n\r\n<script>alert(1)</script> & <b>not bold</b>\n',
      );

      expect(document.html, isNot(contains('<script>')));
      expect(document.html, contains('&lt;script&gt;'));
      expect(document.html, contains('&amp;'));
    });
  });

  group('what a message is not allowed to do', () {
    test('a script is removed, and the policy forbids one anyway', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<p>hi</p><script>fetch("https://tracker.example/x")</script>',
      );

      expect(document.html, isNot(contains('fetch(')));
      expect(document.html, contains("script-src 'none'"));
      expect(document.html, contains("default-src 'none'"));
    });

    test('an event handler is not markup a message may carry', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<div onclick="steal()" onmouseover="steal()">hi</div>',
      );

      expect(document.html, isNot(contains('onclick')));
      expect(document.html, isNot(contains('onmouseover')));
      expect(document.html, contains('hi'));
    });

    test('frames, forms and objects are taken out', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<iframe src="https://x.example"></iframe>'
        '<form action="https://x.example"><input name="a"></form>'
        '<object data="x.swf"></object><embed src="y">'
        '<p>kept</p>',
      );

      expect(document.html, isNot(contains('<iframe')));
      expect(document.html, isNot(contains('<form')));
      expect(document.html, isNot(contains('<object')));
      expect(document.html, isNot(contains('<embed')));
      expect(document.html, contains('kept'));
    });

    test('a javascript link is dropped but an ordinary one is kept', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<a href="javascript:steal()">bad</a>'
        '<a href="https://example.org/post">good</a>'
        '<a href="mailto:ada@example.org">write</a>',
      );

      expect(document.html, isNot(contains('javascript:')));
      expect(document.html, contains('https://example.org/post'));
      expect(document.html, contains('mailto:ada@example.org'));
    });
  });

  group('pictures', () {
    String withInlineImage({required String src}) =>
        'Content-Type: multipart/related; boundary="edge"\r\n'
        '\r\n'
        '--edge\r\n'
        'Content-Type: text/html\r\n'
        '\r\n'
        '<img src="$src">\r\n'
        '--edge\r\n'
        'Content-Type: image/png\r\n'
        'Content-ID: <logo@example.org>\r\n'
        'Content-Transfer-Encoding: base64\r\n'
        '\r\n'
        '${base64.encode(const <int>[137, 80, 78, 71])}\r\n'
        '--edge--\r\n';

    test('a picture carried inside the message is always shown', () {
      final document = _render(withInlineImage(src: 'cid:logo@example.org'));

      expect(document.inlineImageCount, 1);
      expect(document.html, contains('data:image/png;base64,'));
      expect(document.html, isNot(contains('cid:')));
      expect(document.hasBlockedRemoteContent, isFalse);
    });

    test('a cid nothing answers is dropped rather than left broken', () {
      final document = _render(
        'Content-Type: text/html\r\n\r\n<img src="cid:missing@example.org">',
      );

      expect(document.html, isNot(contains('cid:')));
      expect(document.inlineImageCount, 0);
    });

    test('a remote picture is held back and counted', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<img src="https://tracker.example/open.gif?id=42">',
      );

      expect(document.hasBlockedRemoteContent, isTrue);
      expect(document.blockedRemoteCount, 1);
      expect(document.html, isNot(contains('tracker.example')));
      // Only what the message carries may load until the reader says so.
      expect(document.html, contains('img-src data:'));
    });

    test('asking for the pictures lets them through', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<img src="https://cdn.example/hero.png">',
        allowRemote: true,
      );

      expect(document.hasBlockedRemoteContent, isFalse);
      expect(document.html, contains('https://cdn.example/hero.png'));
      expect(document.html, contains('img-src data: https:'));
    });

    test('what a message fetches is counted even when it is allowed', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<img src="https://cdn.example/hero.png">'
        '<div style="background:url(https://tracker.example/q.gif)">hi</div>',
        allowRemote: true,
      );

      // The reader offers to turn pictures off, so it has to know there are
      // some to turn off.
      expect(document.hasRemoteContent, isTrue);
      expect(document.remoteReferenceCount, 2);
      expect(document.blockedRemoteCount, 0);
    });

    test('a style sheet cannot fetch behind the block either', () {
      final document = _render(
        'Content-Type: text/html\r\n'
        '\r\n'
        '<style>.a { background: url(https://tracker.example/p.gif); }</style>'
        '<div style="background:url(//tracker.example/q.gif)">hi</div>',
      );

      expect(document.html, isNot(contains('tracker.example')));
      expect(document.blockedRemoteCount, 2);
    });
  });

  group('fetching on a schedule', () {
    test('off by default, and remembered once chosen', () {
      const settings = EmailSettings();
      expect(settings.syncsOnItsOwn, isFalse);

      final every = settings.copyWith(syncMinutes: 15);
      expect(every.syncsOnItsOwn, isTrue);

      final restored = EmailSettings.fromJson(every.toJson());
      expect(restored.syncMinutes, 15);
    });

    test('the offered intervals start with off', () {
      expect(emailSyncIntervals.first, 0);
      expect(emailSyncIntervals, contains(15));
    });
  });

  group('the accounts the settings panel lists', () {
    test('an entry survives a round trip and carries no secret', () {
      final account = ConnectedAccount.fromAccount(
        MailAccount.forProvider(MailProvider.gmail).copyWith(
          username: 'ada@gmail.com',
          mailbox: 'INBOX',
          lastSyncAt: DateTime.utc(2026, 8, 5),
        ),
        collectionId: 'collection-1',
        collectionName: 'Mail',
      );

      final json = account.toJson();
      expect(json.toString(), isNot(contains('password')));

      final restored =
          ConnectedAccount.fromJson(Map<String, dynamic>.from(json));
      expect(restored, isNotNull);
      expect(restored!.username, 'ada@gmail.com');
      expect(restored.provider, MailProvider.gmail);
      expect(restored.collectionName, 'Mail');
      expect(restored.lastSyncAt, DateTime.utc(2026, 8, 5));
    });

    test('an entry with no identity is not an account', () {
      expect(ConnectedAccount.fromJson(<String, dynamic>{}), isNull);
    });
  });
}
