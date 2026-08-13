import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// One file a row carries, wherever it was found.
///
/// A media cell, a page's picture and a link in a column are three different
/// things to the backend and the same thing to a reader, so they are all read
/// as this and drawn by one widget.
@immutable
class RowMediaFile {
  const RowMediaFile({
    required this.name,
    required this.url,
    required this.uploadType,
    required this.isImage,
  });

  /// A file named by a plain address, with its home worked out from the shape
  /// of the address rather than from anything recorded beside it.
  factory RowMediaFile.fromUrl(String url) {
    final trimmed = url.trim();
    final isRemote =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    return RowMediaFile(
      name: tableFileNameOf(trimmed),
      url: trimmed,
      uploadType:
          isRemote ? FileUploadTypePB.NetworkFile : FileUploadTypePB.LocalFile,
      isImage: looksLikeTableImage(trimmed),
    );
  }

  final String name;
  final String url;
  final FileUploadTypePB uploadType;
  final bool isImage;

  @override
  bool operator ==(Object other) =>
      other is RowMediaFile &&
      other.name == name &&
      other.url == url &&
      other.uploadType == uploadType &&
      other.isImage == isImage;

  @override
  int get hashCode => Object.hash(name, url, uploadType, isImage);
}

/// The name at the end of a path or a link.
String tableFileNameOf(String value) {
  final path = value.split('?').first;
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty || parts.last.isEmpty ? value : parts.last;
}

/// What a media cell actually holds.
///
/// ⚠️ A media cell reaches a table view as the file NAMES alone — that is what
/// the backend writes a media cell out as — so a picture read from the text of
/// a table can never be shown. The addresses only exist on the cell itself,
/// which is why they are fetched here, once per cell and remembered, rather
/// than guessed from the name.
class RowMediaCells {
  const RowMediaCells._();

  static final Map<String, List<RowMediaFile>> _read = {};
  static final Map<String, Future<List<RowMediaFile>>> _reading = {};

  static String _key(String viewId, String fieldId, String rowId) =>
      '$viewId|$fieldId|$rowId';

  static List<RowMediaFile>? peek({
    required String viewId,
    required String fieldId,
    required String rowId,
  }) =>
      _read[_key(viewId, fieldId, rowId)];

  static Future<List<RowMediaFile>> read({
    required String viewId,
    required String fieldId,
    required String rowId,
  }) {
    if (viewId.isEmpty || fieldId.isEmpty || rowId.isEmpty) {
      return Future.value(const []);
    }
    final key = _key(viewId, fieldId, rowId);
    final known = _read[key];
    if (known != null) {
      return Future.value(known);
    }
    return _reading[key] ??= _load(key, viewId, fieldId, rowId);
  }

  static Future<List<RowMediaFile>> _load(
    String key,
    String viewId,
    String fieldId,
    String rowId,
  ) async {
    try {
      final result = await CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: fieldId, rowId: rowId),
      );
      final files = result.fold<List<RowMediaFile>>(
        (cell) => _filesOf(cell),
        (_) => const [],
      );
      _read[key] = files;
      return files;
    } finally {
      _reading.removeWhere((waiting, _) => waiting == key);
    }
  }

  static List<RowMediaFile> _filesOf(CellPB cell) {
    if (cell.data.isEmpty) {
      return const [];
    }
    try {
      final data = MediaCellDataPB.fromBuffer(cell.data);
      return [
        for (final file in data.files)
          RowMediaFile(
            name: file.name,
            url: file.url,
            uploadType: file.uploadType,
            // A file the backend never classified is still a picture when its
            // name says so — that is how a link pasted into a media cell reads.
            isImage: file.fileType == MediaFileTypePB.Image ||
                looksLikeTableImage(file.name) ||
                looksLikeTableImage(file.url),
          ),
      ];
    } on Object {
      // A cell that cannot be read as media holds nothing this can draw.
      return const [];
    }
  }

  /// Reads the cells again the next time somebody asks for them.
  static void forget() {
    _read.clear();
  }
}

/// The current profile, which a cloud file cannot be fetched without.
class RowMediaProfile {
  const RowMediaProfile._();

  static UserProfilePB? _profile;
  static Future<UserProfilePB?>? _reading;

  static UserProfilePB? get peek => _profile;

  static Future<UserProfilePB?> read() {
    final known = _profile;
    if (known != null) {
      return Future.value(known);
    }
    return _reading ??= UserBackendService.getCurrentUserProfile().then(
      (result) => _profile = result.fold((profile) => profile, (_) => null),
    );
  }
}

/// The first picture written into a page, if there is one.
///
/// A page is walked rather than searched: a picture inside a toggle or a
/// column is still a picture the row carries.
RowMediaFile? pictureInDocument(Document document) =>
    _pictureIn(document.root.children);

RowMediaFile? _pictureIn(Iterable<Node> nodes) {
  for (final node in nodes) {
    final found = _pictureOf(node);
    if (found != null) {
      return found;
    }
    final inside = _pictureIn(node.children);
    if (inside != null) {
      return inside;
    }
  }
  return null;
}

RowMediaFile? _pictureOf(Node node) {
  switch (node.type) {
    case CustomImageBlockKeys.type:
      final url = node.attributes[CustomImageBlockKeys.url] as String? ?? '';
      if (url.trim().isEmpty) {
        return null;
      }
      return _pictureAt(
        url,
        node.attributes[CustomImageBlockKeys.imageType] as int?,
      );
    case MultiImageBlockKeys.type:
      final raw = node.attributes[MultiImageBlockKeys.images];
      for (final image in _imageList(raw)) {
        if (image.url.trim().isNotEmpty) {
          return _pictureAt(image.url, image.type.toIntValue());
        }
      }
      return null;
    case FileBlockKeys.type:
      final url = node.attributes[FileBlockKeys.url] as String? ?? '';
      final name = node.attributes[FileBlockKeys.name] as String? ?? '';
      if (!looksLikeTableImage(name) && !looksLikeTableImage(url)) {
        return null;
      }
      return RowMediaFile.fromUrl(url);
    default:
      return null;
  }
}

/// A page's image type says where it lives, in the editor's own words.
RowMediaFile _pictureAt(String url, int? imageType) {
  final type = switch (imageType) {
    0 => CustomImageType.local,
    1 => CustomImageType.internal,
    2 => CustomImageType.external,
    _ => null,
  };
  if (type == null) {
    return RowMediaFile.fromUrl(url);
  }
  return RowMediaFile(
    name: tableFileNameOf(url),
    url: url.trim(),
    uploadType: switch (type) {
      CustomImageType.local => FileUploadTypePB.LocalFile,
      CustomImageType.internal => FileUploadTypePB.CloudFile,
      CustomImageType.external => FileUploadTypePB.NetworkFile,
    },
    isImage: true,
  );
}

List<ImageBlockData> _imageList(Object? raw) {
  final values = raw is String
      ? (jsonDecode(raw) as List<dynamic>? ?? const [])
      : (raw is List ? raw : const []);
  final images = <ImageBlockData>[];
  for (final value in values) {
    if (value is! Map) {
      continue;
    }
    try {
      images.add(ImageBlockData.fromJson(Map<String, dynamic>.from(value)));
    } on Object {
      continue;
    }
  }
  return images;
}

/// Draws one file, when it is a picture worth looking at.
class RowMediaImage extends StatefulWidget {
  const RowMediaImage({
    super.key,
    required this.file,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  final RowMediaFile file;

  /// Shown while the profile a cloud file needs is still being read, and when
  /// the picture cannot be fetched at all.
  final Widget placeholder;

  final BoxFit fit;

  @override
  State<RowMediaImage> createState() => _RowMediaImageState();
}

class _RowMediaImageState extends State<RowMediaImage> {
  UserProfilePB? _profile = RowMediaProfile.peek;

  @override
  void initState() {
    super.initState();
    if (_profile == null &&
        widget.file.uploadType == FileUploadTypePB.CloudFile) {
      unawaited(
        RowMediaProfile.read().then((profile) {
          if (mounted) {
            setState(() => _profile = profile);
          }
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (file.url.trim().isEmpty) {
      return widget.placeholder;
    }
    if (file.uploadType == FileUploadTypePB.CloudFile && _profile == null) {
      return widget.placeholder;
    }
    return AFImage(
      url: file.url,
      uploadType: file.uploadType,
      userProfile: _profile,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

/// Hands its builder whatever a media cell holds.
///
/// The files are null while the cell is still being read, so a surface can
/// tell "not read yet" from "this cell is empty".
class RowMediaView extends StatefulWidget {
  const RowMediaView({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.rowId,
    required this.builder,
  });

  final String viewId;
  final String fieldId;
  final String rowId;
  final Widget Function(BuildContext context, List<RowMediaFile>? files)
      builder;

  @override
  State<RowMediaView> createState() => _RowMediaViewState();
}

class _RowMediaViewState extends State<RowMediaView> {
  List<RowMediaFile>? _files;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(RowMediaView old) {
    super.didUpdateWidget(old);
    if (old.viewId != widget.viewId ||
        old.fieldId != widget.fieldId ||
        old.rowId != widget.rowId) {
      _adopt();
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  void _adopt() {
    final request = ++_request;
    _files = RowMediaCells.peek(
      viewId: widget.viewId,
      fieldId: widget.fieldId,
      rowId: widget.rowId,
    );
    if (_files != null) {
      return;
    }
    unawaited(
      RowMediaCells.read(
        viewId: widget.viewId,
        fieldId: widget.fieldId,
        rowId: widget.rowId,
      ).then((files) {
        if (mounted && request == _request) {
          setState(() => _files = files);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _files);
}

/// Everywhere a row could be carrying a picture, in the order worth trying.
///
/// A column wins over the row's own cover, and both win over the page — what
/// somebody filed against the row says more about it than a decoration, and a
/// picture chosen deliberately says more than the first one that happens to
/// appear in the writing.
class RowPictureFinder {
  const RowPictureFinder._();

  /// The picture a row already knows about, with nothing left to fetch.
  static RowMediaFile? peek({
    required String viewId,
    required TableRowCard card,
  }) {
    for (final property in card.properties) {
      final found = _pictureOfProperty(viewId, card.rowId, property);
      if (found != null) {
        return found;
      }
    }
    final cover = card.coverUrl?.trim() ?? '';
    if (cover.isNotEmpty && looksLikeTableImage(cover)) {
      return RowMediaFile.fromUrl(cover);
    }
    final page = card.documentId.isEmpty
        ? null
        : RowPageDocument.peek(card.documentId)?.toDocument();
    return page == null ? null : pictureInDocument(page);
  }

  /// Reads whatever is still unread, then answers.
  static Future<RowMediaFile?> read({
    required String viewId,
    required TableRowCard card,
  }) async {
    for (final property in card.properties) {
      if (property.isEmpty) {
        continue;
      }
      if (property.isMedia) {
        final files = await RowMediaCells.read(
          viewId: viewId,
          fieldId: property.fieldId,
          rowId: card.rowId,
        );
        final picture = files.firstWhereOrNull((file) => file.isImage);
        if (picture != null) {
          return picture;
        }
        continue;
      }
      final found = _pictureOfProperty(viewId, card.rowId, property);
      if (found != null) {
        return found;
      }
    }

    final cover = card.coverUrl?.trim() ?? '';
    if (cover.isNotEmpty && looksLikeTableImage(cover)) {
      return RowMediaFile.fromUrl(cover);
    }

    if (card.documentId.isEmpty) {
      return null;
    }
    final data = await RowPageDocument.read(card.documentId);
    final document = data?.toDocument();
    return document == null ? null : pictureInDocument(document);
  }

  /// A picture a column names outright, needing no second read.
  static RowMediaFile? _pictureOfProperty(
    String viewId,
    String rowId,
    TableProperty property,
  ) {
    if (property.isEmpty) {
      return null;
    }
    if (property.isMedia) {
      final files = RowMediaCells.peek(
        viewId: viewId,
        fieldId: property.fieldId,
        rowId: rowId,
      );
      return files?.firstWhereOrNull((file) => file.isImage);
    }
    if (property.kind != TablePropertyKind.image) {
      return null;
    }
    final source = tablePartsOf(property.value).firstWhereOrNull(
      looksLikeTableImage,
    );
    return source == null ? null : RowMediaFile.fromUrl(source);
  }
}

/// A small picture standing for a whole row.
///
/// Nothing is drawn until a picture is actually found, so a row with none is
/// exactly as tall as it was before.
class RowThumbnail extends StatefulWidget {
  const RowThumbnail({
    super.key,
    required this.viewId,
    required this.card,
    required this.background,
    this.size = 44,
    this.radius = 8,
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final TableRowCard card;

  /// What is shown behind a picture that is still arriving.
  final Color background;

  final double size;
  final double radius;

  /// Room kept around the picture — and only around a picture, so a row with
  /// none is laid out exactly as it was before.
  final EdgeInsets padding;

  @override
  State<RowThumbnail> createState() => _RowThumbnailState();
}

class _RowThumbnailState extends State<RowThumbnail> {
  RowMediaFile? _picture;
  int _request = 0;
  int _revision = RowPageText.revision.value;

  @override
  void initState() {
    super.initState();
    RowPageText.onForget.add(_dropCells);
    RowPageText.revision.addListener(_onForgotten);
    _adopt();
  }

  @override
  void didUpdateWidget(RowThumbnail old) {
    super.didUpdateWidget(old);
    if (old.card.rowId != widget.card.rowId ||
        old.viewId != widget.viewId ||
        old.card.properties != widget.card.properties) {
      _adopt();
    }
  }

  @override
  void dispose() {
    RowPageText.revision.removeListener(_onForgotten);
    _request++;
    super.dispose();
  }

  static void _dropCells(String? documentId) => RowMediaCells.forget();

  void _onForgotten() {
    if (!mounted || _revision == RowPageText.revision.value) {
      return;
    }
    _revision = RowPageText.revision.value;
    _adopt();
  }

  void _adopt() {
    final request = ++_request;
    _picture = RowPictureFinder.peek(viewId: widget.viewId, card: widget.card);
    if (_picture != null) {
      return;
    }
    unawaited(
      RowPictureFinder.read(viewId: widget.viewId, card: widget.card)
          .then((picture) {
        if (mounted && request == _request && picture != _picture) {
          setState(() => _picture = picture);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    if (picture == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RowMediaImage(
            file: picture,
            placeholder: ColoredBox(color: widget.background),
          ),
        ),
      ),
    );
  }
}

extension _FirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
