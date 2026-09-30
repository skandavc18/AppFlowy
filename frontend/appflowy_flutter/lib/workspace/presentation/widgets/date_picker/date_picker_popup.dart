import 'dart:math' as math;

import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

import 'desktop_date_picker.dart';

const _popupWidth = 260.0;

/// Opens AppFlowy's date picker, the one database date cells use, in a popup
/// below the widget that owns [context], or above it when there is no room.
///
/// Without [includeTime], choosing a day closes the popup. With it, the popup
/// stays open so the time can be typed too. Resolves with the last date the
/// picker reported, or null when nothing was chosen.
Future<DateTime?> showDatePickerPopup({
  required BuildContext context,
  DateTime? initialDate,
  bool includeTime = false,
}) async {
  final box = context.findRenderObject();
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject();
  if (box is! RenderBox ||
      !box.hasSize ||
      overlay is! RenderBox ||
      !overlay.hasSize) {
    return null;
  }
  final clock = MaterialLocalizations.of(context).timeOfDayFormat(
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final route = _DatePickerPopupRoute(
    anchor: MatrixUtils.transformRect(
      box.getTransformTo(overlay),
      Offset.zero & box.size,
    ),
    initialDate: initialDate,
    includeTime: includeTime,
    timeFormat: hourFormat(of: clock) == HourFormat.h
        ? TimeFormatPB.TwelveHour
        : TimeFormatPB.TwentyFourHour,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  );
  await navigator.push(route);
  // A typed time is submitted when its field loses focus, which happens as
  // the popup closes. Read the choice once the popup has finished closing.
  await route.completed;
  return route.chosen;
}

class _DatePickerPopupRoute extends PopupRoute<void> {
  _DatePickerPopupRoute({
    required this.anchor,
    required this.initialDate,
    required this.includeTime,
    required this.timeFormat,
    required this.themes,
    required this.barrierLabel,
  });

  final Rect anchor;
  final DateTime? initialDate;
  final bool includeTime;
  final TimeFormatPB timeFormat;
  final CapturedThemes themes;

  /// The last date the picker reported.
  DateTime? chosen;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final viewport = MediaQuery.of(context);
    return themes.wrap(
      CustomSingleChildLayout(
        delegate: _PopupPlacement(
          anchor: anchor,
          insets: EdgeInsets.fromLTRB(
            math.max(viewport.padding.left, viewport.viewInsets.left),
            math.max(viewport.padding.top, viewport.viewInsets.top),
            math.max(viewport.padding.right, viewport.viewInsets.right),
            math.max(viewport.padding.bottom, viewport.viewInsets.bottom),
          ),
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: Builder(
            builder: (context) => Material(
              type: MaterialType.transparency,
              child: Container(
                key: const ValueKey('date_picker_popup'),
                decoration: context.getPopoverDecoration(),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  primary: false,
                  child: DesktopAppFlowyDatePicker(
                    dateTime: initialDate,
                    includeTime: includeTime,
                    isRange: false,
                    dateFormat: DateFormatPB.Friendly,
                    timeFormat: timeFormat,
                    onDaySelected: (day) {
                      chosen = day;
                      if (!includeTime && isCurrent) navigator?.pop();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopupPlacement extends SingleChildLayoutDelegate {
  const _PopupPlacement({required this.anchor, required this.insets});

  final Rect anchor;
  final EdgeInsets insets;

  Rect _available(Size size) {
    final left = math.min(insets.left + 8, size.width);
    final top = math.min(insets.top + 8, size.height);
    return Rect.fromLTRB(
      left,
      top,
      math.max(left, size.width - insets.right - 8),
      math.max(top, size.height - insets.bottom - 8),
    );
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = _available(constraints.biggest);
    final width = math.min(_popupWidth, available.width);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: available.height,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final available = _available(size);
    final below = anchor.bottom + 6;
    final above = anchor.top - 6 - childSize.height;
    final lowest = math.max(available.top, available.bottom - childSize.height);
    final y = below + childSize.height <= available.bottom
        ? below
        : above >= available.top
            ? above
            : lowest;
    return Offset(
      anchor.left.clamp(
        available.left,
        math.max(available.left, available.right - childSize.width),
      ),
      y.clamp(available.top, lowest),
    );
  }

  @override
  bool shouldRelayout(_PopupPlacement oldDelegate) =>
      anchor != oldDelegate.anchor || insets != oldDelegate.insets;
}
