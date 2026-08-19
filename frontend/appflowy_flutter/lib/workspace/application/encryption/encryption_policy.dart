import 'dart:convert';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:flutter/foundation.dart';

/// What kind of thing is being protected.
///
/// A container (a page, a folder, a collection, a table, a file) is *gated*:
/// it cannot be opened until the workspace key has been entered. Content
/// (a block, a column) is *sealed*: the words themselves are replaced by
/// ciphertext where they are stored. Both are worth having and they are not the
/// same promise, so they are named apart everywhere they are shown.
enum EncryptionScope {
  workspace,
  page,
  folder,
  collection,
  table,
  file,
  block,
  column;

  /// Whether protecting this means gating the way in rather than sealing bytes.
  bool get gatesEntry => switch (this) {
        EncryptionScope.workspace ||
        EncryptionScope.page ||
        EncryptionScope.folder ||
        EncryptionScope.collection ||
        EncryptionScope.table ||
        EncryptionScope.file =>
          true,
        EncryptionScope.block || EncryptionScope.column => false,
      };
}

/// Everything the application has been told about the workspace key.
///
/// The passphrase itself is never here and is never written anywhere. What is
/// stored is a salt, the work factor used with it, and a [verifier] — a known
/// phrase sealed with the derived key. Because the cipher authenticates, a
/// verifier that opens proves the passphrase without the passphrase ever having
/// been kept.
@immutable
class EncryptionPolicy {
  const EncryptionPolicy({
    this.enabled = false,
    this.salt = '',
    this.verifier = '',
    this.hint = '',
    this.iterations = defaultKeyIterations,
    this.lockAfterMinutes = 15,
    this.gateWholeWorkspace = false,
  });

  factory EncryptionPolicy.fromJson(Map<String, Object?> json) {
    int readInt(String key, int fallback) {
      final value = json[key];
      return value is int ? value : fallback;
    }

    bool readBool(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    return EncryptionPolicy(
      enabled: readBool('enabled', false),
      salt: readString('salt'),
      verifier: readString('verifier'),
      hint: readString('hint'),
      iterations: readInt('iterations', defaultKeyIterations),
      lockAfterMinutes: readInt('lock_after_minutes', 15),
      // Deliberately a NEW key. An earlier build defaulted this to true and
      // wrote it whenever a passphrase was set, so a person protecting one
      // collection had the whole workspace closed behind them. Reading the old
      // `gate_whole_workspace` would carry that mistake forward.
      gateWholeWorkspace: readBool('gates_workspace', false),
    );
  }

  /// The words the verifier holds. They are not secret — what matters is that
  /// only the right key can produce them again.
  static const verifierPhrase = 'appflowy-workspace-key-v1';

  /// How long the key may stay in memory with nothing happening.
  ///
  /// Zero means "until the application closes", which is a real choice for a
  /// machine only one person uses.
  static const lockDelayChoices = <int>[0, 1, 5, 15, 30, 60, 240];

  final bool enabled;
  final String salt;
  final String verifier;
  final String hint;
  final int iterations;
  final int lockAfterMinutes;

  /// Whether the whole workspace waits behind the passphrase, or only the
  /// items that were protected one at a time.
  ///
  /// The key is never written down, so a workspace always starts locked. What
  /// this decides is how much that covers. It defaults to FALSE: a passphrase
  /// chosen in order to protect one collection must not quietly close the way
  /// in to everything else.
  final bool gateWholeWorkspace;

  bool get locksOnIdle => lockAfterMinutes > 0;

  bool get isConfigured => enabled && salt.isNotEmpty && verifier.isNotEmpty;

  Uint8List get saltBytes {
    try {
      return Uint8List.fromList(base64Decode(salt));
    } on FormatException {
      return Uint8List(0);
    }
  }

  EncryptionPolicy copyWith({
    bool? enabled,
    String? salt,
    String? verifier,
    String? hint,
    int? iterations,
    int? lockAfterMinutes,
    bool? gateWholeWorkspace,
  }) =>
      EncryptionPolicy(
        enabled: enabled ?? this.enabled,
        salt: salt ?? this.salt,
        verifier: verifier ?? this.verifier,
        hint: hint ?? this.hint,
        iterations: iterations ?? this.iterations,
        lockAfterMinutes: lockAfterMinutes ?? this.lockAfterMinutes,
        gateWholeWorkspace: gateWholeWorkspace ?? this.gateWholeWorkspace,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'salt': salt,
        'verifier': verifier,
        'hint': hint,
        'iterations': iterations,
        'lock_after_minutes': lockAfterMinutes,
        'gates_workspace': gateWholeWorkspace,
      };

  @override
  bool operator ==(Object other) =>
      other is EncryptionPolicy &&
      other.enabled == enabled &&
      other.salt == salt &&
      other.verifier == verifier &&
      other.hint == hint &&
      other.iterations == iterations &&
      other.lockAfterMinutes == lockAfterMinutes &&
      other.gateWholeWorkspace == gateWholeWorkspace;

  @override
  int get hashCode => Object.hash(
        enabled,
        salt,
        verifier,
        hint,
        iterations,
        lockAfterMinutes,
        gateWholeWorkspace,
      );
}

/// Builds the policy that goes with a freshly chosen passphrase.
///
/// Pure, so the whole "does this passphrase open this policy?" question can be
/// answered in a test with no storage and no widgets.
EncryptionPolicy newEncryptionPolicy({
  required String passphrase,
  String hint = '',
  int iterations = defaultKeyIterations,
  EncryptionPolicy previous = const EncryptionPolicy(),
  Uint8List? salt,
}) {
  final chosenSalt = salt ?? newEncryptionSalt();
  final key = deriveKeyFromPassphrase(
    passphrase: passphrase,
    salt: chosenSalt,
    iterations: iterations,
  );
  return previous.copyWith(
    enabled: true,
    salt: base64Encode(chosenSalt),
    iterations: iterations,
    hint: hint,
    verifier: sealText(
      key: key,
      plaintext: EncryptionPolicy.verifierPhrase,
      context: EncryptionPolicy.verifierPhrase,
    ),
  );
}

/// The key [passphrase] unlocks, or null when it is the wrong passphrase.
///
/// Returning null rather than throwing is deliberate: a wrong passphrase is an
/// ordinary answer to an ordinary question, not a fault.
Uint8List? unlockEncryptionKey({
  required EncryptionPolicy policy,
  required String passphrase,
}) {
  if (!policy.isConfigured) {
    return null;
  }
  final salt = policy.saltBytes;
  if (salt.isEmpty) {
    return null;
  }

  final key = deriveKeyFromPassphrase(
    passphrase: passphrase,
    salt: salt,
    iterations: policy.iterations,
  );
  try {
    final opened = openText(
      key: key,
      value: policy.verifier,
      context: EncryptionPolicy.verifierPhrase,
    );
    return opened == EncryptionPolicy.verifierPhrase ? key : null;
  } on AesGcmAuthenticationError {
    return null;
  } on FormatException {
    return null;
  }
}
