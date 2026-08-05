import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/imap_client.dart';
import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:flutter/foundation.dart';

/// How a sync is getting on, for the interface to report.
@immutable
class MailSyncProgress {
  const MailSyncProgress({
    required this.stage,
    this.fetched = 0,
    this.total = 0,
  });

  final MailSyncStage stage;
  final int fetched;
  final int total;
}

enum MailSyncStage { connecting, signingIn, searching, fetching, done }

/// What a finished sync produced.
@immutable
class MailSyncResult {
  const MailSyncResult({
    this.account,
    this.fetched = 0,
    this.skipped = 0,
    this.error,
    this.isAuthFailure = false,
  });

  /// The account with its new watermark, to be written back.
  final MailAccount? account;

  final int fetched;
  final int skipped;
  final String? error;
  final bool isAuthFailure;

  bool get succeeded => error == null;
}

/// Brings new messages down from a mailbox and files them in the collection.
///
/// A synced message is written as the `.eml` file the server sent, so the
/// mailbox is always reading the real thing and everything downstream — the
/// threading, the three views, the search — works on it unchanged. Nothing is
/// ever sent, and nothing on the server is altered: every fetch peeks.
class MailSyncService {
  const MailSyncService({
    this.items = const WorkspaceItemService(),
    this.connect = ImapClient.connect,
  });

  final WorkspaceItemService items;

  /// Injectable so the sync can be exercised without a server.
  final Future<ImapClient> Function({
    required String host,
    required int port,
    bool secure,
    Duration timeout,
  }) connect;

  /// Signs in and reports the mailboxes on offer, for the connect panel.
  Future<List<ImapMailbox>> listMailboxes({
    required MailAccount account,
    required String secret,
  }) async {
    final client = await connect(
      host: account.host,
      port: account.port,
      secure: account.useSsl,
    );
    try {
      await _signIn(client, account, secret);
      final mailboxes = await client.listMailboxes();
      return mailboxes.where((mailbox) => mailbox.isSelectable).toList();
    } finally {
      await client.logout();
    }
  }

  /// Fetches whatever is new.
  ///
  /// [knownMessageIds] are the `Message-ID`s already in the collection: a
  /// mailbox that was synced, exported and synced again must not gain the same
  /// message twice.
  Future<MailSyncResult> sync({
    required MailAccount account,
    required String secret,
    required String parentViewId,
    Set<String> knownMessageIds = const <String>{},
    void Function(MailSyncProgress progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    ImapClient? client;
    var fetched = 0;
    var skipped = 0;

    try {
      onProgress?.call(
        const MailSyncProgress(stage: MailSyncStage.connecting),
      );
      client = await connect(
        host: account.host,
        port: account.port,
        secure: account.useSsl,
      );

      onProgress?.call(
        const MailSyncProgress(stage: MailSyncStage.signingIn),
      );
      await _signIn(client, account, secret);

      onProgress?.call(
        const MailSyncProgress(stage: MailSyncStage.searching),
      );
      final selection = await client.select(account.mailbox);

      // A changed UIDVALIDITY means the server renumbered the mailbox and
      // every UID this account remembered is meaningless.
      final renumbered = account.uidValidity != 0 &&
          selection.uidValidity != account.uidValidity;
      final afterUid = renumbered ? 0 : account.lastUid;

      final uids = await client.searchUids(
        afterUid: afterUid > 0 ? afterUid : null,
        since: afterUid > 0
            ? null
            : DateTime.now().subtract(Duration(days: account.sinceDays)),
      );

      // Newest first, so a capped sync brings down what matters most.
      final wanted = uids.reversed.take(account.syncLimit).toList()..sort();
      onProgress?.call(
        MailSyncProgress(
          stage: MailSyncStage.fetching,
          total: wanted.length,
        ),
      );

      var highest = afterUid;
      for (final uid in wanted) {
        if (cancelled?.call() ?? false) {
          break;
        }

        final bytes = await client.fetchMessage(uid);
        if (bytes == null || bytes.isEmpty) {
          skipped += 1;
          continue;
        }

        if (_isAlreadyHere(bytes, knownMessageIds)) {
          skipped += 1;
          highest = uid > highest ? uid : highest;
          continue;
        }

        final result = await items.createBlankFile(
          parentViewId: parentViewId,
          kind: WorkspaceFileKind.file,
          name: emailFileNameFor(bytes),
          content: bytes,
        );
        result.fold((_) => fetched += 1, (_) => skipped += 1);

        highest = uid > highest ? uid : highest;
        onProgress?.call(
          MailSyncProgress(
            stage: MailSyncStage.fetching,
            fetched: fetched,
            total: wanted.length,
          ),
        );
      }

      onProgress?.call(const MailSyncProgress(stage: MailSyncStage.done));
      return MailSyncResult(
        account: account.copyWith(
          lastUid: highest,
          uidValidity: selection.uidValidity,
          lastSyncAt: DateTime.now().toUtc(),
          clearError: true,
        ),
        fetched: fetched,
        skipped: skipped,
      );
    } on ImapException catch (error) {
      return MailSyncResult(
        account: account.copyWith(lastError: error.message),
        fetched: fetched,
        skipped: skipped,
        error: error.message,
        isAuthFailure: error.isAuthFailure,
      );
    } catch (error) {
      final message = '$error';
      return MailSyncResult(
        account: account.copyWith(lastError: message),
        fetched: fetched,
        skipped: skipped,
        error: message,
      );
    } finally {
      await client?.logout();
    }
  }

  Future<void> _signIn(
    ImapClient client,
    MailAccount account,
    String secret,
  ) async {
    await client.capability();
    if (account.authKind == MailAuthKind.oauth) {
      await client.authenticateXOAuth2(account.username, secret);
      return;
    }
    await client.login(account.username, secret);
  }

  /// Whether the collection already holds this message.
  static bool _isAlreadyHere(Uint8List bytes, Set<String> knownMessageIds) {
    if (knownMessageIds.isEmpty) {
      return false;
    }
    try {
      final id = parseMimeMessage(bytes).messageId;
      return id != null && knownMessageIds.contains(id);
    } catch (_) {
      return false;
    }
  }
}
