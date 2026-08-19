import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String value) {
  final cleaned = value.replaceAll(RegExp(r'\s'), '');
  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('AES-256-GCM answers the published test vectors', () {
    // NIST / McGrew-Viega GCM test cases 13, 14 and 15 (AES-256).
    test('case 13 — no key material, nothing to encrypt', () {
      final gcm = AesGcm(Uint8List(32));
      final sealed = gcm.encrypt(
        nonce: Uint8List(12),
        plaintext: Uint8List(0),
      );
      expect(_toHex(sealed), '530f8afbc74536b9a963b4f1c4cb738b');
    });

    test('case 14 — one block of zeros', () {
      final gcm = AesGcm(Uint8List(32));
      final sealed = gcm.encrypt(
        nonce: Uint8List(12),
        plaintext: Uint8List(16),
      );
      expect(
        _toHex(sealed),
        'cea7403d4d606b6e074ec5d3baf39d18'
        'd0d1c8a799996bf0265b98b5d48ab919',
      );
    });

    test('case 15 — four blocks with a real key', () {
      final gcm = AesGcm(
        _hex(
          'feffe9928665731c6d6a8f9467308308'
          'feffe9928665731c6d6a8f9467308308',
        ),
      );
      final sealed = gcm.encrypt(
        nonce: _hex('cafebabefacedbaddecaf888'),
        plaintext: _hex(
          'd9313225f88406e5a55909c5aff5269a'
          '86a7a9531534f7da2e4c303d8a318a72'
          '1c3c0c95956809532fcf0e2449a6b525'
          'b16aedf5aa0de657ba637b391aafd255',
        ),
      );
      expect(
        _toHex(sealed),
        '522dc1f099567d07f47f37a32a84427d'
        '643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838'
        'c5f61e6393ba7a0abcc9f662898015ad'
        'b094dac5d93471bdec1a502270e3cc6c',
      );
    });

    test('case 16 — additional data is authenticated but not encrypted', () {
      final gcm = AesGcm(
        _hex(
          'feffe9928665731c6d6a8f9467308308'
          'feffe9928665731c6d6a8f9467308308',
        ),
      );
      final sealed = gcm.encrypt(
        nonce: _hex('cafebabefacedbaddecaf888'),
        plaintext: _hex(
          'd9313225f88406e5a55909c5aff5269a'
          '86a7a9531534f7da2e4c303d8a318a72'
          '1c3c0c95956809532fcf0e2449a6b525'
          'b16aedf5aa0de657ba637b39',
        ),
        aad: _hex('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
      );
      expect(
        _toHex(sealed),
        '522dc1f099567d07f47f37a32a84427d'
        '643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838'
        'c5f61e6393ba7a0abcc9f662'
        '76fc6ece0f4e1768cddf8853bb2d551b',
      );
    });

    test('a sealed value opens back to what went in', () {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('a page of notes ✓'));
      final gcm = AesGcm(key);

      final sealed = gcm.encrypt(nonce: nonce, plaintext: plaintext);
      expect(gcm.decrypt(nonce: nonce, sealed: sealed), plaintext);
    });

    test('a changed byte is refused, not silently decrypted', () {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final gcm = AesGcm(key);
      final sealed = gcm.encrypt(
        nonce: nonce,
        plaintext: Uint8List.fromList(utf8.encode('transfer 100')),
      );

      sealed[2] ^= 0x01;
      expect(
        () => gcm.decrypt(nonce: nonce, sealed: sealed),
        throwsA(isA<AesGcmAuthenticationError>()),
      );
    });

    test('a wrong key is refused', () {
      final nonce = randomBytes(12);
      final sealed = AesGcm(randomBytes(32)).encrypt(
        nonce: nonce,
        plaintext: Uint8List.fromList(utf8.encode('secret')),
      );

      expect(
        () => AesGcm(randomBytes(32)).decrypt(nonce: nonce, sealed: sealed),
        throwsA(isA<AesGcmAuthenticationError>()),
      );
    });
  });

  group('deriving a key from a passphrase', () {
    test('answers the published PBKDF2-HMAC-SHA256 vectors', () {
      expect(
        _toHex(
          deriveKeyFromPassphrase(
            passphrase: 'password',
            salt: Uint8List.fromList(utf8.encode('salt')),
            iterations: 1,
          ),
        ),
        '120fb6cffcf8b32c43e7225256c4f837'
        'a86548c92ccc35480805987cb70be17b',
      );
      expect(
        _toHex(
          deriveKeyFromPassphrase(
            passphrase: 'password',
            salt: Uint8List.fromList(utf8.encode('salt')),
            iterations: 2,
          ),
        ),
        'ae4d0c95af6b46d32d0adff928f06dd0'
        '2a303f8ef3c251dfd6e2d85a95474c43',
      );
      expect(
        _toHex(
          deriveKeyFromPassphrase(
            passphrase: 'password',
            salt: Uint8List.fromList(utf8.encode('salt')),
            iterations: 4096,
          ),
        ),
        'c5e478d59288c841aa530db6845c4c8d'
        '962893a001ce4e11a4963873aa98134a',
      );
    });

    test('a different salt gives a different key for the same words', () {
      final first = deriveKeyFromPassphrase(
        passphrase: 'correct horse battery staple',
        salt: _hex('00000000000000000000000000000001'),
        iterations: 100,
      );
      final second = deriveKeyFromPassphrase(
        passphrase: 'correct horse battery staple',
        salt: _hex('00000000000000000000000000000002'),
        iterations: 100,
      );
      expect(first, isNot(second));
    });

    test('random bytes are not the same twice', () {
      expect(randomBytes(32), isNot(randomBytes(32)));
    });

    test('length is what makes a passphrase strong, not punctuation', () {
      expect(ratePassphrase('abc'), PassphraseStrength.tooShort);
      expect(ratePassphrase('password'), PassphraseStrength.weak);
      expect(
        ratePassphrase('the quiet blue notebook on my desk'),
        PassphraseStrength.strong,
      );
    });
  });

  group('the sealed value written into a page, a cell or a view', () {
    final key = randomBytes(32);

    test('round trips through its text form', () {
      final written = sealText(key: key, plaintext: 'Meeting notes');
      expect(looksSealed(written), isTrue);
      expect(openText(key: key, value: written), 'Meeting notes');
    });

    test('two seals of the same words never look alike', () {
      final first = sealText(key: key, plaintext: 'same');
      final second = sealText(key: key, plaintext: 'same');
      expect(first, isNot(second));
      expect(openText(key: key, value: second), 'same');
    });

    test('cannot be lifted out of what it was sealed against', () {
      final written = sealText(
        key: key,
        plaintext: 'only for this block',
        context: 'block-a',
      );
      expect(
        openText(key: key, value: written, context: 'block-a'),
        'only for this block',
      );
      expect(
        () => openText(key: key, value: written, context: 'block-b'),
        throwsA(isA<AesGcmAuthenticationError>()),
      );
    });

    test('plain text is reported as plain text, never as a bad key', () {
      expect(looksSealed('Meeting notes'), isFalse);
      expect(looksSealed(null), isFalse);
      expect(
        () => openText(key: key, value: 'Meeting notes'),
        throwsA(isA<FormatException>()),
      );
    });

    test('an empty value seals and opens', () {
      final written = sealText(key: key, plaintext: '');
      expect(openText(key: key, value: written), isEmpty);
    });

    test('carries bytes as well as words', () {
      final payload = randomBytes(1000);
      final written = sealBytes(key: key, plaintext: payload);
      expect(openBytes(key: key, value: written), payload);
    });
  });
}
