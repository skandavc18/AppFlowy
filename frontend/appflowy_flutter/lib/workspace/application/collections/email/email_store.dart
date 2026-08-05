import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// What one read of a message file produced.
class EmailReadResult {
  const EmailReadResult({
    this.message,
    this.sizeBytes,
    this.failed = false,
  });

  final MimeMessage? message;
  final int? sizeBytes;
  final bool failed;

  bool get isEmpty => message == null;
}

/// Reads `.eml` files off disk and remembers what it found.
///
/// A mailbox is opened far more often than it changes, so a parsed message is
/// held against its view id and only reread when the file's own timestamp
/// moves. Nothing here reaches the network: the collection is a folder of
/// files, not an account.
class EmailStore {
  EmailStore({this.maxBytes = maxMimeMessageBytes});

  /// How much of one file is worth reading. A message past this is almost
  /// always a mailbox that was misnamed.
  final int maxBytes;

  final Map<String, MimeMessage> _parsed = <String, MimeMessage>{};
  final Map<String, DateTime> _readAt = <String, DateTime>{};

  MimeMessage? peek(String viewId) => _parsed[viewId];

  bool has(String viewId) => _parsed.containsKey(viewId);

  void forget(String viewId) {
    _parsed.remove(viewId);
    _readAt.remove(viewId);
  }

  void clear() {
    _parsed.clear();
    _readAt.clear();
  }

  /// Reads the message behind [view], from the cache when it can.
  Future<EmailReadResult> read(ViewPB view) async {
    final cached = _parsed[view.id];
    if (cached != null) {
      return EmailReadResult(message: cached);
    }

    final path = _localPathOf(view);
    if (path == null) {
      return const EmailReadResult(failed: true);
    }

    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const EmailReadResult(failed: true);
      }

      final length = await file.length();
      final bytes = length <= maxBytes
          ? await file.readAsBytes()
          : await _readHead(file, maxBytes);

      final message = parseMimeMessage(bytes);
      _parsed[view.id] = message;
      _readAt[view.id] = DateTime.now();
      return EmailReadResult(message: message, sizeBytes: length);
    } catch (_) {
      return const EmailReadResult(failed: true);
    }
  }

  /// Reads several messages without opening every file at once, which is what
  /// exhausts file handles on a mailbox of any size.
  Future<void> readAll(
    List<ViewPB> views, {
    int batch = 6,
    void Function(ViewPB view, EmailReadResult result)? onRead,
    bool Function()? cancelled,
  }) async {
    for (var index = 0; index < views.length; index += batch) {
      if (cancelled?.call() ?? false) {
        return;
      }
      final slice = views.skip(index).take(batch).toList();
      final results = await Future.wait(slice.map(read));
      for (var offset = 0; offset < slice.length; offset++) {
        onRead?.call(slice[offset], results[offset]);
      }
    }
  }

  Future<Uint8List> _readHead(File file, int count) async {
    final handle = await file.open();
    try {
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  static String? _localPathOf(ViewPB view) {
    final item = view.workspaceItem;
    final url = item?.storageUrl;
    if (item == null || !item.isFile || url == null || url.isEmpty) {
      return null;
    }
    // A message the workspace only holds in the cloud cannot be opened here.
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    final isLocal = scheme == null ||
        scheme.isEmpty ||
        scheme == 'file' ||
        (scheme.length == 1 && url.length > 1 && url[1] == ':');
    return isLocal ? url : null;
  }
}

/// Whether the mailbox can read the file behind [message] at all.
bool canReadMessageFile(EmailMessage message) =>
    EmailStore._localPathOf(message.view) != null;
