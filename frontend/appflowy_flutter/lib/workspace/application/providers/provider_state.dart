import 'package:flutter/foundation.dart';

/// Everything external content can be doing, from the reader's point of view.
///
/// These are the only states the interface ever renders. A raw API error is
/// never shown: it is classified into one of these first, so a rate limit
/// reads as "too many requests just now" rather than `HTTP 429 {"message":…}`.
enum ProviderStatus {
  /// Nothing has been asked for yet.
  idle,

  /// A first read is in flight and there is nothing to show underneath.
  loading,

  /// Content is on screen and a refresh is running behind it.
  syncing,

  /// Content is on screen and current.
  ready,

  /// The machine cannot reach the service.
  offline,

  /// The connection is there but the token has expired or been revoked.
  authExpired,

  /// The account cannot see or change this.
  permissionDenied,

  /// The album, repository or folder is gone.
  notFound,

  /// The service asked us to slow down.
  rateLimited,

  /// Something else went wrong.
  error;

  bool get isBusy => this == loading || this == syncing;

  bool get isFailure => switch (this) {
        ProviderStatus.offline ||
        ProviderStatus.authExpired ||
        ProviderStatus.permissionDenied ||
        ProviderStatus.notFound ||
        ProviderStatus.rateLimited ||
        ProviderStatus.error =>
          true,
        _ => false,
      };

  /// Whether trying again is worth offering.
  bool get isRetryable => switch (this) {
        ProviderStatus.offline ||
        ProviderStatus.rateLimited ||
        ProviderStatus.error =>
          true,
        _ => false,
      };

  /// Whether the way out is to sign in again.
  bool get needsReconnect => this == ProviderStatus.authExpired;
}

/// A failure a person can read.
///
/// [detail] is kept for the log only. Nothing in [detail] is ever rendered,
/// because a stranger's server decides what goes in it.
@immutable
class ProviderFailure implements Exception {
  const ProviderFailure(
    this.status, {
    this.detail = '',
    this.retryAfter,
  });

  /// Classifies one HTTP answer.
  ///
  /// Everything a provider talks to answers over HTTP, so this is the single
  /// place a status code becomes something the interface can render.
  factory ProviderFailure.fromStatusCode(
    int code, {
    String detail = '',
    String? retryAfterHeader,
  }) {
    final retryAfter = _parseRetryAfter(retryAfterHeader);
    return switch (code) {
      401 => ProviderFailure(ProviderStatus.authExpired, detail: detail),
      403 when retryAfter != null => ProviderFailure(
          ProviderStatus.rateLimited,
          detail: detail,
          retryAfter: retryAfter,
        ),
      403 => ProviderFailure(ProviderStatus.permissionDenied, detail: detail),
      404 || 410 => ProviderFailure(ProviderStatus.notFound, detail: detail),
      429 => ProviderFailure(
          ProviderStatus.rateLimited,
          detail: detail,
          retryAfter: retryAfter,
        ),
      _ => ProviderFailure(ProviderStatus.error, detail: 'HTTP $code $detail'),
    };
  }

  const ProviderFailure.offline([this.detail = ''])
      : status = ProviderStatus.offline,
        retryAfter = null;

  const ProviderFailure.authExpired([this.detail = ''])
      : status = ProviderStatus.authExpired,
        retryAfter = null;

  const ProviderFailure.permissionDenied([this.detail = ''])
      : status = ProviderStatus.permissionDenied,
        retryAfter = null;

  const ProviderFailure.notFound([this.detail = ''])
      : status = ProviderStatus.notFound,
        retryAfter = null;

  final ProviderStatus status;
  final String detail;
  final Duration? retryAfter;

  static Duration? _parseRetryAfter(String? header) {
    if (header == null || header.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(header.trim());
    if (seconds != null) {
      return Duration(seconds: seconds.clamp(0, 3600));
    }
    final when = DateTime.tryParse(header.trim());
    if (when == null) {
      return null;
    }
    final wait = when.difference(DateTime.now());
    return wait.isNegative ? null : wait;
  }

  @override
  String toString() => 'ProviderFailure(${status.name}: $detail)';
}

/// What a provider can be asked to do.
///
/// The interface reads this rather than guessing: an action a service will
/// refuse is never offered, so nobody discovers a permission by being told no.
@immutable
class ProviderCapabilities {
  const ProviderCapabilities({
    this.canList = true,
    this.canSearch = false,
    this.canRead = true,
    this.canCreate = false,
    this.canUpload = false,
    this.canCreateFolder = false,
    this.canRename = false,
    this.canMove = false,
    this.canDelete = false,
    this.canDownload = true,
    this.canFavourite = false,
    this.canSync = true,
    this.canWriteBack = false,
  });

  /// Everything a workspace folder can do.
  static const full = ProviderCapabilities(
    canSearch: true,
    canCreate: true,
    canUpload: true,
    canCreateFolder: true,
    canRename: true,
    canMove: true,
    canDelete: true,
    canFavourite: true,
    canWriteBack: true,
  );

  /// A service we may only look at.
  static const readOnly = ProviderCapabilities(canSearch: true);

  final bool canList;
  final bool canSearch;
  final bool canRead;
  final bool canCreate;
  final bool canUpload;
  final bool canCreateFolder;
  final bool canRename;
  final bool canMove;
  final bool canDelete;
  final bool canDownload;
  final bool canFavourite;
  final bool canSync;

  /// Whether an edit made here can be pushed back to the service.
  final bool canWriteBack;

  bool get isReadOnly =>
      !canCreate &&
      !canUpload &&
      !canCreateFolder &&
      !canRename &&
      !canMove &&
      !canDelete;

  /// Narrows every write to false, for an account the service told us has
  /// read access only.
  ProviderCapabilities readOnlyCopy() => ProviderCapabilities(
        canList: canList,
        canSearch: canSearch,
        canRead: canRead,
        canDownload: canDownload,
        canSync: canSync,
      );
}
