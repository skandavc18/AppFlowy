import 'package:flutter/animation.dart';

/// Desktop-first motion tokens for AppFlowy UI components.
///
/// These curves are intentionally restrained: no springs, bounce, or
/// overshoot. Motion communicates state without becoming decoration.
abstract final class AppFlowyMotion {
  static const instant = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 160);
  static const gentle = Duration(milliseconds: 180);
  static const deliberate = Duration(milliseconds: 240);

  static const standardCurve = Cubic(0.2, 0, 0, 1);
  static const enterCurve = Cubic(0.16, 1, 0.3, 1);
  static const exitCurve = Cubic(0.4, 0, 1, 1);
}
