import 'dart:convert';

import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// What a collection is backed by.
///
/// This rides in `ViewPB.extra` beside the collection envelope, so a collection
/// keeps every folder behaviour it already had and simply gains an answer to
/// "where does this content come from". A collection with no source at all is
/// local, which is why every reader treats a missing envelope as
/// [CollectionSource.local].
@immutable
class CollectionSource {
  const CollectionSource({
    required this.service,
    this.connectionId = '',
    this.remoteId = '',
    this.remoteName = '',
    this.remoteUrl = '',
    this.readOnly = false,
    this.lastSyncedAt,
    this.options = const <String, dynamic>{},
  });

  static const envelopeKey = 'appflowy_collection_source';
  static const currentVersion = 1;

  /// The workspace's own content: the state every collection starts in.
  static const local = CollectionSource(service: ProviderService.local);

  final ProviderService service;

  /// Which connection answers for it. Empty for the local service.
  final String connectionId;

  /// The service's own identifier for the album, repository or folder.
  final String remoteId;

  /// What the service calls it, so the collection can show the real name even
  /// before the first read finishes.
  final String remoteName;

  /// The service's own page, for "Open in …".
  final String remoteUrl;

  /// Whether the account may only look. Set from what the service reports, and
  /// the interface hides every write when it is true.
  final bool readOnly;

  final DateTime? lastSyncedAt;

  /// Per service settings: a GitHub branch, a Drive shared-drive id, an Immich
  /// "include archived" flag.
  final Map<String, dynamic> options;

  bool get isLocal => service.isLocal;
  bool get isRemote => service.isRemote;

  ProviderServiceInfo get info => ProviderServices.of(service);

  /// A key that identifies this exact backing, for caches.
  String get cacheKey => '${service.name}:$connectionId:$remoteId';

  T? option<T>(String key) {
    final value = options[key];
    return value is T ? value : null;
  }

  CollectionSource copyWith({
    ProviderService? service,
    String? connectionId,
    String? remoteId,
    String? remoteName,
    String? remoteUrl,
    bool? readOnly,
    DateTime? lastSyncedAt,
    Map<String, dynamic>? options,
  }) =>
      CollectionSource(
        service: service ?? this.service,
        connectionId: connectionId ?? this.connectionId,
        remoteId: remoteId ?? this.remoteId,
        remoteName: remoteName ?? this.remoteName,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        readOnly: readOnly ?? this.readOnly,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        options: options ?? this.options,
      );

  CollectionSource withOption(String key, Object? value) {
    final next = Map<String, dynamic>.from(options);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return copyWith(options: next);
  }

  CollectionSource synced([DateTime? at]) =>
      copyWith(lastSyncedAt: at ?? DateTime.now());

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'service': service.name,
        if (connectionId.isNotEmpty) 'connection': connectionId,
        if (remoteId.isNotEmpty) 'remote_id': remoteId,
        if (remoteName.isNotEmpty) 'remote_name': remoteName,
        if (remoteUrl.isNotEmpty) 'remote_url': remoteUrl,
        if (readOnly) 'read_only': true,
        if (lastSyncedAt != null)
          'last_synced_at': lastSyncedAt!.millisecondsSinceEpoch,
        if (options.isNotEmpty) 'options': options,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    if (isLocal) {
      // A collection that has gone back to the workspace carries no envelope
      // at all, so nothing downstream has to know about a "none" service.
      values.remove(envelopeKey);
    } else {
      values[envelopeKey] = toJson();
    }
    return jsonEncode(values);
  }

  static CollectionSource? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }

    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return null;
    }

    final lastSyncedAt = values['last_synced_at'];
    return CollectionSource(
      service: ProviderService.fromValue(values['service']),
      connectionId: _string(values['connection']),
      remoteId: _string(values['remote_id']),
      remoteName: _string(values['remote_name']),
      remoteUrl: _string(values['remote_url']),
      readOnly: values['read_only'] == true,
      lastSyncedAt: lastSyncedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncedAt)
          : null,
      options: values['options'] is Map
          ? Map<String, dynamic>.from(values['options'] as Map)
          : const <String, dynamic>{},
    );
  }

  static String _string(Object? value) => value is String ? value : '';
}

extension CollectionSourceViewExtension on ViewPB {
  /// Where this collection's content lives. Never null: a collection with no
  /// envelope is a local one.
  CollectionSource get source =>
      CollectionSource.fromExtra(extra) ?? CollectionSource.local;

  /// Whether this collection is backed by an external service.
  bool get hasExternalSource => source.isRemote;
}
