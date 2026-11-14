// Syncing through a self-hosted AppFlowy Cloud.
//
// The server keeps the same files a Google Drive folder would, behind
// `/api/sync-folders`, and its GoTrue signs people in. The password is used
// once, to get the tokens GoTrue issues; only the tokens are kept, in the same
// store as every other service's.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/backup/provider_file_transfer.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Someone's account on a self-hosted AppFlowy Cloud.
@immutable
class SelfHostedCloudAccount {
  const SelfHostedCloudAccount({
    required this.id,
    required this.server,
    required this.email,
    this.userId = '',
  });

  static SelfHostedCloudAccount? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final server = json['server'];
    final email = json['email'];
    final userId = json['user_id'];
    if (id is! String || id.isEmpty || server is! String || server.isEmpty) {
      return null;
    }
    return SelfHostedCloudAccount(
      id: id,
      server: server,
      email: email is String ? email : '',
      userId: userId is String ? userId : '',
    );
  }

  final String id;

  /// The server's address, as [SelfHostedCloud.normalizeServer] writes it.
  final String server;
  final String email;

  /// GoTrue's id for the person.
  final String userId;

  String get host => serverHost(server);

  String get label => email.isEmpty ? host : '$email · $host';

  Map<String, Object?> toJson() => {
        'id': id,
        'server': server,
        'email': email,
        if (userId.isNotEmpty) 'user_id': userId,
      };
}

/// The host (and port, when it isn't the usual one) of a server address.
String serverHost(String server) {
  final uri = Uri.tryParse(server);
  if (uri == null || uri.host.isEmpty) {
    return server;
  }
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// What GoTrue issued for one sign in.
@immutable
class SelfHostedCloudTokens {
  const SelfHostedCloudTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Reads GoTrue's answer to a sign in or a refresh.
  static SelfHostedCloudTokens? fromGoTrue(
    Map<String, Object?> json,
    DateTime now,
  ) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      return null;
    }
    final expiresAt = json['expires_at'];
    final expiresIn = json['expires_in'];
    final DateTime expiry;
    if (expiresAt is num && expiresAt > 0) {
      expiry = DateTime.fromMillisecondsSinceEpoch((expiresAt * 1000).round());
    } else if (expiresIn is num && expiresIn > 0) {
      expiry = now.add(Duration(seconds: expiresIn.round()));
    } else {
      expiry = now.add(const Duration(hours: 1));
    }
    return SelfHostedCloudTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiry,
    );
  }

  static SelfHostedCloudTokens? decode(String? stored) {
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(stored);
      if (json is! Map) {
        return null;
      }
      final access = json['access_token'];
      final refresh = json['refresh_token'];
      final expiresAt = json['expires_at'];
      if (access is! String || refresh is! String || expiresAt is! int) {
        return null;
      }
      return SelfHostedCloudTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      );
    } on FormatException {
      return null;
    }
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Whether the access token will still work for the next request or so.
  bool isFreshAt(DateTime now) =>
      now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  String encode() => jsonEncode({
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.millisecondsSinceEpoch,
      });
}

/// The accounts kept for syncing through self-hosted AppFlowy Clouds.
class SelfHostedCloudAccounts extends ChangeNotifier {
  SelfHostedCloudAccounts({
    KeyValueStorage? storage,
    ProviderSecretStore? secrets,
  })  : _storage = storage,
        secrets = secrets ?? ProviderSecretStore(storage: storage);

  static final SelfHostedCloudAccounts instance = SelfHostedCloudAccounts();

  static const storageKey = 'appflowy_self_hosted_cloud_accounts';

  final KeyValueStorage? _storage;
  final ProviderSecretStore secrets;

  final List<SelfHostedCloudAccount> _accounts = <SelfHostedCloudAccount>[];
  bool _loaded = false;
  Future<void>? _loading;

  List<SelfHostedCloudAccount> get all =>
      List<SelfHostedCloudAccount>.unmodifiable(_accounts);

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future<void>.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _kv?.get(storageKey);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is List) {
        for (final account in decoded
            .map(SelfHostedCloudAccount.fromJson)
            .whereType<SelfHostedCloudAccount>()) {
          if (_accounts.every((kept) => kept.id != account.id)) {
            _accounts.add(account);
          }
        }
      }
    } catch (error) {
      Log.warn(
        'Unable to read the self-hosted AppFlowy Cloud accounts: $error',
      );
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

  SelfHostedCloudAccount? byId(String id) =>
      _accounts.firstWhereOrNull((account) => account.id == id);

  SelfHostedCloudAccount? find({
    required String server,
    required String email,
  }) =>
      _accounts.firstWhereOrNull(
        (account) =>
            account.server == server &&
            account.email.toLowerCase() == email.toLowerCase(),
      );

  /// Keeps [tokens] for [email] on [server] — under [id] when given, so a
  /// sync folder that names an account keeps naming it after signing in again,
  /// and otherwise under the account already kept for that person.
  Future<SelfHostedCloudAccount> remember({
    required String server,
    required String email,
    required SelfHostedCloudTokens tokens,
    String userId = '',
    String? id,
  }) async {
    await ensureLoaded();
    final existing = id == null ? find(server: server, email: email) : byId(id);
    final account = SelfHostedCloudAccount(
      id: id ?? existing?.id ?? 'afcloud-${const Uuid().v4()}',
      server: server,
      email: email,
      userId: userId.isNotEmpty ? userId : existing?.userId ?? '',
    );
    _accounts
      ..removeWhere((kept) => kept.id == account.id)
      ..add(account);
    await secrets.write(account.id, tokens.encode());
    await _write();
    notifyListeners();
    return account;
  }

  Future<SelfHostedCloudTokens?> tokensFor(String id) async =>
      SelfHostedCloudTokens.decode(await secrets.read(id));

  Future<void> keepTokens(String id, SelfHostedCloudTokens tokens) =>
      secrets.write(id, tokens.encode());

  Future<void> forget(String id) async {
    await ensureLoaded();
    _accounts.removeWhere((account) => account.id == id);
    await secrets.forget(id);
    await _write();
    notifyListeners();
  }

  /// Forgets every account and its tokens, as starting afresh does.
  Future<void> forgetAll() async {
    await ensureLoaded();
    for (final account in List.of(_accounts)) {
      await secrets.forget(account.id);
    }
    _accounts.clear();
    await _write();
    notifyListeners();
  }

  Future<void> _write() async => _kv?.set(
        storageKey,
        jsonEncode([for (final account in _accounts) account.toJson()]),
      );
}

/// What answers at an address someone typed.
enum SelfHostedCloudCheck {
  /// An AppFlowy Cloud that keeps sync folders.
  ready,

  /// An AppFlowy Cloud without sync folders: one that hasn't been updated, or
  /// AppFlowy's own service.
  noSyncFolders,

  /// Something that isn't an AppFlowy Cloud.
  notAppFlowyCloud,

  /// Nothing answered.
  unreachable,
}

/// Why signing in or signing up didn't work.
enum SelfHostedCloudAuthProblem {
  wrongPassword,
  emailNotConfirmed,
  signUpsClosed,
  accountExists,
  weakPassword,
  unreachable,
  refused,
}

class SelfHostedCloudAuthError implements Exception {
  const SelfHostedCloudAuthError(this.problem, [this.detail = '']);

  final SelfHostedCloudAuthProblem problem;

  /// For the log only: a stranger's server decides what is in it.
  final String detail;

  @override
  String toString() => 'SelfHostedCloudAuthError($problem): $detail';
}

/// The outcome of signing up: an account to use now, or an email to confirm
/// before signing in.
@immutable
class SelfHostedCloudSignUp {
  const SelfHostedCloudSignUp(this.account);

  final SelfHostedCloudAccount? account;

  bool get needsConfirmation => account == null;
}

/// A file in a sync folder on the server.
@immutable
class SelfHostedCloudFile {
  const SelfHostedCloudFile({
    required this.name,
    required this.bytes,
    this.modifiedAt,
  });

  final String name;
  final int bytes;
  final DateTime? modifiedAt;
}

/// Talks to self-hosted AppFlowy Clouds: signs in, and keeps sync folders.
class SelfHostedCloud {
  SelfHostedCloud({
    http.Client? client,
    SelfHostedCloudAccounts? accounts,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _accounts = accounts ?? SelfHostedCloudAccounts.instance,
        _clock = clock ?? DateTime.now;

  static final SelfHostedCloud instance = SelfHostedCloud();

  final http.Client _client;
  final SelfHostedCloudAccounts _accounts;
  final DateTime Function() _clock;

  /// How long a request may wait for an answer. A transfer's own bytes are
  /// not timed: a large file on a slow line takes as long as it takes.
  final Duration timeout;

  final Map<String, Future<SelfHostedCloudTokens>> _refreshing = {};

  static const _json = {'Content-Type': 'application/json'};

  /// The address [typed] names — with a scheme, without a trailing slash — or
  /// null when it can't be a server's address.
  static String? normalizeServer(String typed) {
    var text = typed.trim();
    if (text.isEmpty) {
      return null;
    }
    if (!text.contains('://')) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceAll(RegExp(r'/+$'), ''),
    ).toString();
  }

  static final RegExp _folderPattern =
      RegExp(r'^[A-Za-z0-9_-]([A-Za-z0-9._ -]*[A-Za-z0-9_-])?$');

  /// Whether the server accepts [name] for a sync folder.
  static bool isValidFolderName(String name) =>
      name.length <= 100 && _folderPattern.hasMatch(name);

  Uri _api(String server, List<String> segments, {bool? blobs}) {
    final base = Uri.parse(server);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'api',
        'sync-folders',
        ...segments,
      ],
      queryParameters: blobs == null ? null : {'blobs': '$blobs'},
    );
  }

  Uri _gotrue(String server, String path, [Map<String, String>? query]) {
    final base = Uri.parse(server);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'gotrue',
        path,
      ],
      queryParameters: query,
    );
  }

  /// Finds out whether [server] is an AppFlowy Cloud that keeps sync folders:
  /// one asks who is calling before it answers.
  Future<SelfHostedCloudCheck> check(String server) async {
    try {
      final response =
          await _client.get(_api(server, const [])).timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return SelfHostedCloudCheck.ready;
      }
      final health =
          await _client.get(_gotrue(server, 'health')).timeout(timeout);
      return health.statusCode == 200
          ? SelfHostedCloudCheck.noSyncFolders
          : SelfHostedCloudCheck.notAppFlowyCloud;
    } on Object catch (error) {
      Log.info('No AppFlowy Cloud answered at $server: $error');
      return SelfHostedCloudCheck.unreachable;
    }
  }

  Future<SelfHostedCloudAccount> signIn({
    required String server,
    required String email,
    required String password,
    String? keepId,
  }) async {
    final json = await _authPost(
      _gotrue(server, 'token', {'grant_type': 'password'}),
      {'email': email, 'password': password},
    );
    final account = await _remember(server, email, json, keepId);
    if (account == null) {
      throw const SelfHostedCloudAuthError(
        SelfHostedCloudAuthProblem.refused,
        'GoTrue answered without tokens.',
      );
    }
    return account;
  }

  Future<SelfHostedCloudSignUp> signUp({
    required String server,
    required String email,
    required String password,
  }) async {
    final json = await _authPost(
      _gotrue(server, 'signup'),
      {'email': email, 'password': password},
    );
    // A server that confirms email first answers with the person alone.
    return SelfHostedCloudSignUp(await _remember(server, email, json, null));
  }

  Future<Map<String, Object?>> _authPost(
    Uri uri,
    Map<String, String> fields,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: _json, body: jsonEncode(fields))
          .timeout(timeout);
    } on Object catch (error) {
      throw SelfHostedCloudAuthError(
        SelfHostedCloudAuthProblem.unreachable,
        '$error',
      );
    }
    final json = _decodeObject(response.body);
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        json != null) {
      return json;
    }
    throw _authError(response.statusCode, json);
  }

  static SelfHostedCloudAuthError _authError(
    int status,
    Map<String, Object?>? json,
  ) {
    final said = [
      json?['error_code'],
      json?['error'],
      json?['error_description'],
      json?['msg'],
      json?['message'],
    ].whereType<String>().join(' ').toLowerCase();
    final detail = 'HTTP $status $said';
    final problem = switch (said) {
      _
          when said.contains('not confirmed') ||
              said.contains('email_not_confirmed') =>
        SelfHostedCloudAuthProblem.emailNotConfirmed,
      _
          when said.contains('signup') &&
              (said.contains('disabled') || said.contains('not allowed')) =>
        SelfHostedCloudAuthProblem.signUpsClosed,
      _ when said.contains('already') =>
        SelfHostedCloudAuthProblem.accountExists,
      _ when said.contains('weak') || said.contains('password should') =>
        SelfHostedCloudAuthProblem.weakPassword,
      _ when status == 400 || status == 401 =>
        SelfHostedCloudAuthProblem.wrongPassword,
      _ => SelfHostedCloudAuthProblem.refused,
    };
    return SelfHostedCloudAuthError(problem, detail);
  }

  Future<SelfHostedCloudAccount?> _remember(
    String server,
    String typedEmail,
    Map<String, Object?> json,
    String? keepId,
  ) async {
    final tokens = SelfHostedCloudTokens.fromGoTrue(json, _clock());
    if (tokens == null) {
      return null;
    }
    final user = json['user'];
    final email = user is Map && user['email'] is String
        ? user['email'] as String
        : typedEmail;
    return _accounts.remember(
      server: server,
      email: email.isEmpty ? typedEmail : email,
      userId: user is Map && user['id'] is String ? user['id'] as String : '',
      tokens: tokens,
      id: keepId,
    );
  }

  /// A token to send for [account]: the one kept while it still works, and a
  /// renewed one when it is about to run out or is the [rejected] one the
  /// server just turned away.
  Future<String> accessToken(
    SelfHostedCloudAccount account, {
    String? rejected,
  }) async {
    final tokens = await _accounts.tokensFor(account.id);
    if (tokens == null) {
      throw const ProviderFailure.authExpired(
        'No token is kept for this account.',
      );
    }
    if (tokens.accessToken != rejected && tokens.isFreshAt(_clock())) {
      return tokens.accessToken;
    }
    return (await _refresh(account, tokens)).accessToken;
  }

  /// One refresh at a time per account: GoTrue hands out a new refresh token
  /// with every refresh, and two racing would leave one of them stale.
  Future<SelfHostedCloudTokens> _refresh(
    SelfHostedCloudAccount account,
    SelfHostedCloudTokens stale,
  ) {
    final running = _refreshing[account.id];
    if (running != null) {
      return running;
    }
    final renewing = _renew(account, stale);
    _refreshing[account.id] = renewing;
    return renewing.whenComplete(() => _refreshing.remove(account.id));
  }

  Future<SelfHostedCloudTokens> _renew(
    SelfHostedCloudAccount account,
    SelfHostedCloudTokens stale,
  ) async {
    // A refresh that finished while this one was being asked for already
    // has what is needed.
    final current = await _accounts.tokensFor(account.id) ?? stale;
    if (current.accessToken != stale.accessToken &&
        current.isFreshAt(_clock())) {
      return current;
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            _gotrue(account.server, 'token', {'grant_type': 'refresh_token'}),
            headers: _json,
            body: jsonEncode({'refresh_token': current.refreshToken}),
          )
          .timeout(timeout);
    } on Object catch (error) {
      throw ProviderFailure.offline('$error');
    }
    final json = _decodeObject(response.body);
    final renewed = response.statusCode == 200 && json != null
        ? SelfHostedCloudTokens.fromGoTrue(json, _clock())
        : null;
    if (renewed != null) {
      await _accounts.keepTokens(account.id, renewed);
      return renewed;
    }
    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw ProviderFailure.authExpired(
        'The server no longer renews this sign in: HTTP ${response.statusCode}',
      );
    }
    throw ProviderFailure.fromStatusCode(
      response.statusCode,
      detail: 'renewing a sign in',
    );
  }

  /// Sends what [build] makes with [account]'s token, once more with a renewed
  /// token when the first is turned away.
  Future<http.StreamedResponse> _send(
    SelfHostedCloudAccount account,
    http.BaseRequest Function() build, {
    bool timed = true,
  }) async {
    String? rejected;
    while (true) {
      final token = await accessToken(account, rejected: rejected);
      final request = build()
        ..headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      final http.StreamedResponse response;
      try {
        final sending = _client.send(request);
        response = timed ? await sending.timeout(timeout) : await sending;
      } on Object catch (error) {
        throw ProviderFailure.offline('$error');
      }
      if (response.statusCode == 401 && rejected == null) {
        await response.stream.drain<void>();
        rejected = token;
        continue;
      }
      return response;
    }
  }

  /// The `data` of a JSON answer, or the failure it reports.
  Future<Map<String, Object?>> _data(http.StreamedResponse response) async {
    final String body;
    try {
      body = await response.stream.bytesToString();
    } on Object catch (error) {
      throw ProviderFailure.offline('$error');
    }
    final json = _decodeObject(body);
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    final code = json?['code'];
    // Anything but the server's own envelope — a proxy's page, say — is not
    // an answer: read as an empty folder, it would start sync over.
    if (ok && json != null && (code == null || code == 0)) {
      final data = json['data'];
      return data is Map ? data.cast<String, Object?>() : const {};
    }
    final message = json?['message'];
    throw ProviderFailure.fromStatusCode(
      ok ? 500 : response.statusCode,
      detail: message is String ? message : '',
      retryAfterHeader: response.headers['retry-after'],
    );
  }

  /// The sync folders [account] keeps on its server.
  Future<List<String>> folders(SelfHostedCloudAccount account) async {
    final data = await _data(
      await _send(account, () => http.Request('GET', _api(account.server, []))),
    );
    final folders = data['folders'];
    return [
      if (folders is List)
        for (final folder in folders)
          if (folder is Map && folder['name'] is String)
            folder['name'] as String,
    ];
  }

  Future<List<SelfHostedCloudFile>> files(
    SelfHostedCloudAccount account,
    String folder, {
    bool blobs = false,
  }) async {
    final data = await _data(
      await _send(
        account,
        () => http.Request(
          'GET',
          _api(account.server, [folder, 'files'], blobs: blobs),
        ),
      ),
    );
    final files = data['files'];
    return [
      if (files is List)
        for (final file in files)
          if (file is Map && file['name'] is String)
            SelfHostedCloudFile(
              name: file['name'] as String,
              bytes: (file['size'] as num?)?.toInt() ?? 0,
              modifiedAt: _time(file['modified_at']),
            ),
    ];
  }

  Future<SelfHostedCloudFile> upload(
    SelfHostedCloudAccount account,
    String folder,
    String name,
    File file, {
    bool blobs = false,
    FileTransferProgress? onProgress,
  }) async {
    final length = await file.length();
    final response = await _send(
      account,
      () => _FileRequest(
        'PUT',
        _api(account.server, [folder, 'files', name], blobs: blobs),
        file,
        length,
        onProgress,
      ),
      timed: false,
    );
    if (response.statusCode == HttpStatus.requestEntityTooLarge) {
      await response.stream.drain<void>();
      throw const BackupTargetError(
        'A file is larger than your AppFlowy Cloud accepts.',
      );
    }
    final data = await _data(response);
    return SelfHostedCloudFile(
      name: name,
      bytes: (data['size'] as num?)?.toInt() ?? length,
      modifiedAt: _time(data['modified_at']) ?? _clock(),
    );
  }

  Future<void> download(
    SelfHostedCloudAccount account,
    String folder,
    String name,
    File destination, {
    bool blobs = false,
    int expectedBytes = 0,
    FileTransferProgress? onProgress,
  }) async {
    final response = await _get(account, folder, name, blobs: blobs);
    final total = response.contentLength ?? expectedBytes;
    await destination.parent.create(recursive: true);
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } on FileSystemException {
      rethrow;
    } on Object catch (error) {
      throw ProviderFailure.offline('$error');
    } finally {
      await sink.close();
    }
  }

  Future<List<int>> read(
    SelfHostedCloudAccount account,
    String folder,
    String name, {
    bool blobs = false,
  }) async {
    final response = await _get(account, folder, name, blobs: blobs);
    try {
      return await response.stream.toBytes();
    } on Object catch (error) {
      throw ProviderFailure.offline('$error');
    }
  }

  Future<http.StreamedResponse> _get(
    SelfHostedCloudAccount account,
    String folder,
    String name, {
    required bool blobs,
  }) async {
    final response = await _send(
      account,
      () => http.Request(
        'GET',
        _api(account.server, [folder, 'files', name], blobs: blobs),
      ),
    );
    if (response.statusCode == HttpStatus.notFound) {
      await response.stream.drain<void>();
      throw const BackupTargetError('A sync file is no longer in the folder.');
    }
    if (response.statusCode != HttpStatus.ok) {
      await _data(response);
    }
    return response;
  }

  Future<void> delete(
    SelfHostedCloudAccount account,
    String folder,
    String name, {
    bool blobs = false,
  }) async {
    final response = await _send(
      account,
      () => http.Request(
        'DELETE',
        _api(account.server, [folder, 'files', name], blobs: blobs),
      ),
    );
    if (response.statusCode == HttpStatus.notFound) {
      await response.stream.drain<void>();
      return;
    }
    await _data(response);
  }

  static Map<String, Object?>? _decodeObject(String body) {
    if (body.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(body);
      return json is Map ? json.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  static DateTime? _time(Object? milliseconds) => milliseconds is num
      ? DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt())
      : null;
}

/// A file sent as it is read, so a large one is never held in memory.
class _FileRequest extends http.BaseRequest {
  _FileRequest(
    super.method,
    super.url,
    this.file,
    int length,
    this.onProgress,
  ) {
    contentLength = length;
    headers[HttpHeaders.contentTypeHeader] = 'application/octet-stream';
  }

  final File file;
  final FileTransferProgress? onProgress;

  @override
  http.ByteStream finalize() {
    super.finalize();
    final total = contentLength ?? 0;
    var sent = 0;
    return http.ByteStream(
      file.openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      }),
    );
  }
}
