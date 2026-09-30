import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/appflowy_cloud_auth.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

/// Reads at most `maxBytes` from the start of a file stored online, or null
/// when it cannot be read.
typedef RemoteFileHeadReader = Future<List<int>?> Function(
  Uri uri,
  int maxBytes,
);

const _timeout = Duration(seconds: 10);
const _maximumRedirects = 3;
const _maximumConcurrentReads = 3;

final _slots = _ReadSlots(_maximumConcurrentReads);

/// Reads the opening of a file stored online, for a preview card.
///
/// Only the first bytes are asked for, and the transfer is cut off at the
/// limit even when the server ignores the range, so a large file costs a few
/// kilobytes. At most a few reads are in flight at once, so a wall of cards
/// cannot start a wall of downloads.
///
/// The signed-in user's token goes only to the AppFlowy Cloud the app is
/// connected to. Redirects are followed by hand so that it never follows a
/// redirect to anywhere else.
Future<List<int>?> readRemoteFileHead(
  Uri uri,
  int maxBytes, {
  http.Client? client,
  Future<Map<String, String>> Function(Uri uri)? headersFor,
}) async {
  if (maxBytes <= 0) return const [];
  await _slots.acquire();
  final owned = client == null;
  final http.Client transport = client ?? http.Client();
  try {
    var target = uri;
    for (var hop = 0; hop <= _maximumRedirects; hop++) {
      final scheme = target.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return null;
      final headers = await (headersFor ?? appFlowyCloudHeadersFor)(target);
      final request = http.Request('GET', target)
        ..followRedirects = false
        ..headers.addAll(headers)
        ..headers[HttpHeaders.rangeHeader] = 'bytes=0-${maxBytes - 1}';
      final response = await transport.send(request).timeout(_timeout);
      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        await _discard(response);
        final location = response.headers[HttpHeaders.locationHeader];
        if (location == null || location.isEmpty) return null;
        target = target.resolve(location);
        continue;
      }
      if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
        await _discard(response);
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_timeout)) {
        bytes.add(chunk);
        // Leaving the loop cancels the transfer.
        if (bytes.length >= maxBytes) break;
      }
      final head = bytes.takeBytes();
      return head.length > maxBytes
          ? Uint8List.sublistView(head, 0, maxBytes)
          : head;
    }
    return null;
  } on Object catch (error) {
    Log.info('Unable to read the start of a remote file: $error');
    return null;
  } finally {
    if (owned) transport.close();
    _slots.release();
  }
}

/// The AppFlowy Cloud token, for the connected AppFlowy Cloud only.
Future<Map<String, String>> appFlowyCloudHeadersFor(Uri uri) async {
  try {
    final cloud = Uri.tryParse(await getAppFlowyCloudUrl());
    if (cloud == null ||
        cloud.scheme.toLowerCase() != uri.scheme.toLowerCase() ||
        cloud.host.toLowerCase() != uri.host.toLowerCase() ||
        cloud.port != uri.port) {
      return const {};
    }
    final profile = await UserBackendService.getCurrentUserProfile();
    return profile.fold(appFlowyCloudAuthHeaders, (_) => const {});
  } on Object {
    return const {};
  }
}

Future<void> _discard(http.StreamedResponse response) async {
  try {
    await response.stream.listen(null).cancel();
  } on Object {
    // Nothing to keep from a response that is not used.
  }
}

class _ReadSlots {
  _ReadSlots(this._capacity);

  final int _capacity;
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;

  Future<void> acquire() {
    if (_active < _capacity) {
      _active++;
      return Future.value();
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    return turn.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      // The slot passes straight to the next read.
      _waiting.removeFirst().complete();
    } else if (_active > 0) {
      _active--;
    }
  }
}
