// Sealing a copy before it leaves this computer.
//
// The whole point of client-side encryption is that the service holding the
// backup is not trusted with what is in it, so the sealing happens here and the
// passphrase never goes anywhere. A backup is far too big to seal in one go —
// it is written as a run of independently sealed chunks, each authenticated,
// each bound to its own position, with a final marker that pins how many there
// were so a truncated file is refused rather than half restored.
//
// ⚠️ The cipher is the workspace's own hand-rolled AES-256-GCM, which runs at a
// few megabytes a second. That is fine for a file on disk and hopeless on the
// interface thread, so every long operation here happens in an isolate and
// reports progress back.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:flutter/foundation.dart';

/// Four bytes nothing else writes, so a file that is not one of ours is said
/// to be not one of ours instead of failing to authenticate.
const List<int> backupCipherMagic = [0x41, 0x46, 0x42, 0x4B]; // 'AFBK'

const int backupCipherVersion = 1;

/// How much plaintext each sealed chunk holds.
///
/// Four mebibytes is a compromise: large enough that the per-chunk overhead
/// (a nonce, a tag, a length) is nothing, small enough that neither sealing nor
/// opening ever needs more than a few megabytes of memory whatever the size of
/// the workspace.
const int backupChunkBytes = 4 * 1024 * 1024;

/// The header is the magic, the version and the chunk size.
const int backupHeaderBytes = 4 + 1 + 4;

const int _nonceBytes = 12;
const int _tagBytes = 16;

/// Raised when a sealed backup is not what it claims to be.
class BackupCipherError implements Exception {
  const BackupCipherError(this.reason);

  final BackupCipherFailure reason;

  @override
  String toString() => 'BackupCipherError: ${reason.name}';
}

enum BackupCipherFailure {
  /// The file was never a sealed backup.
  notABackup,

  /// Written by a later version of AppFlowy.
  unsupportedVersion,

  /// The passphrase is wrong, or the bytes have been altered.
  wrongKeyOrAltered,

  /// The file stops before its last chunk.
  truncated,
}

/// The key a passphrase becomes, for a backup.
///
/// Deliberately its own derivation and its own salt rather than the workspace
/// key: a backup has to be openable on a machine that has never seen this
/// workspace, and the workspace key is held in memory only and is never written
/// down anywhere a restore could read it.
Uint8List deriveBackupKey({
  required String passphrase,
  required Uint8List salt,
  int iterations = defaultKeyIterations,
}) =>
    deriveKeyFromPassphrase(
      passphrase: passphrase,
      salt: salt,
      iterations: iterations,
    );

/// The salt and verifier a freshly chosen backup passphrase produces.
///
/// The passphrase itself is never returned and never stored. The verifier is a
/// known phrase sealed with the derived key: because the cipher authenticates,
/// a verifier that opens IS the proof that the passphrase was right.
({String salt, String verifier}) newBackupPassphrase({
  required String passphrase,
  required String verifierPhrase,
  int iterations = defaultKeyIterations,
  Uint8List? salt,
}) {
  final chosenSalt = salt ?? newEncryptionSalt();
  final key = deriveBackupKey(
    passphrase: passphrase,
    salt: chosenSalt,
    iterations: iterations,
  );
  return (
    salt: base64Encode(chosenSalt),
    verifier: sealText(
      key: key,
      plaintext: verifierPhrase,
      context: 'backup',
    ),
  );
}

/// The key for [passphrase], or null when it is the wrong one.
///
/// Returns rather than throws, because a wrong passphrase is an ordinary thing
/// for somebody to type and not an error in the program.
Uint8List? unlockBackupKey({
  required String passphrase,
  required String salt,
  required String verifier,
  required String verifierPhrase,
  int iterations = defaultKeyIterations,
}) {
  if (salt.isEmpty || verifier.isEmpty) {
    return null;
  }
  final Uint8List saltBytes;
  try {
    saltBytes = Uint8List.fromList(base64Decode(salt));
  } on FormatException {
    return null;
  }
  final key = deriveBackupKey(
    passphrase: passphrase,
    salt: saltBytes,
    iterations: iterations,
  );
  try {
    final opened = openText(key: key, value: verifier, context: 'backup');
    return opened == verifierPhrase ? key : null;
  } on Object {
    return null;
  }
}

/// How far along a long sealing or opening is.
typedef BackupCipherProgress = void Function(int done, int total);

/// Seals [source] into [destination], reporting progress as it goes.
///
/// Returns the size of what was written. Runs off the interface thread.
Future<int> sealBackupFile({
  required File source,
  required File destination,
  required Uint8List key,
  int chunkBytes = backupChunkBytes,
  BackupCipherProgress? onProgress,
}) =>
    _runInIsolate(
      _sealEntryPoint,
      _CipherRequest(
        sourcePath: source.path,
        destinationPath: destination.path,
        key: key,
        chunkBytes: chunkBytes,
      ),
      onProgress,
    );

/// Opens what [sealBackupFile] wrote.
///
/// Throws [BackupCipherError] for a wrong passphrase, a truncated file or
/// something that was never a backup at all.
Future<int> openBackupFile({
  required File source,
  required File destination,
  required Uint8List key,
  BackupCipherProgress? onProgress,
}) =>
    _runInIsolate(
      _openEntryPoint,
      _CipherRequest(
        sourcePath: source.path,
        destinationPath: destination.path,
        key: key,
      ),
      onProgress,
    );

/// Whether [file] begins the way a sealed backup does.
///
/// Reads nine bytes, so it is cheap enough to ask of every file in a folder.
Future<bool> looksLikeSealedBackup(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final header = await handle.read(backupHeaderBytes);
    if (header.length < backupHeaderBytes) {
      return false;
    }
    for (var i = 0; i < backupCipherMagic.length; i++) {
      if (header[i] != backupCipherMagic[i]) {
        return false;
      }
    }
    return true;
  } on Object {
    return false;
  } finally {
    await handle?.close();
  }
}

// --- The work itself, written so it can run on either thread ------------------

/// Seals [sourcePath] into [destinationPath]. Blocking; call it in an isolate.
@visibleForTesting
int sealBackupFileSync({
  required String sourcePath,
  required String destinationPath,
  required Uint8List key,
  int chunkBytes = backupChunkBytes,
  BackupCipherProgress? onProgress,
}) {
  final cipher = AesGcm(key);
  final source = File(sourcePath).openSync();
  final sink = File(destinationPath).openSync(mode: FileMode.write);
  try {
    final total = source.lengthSync();

    final header = Uint8List(backupHeaderBytes);
    header.setRange(0, 4, backupCipherMagic);
    header[4] = backupCipherVersion;
    ByteData.sublistView(header).setUint32(5, chunkBytes);
    sink.writeFromSync(header);

    var index = 0;
    var read = 0;
    var written = header.length;
    while (read < total) {
      final plain = source.readSync(chunkBytes);
      if (plain.isEmpty) {
        break;
      }
      read += plain.length;
      written += _writeChunk(sink, cipher, plain, index);
      index++;
      onProgress?.call(read, total);
    }

    // The last record seals nothing but names how many chunks there were, so a
    // file that stops early cannot pass as a whole one.
    written += _writeChunk(sink, cipher, Uint8List(0), index, isEnd: true);
    return written;
  } finally {
    source.closeSync();
    sink.closeSync();
  }
}

/// Opens [sourcePath] into [destinationPath]. Blocking; call it in an isolate.
@visibleForTesting
int openBackupFileSync({
  required String sourcePath,
  required String destinationPath,
  required Uint8List key,
  BackupCipherProgress? onProgress,
}) {
  final cipher = AesGcm(key);
  final source = File(sourcePath).openSync();
  final sink = File(destinationPath).openSync(mode: FileMode.write);
  try {
    final total = source.lengthSync();
    final header = source.readSync(backupHeaderBytes);
    if (header.length < backupHeaderBytes) {
      throw const BackupCipherError(BackupCipherFailure.notABackup);
    }
    for (var i = 0; i < backupCipherMagic.length; i++) {
      if (header[i] != backupCipherMagic[i]) {
        throw const BackupCipherError(BackupCipherFailure.notABackup);
      }
    }
    if (header[4] != backupCipherVersion) {
      throw const BackupCipherError(BackupCipherFailure.unsupportedVersion);
    }

    var index = 0;
    var written = 0;
    while (true) {
      final record = _readChunk(source, cipher, index);
      if (record == null) {
        // Ran out of file without ever reading the marker.
        throw const BackupCipherError(BackupCipherFailure.truncated);
      }
      if (record.isEnd) {
        break;
      }
      sink.writeFromSync(record.plaintext);
      written += record.plaintext.length;
      index++;
      onProgress?.call(source.positionSync(), total);
    }
    return written;
  } finally {
    source.closeSync();
    sink.closeSync();
  }
}

int _writeChunk(
  RandomAccessFile sink,
  AesGcm cipher,
  Uint8List plaintext,
  int index, {
  bool isEnd = false,
}) {
  final nonce = randomBytes(_nonceBytes);
  final sealed = cipher.encrypt(
    nonce: nonce,
    plaintext: plaintext,
    aad: Uint8List.fromList(utf8.encode(_chunkContext(index, isEnd: isEnd))),
  );
  final length = Uint8List(4);
  ByteData.sublistView(length).setUint32(0, sealed.length);
  sink
    ..writeFromSync(length)
    ..writeFromSync(nonce)
    ..writeFromSync(sealed);
  return length.length + nonce.length + sealed.length;
}

({Uint8List plaintext, bool isEnd})? _readChunk(
  RandomAccessFile source,
  AesGcm cipher,
  int index,
) {
  final length = source.readSync(4);
  if (length.length < 4) {
    return null;
  }
  final sealedLength = ByteData.sublistView(length).getUint32(0);
  if (sealedLength < _tagBytes) {
    throw const BackupCipherError(BackupCipherFailure.notABackup);
  }
  final nonce = source.readSync(_nonceBytes);
  if (nonce.length < _nonceBytes) {
    throw const BackupCipherError(BackupCipherFailure.truncated);
  }
  final sealed = source.readSync(sealedLength);
  if (sealed.length < sealedLength) {
    throw const BackupCipherError(BackupCipherFailure.truncated);
  }

  // A record is either the next chunk or the end marker, and only its own
  // context opens it — so a chunk cannot be moved, repeated or dropped.
  for (final isEnd in const [false, true]) {
    try {
      final plaintext = cipher.decrypt(
        nonce: nonce,
        sealed: sealed,
        aad: Uint8List.fromList(
          utf8.encode(_chunkContext(index, isEnd: isEnd)),
        ),
      );
      return (plaintext: plaintext, isEnd: isEnd);
    } on AesGcmAuthenticationError {
      continue;
    }
  }
  throw const BackupCipherError(BackupCipherFailure.wrongKeyOrAltered);
}

String _chunkContext(int index, {required bool isEnd}) =>
    isEnd ? 'afbackup:end:$index' : 'afbackup:$index';

// --- Running it on another thread --------------------------------------------

class _CipherRequest {
  const _CipherRequest({
    required this.sourcePath,
    required this.destinationPath,
    required this.key,
    this.chunkBytes = backupChunkBytes,
  });

  final String sourcePath;
  final String destinationPath;
  final Uint8List key;
  final int chunkBytes;
}

class _CipherMessage {
  const _CipherMessage(this.request, this.replyTo);

  final _CipherRequest request;
  final SendPort replyTo;
}

Future<int> _runInIsolate(
  void Function(_CipherMessage) entryPoint,
  _CipherRequest request,
  BackupCipherProgress? onProgress,
) async {
  final port = ReceivePort();
  final completer = Completer<int>();

  final subscription = port.listen((Object? message) {
    if (message is List && message.length == 3 && message.first == 'progress') {
      onProgress?.call(message[1] as int, message[2] as int);
      return;
    }
    if (message is List && message.length == 2 && message.first == 'done') {
      if (!completer.isCompleted) {
        completer.complete(message[1] as int);
      }
      return;
    }
    if (message is List && message.length == 2 && message.first == 'failed') {
      if (!completer.isCompleted) {
        completer.completeError(
          BackupCipherError(message[1] as BackupCipherFailure),
        );
      }
      return;
    }
    if (message is List && message.length == 2 && message.first == 'error') {
      if (!completer.isCompleted) {
        completer.completeError(StateError(message[1] as String));
      }
    }
  });

  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
      entryPoint,
      _CipherMessage(request, port.sendPort),
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    return await completer.future;
  } finally {
    await subscription.cancel();
    port.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

void _sealEntryPoint(_CipherMessage message) {
  _report(message, () {
    var lastReported = 0;
    return sealBackupFileSync(
      sourcePath: message.request.sourcePath,
      destinationPath: message.request.destinationPath,
      key: message.request.key,
      chunkBytes: message.request.chunkBytes,
      onProgress: (done, total) {
        // One message a chunk is plenty; a port send per read would cost more
        // than the cipher does.
        if (done - lastReported >= backupChunkBytes || done >= total) {
          lastReported = done;
          message.replyTo.send(['progress', done, total]);
        }
      },
    );
  });
}

void _openEntryPoint(_CipherMessage message) {
  _report(message, () {
    var lastReported = 0;
    return openBackupFileSync(
      sourcePath: message.request.sourcePath,
      destinationPath: message.request.destinationPath,
      key: message.request.key,
      onProgress: (done, total) {
        if (done - lastReported >= backupChunkBytes || done >= total) {
          lastReported = done;
          message.replyTo.send(['progress', done, total]);
        }
      },
    );
  });
}

void _report(_CipherMessage message, int Function() work) {
  try {
    message.replyTo.send(['done', work()]);
  } on BackupCipherError catch (error) {
    message.replyTo.send(['failed', error.reason]);
  } on Object catch (error) {
    message.replyTo.send(['error', error.toString()]);
  }
}
