import 'dart:typed_data';

/// AES-256 in Galois/Counter Mode, written out rather than taken from a
/// package.
///
/// Nothing in this repository's dependency set can encrypt — `crypto` only
/// hashes — and a note application must not gain a native dependency to keep a
/// passphrase. GCM is chosen because it authenticates as well as encrypts: a
/// wrong key, a truncated file or a tampered block is refused outright instead
/// of decrypting into rubbish, which is exactly the behaviour a "did I type the
/// right passphrase?" check needs.
///
/// Pinned against the published NIST GCM known-answer vectors in
/// `test/unit_test/shared/encryption_test.dart`. Do not change anything here
/// without running them.
class AesGcm {
  AesGcm(Uint8List key)
      : assert(key.length == 32, 'AES-256 needs a 32 byte key'),
        _aes = _Aes(key) {
    // H = E(K, 0^128), the hash subkey GHASH multiplies by.
    final zero = Uint8List(blockLength);
    final h = Uint8List(blockLength);
    _aes.encryptBlock(zero, 0, h, 0);
    _h = _wordsOf(h);
  }

  /// GCM's own nonce length. Ninety-six bits is the only size that needs no
  /// pre-hashing, and the only size anything here ever writes.
  static const nonceLength = 12;

  static const blockLength = 16;

  /// The authentication tag, appended to the ciphertext.
  static const tagLength = 16;

  final _Aes _aes;
  late final Uint32List _h;

  /// Encrypts [plaintext] and returns the ciphertext with its tag appended.
  ///
  /// [aad] is authenticated but not encrypted: it is the place to bind a
  /// ciphertext to where it lives, so a sealed block cannot be lifted out of
  /// one page and dropped into another.
  Uint8List encrypt({
    required Uint8List nonce,
    required Uint8List plaintext,
    Uint8List? aad,
  }) {
    _checkNonce(nonce);
    final counter = _initialCounter(nonce);
    final output = Uint8List(plaintext.length + tagLength);
    _applyKeyStream(counter, plaintext, output);

    final ciphertext = Uint8List.sublistView(output, 0, plaintext.length);
    final tag = _tag(counter: counter, ciphertext: ciphertext, aad: aad);
    output.setRange(plaintext.length, output.length, tag);
    return output;
  }

  /// Recovers the plaintext, or throws [AesGcmAuthenticationError] when the
  /// key is wrong or the bytes have been altered.
  Uint8List decrypt({
    required Uint8List nonce,
    required Uint8List sealed,
    Uint8List? aad,
  }) {
    _checkNonce(nonce);
    if (sealed.length < tagLength) {
      throw const AesGcmAuthenticationError();
    }

    final counter = _initialCounter(nonce);
    final ciphertext =
        Uint8List.sublistView(sealed, 0, sealed.length - tagLength);
    final claimed = Uint8List.sublistView(sealed, sealed.length - tagLength);
    final expected = _tag(counter: counter, ciphertext: ciphertext, aad: aad);

    if (!_equalInConstantTime(claimed, expected)) {
      throw const AesGcmAuthenticationError();
    }

    final plaintext = Uint8List(ciphertext.length);
    _applyKeyStream(counter, ciphertext, plaintext);
    return plaintext;
  }

  void _checkNonce(Uint8List nonce) {
    if (nonce.length != nonceLength) {
      throw ArgumentError.value(
        nonce.length,
        'nonce',
        'AES-GCM here always uses a $nonceLength byte nonce',
      );
    }
  }

  /// J0 for a 96-bit nonce: the nonce followed by the counter 1.
  Uint8List _initialCounter(Uint8List nonce) {
    final counter = Uint8List(blockLength)..setRange(0, nonceLength, nonce);
    counter[15] = 1;
    return counter;
  }

  /// CTR mode over the blocks after J0.
  void _applyKeyStream(Uint8List counter, Uint8List input, Uint8List output) {
    final block = Uint8List.fromList(counter);
    final stream = Uint8List(blockLength);
    for (var offset = 0; offset < input.length; offset += blockLength) {
      _increment32(block);
      _aes.encryptBlock(block, 0, stream, 0);
      final end = offset + blockLength <= input.length
          ? blockLength
          : input.length - offset;
      for (var i = 0; i < end; i++) {
        output[offset + i] = input[offset + i] ^ stream[i];
      }
    }
  }

  Uint8List _tag({
    required Uint8List counter,
    required Uint8List ciphertext,
    required Uint8List? aad,
  }) {
    final hash = Uint32List(4);
    if (aad != null && aad.isNotEmpty) {
      _ghashBytes(hash, aad);
    }
    _ghashBytes(hash, ciphertext);

    // The final block is the two lengths, in bits, as 64-bit counts. ByteData
    // writes big-endian by default, which is the order GCM asks for.
    final lengths = Uint8List(blockLength);
    ByteData.sublistView(lengths)
      ..setUint64(0, (aad?.length ?? 0) * 8)
      ..setUint64(8, ciphertext.length * 8);
    _ghashBlock(hash, lengths, 0);

    final mask = Uint8List(blockLength);
    _aes.encryptBlock(counter, 0, mask, 0);

    final tag = Uint8List(tagLength);
    final digest = _bytesOf(hash);
    for (var i = 0; i < tagLength; i++) {
      tag[i] = digest[i] ^ mask[i];
    }
    return tag;
  }

  void _ghashBytes(Uint32List hash, Uint8List data) {
    final whole = data.length - (data.length % blockLength);
    for (var offset = 0; offset < whole; offset += blockLength) {
      _ghashBlock(hash, data, offset);
    }
    if (whole != data.length) {
      // A partial block is padded with zeros, never with its own bytes.
      final tail = Uint8List(blockLength)
        ..setRange(0, data.length - whole, data, whole);
      _ghashBlock(hash, tail, 0);
    }
  }

  void _ghashBlock(Uint32List hash, Uint8List data, int offset) {
    hash[0] ^= _wordAt(data, offset);
    hash[1] ^= _wordAt(data, offset + 4);
    hash[2] ^= _wordAt(data, offset + 8);
    hash[3] ^= _wordAt(data, offset + 12);
    _multiplyByH(hash);
  }

  /// Multiplication in GF(2^128) with the reversed bit order GCM specifies.
  ///
  /// The bit-at-a-time form is used deliberately: a lookup table would leak the
  /// key through the cache, and this runs on a page of text, not a video
  /// stream.
  void _multiplyByH(Uint32List x) {
    var z0 = 0, z1 = 0, z2 = 0, z3 = 0;
    var v0 = _h[0], v1 = _h[1], v2 = _h[2], v3 = _h[3];

    for (var i = 0; i < 128; i++) {
      final bit = (x[i >> 5] >>> (31 - (i & 31))) & 1;
      if (bit == 1) {
        z0 ^= v0;
        z1 ^= v1;
        z2 ^= v2;
        z3 ^= v3;
      }
      final carry = v3 & 1;
      v3 = ((v3 >>> 1) | ((v2 & 1) << 31)) & 0xFFFFFFFF;
      v2 = ((v2 >>> 1) | ((v1 & 1) << 31)) & 0xFFFFFFFF;
      v1 = ((v1 >>> 1) | ((v0 & 1) << 31)) & 0xFFFFFFFF;
      v0 = (v0 >>> 1) & 0xFFFFFFFF;
      if (carry == 1) {
        v0 ^= 0xE1000000;
      }
    }

    x[0] = z0;
    x[1] = z1;
    x[2] = z2;
    x[3] = z3;
  }
}

/// Raised when a sealed payload does not authenticate — a wrong key, a wrong
/// context, or bytes that have been changed since they were written.
class AesGcmAuthenticationError implements Exception {
  const AesGcmAuthenticationError();

  @override
  String toString() =>
      'AesGcmAuthenticationError: the sealed data could not be authenticated';
}

/// Compares without returning early, so the time taken says nothing about how
/// much of a forged tag was right.
bool _equalInConstantTime(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

void _increment32(Uint8List block) {
  for (var i = 15; i >= 12; i--) {
    block[i] = (block[i] + 1) & 0xFF;
    if (block[i] != 0) {
      return;
    }
  }
}

int _wordAt(Uint8List bytes, int offset) =>
    ((bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3]) &
    0xFFFFFFFF;

Uint32List _wordsOf(Uint8List block) => Uint32List(4)
  ..[0] = _wordAt(block, 0)
  ..[1] = _wordAt(block, 4)
  ..[2] = _wordAt(block, 8)
  ..[3] = _wordAt(block, 12);

Uint8List _bytesOf(Uint32List words) {
  final bytes = Uint8List(16);
  for (var i = 0; i < 4; i++) {
    final word = words[i];
    bytes[i * 4] = (word >>> 24) & 0xFF;
    bytes[i * 4 + 1] = (word >>> 16) & 0xFF;
    bytes[i * 4 + 2] = (word >>> 8) & 0xFF;
    bytes[i * 4 + 3] = word & 0xFF;
  }
  return bytes;
}

/// The AES block cipher, encryption only — counter mode never decrypts a block.
class _Aes {
  _Aes(Uint8List key) : _rounds = _roundsFor(key.length) {
    _roundKeys = _expandKey(key, _rounds);
  }

  final int _rounds;
  late final Uint8List _roundKeys;

  static int _roundsFor(int keyLength) => switch (keyLength) {
        16 => 10,
        24 => 12,
        32 => 14,
        _ => throw ArgumentError.value(keyLength, 'key', 'unsupported AES key'),
      };

  void encryptBlock(Uint8List input, int inOffset, Uint8List out, int outOff) {
    final state = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      state[i] = input[inOffset + i] ^ _roundKeys[i];
    }

    for (var round = 1; round < _rounds; round++) {
      _substitute(state);
      _shiftRows(state);
      _mixColumns(state);
      _addRoundKey(state, round);
    }

    _substitute(state);
    _shiftRows(state);
    _addRoundKey(state, _rounds);

    out.setRange(outOff, outOff + 16, state);
  }

  void _addRoundKey(Uint8List state, int round) {
    final base = round * 16;
    for (var i = 0; i < 16; i++) {
      state[i] ^= _roundKeys[base + i];
    }
  }

  static void _substitute(Uint8List state) {
    for (var i = 0; i < 16; i++) {
      state[i] = _sBox[state[i]];
    }
  }

  /// Rows one, two and three rotate left by one, two and three. The state is
  /// held column by column, so row `r` is the bytes at `r`, `r+4`, `r+8`,
  /// `r+12`.
  static void _shiftRows(Uint8List s) {
    var t = s[1];
    s[1] = s[5];
    s[5] = s[9];
    s[9] = s[13];
    s[13] = t;

    t = s[2];
    s[2] = s[10];
    s[10] = t;
    t = s[6];
    s[6] = s[14];
    s[14] = t;

    t = s[15];
    s[15] = s[11];
    s[11] = s[7];
    s[7] = s[3];
    s[3] = t;
  }

  static void _mixColumns(Uint8List s) {
    for (var c = 0; c < 16; c += 4) {
      final a0 = s[c], a1 = s[c + 1], a2 = s[c + 2], a3 = s[c + 3];
      final all = a0 ^ a1 ^ a2 ^ a3;
      s[c] = a0 ^ all ^ _xtime(a0 ^ a1);
      s[c + 1] = a1 ^ all ^ _xtime(a1 ^ a2);
      s[c + 2] = a2 ^ all ^ _xtime(a2 ^ a3);
      s[c + 3] = a3 ^ all ^ _xtime(a3 ^ a0);
    }
  }

  static int _xtime(int value) {
    final shifted = (value << 1) & 0xFF;
    return (value & 0x80) != 0 ? shifted ^ 0x1B : shifted;
  }

  static Uint8List _expandKey(Uint8List key, int rounds) {
    final words = key.length ~/ 4;
    final total = (rounds + 1) * 16;
    final expanded = Uint8List(total)..setRange(0, key.length, key);

    var rcon = 1;
    for (var i = key.length; i < total; i += 4) {
      var t0 = expanded[i - 4];
      var t1 = expanded[i - 3];
      var t2 = expanded[i - 2];
      var t3 = expanded[i - 1];

      final word = i ~/ 4;
      if (word % words == 0) {
        // Rotate, substitute, then fold in the round constant.
        final rotated = t0;
        t0 = _sBox[t1] ^ rcon;
        t1 = _sBox[t2];
        t2 = _sBox[t3];
        t3 = _sBox[rotated];
        rcon = _xtime(rcon);
      } else if (words > 6 && word % words == 4) {
        t0 = _sBox[t0];
        t1 = _sBox[t1];
        t2 = _sBox[t2];
        t3 = _sBox[t3];
      }

      expanded[i] = expanded[i - key.length] ^ t0;
      expanded[i + 1] = expanded[i - key.length + 1] ^ t1;
      expanded[i + 2] = expanded[i - key.length + 2] ^ t2;
      expanded[i + 3] = expanded[i - key.length + 3] ^ t3;
    }

    return expanded;
  }
}

const List<int> _sBox = <int>[
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, //
  0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
  0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
  0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
  0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc,
  0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a,
  0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
  0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
  0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
  0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b,
  0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85,
  0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
  0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
  0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
  0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17,
  0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88,
  0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
  0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
  0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
  0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9,
  0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6,
  0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
  0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
  0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
  0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94,
  0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68,
  0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
];
