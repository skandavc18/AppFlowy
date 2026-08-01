import 'dart:convert';

import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// How far through a saved page the reader has got.
enum BookmarkReadState {
  unread,
  reading,
  read;

  static BookmarkReadState fromValue(Object? value) {
    for (final state in BookmarkReadState.values) {
      if (state.name == value) {
        return state;
      }
    }
    return BookmarkReadState.unread;
  }
}

/// Everything a saved link knows about itself.
///
/// A bookmark is a child view of the collection carrying this envelope on top
/// of [WorkspaceItemMetadata.file], so renaming, deleting, moving, searching
/// and drag and drop all keep working through the ordinary workspace plumbing
/// while the link's own facts live here rather than in a side table.
@immutable
class BookmarkMetadata {
  const BookmarkMetadata({
    required this.url,
    this.canonicalUrl,
    this.title,
    this.description,
    this.siteName,
    this.author,
    this.imageUrl,
    this.faviconUrl,
    this.excerpt,
    this.publishedAt,
    this.addedAt,
    this.fetchedAt,
    this.wordCount,
    this.tags = const <String>[],
    this.notes = '',
    this.starred = false,
    this.readState = BookmarkReadState.unread,
    this.readProgress = 0,
    this.snapshotPath,
    this.snapshotAt,
    this.snapshotBytes,
    this.fetchFailed = false,
  });

  static const envelopeKey = 'appflowy_bookmark';
  static const currentVersion = 1;

  /// The address as saved. Always the source of truth for opening the link.
  final String url;

  /// The address the page declares for itself, when it differs from [url].
  final String? canonicalUrl;

  final String? title;
  final String? description;
  final String? siteName;
  final String? author;
  final String? imageUrl;
  final String? faviconUrl;

  /// The opening of the article, kept for previews that have no snapshot.
  final String? excerpt;

  final DateTime? publishedAt;
  final DateTime? addedAt;

  /// When the metadata was last read off the network.
  final DateTime? fetchedAt;

  final int? wordCount;
  final List<String> tags;
  final String notes;
  final bool starred;
  final BookmarkReadState readState;

  /// 0..1 through the reading view.
  final double readProgress;

  /// The directory holding the offline copy, when one was taken.
  final String? snapshotPath;
  final DateTime? snapshotAt;
  final int? snapshotBytes;

  /// Whether the last attempt to read the page failed, so the interface can
  /// say so instead of showing an empty card forever.
  final bool fetchFailed;

  bool get hasSnapshot => snapshotPath != null && snapshotPath!.isNotEmpty;

  bool get hasMetadata => title != null || description != null;

  /// The name to show, falling back through the page title to the address.
  String displayTitle(String viewName) {
    if (viewName.trim().isNotEmpty && viewName != untitledBookmarkName) {
      return viewName;
    }
    final pageTitle = title?.trim();
    if (pageTitle != null && pageTitle.isNotEmpty) {
      return pageTitle;
    }
    return bookmarkHost(url) ?? url;
  }

  /// Minutes of reading at an average pace, or null when it is not an article.
  int? get readingMinutes {
    final words = wordCount;
    if (words == null || words < 120) {
      return null;
    }
    return (words / 220).ceil();
  }

  BookmarkMetadata copyWith({
    String? url,
    String? canonicalUrl,
    String? title,
    String? description,
    String? siteName,
    String? author,
    String? imageUrl,
    String? faviconUrl,
    String? excerpt,
    DateTime? publishedAt,
    DateTime? addedAt,
    DateTime? fetchedAt,
    int? wordCount,
    List<String>? tags,
    String? notes,
    bool? starred,
    BookmarkReadState? readState,
    double? readProgress,
    String? snapshotPath,
    DateTime? snapshotAt,
    int? snapshotBytes,
    bool? fetchFailed,
    bool clearSnapshot = false,
  }) =>
      BookmarkMetadata(
        url: url ?? this.url,
        canonicalUrl: canonicalUrl ?? this.canonicalUrl,
        title: title ?? this.title,
        description: description ?? this.description,
        siteName: siteName ?? this.siteName,
        author: author ?? this.author,
        imageUrl: imageUrl ?? this.imageUrl,
        faviconUrl: faviconUrl ?? this.faviconUrl,
        excerpt: excerpt ?? this.excerpt,
        publishedAt: publishedAt ?? this.publishedAt,
        addedAt: addedAt ?? this.addedAt,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        wordCount: wordCount ?? this.wordCount,
        tags: tags ?? this.tags,
        notes: notes ?? this.notes,
        starred: starred ?? this.starred,
        readState: readState ?? this.readState,
        readProgress: readProgress ?? this.readProgress,
        snapshotPath: clearSnapshot ? null : snapshotPath ?? this.snapshotPath,
        snapshotAt: clearSnapshot ? null : snapshotAt ?? this.snapshotAt,
        snapshotBytes:
            clearSnapshot ? null : snapshotBytes ?? this.snapshotBytes,
        fetchFailed: fetchFailed ?? this.fetchFailed,
      );

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'url': url,
        if (canonicalUrl != null) 'canonical_url': canonicalUrl,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (siteName != null) 'site_name': siteName,
        if (author != null) 'author': author,
        if (imageUrl != null) 'image_url': imageUrl,
        if (faviconUrl != null) 'favicon_url': faviconUrl,
        if (excerpt != null) 'excerpt': excerpt,
        if (publishedAt != null)
          'published_at': publishedAt!.millisecondsSinceEpoch,
        if (addedAt != null) 'added_at': addedAt!.millisecondsSinceEpoch,
        if (fetchedAt != null) 'fetched_at': fetchedAt!.millisecondsSinceEpoch,
        if (wordCount != null) 'word_count': wordCount,
        if (tags.isNotEmpty) 'tags': tags,
        if (notes.isNotEmpty) 'notes': notes,
        if (starred) 'starred': true,
        if (readState != BookmarkReadState.unread) 'read_state': readState.name,
        if (readProgress > 0) 'read_progress': readProgress,
        if (snapshotPath != null) 'snapshot_path': snapshotPath,
        if (snapshotAt != null)
          'snapshot_at': snapshotAt!.millisecondsSinceEpoch,
        if (snapshotBytes != null) 'snapshot_bytes': snapshotBytes,
        if (fetchFailed) 'fetch_failed': true,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static BookmarkMetadata? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }

    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    final url = values['url'];
    if (version is! int ||
        version < 1 ||
        version > currentVersion ||
        url is! String ||
        url.isEmpty) {
      return null;
    }

    return BookmarkMetadata(
      url: url,
      canonicalUrl: _string(values['canonical_url']),
      title: _string(values['title']),
      description: _string(values['description']),
      siteName: _string(values['site_name']),
      author: _string(values['author']),
      imageUrl: _string(values['image_url']),
      faviconUrl: _string(values['favicon_url']),
      excerpt: _string(values['excerpt']),
      publishedAt: _date(values['published_at']),
      addedAt: _date(values['added_at']),
      fetchedAt: _date(values['fetched_at']),
      wordCount:
          values['word_count'] is int ? values['word_count'] as int : null,
      tags: _tags(values['tags']),
      notes: _string(values['notes']) ?? '',
      starred: values['starred'] == true,
      readState: BookmarkReadState.fromValue(values['read_state']),
      readProgress: switch (values['read_progress']) {
        final num value => value.toDouble().clamp(0.0, 1.0),
        _ => 0.0,
      },
      snapshotPath: _string(values['snapshot_path']),
      snapshotAt: _date(values['snapshot_at']),
      snapshotBytes: values['snapshot_bytes'] is int
          ? values['snapshot_bytes'] as int
          : null,
      fetchFailed: values['fetch_failed'] == true,
    );
  }

  /// The `extra` payload of a brand new bookmark: a workspace file that also
  /// declares itself a saved link.
  static String newExtra(String url, {DateTime? addedAt}) =>
      BookmarkMetadata(url: url, addedAt: addedAt ?? DateTime.now())
          .mergeIntoExtra(
        const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          mimeType: bookmarkMimeType,
        ).mergeIntoExtra(''),
      );

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _date(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  static List<String> _tags(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    final tags = <String>[];
    for (final entry in value) {
      final tag = normalizeBookmarkTag(entry is String ? entry : '');
      if (tag != null && !tags.contains(tag)) {
        tags.add(tag);
      }
    }
    return tags;
  }
}

/// The media type a saved link is stored as.
const bookmarkMimeType = 'text/uri-list';

/// The name a bookmark carries until its page names itself.
const untitledBookmarkName = 'Untitled bookmark';

extension BookmarkViewExtension on ViewPB {
  BookmarkMetadata? get bookmark => BookmarkMetadata.fromExtra(extra);

  bool get isBookmark => bookmark != null;
}

/// A saved link paired with the view it lives in.
@immutable
class BookmarkEntry {
  const BookmarkEntry({required this.view, required this.metadata});

  final ViewPB view;
  final BookmarkMetadata metadata;

  String get id => view.id;
  String get url => metadata.url;
  String get title => metadata.displayTitle(view.name);
  String? get host => bookmarkHost(metadata.url);

  /// The moment the bookmark belongs at on a timeline: when the page was
  /// published if it says, otherwise when it was saved.
  DateTime get timelineDate =>
      metadata.publishedAt ?? metadata.addedAt ?? DateTime.now();

  DateTime get savedDate => metadata.addedAt ?? DateTime.now();

  /// The text a search runs against.
  String get searchText => [
        view.name,
        metadata.title,
        metadata.description,
        metadata.siteName,
        metadata.author,
        metadata.url,
        metadata.notes,
        ...metadata.tags,
      ].whereType<String>().join(' ').toLowerCase();
}

/// Builds the entries of [views], skipping anything that is not a bookmark.
List<BookmarkEntry> bookmarkEntriesFrom(List<ViewPB> views) {
  final entries = <BookmarkEntry>[];
  for (final view in views) {
    final metadata = view.bookmark;
    if (metadata != null) {
      entries.add(BookmarkEntry(view: view, metadata: metadata));
    }
  }
  return entries;
}

/// Query parameters that identify a campaign rather than a page.
///
/// Two saves of the same article should be the same bookmark, and a tracking
/// tag is the usual reason they are not.
const _trackingParameters = <String>{
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_id',
  'utm_name',
  'utm_reader',
  'fbclid',
  'gclid',
  'dclid',
  'msclkid',
  'igshid',
  'mc_cid',
  'mc_eid',
  'ref_src',
  'ref_url',
  '_hsenc',
  '_hsmi',
  'vero_id',
  'yclid',
  'twclid',
  'si',
};

/// Turns whatever was typed or pasted into an address that can be opened.
///
/// Returns null when the text is not a web address at all.
String? normalizeBookmarkUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  // A pasted address is often wrapped in markdown or angle brackets.
  if (text.startsWith('<') && text.endsWith('>')) {
    text = text.substring(1, text.length - 1).trim();
  }
  if (!text.contains('://')) {
    if (text.startsWith('//')) {
      text = 'https:$text';
    } else if (RegExp(r'^[\w.-]+\.[a-z]{2,}(?=[/:?#]|$)', caseSensitive: false)
        .hasMatch(text)) {
      text = 'https://$text';
    } else {
      return null;
    }
  }

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }

  final parameters = <String, List<String>>{};
  uri.queryParametersAll.forEach((key, values) {
    if (!_trackingParameters.contains(key.toLowerCase())) {
      parameters[key] = values;
    }
  });

  final path = uri.path == '/' ? '' : uri.path;
  return Uri(
    scheme: scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort && uri.port != 80 && uri.port != 443 ? uri.port : null,
    path: path,
    queryParameters: parameters.isEmpty ? null : parameters,
    fragment: uri.fragment.isEmpty ? null : uri.fragment,
  ).toString();
}

/// The site a link belongs to, without the `www.` nobody reads.
String? bookmarkHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) {
    return null;
  }
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// The address as it should be shown: host plus a shortened path.
String bookmarkDisplayUrl(String url, {int maxLength = 64}) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return url;
  }
  final host = bookmarkHost(url) ?? uri.host;
  final path = uri.path == '/' ? '' : uri.path;
  final text = '$host$path';
  return text.length <= maxLength
      ? text
      : '${text.substring(0, maxLength - 1)}…';
}

/// Normalises a tag so `Design`, `design ` and `#design` are one tag.
String? normalizeBookmarkTag(String raw) {
  var tag = raw.trim().toLowerCase();
  while (tag.startsWith('#')) {
    tag = tag.substring(1).trim();
  }
  tag = tag.replaceAll(RegExp(r'\s+'), ' ');
  if (tag.isEmpty || tag.length > 32) {
    return null;
  }
  return tag;
}

/// Pulls every address out of a block of text, for pasting a list at once.
List<String> extractBookmarkUrls(String text) {
  final found = <String>[];
  final pattern = RegExp(
    r'(?:https?://|www\.)[^\s<>"'
    r"'\]\)]+",
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(text)) {
    // Trailing punctuation belongs to the sentence, not to the address.
    final candidate = match.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    final url = normalizeBookmarkUrl(candidate);
    if (url != null && !found.contains(url)) {
      found.add(url);
    }
  }
  return found;
}
