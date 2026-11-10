// The desktop keyring on Linux: GNOME Keyring, KWallet, KeePassXC or anything
// else that speaks the Secret Service API, reached through libsecret.
//
// A secret kept there is encrypted with the login of the person at the
// desktop and unlocked with it, which is what DPAPI does on Windows. libsecret
// is reached straight through FFI, as DPAPI is, so no plugin is needed.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:appflowy/shared/libsecret.dart';
import 'package:path_provider/path_provider.dart';

export 'package:appflowy/shared/libsecret.dart' show KeyringError;

/// Somewhere secrets outlive the application, sealed to the person using it.
abstract class DesktopKeyring {
  bool get isAvailable;

  /// Keeps [secret] as [id] within [scope], replacing whatever was there.
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  });

  /// The secret kept as [id] within [scope], or null when there is none.
  Future<String?> lookup({required String scope, required String id});

  /// Removes the secret kept as [id] within [scope], if there is one.
  Future<void> clear({required String scope, required String id});
}

/// Keeps secrets in the keyring of the person signed in to the desktop.
///
/// Each call runs on an isolate of its own: the keyring may have to be
/// unlocked first, and the prompt asking for that must not freeze the window
/// behind it.
///
/// Every secret is filed under the AppFlowy profile it belongs to — the folder
/// that holds the preferences naming it — so a second profile, such as one a
/// test runs with, can neither read nor replace this one's secrets.
class LinuxKeyring implements DesktopKeyring {
  LinuxKeyring._();

  static final LinuxKeyring instance = LinuxKeyring._();

  // Long enough to type a password into an unlock prompt.
  static const _timeout = Duration(minutes: 2);

  bool? _loadable;
  bool _refused = false;
  Future<String>? _profile;

  // Asked for this session and not there, so a list drawing a row per account
  // does not ask again for every row; and lookups still out, so two asking at
  // once share one answer.
  final Set<String> _absent = <String>{};
  final Map<String, Future<String?>> _reading = <String, Future<String?>>{};

  /// Whether secrets can be kept here: this is Linux, libsecret is installed
  /// and the keyring has not refused so far. Unit tests never touch the
  /// keyring of the person running them.
  @override
  bool get isAvailable {
    if (!Platform.isLinux ||
        _refused ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    return _loadable ??= Libsecret.load() != null;
  }

  @override
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  }) async {
    final key = _key(scope, id);
    _absent.remove(key);
    await _run((profile) => _storeIn(profile, scope, id, label, secret));
    // A lookup that was out while this was stored may have found nothing.
    _absent.remove(key);
  }

  @override
  Future<String?> lookup({required String scope, required String id}) {
    final key = _key(scope, id);
    if (_absent.contains(key)) {
      return Future<String?>.value();
    }
    return _reading[key] ??= () async {
      try {
        final found = await _run((profile) => _lookupIn(profile, scope, id));
        if (found == null) {
          _absent.add(key);
        }
        return found;
      } finally {
        unawaited(_reading.remove(key));
      }
    }();
  }

  @override
  Future<void> clear({required String scope, required String id}) async {
    await _run((profile) => _clearIn(profile, scope, id));
    _absent.add(_key(scope, id));
  }

  /// Removes every secret this AppFlowy profile kept, for a profile that is
  /// going away — a test's, say.
  Future<void> clearProfile() async {
    await _run(_clearProfileIn);
    _absent.clear();
  }

  static String _key(String scope, String id) => '$scope\n$id';

  // A closure sent to another isolate takes every variable of the scopes it
  // was made in along, and one made in a method of this keyring takes the
  // keyring itself, whose pending lookups cannot be sent. Made here, each one
  // takes only the strings it is given.
  static Future<void> _storeIn(
    String profile,
    String scope,
    String id,
    String label,
    String secret,
  ) =>
      Isolate.run(
        () => Libsecret.require().store(profile, scope, id, label, secret),
      );

  static Future<String?> _lookupIn(String profile, String scope, String id) =>
      Isolate.run(() => Libsecret.require().lookup(profile, scope, id));

  static Future<void> _clearIn(String profile, String scope, String id) =>
      Isolate.run(() => Libsecret.require().clear(profile, scope, id));

  static Future<void> _clearProfileIn(String profile) =>
      Isolate.run(() => Libsecret.require().clearProfile(profile));

  Future<T> _run<T>(Future<T> Function(String profile) call) async {
    if (!isAvailable) {
      throw const KeyringError('No desktop keyring is available.');
    }
    final profile = await (_profile ??= _profilePath());
    try {
      return await call(profile).timeout(_timeout);
    } on Object catch (error) {
      // A keyring that refused once, or never answered, is not asked again
      // this session: what it should have kept is held in memory instead, and
      // the interface says so.
      _refused = true;
      throw error is KeyringError ? error : KeyringError('$error');
    }
  }

  static Future<String> _profilePath() async =>
      (await getApplicationSupportDirectory()).path;
}
