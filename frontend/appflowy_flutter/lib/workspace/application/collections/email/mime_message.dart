import 'dart:convert';

import 'package:appflowy/workspace/application/collections/email/mime_header.dart';
import 'package:flutter/foundation.dart';

/// How much of one message is worth holding in memory.
const maxMimeMessageBytes = 12 * 1024 * 1024;

/// One node of a message: either a leaf carrying content or a multipart
/// wrapper carrying [children].
@immutable
class MimePart {
  const MimePart({
    required this.headers,
    required this.mediaType,
    required this.parameters,
    required this.content,
    this.disposition = '',
    this.filename,
    this.children = const <MimePart>[],
  });

  final MimeHeaders headers;

  /// `text/plain`, `multipart/alternative`, `image/png` …
  final String mediaType;
  final Map<String, String> parameters;

  /// `inline`, `attachment`, or empty when the part did not say.
  final String disposition;
  final String? filename;
  final List<MimePart> children;

  /// The decoded payload of a leaf part. Empty for a multipart wrapper.
  final Uint8List content;

  String get topLevelType {
    final slash = mediaType.indexOf('/');
    return slash < 0 ? mediaType : mediaType.substring(0, slash);
  }

  bool get isMultipart => topLevelType == 'multipart';

  bool get isText => topLevelType == 'text';

  String? get charset => parameters['charset'];

  int get size => content.length;

  /// Whether the part is something to offer as a file rather than to read
  /// inline. A named part is an attachment even when it says `inline`, which
  /// is how most clients send images meant to be saved.
  bool get isAttachment {
    if (disposition == 'attachment') {
      return true;
    }
    if (isMultipart) {
      return false;
    }
    return filename != null && filename!.isNotEmpty;
  }

  /// The payload as text, decoded with the charset the part declared.
  String get text => decodeMimeText(content, charset);
}

/// A whole message, read out of an `.eml` file.
@immutable
class MimeMessage {
  const MimeMessage({required this.headers, required this.root});

  final MimeHeaders headers;
  final MimePart root;

  String get subject => headers.value('subject')?.trim() ?? '';

  MimeAddress? get from {
    final addresses = parseAddressList(headers.value('from'));
    return addresses.isEmpty ? null : addresses.first;
  }

  MimeAddress? get sender {
    final addresses = parseAddressList(headers.value('sender'));
    return addresses.isEmpty ? from : addresses.first;
  }

  List<MimeAddress> get to => parseAddressList(headers.value('to'));

  List<MimeAddress> get cc => parseAddressList(headers.value('cc'));

  List<MimeAddress> get bcc => parseAddressList(headers.value('bcc'));

  List<MimeAddress> get replyTo => parseAddressList(headers.value('reply-to'));

  DateTime? get date => parseMailDate(headers.raw('date'));

  String? get messageId {
    final ids = parseMessageIds(headers.raw('message-id'));
    return ids.isEmpty ? null : ids.first;
  }

  String? get inReplyTo {
    final ids = parseMessageIds(headers.raw('in-reply-to'));
    return ids.isEmpty ? null : ids.last;
  }

  List<String> get references => parseMessageIds(headers.raw('references'));

  /// Every part in the tree, parents before children.
  List<MimePart> get parts {
    final flat = <MimePart>[];
    void walk(MimePart part) {
      flat.add(part);
      part.children.forEach(walk);
    }

    walk(root);
    return flat;
  }

  /// The plain text body, preferring the part a reader is meant to see.
  String? get plainBody => _body('text/plain');

  String? get htmlBody => _body('text/html');

  List<MimePart> get attachments =>
      parts.where((part) => part.isAttachment).toList();

  String? _body(String mediaType) {
    for (final part in parts) {
      if (part.mediaType == mediaType && !part.isAttachment) {
        return part.text;
      }
    }
    return null;
  }
}

/// Reads an `.eml` file.
///
/// The bytes are carried through as Latin-1 while the structure is worked out,
/// because that mapping is lossless byte for byte; only when a leaf part's
/// charset is known does its payload get decoded properly.
MimeMessage parseMimeMessage(Uint8List bytes) {
  final capped = bytes.length > maxMimeMessageBytes
      ? Uint8List.sublistView(bytes, 0, maxMimeMessageBytes)
      : bytes;
  return parseMimeText(const Latin1Decoder(allowInvalid: true).convert(capped));
}

/// The same reader, for text that has already been decoded.
@visibleForTesting
MimeMessage parseMimeText(String raw) {
  final source = raw.replaceAll('\r\n', '\n');
  final split = _splitHeaders(source);
  final headers = MimeHeaders.parse(split.$1);
  return MimeMessage(
    headers: headers,
    root: _readPart(headers, split.$2, depth: 0),
  );
}

/// Splits an mbox archive into the messages it holds.
///
/// An mbox separates messages with a line beginning `From ` — the one line in
/// the format that is not a header — which is how a whole mailbox export can
/// be taken apart without a mail server.
List<Uint8List> splitMboxArchive(Uint8List bytes) {
  final text = const Latin1Decoder(allowInvalid: true).convert(bytes);
  final lines = text.split('\n');
  final messages = <Uint8List>[];
  final buffer = StringBuffer();

  void flush() {
    final message = buffer.toString().trim();
    buffer.clear();
    if (message.isNotEmpty) {
      messages.add(Uint8List.fromList(latin1.encode(message)));
    }
  }

  for (final line in lines) {
    if (line.startsWith('From ')) {
      flush();
      continue;
    }
    // An mbox escapes a body line that would look like a separator.
    buffer
      ..write(line.startsWith('>From ') ? line.substring(1) : line)
      ..write('\n');
  }
  flush();

  return messages;
}

/// Whether the bytes look like an mbox archive rather than a single message.
bool looksLikeMboxArchive(Uint8List bytes) {
  final head = const Latin1Decoder(allowInvalid: true)
      .convert(Uint8List.sublistView(bytes, 0, bytes.length.clamp(0, 512)));
  return head.startsWith('From ');
}

(String, String) _splitHeaders(String source) {
  final blank = source.indexOf('\n\n');
  if (blank < 0) {
    return (source, '');
  }
  return (source.substring(0, blank), source.substring(blank + 2));
}

MimePart _readPart(MimeHeaders headers, String body, {required int depth}) {
  final contentType = parseFieldValue(headers.raw('content-type'));
  final mediaType =
      contentType.value.isEmpty ? 'text/plain' : contentType.value;
  final disposition = parseFieldValue(headers.raw('content-disposition'));
  final filename = disposition.parameter('filename') ??
      contentType.parameter('name') ??
      disposition.parameter('filename*');

  if (mediaType.startsWith('multipart/') && depth < 12) {
    final boundary = contentType.parameter('boundary');
    if (boundary != null && boundary.isNotEmpty) {
      return MimePart(
        headers: headers,
        mediaType: mediaType,
        parameters: contentType.parameters,
        disposition: disposition.value,
        filename: filename,
        content: Uint8List(0),
        children: _readMultipart(body, boundary, depth: depth),
      );
    }
  }

  return MimePart(
    headers: headers,
    mediaType: mediaType,
    parameters: contentType.parameters,
    disposition: disposition.value,
    filename: filename,
    content: _decodeBody(body, headers.raw('content-transfer-encoding')),
  );
}

List<MimePart> _readMultipart(
  String body,
  String boundary, {
  required int depth,
}) {
  final opening = '--$boundary';
  final closing = '--$boundary--';
  final parts = <MimePart>[];
  final buffer = StringBuffer();
  var started = false;

  void flush() {
    if (!started) {
      return;
    }
    final section = buffer.toString();
    buffer.clear();
    final split = _splitHeaders(section);
    final headers = MimeHeaders.parse(split.$1);
    // A section with no headers of its own is a preamble, not a part.
    if (headers.isEmpty && split.$2.trim().isEmpty) {
      return;
    }
    parts.add(_readPart(headers, split.$2, depth: depth + 1));
  }

  for (final line in body.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed == closing) {
      flush();
      break;
    }
    if (trimmed == opening) {
      flush();
      started = true;
      continue;
    }
    if (started) {
      buffer
        ..write(line)
        ..write('\n');
    }
  }

  return parts;
}

Uint8List _decodeBody(String body, String? encoding) {
  final name = (encoding ?? '').trim().toLowerCase();
  if (name == 'base64') {
    final cleaned = body.replaceAll(RegExp('[^A-Za-z0-9+/=]'), '');
    if (cleaned.isEmpty) {
      return Uint8List(0);
    }
    try {
      return Uint8List.fromList(
        base64.decode(cleaned.padRight((cleaned.length + 3) & ~3, '=')),
      );
    } catch (_) {
      return Uint8List(0);
    }
  }
  if (name == 'quoted-printable') {
    return decodeQuotedPrintable(body);
  }
  return Uint8List.fromList(latin1.encode(body));
}
