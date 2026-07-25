import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

enum WorkspaceItemKind {
  folder,
  file;

  static WorkspaceItemKind? fromValue(Object? value) {
    return switch (value) {
      'folder' => WorkspaceItemKind.folder,
      'file' => WorkspaceItemKind.file,
      _ => null,
    };
  }
}

enum WorkspaceFileContentKind {
  collaborativeText,
  binary;

  static WorkspaceFileContentKind? fromValue(Object? value) {
    return switch (value) {
      'collaborative_text' => WorkspaceFileContentKind.collaborativeText,
      'binary' => WorkspaceFileContentKind.binary,
      _ => null,
    };
  }

  String get value => switch (this) {
        WorkspaceFileContentKind.collaborativeText => 'collaborative_text',
        WorkspaceFileContentKind.binary => 'binary',
      };
}

@immutable
class WorkspaceItemMetadata {
  const WorkspaceItemMetadata._({
    required this.kind,
    required this.contentKind,
    required this.mimeType,
    required this.storageUrl,
    required this.size,
    required this.modifiedAt,
  });

  const WorkspaceItemMetadata.folder()
      : this._(
          kind: WorkspaceItemKind.folder,
          contentKind: null,
          mimeType: null,
          storageUrl: null,
          size: null,
          modifiedAt: null,
        );

  const WorkspaceItemMetadata.file({
    required WorkspaceFileContentKind contentKind,
    String? mimeType,
    String? storageUrl,
    int? size,
    DateTime? modifiedAt,
  }) : this._(
          kind: WorkspaceItemKind.file,
          contentKind: contentKind,
          mimeType: mimeType,
          storageUrl: storageUrl,
          size: size,
          modifiedAt: modifiedAt,
        );

  static const envelopeKey = 'appflowy_workspace_item';
  static const currentVersion = 1;

  final WorkspaceItemKind kind;
  final WorkspaceFileContentKind? contentKind;
  final String? mimeType;
  final String? storageUrl;
  final int? size;
  final DateTime? modifiedAt;

  bool get isFolder => kind == WorkspaceItemKind.folder;
  bool get isFile => kind == WorkspaceItemKind.file;
  bool get isCollaborativeText =>
      contentKind == WorkspaceFileContentKind.collaborativeText;

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'kind': kind.name,
        if (contentKind != null) 'content_kind': contentKind!.value,
        if (mimeType != null) 'mime_type': mimeType,
        if (storageUrl != null) 'storage_url': storageUrl,
        if (size != null) 'size': size,
        if (modifiedAt != null)
          'modified_at': modifiedAt!.millisecondsSinceEpoch,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static WorkspaceItemMetadata? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }

    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    final kind = WorkspaceItemKind.fromValue(values['kind']);
    if (version is! int ||
        version < 1 ||
        version > currentVersion ||
        kind == null) {
      return null;
    }

    final contentKind =
        WorkspaceFileContentKind.fromValue(values['content_kind']);
    if (kind == WorkspaceItemKind.file && contentKind == null) {
      return null;
    }

    final modifiedAtValue = values['modified_at'];
    final mimeType = values['mime_type'];
    final storageUrl = values['storage_url'];
    final size = values['size'];
    return WorkspaceItemMetadata._(
      kind: kind,
      contentKind: contentKind,
      mimeType: mimeType is String ? mimeType : null,
      storageUrl: storageUrl is String ? storageUrl : null,
      size: size is int ? size : null,
      modifiedAt: modifiedAtValue is int
          ? DateTime.fromMillisecondsSinceEpoch(modifiedAtValue)
          : null,
    );
  }
}

Map<String, dynamic> decodeViewExtra(String extra) {
  if (extra.isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final value = jsonDecode(extra);
    return value is Map ? Map<String, dynamic>.from(value) : {};
  } on FormatException {
    return <String, dynamic>{};
  }
}

extension WorkspaceItemViewExtension on ViewPB {
  WorkspaceItemMetadata? get workspaceItem =>
      WorkspaceItemMetadata.fromExtra(extra);

  bool get isWorkspaceFolder => workspaceItem?.isFolder ?? false;
  bool get isWorkspaceFile => workspaceItem?.isFile ?? false;
  bool get isWorkspaceItem => workspaceItem != null;
  bool get canContainWorkspaceItems =>
      layout == ViewLayoutPB.Document && !isWorkspaceFile;
}
