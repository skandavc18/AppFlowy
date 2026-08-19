import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/shared/encryption/aes_gcm.dart';
import 'package:appflowy/shared/encryption/key_derivation.dart';

/// One sealed value, and the text it is written down as.
///
/// A sealed value has to survive being stored in a JSON attribute, a database
/// cell and a view's `extra`, so it is a single self-describing string rather
/// than a map: `af1.<nonce>.<ciphertext and tag>`, both parts base64url with no
/// padding. The version at the front is what lets the format change later
/// without guessing at what an old value meant.
class SecretBox {
  const SecretBox({required this.nonce, required this.sealed});

  static const prefix = 'af1';
  static const separator = '.';

  final Uint8List nonce;

  /// Ciphertext with the authentication tag appended.
  final Uint8List sealed;

  @override
  String toString() =>
      '$prefix$separator${_encode(nonce)}$separator${_encode(sealed)}';

  static SecretBox? tryParse(String value) {
    final parts = value.split(separator);
    if (parts.length != 3 || parts.first != prefix) {
      return null;
    }
    try {
      final nonce = _decode(parts[1]);
      final sealed = _decode(parts[2]);
      if (nonce.length != AesGcm.nonceLength ||
          sealed.length < AesGcm.tagLength) {
        return null;
      }
      return SecretBox(nonce: nonce, sealed: sealed);
    } on FormatException {
      return null;
    }
  }
}

/// Whether [value] looks like something this layer wrote.
///
/// Used everywhere a field may hold either plain text or a sealed value, so
/// that reading a page written before encryption existed never throws.
bool looksSealed(String? value) =>
    value != null &&
    value.length > 8 &&
    value.startsWith('${SecretBox.prefix}${SecretBox.separator}');

/// Seals [plaintext] with [key], binding it to [context].
///
/// [context] is authenticated but not hidden. Passing the id of whatever owns
/// the value — a block, a field, a row — means a sealed value cannot be copied
/// out of one place and pasted into another and still open.
String sealBytes({
  required Uint8List key,
  required Uint8List plaintext,
  String context = '',
}) {
  final nonce = randomBytes(AesGcm.nonceLength);
  final sealed = AesGcm(key).encrypt(
    nonce: nonce,
    plaintext: plaintext,
    aad: context.isEmpty ? null : Uint8List.fromList(utf8.encode(context)),
  );
  return SecretBox(nonce: nonce, sealed: sealed).toString();
}

/// Opens what [sealBytes] wrote, or throws.
///
/// Throws [AesGcmAuthenticationError] for a wrong key or altered bytes, and
/// [FormatException] for something that was never a sealed value at all. The
/// two are kept apart on purpose: one means "wrong passphrase", the other means
/// "this was not encrypted".
Uint8List openBytes({
  required Uint8List key,
  required String value,
  String context = '',
}) {
  final box = SecretBox.tryParse(value);
  if (box == null) {
    throw const FormatException('Not a sealed value');
  }
  return AesGcm(key).decrypt(
    nonce: box.nonce,
    sealed: box.sealed,
    aad: context.isEmpty ? null : Uint8List.fromList(utf8.encode(context)),
  );
}

String sealText({
  required Uint8List key,
  required String plaintext,
  String context = '',
}) =>
    sealBytes(
      key: key,
      plaintext: Uint8List.fromList(utf8.encode(plaintext)),
      context: context,
    );

String openText({
  required Uint8List key,
  required String value,
  String context = '',
}) =>
    utf8.decode(openBytes(key: key, value: value, context: context));

String _encode(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decode(String value) {
  final padding = (4 - value.length % 4) % 4;
  return base64Url.decode(value + '=' * padding);
}
