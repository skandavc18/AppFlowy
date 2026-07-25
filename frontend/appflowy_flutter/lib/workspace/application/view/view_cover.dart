import 'package:collection/collection.dart';

enum PageStyleCoverImageType {
  none,
  pureColor,
  gradientColor,
  builtInImage,
  customImage,
  localImage,
  unsplashImage;

  @override
  String toString() {
    return switch (this) {
      PageStyleCoverImageType.none => 'none',
      PageStyleCoverImageType.pureColor => 'color',
      PageStyleCoverImageType.gradientColor => 'gradient',
      PageStyleCoverImageType.builtInImage => 'built_in',
      PageStyleCoverImageType.customImage => 'custom',
      PageStyleCoverImageType.localImage => 'local',
      PageStyleCoverImageType.unsplashImage => 'unsplash',
    };
  }

  static PageStyleCoverImageType fromString(String? value) {
    return PageStyleCoverImageType.values.firstWhereOrNull(
          (type) => type.toString() == value,
        ) ??
        PageStyleCoverImageType.none;
  }

  static String builtInImagePath(String value) {
    return 'assets/images/built_in_cover_images/m_cover_image_$value.png';
  }
}

class PageStyleCover {
  const PageStyleCover({
    required this.type,
    required this.value,
  });

  const PageStyleCover.none()
      : type = PageStyleCoverImageType.none,
        value = '';

  final PageStyleCoverImageType type;
  final String value;

  bool get isPresets => isPureColor || isGradient || isBuiltInImage;
  bool get isPhoto => isCustomImage || isLocalImage || isUnsplashImage;

  bool get isNone => type == PageStyleCoverImageType.none;
  bool get isPureColor => type == PageStyleCoverImageType.pureColor;
  bool get isGradient => type == PageStyleCoverImageType.gradientColor;
  bool get isBuiltInImage => type == PageStyleCoverImageType.builtInImage;
  bool get isCustomImage => type == PageStyleCoverImageType.customImage;
  bool get isUnsplashImage => type == PageStyleCoverImageType.unsplashImage;
  bool get isLocalImage => type == PageStyleCoverImageType.localImage;

  @override
  bool operator ==(Object other) {
    return other is PageStyleCover &&
        type == other.type &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(type, value);
}
