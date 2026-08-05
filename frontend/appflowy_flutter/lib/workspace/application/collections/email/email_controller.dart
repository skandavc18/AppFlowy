import 'dart:async';

import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/email_service.dart';
import 'package:appflowy/workspace/application/collections/email/email_state.dart';
import 'package:appflowy/workspace/application/collections/email/email_store.dart';
import 'package:appflowy/workspace/application/collections/email/email_thread.dart';
import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/collections/email/mail_sync.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The mailbox: what is in it, what is showing, and what the reader has done
/// to it.
class EmailController extends ChangeNotifier {
  EmailController({
    Map<String, dynamic>? initialState,
    this.onPersist,
    this.onSynced,
    this.collectionId = '',
    EmailStore? store,
    EmailService service = const EmailService(),
    MailSyncService sync = const MailSyncService(),
    MailSecretStore? secrets,
    ConnectedAccountRegistry registry = const ConnectedAccountRegistry(),
    Duration persistDebounce = const Duration(milliseconds: 900),
  })  : _store = store ?? EmailStore(),
        _service = service,
        _sync = sync,
        _secrets = secrets ?? MailSecretStore(),
        _registry = registry,
        _persistDebounce = persistDebounce,
        _state = initialState == null
            ? const EmailState()
            : EmailState.fromJson(initialState);

  final EmailStore _store;
  final EmailService _service;
  final MailSyncService _sync;
  final MailSecretStore _secrets;
  final ConnectedAccountRegistry _registry;
  final Duration _persistDebounce;

  /// The name of the collection this mailbox is, for the accounts panel.
  String collectionName = '';

  /// Called with the state to remember whenever a choice changes.
  final void Function(Map<String, dynamic> state)? onPersist;

  /// Called once a sync has filed new messages, so the folder can be reread.
  final Future<void> Function()? onSynced;

  /// The collection new messages are filed into.
  final String collectionId;

  EmailState _state;
  Timer? _persistTimer;
  Timer? _syncTimer;
  bool _disposed = false;
  bool _indexing = false;
  bool _syncing = false;
  MailSyncProgress? _syncProgress;
  int _generation = 0;

  final Map<String, EmailMessage> _byId = <String, EmailMessage>{};
  List<String> _order = const <String>[];
  String _query = '';

  List<EmailMessage> _visible = const <EmailMessage>[];
  List<EmailThread> _threads = const <EmailThread>[];
  List<EmailFacet> _senders = const <EmailFacet>[];
  List<EmailFacet> _labels = const <EmailFacet>[];
  EmailStats _stats = const EmailStats();

  EmailState get state => _state;

  EmailSettings get settings => _state.settings;

  String get query => _query;

  /// Every message in the mailbox, in the order the folder holds them.
  List<EmailMessage> get all =>
      _order.map((id) => _byId[id]).whereType<EmailMessage>().toList();

  /// The messages the current filter, search and sort leave showing.
  List<EmailMessage> get messages => _visible;

  /// The same messages gathered into conversations.
  List<EmailThread> get threads => _threads;

  List<EmailFacet> get senders => _senders;

  List<EmailFacet> get labels => _labels;

  EmailStats get stats => _stats;

  bool get isIndexing => _indexing;

  bool get isEmpty => _order.isEmpty;

  String? get activeId => _state.activeMessageId;

  EmailMessage? get activeMessage {
    final id = _state.activeMessageId;
    return id == null ? null : _byId[id];
  }

  /// The conversation the open message belongs to.
  EmailThread? get activeThread {
    final id = _state.activeMessageId;
    if (id == null) {
      return null;
    }
    for (final thread in _threads) {
      if (thread.messages.any((message) => message.id == id)) {
        return thread;
      }
    }
    return null;
  }

  MimeMessage? bodyOf(String viewId) => _store.peek(viewId);

  // ---------------------------------------------------------------- mailbox

  /// The server this mailbox is joined to, if any.
  MailAccount? get account => _state.account;

  bool get isConnected => _state.account?.isConfigured ?? false;

  bool get isSyncing => _syncing;

  MailSyncProgress? get syncProgress => _syncProgress;

  /// Whether a password can be kept between sessions on this machine.
  bool get canRememberSecret => _secrets.canPersist;

  MailSecretStore get secrets => _secrets;

  /// Joins the mailbox to a server, keeping the secret where it belongs.
  Future<void> connectAccount(
    MailAccount account, {
    required String secret,
  }) async {
    if (secret.isNotEmpty) {
      await _secrets.write(
        account.id,
        secret,
        remember: account.rememberSecret,
      );
    }
    _state = _state.copyWith(account: account);
    flush();
    unawaited(
      _registry.upsert(
        ConnectedAccount.fromAccount(
          account,
          collectionId: collectionId,
          collectionName: collectionName,
        ),
      ),
    );
    _restartSyncTimer();
    notifyListeners();
  }

  /// Forgets the server and the password with it.
  Future<void> disconnectAccount() async {
    final account = _state.account;
    if (account != null) {
      await _secrets.forget(account.id);
      await _registry.remove(account.id);
    }
    _state = _state.copyWith(clearAccount: true);
    flush();
    _syncTimer?.cancel();
    _syncTimer = null;
    notifyListeners();
  }

  /// Whether the account's password is to hand, or has to be asked for again
  /// because this machine will not keep one.
  Future<bool> hasSecret() async {
    final account = _state.account;
    return account == null ? false : await _secrets.has(account.id);
  }

  /// Brings down whatever is new.
  ///
  /// Returns null when there is nothing to sync or no password to sync with —
  /// the caller then asks for one rather than reporting a failure.
  Future<MailSyncResult?> syncNow({String? secret}) async {
    final account = _state.account;
    if (account == null || !account.isConfigured || _syncing) {
      return null;
    }

    final password = secret ?? await _secrets.read(account.id);
    if (password == null || password.isEmpty) {
      return null;
    }
    if (secret != null) {
      await _secrets.write(
        account.id,
        secret,
        remember: account.rememberSecret,
      );
    }

    _syncing = true;
    _syncProgress = const MailSyncProgress(stage: MailSyncStage.connecting);
    notifyListeners();

    final result = await _sync.sync(
      account: account,
      secret: password,
      parentViewId: collectionId,
      knownMessageIds: _knownMessageIds(),
      onProgress: (progress) {
        if (_disposed) {
          return;
        }
        _syncProgress = progress;
        notifyListeners();
      },
      cancelled: () => _disposed,
    );

    if (_disposed) {
      return result;
    }

    _syncing = false;
    _syncProgress = null;
    final updated = result.account;
    if (updated != null) {
      _state = _state.copyWith(account: updated);
      flush();
      unawaited(
        _registry.upsert(
          ConnectedAccount.fromAccount(
            updated,
            collectionId: collectionId,
            collectionName: collectionName,
          ),
        ),
      );
    }
    // A refused password is worth forgetting, or every sync repeats the same
    // failure with the same wrong secret.
    if (result.isAuthFailure) {
      await _secrets.forget(account.id);
    }
    notifyListeners();

    if (result.fetched > 0) {
      await onSynced?.call();
    }
    return result;
  }

  Set<String> _knownMessageIds() {
    final ids = <String>{};
    for (final message in _byId.values) {
      final id = message.metadata.messageId;
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
    }
    return ids;
  }

  /// Takes the collection's child views as the mailbox's contents.
  void setViews(List<ViewPB> views) {
    final order = <String>[];
    final next = <String, EmailMessage>{};

    for (final view in views) {
      final message = EmailMessage.fromView(view);
      if (message == null) {
        continue;
      }
      order.add(view.id);
      next[view.id] = message;
    }

    final changed = !listEquals(order, _order) ||
        next.entries.any((entry) {
          final previous = _byId[entry.key];
          return previous == null ||
              previous.view.extra != entry.value.view.extra ||
              previous.view.name != entry.value.view.name;
        });
    if (!changed) {
      return;
    }

    for (final id in _byId.keys.toList()) {
      if (!next.containsKey(id)) {
        _store.forget(id);
      }
    }

    _order = List<String>.unmodifiable(order);
    _byId
      ..clear()
      ..addAll(next);

    _rebuild();
    notifyListeners();
    unawaited(indexPending());
  }

  /// Reads every message that has never been read, so the list can show more
  /// than a file name.
  Future<void> indexPending() async {
    if (_indexing || _disposed) {
      return;
    }

    final pending = _order
        .map((id) => _byId[id])
        .whereType<EmailMessage>()
        .where((message) => !message.metadata.isIndexed)
        .where((message) => !message.metadata.unreadable)
        .map((message) => message.view)
        .toList();
    if (pending.isEmpty) {
      return;
    }

    _indexing = true;
    final generation = ++_generation;
    notifyListeners();

    await _store.readAll(
      pending,
      cancelled: () => _disposed || generation != _generation,
      onRead: (view, result) {
        final message = _byId[view.id];
        if (message == null) {
          return;
        }
        final parsed = result.message;
        final metadata = parsed == null
            ? message.metadata.copyWith(
                unreadable: true,
                indexedAt: DateTime.now(),
              )
            : EmailMetadata.fromMime(parsed, sizeBytes: result.sizeBytes);
        _apply(message.id, metadata, persist: true);
      },
    );

    if (_disposed || generation != _generation) {
      return;
    }
    _indexing = false;
    _rebuild();
    notifyListeners();
  }

  /// Reads one message's body, for the reading pane.
  Future<MimeMessage?> loadBody(String viewId) async {
    final message = _byId[viewId];
    if (message == null) {
      return null;
    }
    final cached = _store.peek(viewId);
    if (cached != null) {
      return cached;
    }

    final result = await _store.read(message.view);
    if (_disposed) {
      return result.message;
    }
    if (result.message == null) {
      _apply(
        viewId,
        message.metadata.copyWith(unreadable: true, indexedAt: DateTime.now()),
        persist: true,
      );
      notifyListeners();
      return null;
    }
    if (!message.metadata.isIndexed) {
      _apply(
        viewId,
        EmailMetadata.fromMime(result.message!, sizeBytes: result.sizeBytes),
        persist: true,
      );
    }
    _rebuild();
    notifyListeners();
    return result.message;
  }

  void select(String? viewId) {
    if (_state.activeMessageId == viewId) {
      return;
    }
    _state = _state.copyWith(
      activeMessageId: viewId,
      clearMessage: viewId == null,
    );
    _schedulePersist();
    notifyListeners();
  }

  /// Opens a message and counts it as read, which is what opening one means.
  Future<void> open(String viewId) async {
    select(viewId);
    final message = _byId[viewId];
    if (message != null && !message.metadata.read) {
      setRead([viewId], read: true);
    }
    await loadBody(viewId);
  }

  void setRead(List<String> viewIds, {required bool read}) {
    var touched = false;
    for (final id in viewIds) {
      final message = _byId[id];
      if (message == null || message.metadata.read == read) {
        continue;
      }
      _apply(id, message.metadata.copyWith(read: read), persist: true);
      touched = true;
    }
    if (touched) {
      _rebuild();
      notifyListeners();
    }
  }

  void toggleRead(String viewId) {
    final message = _byId[viewId];
    if (message != null) {
      setRead([viewId], read: !message.metadata.read);
    }
  }

  void setStarred(List<String> viewIds, {required bool starred}) {
    var touched = false;
    for (final id in viewIds) {
      final message = _byId[id];
      if (message == null || message.metadata.starred == starred) {
        continue;
      }
      _apply(id, message.metadata.copyWith(starred: starred), persist: true);
      touched = true;
    }
    if (touched) {
      _rebuild();
      notifyListeners();
    }
  }

  void toggleStarred(String viewId) {
    final message = _byId[viewId];
    if (message != null) {
      setStarred([viewId], starred: !message.metadata.starred);
    }
  }

  void setLabels(String viewId, List<String> labels) {
    final message = _byId[viewId];
    if (message == null) {
      return;
    }
    final cleaned = <String>[];
    for (final label in labels) {
      final value = label.trim();
      if (value.isNotEmpty && !cleaned.contains(value)) {
        cleaned.add(value);
      }
    }
    _apply(viewId, message.metadata.copyWith(labels: cleaned), persist: true);
    _rebuild();
    notifyListeners();
  }

  void search(String query) {
    final value = query.trim();
    if (value == _query) {
      return;
    }
    _query = value;
    _rebuild();
    notifyListeners();
  }

  void setSort(EmailSort sort) => _settings(settings.copyWith(sort: sort));

  void setFilter(EmailFilter filter) =>
      _settings(settings.copyWith(filter: filter));

  void setDensity(EmailDensity density) =>
      _settings(settings.copyWith(density: density));

  void setGrouping(EmailGrouping grouping) =>
      _settings(settings.copyWith(grouping: grouping));

  void setShowReadingPane({required bool show}) =>
      _settings(settings.copyWith(showReadingPane: show));

  /// How often the mailbox fetches on its own. Zero turns it off.
  ///
  /// This runs while the mailbox is open, not as a service behind the
  /// application: AppFlowy has no background worker, and pretending otherwise
  /// would mean promising mail that never arrives.
  void setSyncMinutes(int minutes) {
    _settings(settings.copyWith(syncMinutes: minutes));
    _restartSyncTimer();
  }

  /// Starts the scheduled fetch, and takes one straight away when the mailbox
  /// has not been reached for longer than the interval.
  void beginScheduledSync() {
    _restartSyncTimer();
    final account = _state.account;
    if (account == null || !settings.syncsOnItsOwn) {
      return;
    }
    final last = account.lastSyncAt;
    final due = last == null ||
        DateTime.now().toUtc().difference(last).inMinutes >=
            settings.syncMinutes;
    if (due) {
      unawaited(syncNow());
    }
  }

  void _restartSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (!settings.syncsOnItsOwn || _disposed) {
      return;
    }
    _syncTimer = Timer.periodic(
      Duration(minutes: settings.syncMinutes),
      (_) => unawaited(syncNow()),
    );
  }

  void setActiveSender(String? sender) {
    if (_state.activeSender == sender) {
      return;
    }
    _state = _state.copyWith(
      activeSender: sender,
      clearSender: sender == null,
    );
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void setActiveLabel(String? label) {
    if (_state.activeLabel == label) {
      return;
    }
    _state = _state.copyWith(
      activeLabel: label,
      clearLabel: label == null,
    );
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void clearNarrowing() {
    _state = _state.copyWith(clearLabel: true, clearSender: true);
    _query = '';
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persist();
  }

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    _syncTimer?.cancel();
    _persist();
    _store.clear();
    super.dispose();
  }

  void _settings(EmailSettings settings) {
    _state = _state.copyWith(settings: settings);
    _rebuild();
    _schedulePersist();
    notifyListeners();
  }

  /// Writes a new summary onto a message here first, then behind it, so the
  /// interface never waits on the backend to show a mark.
  void _apply(String viewId, EmailMetadata metadata, {bool persist = false}) {
    final message = _byId[viewId];
    if (message == null) {
      return;
    }
    final next = message.withMetadata(metadata);
    _byId[viewId] = next;
    if (persist) {
      unawaited(
        _service.updateMetadata(view: message.view, metadata: metadata),
      );
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, _persist);
  }

  void _persist() => onPersist?.call(_state.toJson());

  void _rebuild() {
    final everything = all;

    final narrowed = <EmailMessage>[];
    for (final message in everything) {
      if (!_matchesNarrowing(message)) {
        continue;
      }
      if (!_matchesFilter(message)) {
        continue;
      }
      if (!_matchesQuery(message)) {
        continue;
      }
      narrowed.add(message);
    }

    narrowed.sort(_comparator);
    _visible = List<EmailMessage>.unmodifiable(narrowed);
    _threads = List<EmailThread>.unmodifiable(buildEmailThreads(narrowed));
    _senders = _facetsOf(everything, (message) => [message.sender]);
    _labels = _facetsOf(everything, (message) => message.metadata.labels);
    _stats = _statsOf(everything);
  }

  bool _matchesNarrowing(EmailMessage message) {
    final sender = _state.activeSender;
    if (sender != null &&
        message.sender.toLowerCase() != sender.toLowerCase()) {
      return false;
    }
    final label = _state.activeLabel;
    if (label != null && !message.metadata.labels.contains(label)) {
      return false;
    }
    return true;
  }

  bool _matchesFilter(EmailMessage message) => switch (settings.filter) {
        EmailFilter.all => true,
        EmailFilter.unread => !message.read,
        EmailFilter.starred => message.starred,
        EmailFilter.attachments => message.metadata.hasAttachments,
      };

  bool _matchesQuery(EmailMessage message) {
    if (_query.isEmpty) {
      return true;
    }
    final needle = _query.toLowerCase();
    final metadata = message.metadata;
    return message.subject.toLowerCase().contains(needle) ||
        metadata.senderDisplay.toLowerCase().contains(needle) ||
        metadata.fromAddress.toLowerCase().contains(needle) ||
        metadata.snippet.toLowerCase().contains(needle) ||
        metadata.to.any((name) => name.toLowerCase().contains(needle)) ||
        metadata.labels.any((label) => label.toLowerCase().contains(needle));
  }

  int Function(EmailMessage, EmailMessage) get _comparator =>
      switch (settings.sort) {
        EmailSort.newest => (a, b) => -compareEmailBySentAt(a, b),
        EmailSort.oldest => compareEmailBySentAt,
        EmailSort.sender => (a, b) {
            final result =
                a.sender.toLowerCase().compareTo(b.sender.toLowerCase());
            return result != 0 ? result : -compareEmailBySentAt(a, b);
          },
        EmailSort.subject => (a, b) {
            final result = normalizeEmailSubject(a.subject)
                .toLowerCase()
                .compareTo(normalizeEmailSubject(b.subject).toLowerCase());
            return result != 0 ? result : -compareEmailBySentAt(a, b);
          },
        EmailSort.size => (a, b) =>
            (b.metadata.sizeBytes ?? 0).compareTo(a.metadata.sizeBytes ?? 0),
      };

  List<EmailFacet> _facetsOf(
    List<EmailMessage> messages,
    List<String> Function(EmailMessage) valuesOf,
  ) {
    final counts = <String, int>{};
    final unread = <String, int>{};
    for (final message in messages) {
      for (final value in valuesOf(message)) {
        if (value.isEmpty) {
          continue;
        }
        counts[value] = (counts[value] ?? 0) + 1;
        if (!message.read) {
          unread[value] = (unread[value] ?? 0) + 1;
        }
      }
    }

    final facets = counts.entries
        .map(
          (entry) => EmailFacet(
            value: entry.key,
            count: entry.value,
            unread: unread[entry.key] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) {
        final result = b.count.compareTo(a.count);
        return result != 0
            ? result
            : a.value.toLowerCase().compareTo(b.value.toLowerCase());
      });
    return List<EmailFacet>.unmodifiable(facets);
  }

  EmailStats _statsOf(List<EmailMessage> messages) {
    var unread = 0;
    var starred = 0;
    var attachments = 0;
    var indexed = 0;
    var unreadable = 0;
    for (final message in messages) {
      if (!message.read) {
        unread += 1;
      }
      if (message.starred) {
        starred += 1;
      }
      if (message.metadata.hasAttachments) {
        attachments += 1;
      }
      if (message.metadata.isIndexed) {
        indexed += 1;
      }
      if (message.metadata.unreadable) {
        unreadable += 1;
      }
    }
    return EmailStats(
      total: messages.length,
      unread: unread,
      starred: starred,
      withAttachments: attachments,
      threads: buildEmailThreads(messages).length,
      indexed: indexed,
      unreadable: unreadable,
    );
  }
}
