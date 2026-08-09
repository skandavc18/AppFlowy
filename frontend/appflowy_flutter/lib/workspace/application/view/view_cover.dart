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
    if (value.startsWith(natureCoverPrefix)) {
      final number = value.substring(natureCoverPrefix.length);
      return 'assets/images/built_in_cover_images/'
          'nature_cover_image_$number.png';
    }
    return 'assets/images/built_in_cover_images/m_cover_image_$value.png';
  }
}

/// How many pictures each built-in set holds.
const int builtInCoverCount = 6;

/// What marks a value as belonging to the nature set.
///
/// The abstract set was here first and its covers are stored as bare numbers,
/// so the newer pictures are prefixed rather than renumbered — a page somebody
/// already gave a cover keeps the one they chose.
const String natureCoverPrefix = 'n';

/// The photographs of places, offered first because most pages are writing
/// rather than artwork.
List<String> get natureCoverValues =>
    List.generate(builtInCoverCount, (i) => '$natureCoverPrefix${i + 1}');

/// The original set, kept so nothing that already wears one loses it.
List<String> get abstractCoverValues =>
    List.generate(builtInCoverCount, (i) => '${i + 1}');

/// Every built-in cover, in the order a picker should show them.
List<String> get builtInCoverValues => [
      ...natureCoverValues,
      ...abstractCoverValues,
    ];

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
