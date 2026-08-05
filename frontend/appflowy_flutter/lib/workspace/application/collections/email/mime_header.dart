import 'dart:convert';
import 'dart:typed_data';

/// The header half of a message, read the way RFC 5322 writes it.
///
/// Nothing here touches the network or the file system: hand it the text of a
/// header block and it answers questions about it, which is what makes the
/// whole mail model testable without a mail server.
class MimeHeaders {
  const MimeHeaders(this._fields);

  const MimeHeaders.empty() : _fields = const <String, List<String>>{};

  /// Reads a header block, joining folded continuation lines back together.
  ///
  /// A long header is wrapped by starting the next line with a space or tab,
  /// so a reader that works line by line would lose half of every address
  /// list.
  factory MimeHeaders.parse(String block) {
    final fields = <String, List<String>>{};
    final lines = block.split('\n');
    String? name;
    final value = StringBuffer();

    void flush() {
      final key = name;
      if (key == null) {
        return;
      }
      fields.putIfAbsent(key, () => <String>[]).add(value.toString().trim());
      value.clear();
      name = null;
    }

    for (final raw in lines) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith(' ') || line.startsWith('\t')) {
        // A folded continuation belongs to the header above it.
        value.write(' ');
        value.write(line.trim());
        continue;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      flush();
      name = line.substring(0, colon).trim().toLowerCase();
      value.write(line.substring(colon + 1).trim());
    }
    flush();

    return MimeHeaders(fields);
  }

  /// Lower-cased name to every value that appeared under it, in order.
  final Map<String, List<String>> _fields;

  bool get isEmpty => _fields.isEmpty;

  Iterable<String> get names => _fields.keys;

  /// The first value under [name], decoded out of RFC 2047 encoded words.
  String? value(String name) {
    final values = _fields[name.toLowerCase()];
    if (values == null || values.isEmpty) {
      return null;
    }
    return decodeEncodedWords(values.first);
  }

  /// Every value under [name], in the order they appeared.
  List<String> all(String name) {
    final values = _fields[name.toLowerCase()];
    if (values == null) {
      return const <String>[];
    }
    return values.map(decodeEncodedWords).toList();
  }

  /// The value exactly as written, for headers that must not be decoded.
  String? raw(String name) {
    final values = _fields[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }
}

/// A header value and the parameters hanging off it.
///
/// `Content-Type: multipart/mixed; boundary="=-=-="` is one value and one
/// parameter, and both halves matter.
class MimeFieldValue {
  const MimeFieldValue(this.value, this.parameters);

  final String value;
  final Map<String, String> parameters;

  String? parameter(String name) => parameters[name.toLowerCase()];
}

/// Splits `value; name=x; other="y"` into its parts.
MimeFieldValue parseFieldValue(String? field) {
  if (field == null || field.trim().isEmpty) {
    return const MimeFieldValue('', <String, String>{});
  }

  final segments = _splitOutsideQuotes(field, ';');
  final value = segments.isEmpty ? '' : segments.first.trim().toLowerCase();
  final parameters = <String, String>{};
  // RFC 2231 splits a long parameter across name*0, name*1 …
  final continued = <String, StringBuffer>{};

  for (final segment in segments.skip(1)) {
    final equals = segment.indexOf('=');
    if (equals <= 0) {
      continue;
    }
    var name = segment.substring(0, equals).trim().toLowerCase();
    var raw = _unquote(segment.substring(equals + 1).trim());

    final extended = name.endsWith('*');
    if (extended) {
      name = name.substring(0, name.length - 1);
      raw = _decodeExtendedParameter(raw);
    }

    final star = name.indexOf('*');
    if (star > 0) {
      final base = name.substring(0, star);
      continued.putIfAbsent(base, StringBuffer.new).write(raw);
      continue;
    }
    parameters[name] = raw;
  }

  for (final entry in continued.entries) {
    parameters[entry.key] = entry.value.toString();
  }

  return MimeFieldValue(value, parameters);
}

/// One name and address out of a `From`/`To`/`Cc` header.
class MimeAddress {
  const MimeAddress({required this.address, this.name = ''});

  final String name;
  final String address;

  /// The part before the `@`, which is the best label a bare address has.
  String get local {
    final at = address.indexOf('@');
    return at <= 0 ? address : address.substring(0, at);
  }

  /// The host the address belongs to, lower-cased.
  String get domain {
    final at = address.indexOf('@');
    return at < 0 || at == address.length - 1
        ? ''
        : address.substring(at + 1).toLowerCase();
  }

  /// What to show: the name when there is one, otherwise the address itself.
  String get display => name.isNotEmpty ? name : address;

  @override
  bool operator ==(Object other) =>
      other is MimeAddress &&
      other.name == name &&
      other.address.toLowerCase() == address.toLowerCase();

  @override
  int get hashCode => Object.hash(name, address.toLowerCase());

  @override
  String toString() => name.isEmpty ? address : '$name <$address>';
}

/// Reads an address list, honouring quoted names and grouped addresses.
List<MimeAddress> parseAddressList(String? field) {
  if (field == null || field.trim().isEmpty) {
    return const <MimeAddress>[];
  }

  final addresses = <MimeAddress>[];
  for (final entry in _splitOutsideQuotes(field, ',')) {
    final address = _parseAddress(entry.trim());
    if (address != null) {
      addresses.add(address);
    }
  }
  return addresses;
}

MimeAddress? _parseAddress(String entry) {
  if (entry.isEmpty) {
    return null;
  }

  final open = entry.lastIndexOf('<');
  final close = entry.lastIndexOf('>');
  if (open >= 0 && close > open) {
    final address = entry.substring(open + 1, close).trim();
    final name = _unquote(decodeEncodedWords(entry.substring(0, open)).trim());
    if (address.isEmpty) {
      return null;
    }
    return MimeAddress(address: address, name: name);
  }

  // A group such as `undisclosed-recipients:;` names no one at all.
  var bare = entry.replaceAll(RegExp('[<>]'), '').trim();
  while (bare.endsWith(';')) {
    bare = bare.substring(0, bare.length - 1).trim();
  }
  if (bare.isEmpty || bare.endsWith(':')) {
    return null;
  }
  return MimeAddress(address: bare);
}

/// Decodes the `=?charset?B?…?=` words RFC 2047 uses for non-ASCII headers.
///
/// Adjacent encoded words are joined without the whitespace between them, so
/// a subject split across several words reads as one phrase.
String decodeEncodedWords(String input) {
  if (!input.contains('=?')) {
    return input;
  }

  final buffer = StringBuffer();
  var index = 0;
  var previousWasEncoded = false;

  while (index < input.length) {
    final start = input.indexOf('=?', index);
    if (start < 0) {
      buffer.write(input.substring(index));
      break;
    }

    final charsetEnd = input.indexOf('?', start + 2);
    if (charsetEnd < 0) {
      buffer.write(input.substring(index));
      break;
    }
    final encodingEnd = input.indexOf('?', charsetEnd + 1);
    if (encodingEnd != charsetEnd + 2) {
      buffer.write(input.substring(index, start + 2));
      index = start + 2;
      continue;
    }
    final end = input.indexOf('?=', encodingEnd + 1);
    if (end < 0) {
      buffer.write(input.substring(index));
      break;
    }

    final gap = input.substring(index, start);
    if (!(previousWasEncoded && gap.trim().isEmpty)) {
      buffer.write(gap);
    }

    final charset = input.substring(start + 2, charsetEnd);
    final encoding = input.substring(charsetEnd + 1, encodingEnd).toUpperCase();
    final payload = input.substring(encodingEnd + 1, end);

    final bytes = encoding == 'B'
        ? _decodeBase64(payload)
        : encoding == 'Q'
            ? decodeQuotedPrintable(payload, underscoreIsSpace: true)
            : Uint8List.fromList(latin1.encode(payload));
    buffer.write(decodeMimeText(bytes, charset));

    previousWasEncoded = true;
    index = end + 2;
  }

  return buffer.toString();
}

/// Turns quoted-printable text back into the bytes it stands for.
Uint8List decodeQuotedPrintable(
  String input, {
  bool underscoreIsSpace = false,
}) {
  final bytes = <int>[];
  var index = 0;

  while (index < input.length) {
    final char = input[index];
    if (char == '=') {
      if (index + 1 < input.length &&
          (input[index + 1] == '\n' || input[index + 1] == '\r')) {
        // A soft line break: the `=` and the newline both disappear.
        index += input[index + 1] == '\r' &&
                index + 2 < input.length &&
                input[index + 2] == '\n'
            ? 3
            : 2;
        continue;
      }
      if (index + 2 < input.length) {
        final code =
            int.tryParse(input.substring(index + 1, index + 3), radix: 16);
        if (code != null) {
          bytes.add(code);
          index += 3;
          continue;
        }
      }
    }
    if (underscoreIsSpace && char == '_') {
      bytes.add(0x20);
      index += 1;
      continue;
    }
    bytes.addAll(latin1.encode(char));
    index += 1;
  }

  return Uint8List.fromList(bytes);
}

/// Decodes payload bytes with whatever charset the part declared.
///
/// Unknown charsets fall back to UTF-8 with malformed sequences allowed, which
/// reads a mislabelled message as well as anything can.
String decodeMimeText(Uint8List bytes, String? charset) {
  final name = (charset ?? 'utf-8').toLowerCase().trim();
  try {
    if (name == 'utf-8' || name == 'utf8' || name.isEmpty) {
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    }
    if (name == 'us-ascii' || name == 'ascii') {
      return const AsciiDecoder(allowInvalid: true).convert(bytes);
    }
    if (name == 'iso-8859-1' || name == 'latin1' || name == 'latin-1') {
      return const Latin1Decoder(allowInvalid: true).convert(bytes);
    }
    if (name == 'windows-1252' || name == 'cp1252') {
      return _decodeWindows1252(bytes);
    }
  } catch (_) {
    // Fall through to the forgiving decoder below.
  }
  return const Utf8Decoder(allowMalformed: true).convert(bytes);
}

/// Windows-1252 is Latin-1 except for the 0x80..0x9F band, which carries the
/// smart quotes and dashes that mail is full of.
String _decodeWindows1252(Uint8List bytes) {
  const high = <int>[
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  ];
  final runes = <int>[];
  for (final byte in bytes) {
    runes.add(byte >= 0x80 && byte <= 0x9F ? high[byte - 0x80] : byte);
  }
  return String.fromCharCodes(runes);
}

Uint8List _decodeBase64(String input) {
  final cleaned = input.replaceAll(RegExp('[^A-Za-z0-9+/=]'), '');
  if (cleaned.isEmpty) {
    return Uint8List(0);
  }
  final padded = cleaned.padRight((cleaned.length + 3) & ~3, '=');
  try {
    return Uint8List.fromList(base64.decode(padded));
  } catch (_) {
    return Uint8List(0);
  }
}

/// `charset'language'percent-encoded` per RFC 2231.
String _decodeExtendedParameter(String value) {
  final parts = value.split("'");
  if (parts.length < 3) {
    return value;
  }
  final charset = parts.first;
  final encoded = parts.sublist(2).join("'");
  final bytes = <int>[];
  for (var index = 0; index < encoded.length; index++) {
    if (encoded[index] == '%' && index + 2 < encoded.length) {
      final code =
          int.tryParse(encoded.substring(index + 1, index + 3), radix: 16);
      if (code != null) {
        bytes.add(code);
        index += 2;
        continue;
      }
    }
    bytes.addAll(latin1.encode(encoded[index]));
  }
  return decodeMimeText(Uint8List.fromList(bytes), charset);
}

List<String> _splitOutsideQuotes(String input, String separator) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  var depth = 0;

  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    if (char == '"' && (index == 0 || input[index - 1] != r'\')) {
      quoted = !quoted;
    } else if (!quoted && char == '(') {
      depth += 1;
    } else if (!quoted && char == ')' && depth > 0) {
      depth -= 1;
    }
    if (char == separator && !quoted && depth == 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());
  return parts;
}

String _unquote(String input) {
  final value = input.trim();
  // Space inside the quotes is part of the value: a parameter split across
  // continuations puts the join right where a trim would eat it.
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1).replaceAll(r'\"', '"');
  }
  return value.replaceAll(r'\"', '"').replaceAll(r"\'", "'");
}

const _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Reads an RFC 5322 date such as `Tue, 4 Aug 2026 12:34:56 +0530`.
///
/// The result is in UTC, so two messages sent from different time zones sort
/// against each other correctly.
DateTime? parseMailDate(String? field) {
  if (field == null || field.trim().isEmpty) {
    return null;
  }

  // Drop the optional day name and any trailing `(GMT)` style comment.
  var text = field.trim();
  final comment = text.indexOf('(');
  if (comment > 0) {
    text = text.substring(0, comment).trim();
  }
  final comma = text.indexOf(',');
  if (comma >= 0) {
    text = text.substring(comma + 1).trim();
  }

  final match = RegExp(
    r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{2,4})'
    r'\s+(\d{1,2}):(\d{2})(?::(\d{2}))?'
    r'(?:\s+([+-]\d{4}|[A-Za-z]{1,5}))?',
  ).firstMatch(text);
  if (match == null) {
    return null;
  }

  final month = _months[match.group(2)!.toLowerCase()];
  if (month == null) {
    return null;
  }

  var year = int.parse(match.group(3)!);
  if (year < 100) {
    year += year < 50 ? 2000 : 1900;
  }

  final moment = DateTime.utc(
    year,
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );

  return moment.subtract(_zoneOffset(match.group(7)));
}

Duration _zoneOffset(String? zone) {
  if (zone == null || zone.isEmpty) {
    return Duration.zero;
  }
  if (zone.startsWith('+') || zone.startsWith('-')) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final hours = int.tryParse(zone.substring(1, 3)) ?? 0;
    final minutes = int.tryParse(zone.substring(3, 5)) ?? 0;
    return Duration(hours: sign * hours, minutes: sign * minutes);
  }
  // The obsolete alphabetic zones. Anything else is treated as UTC.
  const zones = <String, int>{
    'ut': 0,
    'gmt': 0,
    'z': 0,
    'est': -5,
    'edt': -4,
    'cst': -6,
    'cdt': -5,
    'mst': -7,
    'mdt': -6,
    'pst': -8,
    'pdt': -7,
  };
  return Duration(hours: zones[zone.toLowerCase()] ?? 0);
}

/// Pulls the `<…>` identifiers out of a `Message-ID` or `References` header.
List<String> parseMessageIds(String? field) {
  if (field == null || field.trim().isEmpty) {
    return const <String>[];
  }
  final ids = <String>[];
  for (final match in RegExp('<([^<>]+)>').allMatches(field)) {
    final id = match.group(1)!.trim();
    if (id.isNotEmpty) {
      ids.add(id);
    }
  }
  if (ids.isEmpty) {
    final bare = field.trim();
    if (bare.isNotEmpty && !bare.contains(' ')) {
      ids.add(bare);
    }
  }
  return ids;
}
