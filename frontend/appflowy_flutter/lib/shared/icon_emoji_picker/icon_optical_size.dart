import 'package:flutter/widgets.dart';

/// Opt-in presentation roles, never applied to cells in the icon picker.
enum IconOpticalRole { sidebar, header }

/// Separates the painted artwork from its stable layout/hit-test slot.
/// Colorful identities need more optical presence than an outlined UI glyph.
@immutable
class IconOpticalSize {
  const IconOpticalSize._(this.slotSize, this.artworkSize);

  factory IconOpticalSize.resolve({
    required IconOpticalRole role,
    required double baseSize,
    bool colorful = true,
  }) {
    assert(baseSize.isFinite && baseSize >= 0);
    final (base, optical, slot) = switch (role) {
      IconOpticalRole.sidebar => (18.0, 22.0, 24.0),
      IconOpticalRole.header => (56.0, 64.0, 66.0),
    };
    return IconOpticalSize._(
      baseSize * slot / base,
      colorful ? baseSize * optical / base : baseSize,
    );
  }

  final double slotSize;
  final double artworkSize;

  EdgeInsets get padding => EdgeInsets.all((slotSize - artworkSize) / 2);
}

/// Builds at the *actual* optical size, not an overflowing paint transform.
/// Hosts should reserve [IconOpticalSize.slotSize] (24 sidebar / 66 header at
/// their default base sizes). A smaller incoming constraint scales the entire
/// padded frame down, never crops its artwork or expands a row's hit target.
class OpticalIconFrame extends StatelessWidget {
  const OpticalIconFrame({
    super.key,
    required this.role,
    required this.baseSize,
    required this.colorful,
    required this.builder,
  });

  final IconOpticalRole role;
  final double baseSize;
  final bool colorful;
  final Widget Function(double artworkSize) builder;

  @override
  Widget build(BuildContext context) {
    final sizes = IconOpticalSize.resolve(
      role: role,
      baseSize: baseSize,
      colorful: colorful,
    );
    return SizedBox.square(
      dimension: sizes.slotSize,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox.square(
          dimension: sizes.slotSize,
          child: Padding(
            padding: sizes.padding,
            // FlowySvg/FlowyText normally follow text scaling. Identity slots
            // are geometry, not text; keep magnified labels from clipping art.
            child: MediaQuery.withNoTextScaling(
              child: builder(sizes.artworkSize),
            ),
          ),
        ),
      ),
    );
  }
}
