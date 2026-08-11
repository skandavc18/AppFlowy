import 'dart:async';

import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/row/cell_menu.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:styled_widget/styled_widget.dart';

import '../../../grid/presentation/layout/sizes.dart';
import '../../../grid/presentation/widgets/row/row.dart';
import '../../cell/editable_cell_builder.dart';
import '../accessory/cell_accessory.dart';
import '../accessory/cell_shortcuts.dart';

class CellContainer extends StatelessWidget {
  const CellContainer({
    super.key,
    required this.child,
    required this.width,
    required this.isPrimary,
    this.accessoryBuilder,
    this.viewId,
    this.fieldId,
    this.rowId,
  });

  final EditableCellWidget child;
  final AccessoryBuilder? accessoryBuilder;
  final double width;
  final bool isPrimary;

  /// Named so the cell can be laid out the way the column asked for, and so a
  /// right click can reach this one cell's settings. Absent on surfaces that
  /// have no column of their own.
  final String? viewId;
  final String? fieldId;
  final String? rowId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: child.cellContainerNotifier,
      child: Selector<CellContainerNotifier, bool>(
        selector: (context, notifier) => notifier.isFocus,
        builder: (providerContext, isFocus, _) {
          Widget container = _aligned(GridCellShortcuts(child: child));

          if (accessoryBuilder != null) {
            final accessories = accessoryBuilder!.call(
              GridCellAccessoryBuildContext(
                anchorContext: context,
                isCellEditing: isFocus,
              ),
            );

            if (accessories.isNotEmpty) {
              container = _GridCellEnterRegion(
                accessories: accessories,
                isPrimary: isPrimary,
                child: container,
              );
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!isFocus) {
                child.requestFocus.notify();
              }
            },
            child: Listener(
              onPointerDown: (event) => _openMenu(providerContext, event),
              child: Container(
                constraints: BoxConstraints(maxWidth: width, minHeight: 32),
                decoration: _makeBoxDecoration(context, isFocus),
                child: container,
              ),
            ),
          );
        },
      ),
    );
  }

  /// A Listener, not a gesture: a grid cell sits inside a scrollable that
  /// claims drags, and a right click must not have to win that arena.
  void _openMenu(BuildContext context, PointerDownEvent event) {
    final view = viewId;
    final field = fieldId;
    final row = rowId;
    if (view == null || field == null || row == null) {
      return;
    }
    if (event.buttons & kSecondaryMouseButton == 0) {
      return;
    }
    unawaited(
      showCellStyleMenu(
        context: context,
        globalPosition: event.position,
        viewId: view,
        fieldId: field,
        rowId: row,
      ),
    );
  }

  /// Centred is what a cell has always been; an explicit choice overrides it.
  Widget _aligned(Widget content) {
    final view = viewId;
    final field = fieldId;
    if (view == null || field == null) {
      return Center(child: content);
    }
    return ValueListenableBuilder<PropertyStyles>(
      valueListenable: PropertyStyleRegistry.instance.listenable(view),
      builder: (context, styles, child) => Align(
        alignment: styles[field]?.align?.alignment ?? Alignment.center,
        child: child,
      ),
      child: content,
    );
  }

  BoxDecoration _makeBoxDecoration(BuildContext context, bool isFocus) {
    if (isFocus) {
      final borderSide = BorderSide(
        color: Theme.of(context).colorScheme.primary,
      );

      return BoxDecoration(border: Border.fromBorderSide(borderSide));
    }

    final borderSide =
        BorderSide(color: AFThemeExtension.of(context).borderColor);
    return BoxDecoration(
      border: Border(right: borderSide, bottom: borderSide),
    );
  }
}

class _GridCellEnterRegion extends StatelessWidget {
  const _GridCellEnterRegion({
    required this.child,
    required this.accessories,
    required this.isPrimary,
  });

  final Widget child;
  final List<GridCellAccessoryBuilder> accessories;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Selector2<RegionStateNotifier, CellContainerNotifier, bool>(
      selector: (context, regionNotifier, cellNotifier) =>
          !cellNotifier.isFocus &&
          (cellNotifier.isHover || regionNotifier.onEnter && isPrimary),
      builder: (context, showAccessory, _) {
        final List<Widget> children = [child];

        if (showAccessory) {
          children.add(
            CellAccessoryContainer(accessories: accessories).positioned(
              right: GridSize.cellContentInsets.right,
            ),
          );
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (p) =>
              CellContainerNotifier.of(context, listen: false).isHover = true,
          onExit: (p) =>
              CellContainerNotifier.of(context, listen: false).isHover = false,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: children,
          ),
        );
      },
    );
  }
}

class CellContainerNotifier extends ChangeNotifier {
  bool _isFocus = false;
  bool _onEnter = false;

  set isFocus(bool value) {
    if (_isFocus != value) {
      _isFocus = value;
      notifyListeners();
    }
  }

  set isHover(bool value) {
    if (_onEnter != value) {
      _onEnter = value;
      notifyListeners();
    }
  }

  bool get isFocus => _isFocus;

  bool get isHover => _onEnter;

  static CellContainerNotifier of(BuildContext context, {bool listen = true}) {
    return Provider.of<CellContainerNotifier>(context, listen: listen);
  }
}
