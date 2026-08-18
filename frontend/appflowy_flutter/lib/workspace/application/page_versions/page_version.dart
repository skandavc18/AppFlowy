import 'dart:convert';

import 'package:appflowy/workspace/application/page_versions/page_version_content.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Why a version was kept.
///
/// The kind is what decides whether a version may be swept away: a copy the
/// application took by itself is housekeeping, a copy somebody asked for is
/// their own record and is never discarded behind their back.
enum PageVersionKind {
  /// Taken by the application after the writing settled.
  automatic,

  /// Asked for by name.
  manual,

  /// Taken just before a restore, so going back is always possible.
  restorePoint;

  bool get isKeptForever => this != PageVersionKind.automatic;

  static PageVersionKind fromName(Object? value) => PageVersionKind.values
      .firstWhere((kind) => kind.name == value, orElse: () => automatic);
}

/// One remembered state of a page.
///
/// The record is only the description; the page itself is a separate file, so
/// a list of a hundred versions can be drawn without reading a hundred
/// documents.
@immutable
class PageVersion {
  const PageVersion({
    required this.id,
    required this.viewId,
    required this.createdAt,
    required this.kind,
    required this.contentHash,
    this.shape = PageVersionShape.document,
    this.name = '',
    this.pageName = '',
    this.blockCount = 0,
    this.wordCount = 0,
    this.characterCount = 0,
    this.bytes = 0,
    this.excerpt = '',
  });

  factory PageVersion.fromJson(Map<String, Object?> values) {
    final createdAt = values['created_at'];
    return PageVersion(
      id: values['id'] as String? ?? '',
      viewId: values['view_id'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAt is int ? createdAt : 0,
        isUtc: true,
      ),
      kind: PageVersionKind.fromName(values['kind']),
      contentHash: values['hash'] as String? ?? '',
      shape: PageVersionShape.fromName(values['shape'] ?? 'document'),
      name: values['name'] as String? ?? '',
      pageName: values['page_name'] as String? ?? '',
      blockCount: _asInt(values['blocks']),
      wordCount: _asInt(values['words']),
      characterCount: _asInt(values['characters']),
      bytes: _asInt(values['bytes']),
      excerpt: values['excerpt'] as String? ?? '',
    );
  }

  final String id;
  final String viewId;

  /// Always held in UTC — a version list read in another time zone must not
  /// reorder itself.
  final DateTime createdAt;
  final PageVersionKind kind;

  /// What this version holds — a page, a file, a folder, a table.
  final PageVersionShape shape;

  /// What the page said, reduced to one short string. Two versions with the
  /// same hash are the same page, which is how an idle document avoids
  /// collecting identical copies.
  final String contentHash;

  /// What somebody called this version, if anything.
  final String name;

  /// What the page was called when the version was taken.
  final String pageName;

  final int blockCount;
  final int wordCount;
  final int characterCount;
  final int bytes;

  /// The opening words, so a row reads as something before its thumbnail has
  /// been drawn.
  final String excerpt;

  bool get isKeptForever => kind.isKeptForever;

  PageVersion copyWith({String? name, PageVersionKind? kind}) => PageVersion(
        id: id,
        viewId: viewId,
        createdAt: createdAt,
        kind: kind ?? this.kind,
        contentHash: contentHash,
        shape: shape,
        name: name ?? this.name,
        pageName: pageName,
        blockCount: blockCount,
        wordCount: wordCount,
        characterCount: characterCount,
        bytes: bytes,
        excerpt: excerpt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'view_id': viewId,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'kind': kind.name,
        'hash': contentHash,
        'shape': shape.name,
        if (name.isNotEmpty) 'name': name,
        if (pageName.isNotEmpty) 'page_name': pageName,
        'blocks': blockCount,
        'words': wordCount,
        'characters': characterCount,
        'bytes': bytes,
        if (excerpt.isNotEmpty) 'excerpt': excerpt,
      };

  @override
  bool operator ==(Object other) =>
      other is PageVersion &&
      other.id == id &&
      other.viewId == viewId &&
      other.createdAt == createdAt &&
      other.kind == kind &&
      other.shape == shape &&
      other.contentHash == contentHash &&
      other.name == name;

  @override
  int get hashCode =>
      Object.hash(id, viewId, createdAt, kind, shape, contentHash, name);
}

int _asInt(Object? value) => value is int ? value : 0;

/// What a stored document says about itself.
///
/// Counting is done once, when the version is written, because a rail of
/// versions must not re-read every document to draw a row.
@immutable
class PageVersionSummary {
  const PageVersionSummary({
    required this.blockCount,
    required this.wordCount,
    required this.characterCount,
    required this.excerpt,
  });

  final int blockCount;
  final int wordCount;
  final int characterCount;
  final String excerpt;
}

/// A short, stable fingerprint of a page.
///
/// It is deliberately not a cryptographic digest — nothing is trusted on the
/// strength of it, it only answers "is this the same page as last time".
String pageContentFingerprint(Object? content) {
  final text = content is String ? content : jsonEncode(content);
  // FNV-1a, 64 bit, kept in two 32-bit halves so the web target agrees with
  // the desktop one.
  var hi = 0x811c9dc5;
  var lo = 0x9dc5811c;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    hi = ((hi ^ code) * 0x01000193) & 0xffffffff;
    lo = ((lo ^ (code >> 8)) * 0x01000193) & 0xffffffff;
  }
  return '${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}

/// How long the versions of one page are kept.
///
/// The whole policy is a value so it can be reasoned about — and tested —
/// without a disk, a clock or a settings screen.
@immutable
class PageVersionPolicy {
  const PageVersionPolicy({
    this.captureAutomatically = true,
    this.captureOnOpen = true,
    this.captureOnClose = true,
    this.keepEveryVersion = false,
    this.maximumCopies = defaultMaximumCopies,
    this.retainedDays = defaultRetainedDays,
    this.quietPeriod = defaultQuietPeriod,
    this.minimumSpacing = defaultMinimumSpacing,
    this.captureInterval = Duration.zero,
    this.maximumPageBytes = 0,
    this.maximumTotalBytes = defaultMaximumTotalBytes,
    this.maximumFileBytes = defaultMaximumFileBytes,
    this.readLinkedCollections = false,
  });

  factory PageVersionPolicy.fromJson(Map<String, Object?> values) {
    Duration span(Object? value, Duration fallback) {
      final seconds = _asInt(value);
      return seconds > 0 ? Duration(seconds: seconds) : fallback;
    }

    return PageVersionPolicy(
      captureAutomatically: values['auto'] != false,
      captureOnOpen: values['on_open'] != false,
      captureOnClose: values['on_close'] != false,
      keepEveryVersion: values['keep_all'] == true,
      maximumCopies: _asInt(values['copies']) > 0
          ? _asInt(values['copies'])
          : defaultMaximumCopies,
      retainedDays: _asInt(values['days']),
      quietPeriod: span(values['quiet_seconds'], defaultQuietPeriod),
      minimumSpacing: Duration(seconds: _asInt(values['spacing_seconds'])),
      captureInterval: Duration(seconds: _asInt(values['interval_seconds'])),
      maximumPageBytes: _asInt(values['page_bytes']),
      maximumTotalBytes: values.containsKey('total_bytes')
          ? _asInt(values['total_bytes'])
          : defaultMaximumTotalBytes,
      maximumFileBytes: values.containsKey('file_bytes')
          ? _asInt(values['file_bytes'])
          : defaultMaximumFileBytes,
      readLinkedCollections: values['read_linked'] == true,
    );
  }

  static const defaultMaximumCopies = 30;
  static const defaultRetainedDays = 30;
  static const defaultQuietPeriod = Duration(seconds: 90);
  static const defaultMinimumSpacing = Duration(minutes: 5);
  static const int megabyte = 1024 * 1024;
  static const defaultMaximumTotalBytes = 512 * megabyte;
  static const defaultMaximumFileBytes = 24 * megabyte;

  /// The counts offered in settings. 0 is spelled "keep every one" there.
  static const copyChoices = <int>[5, 10, 20, 30, 50, 100, 250];

  /// The retention windows offered in settings. 0 means "for ever".
  static const dayChoices = <int>[1, 7, 14, 30, 90, 180, 365, 0];

  /// How long the writing must be still before a version is taken.
  static const quietChoices = <Duration>[
    Duration(seconds: 30),
    Duration(seconds: 90),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// The least time between two automatic versions.
  static const spacingChoices = <Duration>[
    Duration.zero,
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(days: 1),
  ];

  /// How often a copy is taken of something that is open, whether or not it
  /// has settled. Zero means only the quiet period decides.
  static const intervalChoices = <Duration>[
    Duration.zero,
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 4),
  ];

  /// How much room one object's history may take. 0 is no limit of its own.
  static const pageByteChoices = <int>[
    0,
    2 * megabyte,
    10 * megabyte,
    50 * megabyte,
    200 * megabyte,
  ];

  /// How much room the whole history may take. 0 is no limit.
  static const totalByteChoices = <int>[
    0,
    128 * megabyte,
    512 * megabyte,
    1024 * megabyte,
    4096 * megabyte,
  ];

  /// The largest workspace file that is copied into the history at all.
  ///
  /// [anySize] keeps a copy whatever it weighs; 0 keeps none.
  static const fileByteChoices = <int>[
    0,
    megabyte,
    8 * megabyte,
    24 * megabyte,
    128 * megabyte,
    512 * megabyte,
    1024 * megabyte,
    4096 * megabyte,
    16384 * megabyte,
    anySize,
  ];

  /// Stands for no ceiling at all.
  static const int anySize = -1;

  /// Whether the application keeps copies of its own accord.
  final bool captureAutomatically;

  /// Whether opening something is worth a copy of what it was.
  final bool captureOnOpen;

  /// Whether closing something is worth a copy of what it became. This is the
  /// one that catches a file or a table, which change without the page itself
  /// saying anything.
  final bool captureOnClose;

  /// Nothing is ever swept away.
  final bool keepEveryVersion;

  /// How many automatic copies of one object survive.
  final int maximumCopies;

  /// How old an automatic copy may get. 0 means age is no reason to discard.
  final int retainedDays;

  /// How long the writing must go untouched before a copy is taken.
  final Duration quietPeriod;

  /// The least time between two automatic copies, so a long working session
  /// does not fill the list with near-identical states.
  final Duration minimumSpacing;

  /// A copy taken on a clock while something is open, for work that never
  /// pauses long enough to settle. Zero turns it off.
  final Duration captureInterval;

  /// How much room one object's history may take before its oldest automatic
  /// copies are swept. 0 means only the count and the age decide.
  final int maximumPageBytes;

  /// How much room the whole history may take. 0 means no limit.
  final int maximumTotalBytes;

  /// The largest workspace file copied into the history. 0 means files are
  /// never copied — their history is then only what the view says about
  /// itself.
  final int maximumFileBytes;

  /// Whether a collection linked to Google Drive, GitHub or another service is
  /// asked what it holds when a version is taken.
  ///
  /// Off by default: it means reaching out over somebody's network on a timer,
  /// for content that already lives somewhere with a history of its own.
  final bool readLinkedCollections;

  bool get discardsAnything => !keepEveryVersion;

  bool get capturesPeriodically =>
      captureAutomatically && captureInterval > Duration.zero;

  PageVersionPolicy copyWith({
    bool? captureAutomatically,
    bool? captureOnOpen,
    bool? captureOnClose,
    bool? keepEveryVersion,
    int? maximumCopies,
    int? retainedDays,
    Duration? quietPeriod,
    Duration? minimumSpacing,
    Duration? captureInterval,
    int? maximumPageBytes,
    int? maximumTotalBytes,
    int? maximumFileBytes,
    bool? readLinkedCollections,
  }) =>
      PageVersionPolicy(
        captureAutomatically: captureAutomatically ?? this.captureAutomatically,
        captureOnOpen: captureOnOpen ?? this.captureOnOpen,
        captureOnClose: captureOnClose ?? this.captureOnClose,
        keepEveryVersion: keepEveryVersion ?? this.keepEveryVersion,
        maximumCopies: maximumCopies ?? this.maximumCopies,
        retainedDays: retainedDays ?? this.retainedDays,
        quietPeriod: quietPeriod ?? this.quietPeriod,
        minimumSpacing: minimumSpacing ?? this.minimumSpacing,
        captureInterval: captureInterval ?? this.captureInterval,
        maximumPageBytes: maximumPageBytes ?? this.maximumPageBytes,
        maximumTotalBytes: maximumTotalBytes ?? this.maximumTotalBytes,
        maximumFileBytes: maximumFileBytes ?? this.maximumFileBytes,
        readLinkedCollections:
            readLinkedCollections ?? this.readLinkedCollections,
      );

  Map<String, Object?> toJson() => {
        'auto': captureAutomatically,
        'on_open': captureOnOpen,
        'on_close': captureOnClose,
        'keep_all': keepEveryVersion,
        'copies': maximumCopies,
        'days': retainedDays,
        'quiet_seconds': quietPeriod.inSeconds,
        'spacing_seconds': minimumSpacing.inSeconds,
        'interval_seconds': captureInterval.inSeconds,
        'page_bytes': maximumPageBytes,
        'total_bytes': maximumTotalBytes,
        'file_bytes': maximumFileBytes,
        'read_linked': readLinkedCollections,
      };

  @override
  bool operator ==(Object other) =>
      other is PageVersionPolicy &&
      other.captureAutomatically == captureAutomatically &&
      other.captureOnOpen == captureOnOpen &&
      other.captureOnClose == captureOnClose &&
      other.keepEveryVersion == keepEveryVersion &&
      other.maximumCopies == maximumCopies &&
      other.retainedDays == retainedDays &&
      other.quietPeriod == quietPeriod &&
      other.minimumSpacing == minimumSpacing &&
      other.captureInterval == captureInterval &&
      other.maximumPageBytes == maximumPageBytes &&
      other.maximumTotalBytes == maximumTotalBytes &&
      other.maximumFileBytes == maximumFileBytes &&
      other.readLinkedCollections == readLinkedCollections;

  @override
  int get hashCode => Object.hash(
        captureAutomatically,
        captureOnOpen,
        captureOnClose,
        keepEveryVersion,
        maximumCopies,
        retainedDays,
        quietPeriod,
        minimumSpacing,
        captureInterval,
        maximumPageBytes,
        maximumTotalBytes,
        maximumFileBytes,
        readLinkedCollections,
      );
}

/// The versions a policy would sweep away, newest kept first.
///
/// PURE, and the one place the rules live: a version somebody named or asked
/// for is never returned, the newest automatic copy is never returned (an
/// object always keeps at least its last remembered state), and age, count and
/// room are each only a reason to discard once a limit has been chosen.
List<PageVersion> expiredPageVersions(
  Iterable<PageVersion> versions,
  PageVersionPolicy policy, {
  required DateTime now,
}) {
  if (policy.keepEveryVersion) {
    return const [];
  }

  final ordered = sortPageVersions(versions);
  final expired = <PageVersion>[];
  var kept = 0;
  var room = 0;

  for (final version in ordered) {
    if (version.isKeptForever) {
      // It still takes room, so it counts against the budget even though it
      // can never be the thing that is swept.
      room += version.bytes;
      continue;
    }
    kept++;
    if (kept == 1) {
      // The most recent automatic copy is what "undo my afternoon" means.
      room += version.bytes;
      continue;
    }
    if (policy.maximumCopies > 0 && kept > policy.maximumCopies) {
      expired.add(version);
      continue;
    }
    if (policy.retainedDays > 0) {
      final age = now.toUtc().difference(version.createdAt.toUtc());
      if (age > Duration(days: policy.retainedDays)) {
        expired.add(version);
        continue;
      }
    }
    if (policy.maximumPageBytes > 0 &&
        room + version.bytes > policy.maximumPageBytes) {
      expired.add(version);
      continue;
    }
    room += version.bytes;
  }

  return expired;
}

/// Newest first, with a stable tie break so two versions written in the same
/// millisecond do not swap places between reads.
List<PageVersion> sortPageVersions(Iterable<PageVersion> versions) {
  final ordered = versions.toList()
    ..sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  return ordered;
}

/// Whether a fresh automatic copy is worth taking.
///
/// PURE. A page that has not changed, or that was copied a moment ago, is not
/// copied again — that is what keeps a version list readable.
bool shouldCapturePageVersion({
  required PageVersionPolicy policy,
  required String contentHash,
  required Iterable<PageVersion> existing,
  required DateTime now,
  bool manual = false,
}) {
  if (!manual && !policy.captureAutomatically) {
    return false;
  }

  final ordered = sortPageVersions(existing);
  final latest = ordered.firstOrNull;
  if (latest == null) {
    return true;
  }
  if (latest.contentHash == contentHash) {
    return false;
  }
  if (manual) {
    return true;
  }
  if (policy.minimumSpacing > Duration.zero) {
    final since = now.toUtc().difference(latest.createdAt.toUtc());
    if (since < policy.minimumSpacing) {
      return false;
    }
  }
  return true;
}
