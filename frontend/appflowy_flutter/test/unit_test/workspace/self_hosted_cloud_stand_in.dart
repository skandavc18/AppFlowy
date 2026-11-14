// A self-hosted AppFlowy Cloud small enough to run inside a test: GoTrue's
// sign in, sign up and refresh, and the `/api/sync-folders` storage, answering
// exactly as the real server is documented to.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SelfHostedCloudStandIn {
  SelfHostedCloudStandIn._(this._server);

  /// Starts on a free port of this machine. [users] maps an email to its
  /// password.
  static Future<SelfHostedCloudStandIn> start({
    Map<String, String> users = const {},
  }) async {
    final standIn = SelfHostedCloudStandIn._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    users.forEach(standIn.addUser);
    standIn._server.listen(standIn._answer);
    return standIn;
  }

  final HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}';

  /// Whether the server is new enough to keep sync folders.
  bool keepsSyncFolders = true;

  bool signUpsOpen = true;

  /// Whether a new account can sign in straight away, rather than after
  /// confirming its email.
  bool autoConfirm = true;

  /// How long an access token works.
  Duration accessLifetime = const Duration(hours: 1);

  int refreshes = 0;

  final Map<String, ({String password, String id})> _users = {};
  final Map<String, ({String userId, DateTime expires})> _access = {};
  final Map<String, String> _refresh = {};
  int _issued = 0;

  /// Files by user, folder, and whether they are attached files.
  final Map<String, Map<String, Map<bool, Map<String, _File>>>> _files = {};

  void addUser(String email, String password) =>
      _users[email] = (password: password, id: 'user-${_users.length + 1}');

  /// Stops every access token working, as when they all lapse at once.
  void expireAccessTokens() => _access.updateAll(
        (_, token) => (userId: token.userId, expires: DateTime(2000)),
      );

  /// Signs everybody out: no token works or can be renewed.
  void revokeSignIns() {
    expireAccessTokens();
    _refresh.clear();
  }

  /// What a user keeps in [folder].
  Map<String, Uint8List> filesOf(
    String email,
    String folder, {
    bool blobs = false,
  }) =>
      {
        for (final entry
            in (_files[_users[email]!.id]?[folder]?[blobs] ?? {}).entries)
          entry.key: entry.value.bytes,
      };

  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    try {
      if (segments.length == 2 && segments.first == 'gotrue') {
        await _gotrue(request, segments[1]);
      } else if (segments.length >= 2 &&
          segments[0] == 'api' &&
          segments[1] == 'sync-folders' &&
          keepsSyncFolders) {
        await _syncFolders(request, segments.sublist(2));
      } else {
        await _reply(request, HttpStatus.notFound, {'message': 'Not found'});
      }
    } on Object catch (error) {
      await _reply(request, HttpStatus.internalServerError, {'msg': '$error'});
    }
  }

  Future<void> _gotrue(HttpRequest request, String path) async {
    if (path == 'health' && request.method == 'GET') {
      return _reply(request, HttpStatus.ok, {'name': 'GoTrue'});
    }
    final body = jsonDecode(await utf8.decodeStream(request)) as Map;
    if (path == 'signup') {
      final email = body['email'] as String;
      if (!signUpsOpen) {
        return _reply(request, 422, {
          'code': 422,
          'error_code': 'signup_disabled',
          'msg': 'Signups not allowed for this instance',
        });
      }
      if (_users.containsKey(email)) {
        return _reply(request, 422, {
          'code': 422,
          'error_code': 'user_already_exists',
          'msg': 'User already registered',
        });
      }
      addUser(email, body['password'] as String);
      return autoConfirm
          ? _reply(request, HttpStatus.ok, _session(email))
          : _reply(request, HttpStatus.ok, {'id': _users[email]!.id});
    }
    final grant = request.uri.queryParameters['grant_type'];
    if (path == 'token' && grant == 'password') {
      final user = _users[body['email']];
      if (user == null || user.password != body['password']) {
        return _reply(request, HttpStatus.badRequest, {
          'error': 'invalid_grant',
          'error_description': 'Invalid login credentials',
        });
      }
      return _reply(request, HttpStatus.ok, _session(body['email'] as String));
    }
    if (path == 'token' && grant == 'refresh_token') {
      refreshes++;
      final userId = _refresh.remove(body['refresh_token']);
      if (userId == null) {
        return _reply(request, HttpStatus.badRequest, {
          'error': 'invalid_grant',
          'error_description': 'Invalid Refresh Token: Already Used',
        });
      }
      final email = _users.entries.firstWhere((u) => u.value.id == userId).key;
      return _reply(request, HttpStatus.ok, _session(email));
    }
    return _reply(request, HttpStatus.notFound, {'msg': 'Not found'});
  }

  Map<String, Object?> _session(String email) {
    final user = _users[email]!;
    final access = 'access-${++_issued}';
    final refresh = 'refresh-$_issued';
    _access[access] = (
      userId: user.id,
      expires: DateTime.now().add(accessLifetime),
    );
    _refresh[refresh] = user.id;
    return {
      'access_token': access,
      'token_type': 'bearer',
      'expires_in': accessLifetime.inSeconds,
      'refresh_token': refresh,
      'user': {'id': user.id, 'email': email},
    };
  }

  static final _folderName =
      RegExp(r'^[A-Za-z0-9_-]([A-Za-z0-9._ -]*[A-Za-z0-9_-])?$');
  static final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  Future<void> _syncFolders(HttpRequest request, List<String> rest) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final token = _access[header?.replaceFirst('Bearer ', '')];
    if (token == null || token.expires.isBefore(DateTime.now())) {
      await request.drain<void>();
      return _reply(request, HttpStatus.unauthorized, {
        'code': 1003,
        'message': 'Invalid token',
      });
    }
    final mine = _files.putIfAbsent(token.userId, () => {});
    if (rest.isEmpty && request.method == 'GET') {
      final folders = [
        for (final entry in mine.entries)
          if (entry.value.values.any((files) => files.isNotEmpty)) entry.key,
      ]..sort();
      return _ok(request, {
        'folders': [
          for (final name in folders) {'name': name},
        ],
      });
    }
    final folder = rest.first;
    if (folder.length > 100 || !_folderName.hasMatch(folder)) {
      return _reply(request, HttpStatus.badRequest, {
        'code': 1004,
        'message': 'Invalid folder name',
      });
    }
    final blobs = request.uri.queryParameters['blobs'] == 'true';
    final files =
        mine.putIfAbsent(folder, () => {}).putIfAbsent(blobs, () => {});
    if (rest.length == 2 && rest[1] == 'files' && request.method == 'GET') {
      return _ok(request, {
        'files': [
          for (final entry in files.entries)
            {
              'name': entry.key,
              'size': entry.value.bytes.length,
              'modified_at': entry.value.modified.millisecondsSinceEpoch,
            },
        ],
      });
    }
    if (rest.length != 3 || rest[1] != 'files') {
      return _reply(request, HttpStatus.notFound, {'message': 'Not found'});
    }
    final name = rest[2];
    if (name.length > 200 || !_fileName.hasMatch(name)) {
      return _reply(request, HttpStatus.badRequest, {
        'code': 1004,
        'message': 'Invalid file name',
      });
    }
    switch (request.method) {
      case 'PUT':
        final bytes = await request.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (builder, chunk) => builder..add(chunk),
        );
        final file = _File(bytes.takeBytes(), DateTime.now());
        files[name] = file;
        return _ok(request, {
          'name': name,
          'size': file.bytes.length,
          'modified_at': file.modified.millisecondsSinceEpoch,
        });
      case 'GET':
        final file = files[name];
        if (file == null) {
          return _reply(request, HttpStatus.notFound, {
            'code': 1001,
            'message': 'Not found',
          });
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..contentLength = file.bytes.length
          ..add(file.bytes);
        return request.response.close();
      case 'DELETE':
        files.remove(name);
        return _ok(request, null);
    }
    return _reply(request, HttpStatus.methodNotAllowed, {'message': 'No'});
  }

  Future<void> _ok(HttpRequest request, Object? data) =>
      _reply(request, HttpStatus.ok, {'code': 0, 'message': '', 'data': data});

  Future<void> _reply(HttpRequest request, int status, Object body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    return request.response.close();
  }
}

class _File {
  _File(this.bytes, this.modified);

  final Uint8List bytes;
  final DateTime modified;
}
