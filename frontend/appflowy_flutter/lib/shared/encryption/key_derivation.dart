// Turning what somebody types into a key, and making the random values the
// rest of the layer needs.
//
// A passphrase is not a key: it is short, it is memorable and it is guessable.
// PBKDF2 with a large iteration count is what stands between a stolen data
// folder and the words in it, so the count is deliberately high enough to be
// felt (about a fifth of a second on a desktop) and is recorded alongside the
// salt so it can be raised later without stranding anybody.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The OWASP 2023 floor for PBKDF2-HMAC-SHA256.
const int defaultKeyIterations = 210000;

/// A 256 bit key, which is what AES-256 takes.
const int encryptionKeyLength = 32;

/// Sixteen bytes is the usual salt; it only has to be unique, not secret.
const int encryptionSaltLength = 16;

/// PBKDF2-HMAC-SHA256.
///
/// Built on `package:crypto`'s HMAC rather than a cipher package, because
/// hashing is the one primitive this repository already carries.
Uint8List deriveKeyFromPassphrase({
  required String passphrase,
  required Uint8List salt,
  int iterations = defaultKeyIterations,
  int length = encryptionKeyLength,
}) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be at least 1');
  }
  if (length < 1) {
    throw ArgumentError.value(length, 'length', 'must be at least 1');
  }

  final hmac = Hmac(sha256, utf8.encode(passphrase));
  const int digestLength = 32;
  final blocks = (length + digestLength - 1) ~/ digestLength;
  final derived = Uint8List(blocks * digestLength);

  final seed = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);
  final counter = ByteData.sublistView(seed, salt.length);

  for (var block = 1; block <= blocks; block++) {
    // Big-endian is ByteData's default, and is the order PBKDF2 asks for.
    counter.setUint32(0, block);

    var u = Uint8List.fromList(hmac.convert(seed).bytes);
    final accumulated = Uint8List.fromList(u);
    for (var round = 1; round < iterations; round++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var i = 0; i < digestLength; i++) {
        accumulated[i] ^= u[i];
      }
    }
    derived.setRange(
      (block - 1) * digestLength,
      block * digestLength,
      accumulated,
    );
  }

  return Uint8List.sublistView(derived, 0, length);
}

/// Bytes nobody can predict, from the platform's own source.
///
/// `Random()` is seeded from the clock and would make every nonce guessable —
/// only `Random.secure()` is ever used here.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

Uint8List newEncryptionSalt() => randomBytes(encryptionSaltLength);

/// How well a passphrase would stand up, on a scale of nothing to strong.
///
/// This is a hint shown while somebody types, not a gate: refusing a passphrase
/// outright only teaches people to append `1!`.
enum PassphraseStrength { tooShort, weak, fair, good, strong }

PassphraseStrength ratePassphrase(String passphrase) {
  if (passphrase.length < minimumPassphraseLength) {
    return PassphraseStrength.tooShort;
  }

  var families = 0;
  if (passphrase.contains(RegExp('[a-z]'))) families++;
  if (passphrase.contains(RegExp('[A-Z]'))) families++;
  if (passphrase.contains(RegExp('[0-9]'))) families++;
  if (passphrase.contains(RegExp('[^A-Za-z0-9]'))) families++;

  // Length carries far more weight than punctuation: a long spoken phrase beats
  // a short one with a symbol in it.
  final score = passphrase.length + families * 4;
  if (score < 18) return PassphraseStrength.weak;
  if (score < 26) return PassphraseStrength.fair;
  if (score < 34) return PassphraseStrength.good;
  return PassphraseStrength.strong;
}

/// Short enough to remember, long enough to be worth deriving from.
const int minimumPassphraseLength = 8;
