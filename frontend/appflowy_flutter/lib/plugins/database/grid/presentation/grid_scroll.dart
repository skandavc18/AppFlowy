import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

class GridScrollController {
  GridScrollController({
    required LinkedScrollControllerGroup scrollGroupController,
    ScrollController? verticalController,
  })  : _scrollGroupController = scrollGroupController,
        _ownsVerticalController = verticalController == null,
        verticalController = verticalController ?? ScrollController(),
        horizontalController = scrollGroupController.addAndGet();

  final LinkedScrollControllerGroup _scrollGroupController;
  final bool _ownsVerticalController;
  final ScrollController verticalController;
  final ScrollController horizontalController;

  final List<ScrollController> _linkHorizontalControllers = [];

  ScrollController linkHorizontalController() {
    final controller = _scrollGroupController.addAndGet();
    _linkHorizontalControllers.add(controller);
    return controller;
  }

  void dispose() {
    for (final controller in _linkHorizontalControllers) {
      controller.dispose();
    }
    if (_ownsVerticalController) {
      verticalController.dispose();
    }
    horizontalController.dispose();
  }
}
