import 'dart:io';

import 'package:flutter/widgets.dart';

enum CustomImageType {
  local,
  internal, // the images saved in self-host cloud
  external; // the images linked from network, like unsplash, https://xxx/yyy/zzz.jpg

  static CustomImageType fromIntValue(int value) {
    switch (value) {
      case 0:
        return CustomImageType.local;
      case 1:
        return CustomImageType.internal;
      case 2:
        return CustomImageType.external;
      default:
        throw UnimplementedError();
    }
  }

  int toIntValue() {
    switch (this) {
      case CustomImageType.local:
        return 0;
      case CustomImageType.internal:
        return 1;
      case CustomImageType.external:
        return 2;
    }
  }
}

class ImageBlockData {
  factory ImageBlockData.fromJson(Map<String, dynamic> json) {
    return ImageBlockData(
      url: json['url'] as String? ?? '',
      type: CustomImageType.fromIntValue(json['type'] as int),
      workspaceFileId: json['workspace_file_id'] as String?,
    );
  }

  ImageBlockData({
    required this.url,
    required this.type,
    this.workspaceFileId,
  });

  final String url;
  final CustomImageType type;
  final String? workspaceFileId;

  bool get isLocal => type == CustomImageType.local;
  bool get isNotInternal => type != CustomImageType.internal;

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'type': type.toIntValue(),
      if (workspaceFileId != null) 'workspace_file_id': workspaceFileId,
    };
  }

  ImageProvider toImageProvider() {
    switch (type) {
      case CustomImageType.internal:
      case CustomImageType.external:
        return NetworkImage(url);
      case CustomImageType.local:
        return FileImage(File(url));
    }
  }
}
