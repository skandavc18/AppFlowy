import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Something the server said no to, or a connection that went away.
class ImapException implements Exception {
  const ImapException(this.message, {this.isAuthFailure = false});

  final String message;

  /// Whether the credentials were refused, as opposed to anything else. The
  /// interface says something quite different in that case.
  final bool isAuthFailure;

  @override
  String toString() => message;
}

/// One mailbox on the server.
@immutable
class ImapMailbox {
  const ImapMailbox({required this.name, this.flags = const <String>[]});

  final String name;
  final List<String> flags;

  /// A folder that only holds other folders cannot be opened.
  bool get isSelectable => !flags.contains(r'\noselect');

  /// The name to show, without the path in front of it.
  String get displayName {
    final cut = name.lastIndexOf(RegExp('[/.]'));
    return cut <= 0 || cut == name.length - 1 ? name : name.substring(cut + 1);
  }
}

/// What an opened mailbox reports about itself.
@immutable
class ImapSelection {
  const ImapSelection({
    this.exists = 0,
    this.uidValidity = 0,
    this.uidNext = 0,
  });

  final int exists;

  /// The generation of the mailbox's UIDs. When this changes every UID the
  /// account remembered means nothing and the sync has to start over.
  final int uidValidity;

  final int uidNext;
}

/// A small IMAP4rev1 client: enough to list mailboxes and take messages down,
/// and deliberately no more.
///
/// Nothing here sends mail or changes anything on the server — every fetch
/// uses `BODY.PEEK`, which is the form that does not set the `\Seen` flag, so
/// syncing a mailbox never alters what the reader sees in their own client.
class ImapClient {
  ImapClient._(this._socket, this._reader);

  static const _commandTimeout = Duration(seconds: 30);
  static const _fetchTimeout = Duration(seconds: 90);

  final Socket _socket;
  final _ImapReader _reader;

  int _tag = 0;
  bool _closed = false;
  List<String> _capabilities = const <String>[];

  List<String> get capabilities => _capabilities;

  bool get supportsOAuth => _capabilities.contains('auth=xoauth2');

  /// Opens a connection and reads the greeting.
  static Future<ImapClient> connect({
    required String host,
    required int port,
    bool secure = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final Socket socket;
    try {
      socket = secure
          // The certificate is checked: no onBadCertificate hook, ever.
          ? await SecureSocket.connect(host, port, timeout: timeout)
          : await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (error) {
      throw ImapException(error.message.isEmpty ? '$error' : error.message);
    } on HandshakeException catch (error) {
      throw ImapException('${error.message} ($host:$port)');
    } on TlsException catch (error) {
      throw ImapException(error.message);
    }

    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = ImapClient._(socket, _ImapReader(socket));

    final greeting = await client._reader.readLine(timeout);
    if (!greeting.text.startsWith('* OK')) {
      client.destroy();
      throw ImapException('The server did not greet us: ${greeting.text}');
    }
    return client;
  }

  /// Asks what the server can do, which decides how to sign in.
  Future<List<String>> capability() async {
    final response = await _send('CAPABILITY');
    for (final line in response.untagged) {
      if (line.text.toUpperCase().startsWith('* CAPABILITY')) {
        _capabilities = line.text
            .substring('* CAPABILITY'.length)
            .trim()
            .split(RegExp(r'\s+'))
            .map((value) => value.toLowerCase())
            .toList();
      }
    }
    return _capabilities;
  }

  /// Signs in with a password, which for most providers means one they issued
  /// for this purpose rather than the account's own.
  Future<void> login(String username, String password) async {
    if (_hasControlCharacter(username) || _hasControlCharacter(password)) {
      throw const ImapException(
        'The user name or password contains a line break.',
        isAuthFailure: true,
      );
    }
    await _send(
      'LOGIN ${_quote(username)} ${_quote(password)}',
      redact: true,
    );
  }

  /// Signs in with an OAuth 2.0 access token.
  Future<void> authenticateXOAuth2(String username, String accessToken) async {
    final payload = base64.encode(
      utf8.encode('user=$username\u0001auth=Bearer $accessToken\u0001\u0001'),
    );
    await _send('AUTHENTICATE XOAUTH2 $payload', redact: true);
  }

  /// Every mailbox the account can open.
  Future<List<ImapMailbox>> listMailboxes() async {
    final response = await _send('LIST "" "*"');
    final mailboxes = <ImapMailbox>[];
    for (final line in response.untagged) {
      final mailbox = _parseListLine(line.text);
      if (mailbox != null) {
        mailboxes.add(mailbox);
      }
    }
    return mailboxes;
  }

  /// Opens a mailbox. Read-only by default, so a sync cannot change anything.
  Future<ImapSelection> select(String mailbox, {bool readOnly = true}) async {
    final response = await _send(
      '${readOnly ? 'EXAMINE' : 'SELECT'} ${_quote(mailbox)}',
    );

    var exists = 0;
    var uidValidity = 0;
    var uidNext = 0;
    for (final line in response.untagged) {
      final text = line.text;
      final existsMatch = RegExp(r'^\* (\d+) EXISTS').firstMatch(text);
      if (existsMatch != null) {
        exists = int.tryParse(existsMatch.group(1)!) ?? 0;
      }
      final validity = RegExp(r'UIDVALIDITY (\d+)').firstMatch(text);
      if (validity != null) {
        uidValidity = int.tryParse(validity.group(1)!) ?? 0;
      }
      final next = RegExp(r'UIDNEXT (\d+)').firstMatch(text);
      if (next != null) {
        uidNext = int.tryParse(next.group(1)!) ?? 0;
      }
    }
    return ImapSelection(
      exists: exists,
      uidValidity: uidValidity,
      uidNext: uidNext,
    );
  }

  /// The UIDs worth asking for: everything after [afterUid], or everything
  /// since [since] when the mailbox has never been synced.
  Future<List<int>> searchUids({int? afterUid, DateTime? since}) async {
    final criteria = <String>[];
    if (afterUid != null && afterUid > 0) {
      criteria.add('UID ${afterUid + 1}:*');
    }
    if (since != null) {
      criteria.add('SINCE ${_imapDate(since)}');
    }
    if (criteria.isEmpty) {
      criteria.add('ALL');
    }

    final response = await _send('UID SEARCH ${criteria.join(' ')}');
    final uids = <int>[];
    for (final line in response.untagged) {
      final text = line.text;
      if (!text.toUpperCase().startsWith('* SEARCH')) {
        continue;
      }
      for (final piece in text.substring('* SEARCH'.length).trim().split(' ')) {
        final uid = int.tryParse(piece.trim());
        // `UID n:*` always returns at least one message even when none is
        // newer, so anything at or below the mark is dropped here.
        if (uid != null && (afterUid == null || uid > afterUid)) {
          uids.add(uid);
        }
      }
    }
    uids.sort();
    return uids;
  }

  /// The whole message behind [uid], exactly as the server holds it.
  Future<Uint8List?> fetchMessage(int uid) async {
    final response = await _send(
      'UID FETCH $uid (BODY.PEEK[])',
      timeout: _fetchTimeout,
    );
    for (final line in response.untagged) {
      if (line.literals.isNotEmpty) {
        return line.literals.first;
      }
    }
    return null;
  }

  Future<void> logout() async {
    if (_closed) {
      return;
    }
    try {
      await _send('LOGOUT', timeout: const Duration(seconds: 5));
    } catch (_) {
      // A server that hangs up first is the usual case, not a failure.
    }
    destroy();
  }

  void destroy() {
    if (_closed) {
      return;
    }
    _closed = true;
    _reader.dispose();
    _socket.destroy();
  }

  Future<_ImapResponse> _send(
    String command, {
    Duration? timeout,
    bool redact = false,
  }) async {
    if (_closed) {
      throw const ImapException('The connection is closed.');
    }

    final tag = 'A${(++_tag).toString().padLeft(4, '0')}';
    _socket.write('$tag $command\r\n');
    await _socket.flush();

    final untagged = <_ImapLine>[];
    final deadline = timeout ?? _commandTimeout;
    while (true) {
      final line = await _reader.readLine(deadline);
      if (line.text.startsWith('$tag ')) {
        final tail = line.text.substring(tag.length + 1).trim();
        final upper = tail.toUpperCase();
        if (upper.startsWith('OK')) {
          return _ImapResponse(tail, untagged);
        }
        // Never let the command itself into the message: it may hold the
        // password.
        final detail = redact ? _authDetail(tail) : tail;
        throw ImapException(
          detail,
          isAuthFailure: redact || upper.contains('AUTHENTICATIONFAILED'),
        );
      }
      if (line.text.startsWith('+')) {
        // A continuation with nothing to add to it: end the exchange.
        _socket.write('\r\n');
        await _socket.flush();
        continue;
      }
      untagged.add(line);
    }
  }

  static String _authDetail(String tail) {
    final cleaned = tail.replaceFirst(RegExp(r'^(NO|BAD)\s*'), '').trim();
    return cleaned.isEmpty ? 'The server refused the sign in.' : cleaned;
  }

  static bool _hasControlCharacter(String value) =>
      value.contains('\r') || value.contains('\n') || value.contains('\u0000');

  static String _quote(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  static const _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _imapDate(DateTime moment) {
    final utc = moment.toUtc();
    return '${utc.day.toString().padLeft(2, '0')}'
        '-${_monthNames[utc.month - 1]}-${utc.year}';
  }

  @visibleForTesting
  static ImapMailbox? parseListLineForTest(String line) => _parseListLine(line);

  static ImapMailbox? _parseListLine(String line) {
    if (!line.toUpperCase().startsWith('* LIST')) {
      return null;
    }
    final flagsMatch = RegExp(r'\(([^)]*)\)').firstMatch(line);
    final flags = (flagsMatch?.group(1) ?? '')
        .split(RegExp(r'\s+'))
        .where((flag) => flag.isNotEmpty)
        .map((flag) => flag.toLowerCase())
        .toList();

    // The name is the last item, quoted when it holds a space.
    final quoted = RegExp(r'"((?:[^"\\]|\\.)*)"\s*$').firstMatch(line);
    final name = quoted != null
        ? quoted.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\')
        : line.split(' ').last.trim();
    if (name.isEmpty) {
      return null;
    }
    return ImapMailbox(name: name, flags: flags);
  }
}

class _ImapResponse {
  const _ImapResponse(this.result, this.untagged);

  final String result;
  final List<_ImapLine> untagged;
}

class _ImapLine {
  const _ImapLine(this.text, this.literals);

  final String text;
  final List<Uint8List> literals;
}

/// Turns the socket's bytes into IMAP's lines.
///
/// IMAP's one awkwardness is the literal: a line may end with `{1234}`, and
/// the next 1234 bytes are raw content rather than text. A reader that worked
/// line by line would tear a message apart at every newline in its body.
class _ImapReader {
  _ImapReader(Stream<List<int>> stream) {
    _subscription = stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  final List<int> _buffer = <int>[];
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _waiting;
  Object? _error;
  bool _done = false;

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _wake();
  }

  Future<_ImapLine> readLine(Duration timeout) async {
    final text = StringBuffer();
    final literals = <Uint8List>[];

    while (true) {
      final line = await _readUntilCrlf(timeout);
      text.write(line);

      final literal = RegExp(r'\{(\d+)\+?\}$').firstMatch(line.trimRight());
      if (literal == null) {
        return _ImapLine(text.toString(), literals);
      }

      final count = int.parse(literal.group(1)!);
      literals.add(await _readBytes(count, timeout));
      // Keep the pieces apart so the tail after a literal is still readable.
      text.write('\n');
    }
  }

  Future<String> _readUntilCrlf(Duration timeout) async {
    while (true) {
      final index = _indexOfCrlf();
      if (index >= 0) {
        final line =
            latin1.decode(_buffer.sublist(0, index), allowInvalid: true);
        _buffer.removeRange(0, index + 2);
        return line;
      }
      await _await(timeout);
    }
  }

  Future<Uint8List> _readBytes(int count, Duration timeout) async {
    while (_buffer.length < count) {
      await _await(timeout);
    }
    final bytes = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return bytes;
  }

  int _indexOfCrlf() {
    for (var index = 0; index + 1 < _buffer.length; index++) {
      if (_buffer[index] == 13 && _buffer[index + 1] == 10) {
        return index;
      }
    }
    return -1;
  }

  Future<void> _await(Duration timeout) async {
    final error = _error;
    if (error != null) {
      _error = null;
      throw ImapException('The connection failed: $error');
    }
    if (_done) {
      throw const ImapException('The server closed the connection.');
    }

    final waiting = _waiting ??= Completer<void>();
    await waiting.future.timeout(
      timeout,
      onTimeout: () => throw const ImapException('The server did not answer.'),
    );
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _wake();
  }

  void _onError(Object error) {
    _error = error;
    _wake();
  }

  void _onDone() {
    _done = true;
    _wake();
  }

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
  }
}
