import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the workspace key policy', () {
    test('a passphrase opens the policy it was made with', () {
      final policy = newEncryptionPolicy(
        passphrase: 'the quiet blue notebook',
        hint: 'the one on my desk',
        iterations: 200,
      );

      expect(policy.enabled, isTrue);
      expect(policy.isConfigured, isTrue);
      expect(policy.hint, 'the one on my desk');
      expect(
        unlockEncryptionKey(
          policy: policy,
          passphrase: 'the quiet blue notebook',
        ),
        isNotNull,
      );
    });

    test('the wrong passphrase is answered with nothing, not an exception', () {
      final policy = newEncryptionPolicy(
        passphrase: 'the quiet blue notebook',
        iterations: 200,
      );
      expect(
        unlockEncryptionKey(policy: policy, passphrase: 'something else'),
        isNull,
      );
    });

    test('the passphrase itself is never written down', () {
      final policy = newEncryptionPolicy(
        passphrase: 'correct horse battery staple',
        iterations: 200,
      );
      final written = jsonEncode(policy.toJson());

      expect(written.contains('correct horse'), isFalse);
      expect(written.contains('battery'), isFalse);
    });

    test('an unconfigured policy opens for nobody', () {
      expect(
        unlockEncryptionKey(
          policy: const EncryptionPolicy(),
          passphrase: 'anything',
        ),
        isNull,
      );
    });

    test('survives being written down and read back', () {
      final policy = newEncryptionPolicy(
        passphrase: 'the quiet blue notebook',
        iterations: 200,
      ).copyWith(
        lockAfterMinutes: 30,
        gateWholeWorkspace: false,
      );

      final restored = EncryptionPolicy.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(policy.toJson()))),
      );
      expect(restored, policy);
      expect(
        unlockEncryptionKey(
          policy: restored,
          passphrase: 'the quiet blue notebook',
        ),
        isNotNull,
      );
    });

    test('two workspaces with the same words do not share a key', () {
      final first = newEncryptionPolicy(passphrase: 'shared', iterations: 200);
      final second = newEncryptionPolicy(passphrase: 'shared', iterations: 200);

      expect(first.salt, isNot(second.salt));
      expect(
        unlockEncryptionKey(policy: first, passphrase: 'shared'),
        isNot(unlockEncryptionKey(policy: second, passphrase: 'shared')),
      );
    });

    test('a container is gated, content is sealed', () {
      expect(EncryptionScope.page.gatesEntry, isTrue);
      expect(EncryptionScope.folder.gatesEntry, isTrue);
      expect(EncryptionScope.table.gatesEntry, isTrue);
      expect(EncryptionScope.file.gatesEntry, isTrue);
      expect(EncryptionScope.block.gatesEntry, isFalse);
      expect(EncryptionScope.column.gatesEntry, isFalse);
    });

    test('protecting one item does not close the whole workspace', () {
      // A passphrase chosen from a collection's menu must cover that
      // collection, not everything else in the workspace.
      final policy = newEncryptionPolicy(
        passphrase: 'the quiet blue notebook',
        iterations: 200,
      );
      expect(policy.gateWholeWorkspace, isFalse);
    });

    test('a policy written before this setting existed stays per item', () {
      // An earlier build wrote `gate_whole_workspace: true` whenever a
      // passphrase was set, which is not something anybody chose.
      final restored = EncryptionPolicy.fromJson(const {
        'enabled': true,
        'salt': 'AAAA',
        'verifier': 'af1.x.y',
        'gate_whole_workspace': true,
      });
      expect(restored.gateWholeWorkspace, isFalse);
    });
  });

  group('the mark that says an item needs the key', () {
    test('round trips through a view extra', () {
      final mark = EncryptionMark(
        scope: EncryptionScope.collection,
        protectedAt: DateTime.utc(2026, 8, 18, 9, 30),
        note: 'client work',
      );

      final restored = EncryptionMark.fromExtra(mark.mergeIntoExtra(''));
      expect(restored, isNotNull);
      expect(restored!.scope, EncryptionScope.collection);
      expect(restored.protectedAt, DateTime.utc(2026, 8, 18, 9, 30));
      expect(restored.note, 'client work');
    });

    test('leaves the other envelopes on the view alone', () {
      const existing = '{"appflowy_dashboard":{"version":1},"cover_chosen":1}';
      const mark = EncryptionMark(scope: EncryptionScope.page);

      final merged = mark.mergeIntoExtra(existing);
      final decoded = jsonDecode(merged) as Map;
      expect(decoded['appflowy_dashboard'], isNotNull);
      expect(decoded['cover_chosen'], 1);
      expect(decoded[EncryptionMark.envelopeKey], isNotNull);

      final removed = jsonDecode(EncryptionMark.removeFromExtra(merged)) as Map;
      expect(removed.containsKey(EncryptionMark.envelopeKey), isFalse);
      expect(removed['cover_chosen'], 1);
    });

    test('an extra that was never marked reads as unprotected', () {
      expect(EncryptionMark.fromExtra(''), isNull);
      expect(EncryptionMark.fromExtra('{"appflowy_chart":{}}'), isNull);
      expect(EncryptionMark.fromExtra('not json'), isNull);
    });

    test('a mark written by a later version is not guessed at', () {
      const extra = '{"appflowy_encryption":{"version":99,"scope":"page"}}';
      expect(EncryptionMark.fromExtra(extra), isNull);
    });
  });

  group('which columns of a table are sealed', () {
    test('round trips through a view extra', () {
      const columns = EncryptedColumns(fieldIds: {'notes', 'salary'});
      final restored = EncryptedColumns.fromExtra(columns.mergeIntoExtra(''));

      expect(restored.fieldIds, {'notes', 'salary'});
      expect(restored.contains('notes'), isTrue);
      expect(restored.contains('title'), isFalse);
    });

    test('clearing the last column removes the envelope entirely', () {
      const columns = EncryptedColumns(fieldIds: {'notes'});
      final marked = columns.mergeIntoExtra('{"cover_chosen":1}');
      final cleared = columns.with_('notes', sealed: false);

      expect(EncryptedColumns.fromExtra(marked).fieldIds, {'notes'});
      final after = jsonDecode(cleared.mergeIntoExtra(marked)) as Map;
      expect(after.containsKey(EncryptedColumns.envelopeKey), isFalse);
      expect(after['cover_chosen'], 1);
    });

    test('a table nobody has sealed reads as empty, not as broken', () {
      expect(EncryptedColumns.fromExtra('').isEmpty, isTrue);
      expect(EncryptedColumns.fromExtra('{"appflowy_map":{}}').isEmpty, isTrue);
    });
  });

  group('sealing one block', () {
    late Uint8List key;

    setUp(() {
      key = randomBytes(32);
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
          verifier: 'af1.x.y',
        ),
        key: key,
      );
    });

    tearDown(() => EncryptionVault.instance.resetForTest());

    test('a paragraph comes back exactly as it went in', () {
      final original = paragraphNode(text: 'The meeting is on Tuesday');

      final sealed = sealBlock(original);
      expect(sealed, isNotNull);
      expect(sealed!.type, EncryptedBlockKeys.type);
      expect(sealed.encryptedBlockKind, ParagraphBlockKeys.type);

      final opened = openBlock(sealed);
      expect(opened, isNotNull);
      expect(opened!.type, ParagraphBlockKeys.type);
      expect(opened.delta?.toPlainText(), 'The meeting is on Tuesday');
    });

    test('nothing readable is left behind', () {
      final sealed = sealBlock(paragraphNode(text: 'salary is 90000'))!;
      final written = jsonEncode(sealed.toJson());

      expect(written.contains('salary'), isFalse);
      expect(written.contains('90000'), isFalse);
      expect(looksSealed(sealed.encryptedBlockPayload), isTrue);
    });

    test('an embed keeps its attributes and its nested blocks', () {
      final original = Node(
        type: 'page_preview',
        attributes: {'view_id': 'abc-123', 'width': 720},
        children: [paragraphNode(text: 'caption')],
      );

      final opened = openBlock(sealBlock(original)!);
      expect(opened!.type, 'page_preview');
      expect(opened.attributes['view_id'], 'abc-123');
      expect(opened.attributes['width'], 720);
      expect(opened.children.single.delta?.toPlainText(), 'caption');
    });

    test('a locked workspace can neither seal nor open', () {
      final sealed = sealBlock(paragraphNode(text: 'secret'))!;
      EncryptionVault.instance.lock();

      expect(sealBlock(paragraphNode(text: 'more')), isNull);
      expect(openBlock(sealed), isNull);
    });

    test('a different key refuses to open it, rather than emptying it', () {
      final sealed = sealBlock(paragraphNode(text: 'secret'))!;
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(enabled: true, salt: 'x', verifier: 'y'),
        key: randomBytes(32),
      );

      expect(openBlock(sealed), isNull);
    });

    test('a block already sealed is not sealed twice', () {
      final sealed = sealBlock(paragraphNode(text: 'secret'))!;
      expect(sealBlock(sealed), isNull);
      expect(canSealBlock(sealed), isFalse);
    });

    test('the page root itself is never offered', () {
      expect(canSealBlock(Node(type: PageBlockKeys.type)), isFalse);
      expect(canSealBlock(paragraphNode(text: 'x')), isTrue);
    });
  });

  group('what a locked list shows', () {
    tearDown(() => EncryptionVault.instance.resetForTest());

    test('a protected item keeps its name, and loses what is inside it', () {
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'AAAA',
          verifier: 'af1.x.y',
        ),
      );

      final view = _viewWith(
        const EncryptionMark(scope: EncryptionScope.folder).mergeIntoExtra(''),
      );
      expect(view.isProtected, isTrue);
      expect(view.isLockedNow, isTrue);
      // A folder nobody can name is a folder nobody can find again.
      expect(view.name, 'Client work');
      expect(view.hidesChildrenWhileLocked, isTrue);
    });

    test('an unprotected folder lists what is inside it', () {
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'AAAA',
          verifier: 'af1.x.y',
        ),
      );

      final view = _viewWith('');
      expect(view.isProtected, isFalse);
      expect(view.hidesChildrenWhileLocked, isFalse);
    });

    test('the key being in memory is not the same as being open', () {
      // Nothing is revealed on a cold start, so a protected item is shut
      // however long the passphrase has been entered.
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'AAAA',
          verifier: 'af1.x.y',
        ),
        key: randomBytes(32),
      );

      final view = _viewWith(
        const EncryptionMark(scope: EncryptionScope.folder).mergeIntoExtra(''),
      );
      expect(view.isLockedNow, isTrue);
      expect(view.hidesChildrenWhileLocked, isTrue);
    });

    test('what is inside comes back once the item is unlocked', () {
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'AAAA',
          verifier: 'af1.x.y',
        ),
        key: randomBytes(32),
        revealed: {'view-1'},
      );

      final view = _viewWith(
        const EncryptionMark(scope: EncryptionScope.folder).mergeIntoExtra(''),
      );
      expect(view.isLockedNow, isFalse);
      expect(view.hidesChildrenWhileLocked, isFalse);
    });

    test('locking the workspace shuts everything that was open', () {
      EncryptionVault.instance.seedForTest(
        policy: const EncryptionPolicy(
          enabled: true,
          salt: 'AAAA',
          verifier: 'af1.x.y',
        ),
        key: randomBytes(32),
        revealed: {'view-1'},
      );
      EncryptionVault.instance.lock();

      expect(EncryptionVault.instance.isRevealed('view-1'), isFalse);
    });
  });

  group('typing a passphrase', () {
    // The editor and the shell claim Backspace, Enter and the arrows above
    // any field, so a bare TextField silently loses them while ordinary typing
    // still works. Nothing but reading the source catches this — a widget test
    // never exercises the ancestors that do the claiming.
    test('the lock screen restates the editing keys around its field', () {
      final source = File(
        'lib/workspace/presentation/encryption/workspace_lock_screen.dart',
      ).readAsStringSync();

      expect(
        source.contains('TextEntryShortcuts('),
        isTrue,
        reason: 'the passphrase field must restate the editing keys, or '
            'Backspace does nothing in it',
      );
    });

    test('the gate does not put a Focus node over the whole workspace', () {
      final source = File(
        'lib/workspace/presentation/encryption/workspace_lock_screen.dart',
      ).readAsStringSync();

      // Resetting the idle clock is worth a keyboard handler, never a Focus
      // node in everybody else's focus chain.
      expect(source.contains('canRequestFocus'), isFalse);
      expect(source.contains('HardwareKeyboard.instance.addHandler'), isTrue);
    });
  });
}

ViewPB _viewWith(String extra) => ViewPB()
  ..id = 'view-1'
  ..name = 'Client work'
  ..extra = extra;
