import 'dart:typed_data';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/encryption/encrypted_column.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown or malformed protection metadata blocks writers', () {
    expect(EncryptedColumns.forWriting(''), isNotNull);
    expect(EncryptedColumns.forWriting('{"cover":true}'), isNotNull);
    for (final extra in [
      '{broken',
      '[]',
      '{"appflowy_encrypted_columns":{"version":99,"fields":["f"]}}',
      '{"appflowy_encrypted_columns":{"version":1,"fields":[1]}}',
      '{"appflowy_encrypted_columns":null}',
    ]) {
      expect(EncryptedColumns.forWriting(extra), isNull);
    }
  });

  test('locking mid-rewrite cannot encrypt later rows with a wiped key',
      () async {
    final key = randomBytes(32);
    final originalKey = Uint8List.fromList(key);
    final values = {'a': '  first  ', 'b': 'second\n'};
    final written = <String, String>{};
    var marked = false;
    final result = await rewriteColumnEncryption(
      key: key,
      values: values,
      encrypt: true,
      write: (id, value) async {
        written[id] = value;
        key.fillRange(0, key.length, 0);
        return true;
      },
      mark: () async => marked = true,
    );
    expect(result.succeeded, isTrue);
    expect(marked, isTrue);
    for (final entry in written.entries) {
      expect(
          openText(
              key: originalKey,
              value: entry.value,
              context: encryptedCellContext),
          values[entry.key]);
    }
  });

  test('one unreadable cell prevents every decryption write', () async {
    final key = randomBytes(32);
    var writes = 0;
    final result = await rewriteColumnEncryption(
      key: key,
      values: {
        'a': sealText(
            key: key, plaintext: 'kept', context: encryptedCellContext),
        'b': 'af1.invalid.payload'
      },
      encrypt: false,
      write: (_, __) async {
        writes++;
        return true;
      },
      mark: () async => true,
    );
    expect(result.failure, 'wrongKey');
    expect(writes, 0);
  });

  for (final failMark in [false, true]) {
    test(
        '${failMark ? 'mark' : 'cell'} failure rolls back exact original values',
        () async {
      final values = {'a': '  first  ', 'b': 'second\n'};
      final storage = {...values};
      var refused = false;
      final result = await rewriteColumnEncryption(
        key: randomBytes(32),
        values: values,
        encrypt: true,
        write: (id, value) async {
          if (!failMark && id == 'b' && !refused) {
            refused = true;
            return false;
          }
          storage[id] = value;
          return true;
        },
        mark: () async => !failMark,
      );
      expect(result.succeeded, isFalse);
      expect(storage, values);
    });
  }

  test('failed rollback is never reported as successful protection', () async {
    final result = await rewriteColumnEncryption(
      key: randomBytes(32),
      values: {'a': 'first'},
      encrypt: true,
      write: (_, value) async => looksSealed(value),
      mark: () async => false,
    );
    expect(result.succeeded, isFalse);
    expect(result.failure, 'incomplete');
  });

  test('an empty column can be protected before the first entry', () async {
    var marked = false;
    final result = await rewriteColumnEncryption(
      key: randomBytes(32),
      values: const {},
      encrypt: true,
      write: (_, __) async => throw StateError('no writes expected'),
      mark: () async => marked = true,
    );
    expect(result.succeeded, isTrue);
    expect(result.cells, 0);
    expect(marked, isTrue);
  });
}
