import 'dart:math' as math;

import 'package:appflowy/shared/workspace_design.dart';
import 'package:flutter/material.dart';

const commandPalettePreviewBreakpoint = 720.0;
const commandPaletteListMaxWidth = 520.0;
const commandPaletteListWidthFactor = 0.5;

double commandPaletteListWidth(double availableWidth) => math.min(
      commandPaletteListMaxWidth,
      math.max(0.0, availableWidth) * commandPaletteListWidthFactor,
    );

EdgeInsets commandPaletteDialogInsets(Size viewport) => EdgeInsets.symmetric(
      horizontal: viewport.width < 640 ? 16 : 32,
      vertical: viewport.height < 640 ? 16 : 40,
    );

/// A wide, short window still gets a wide search surface. The keyboard only
/// reduces the available height; it must not squeeze both panes horizontally.
Size commandPaletteDialogSize(
  Size viewport, {
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final inset = commandPaletteDialogInsets(viewport);
  return Size(
    math.min(
      1120.0,
      math.max(0.0, viewport.width - viewInsets.horizontal - inset.horizontal),
    ),
    math.min(
      780.0,
      math.max(0.0, viewport.height - viewInsets.vertical - inset.vertical),
    ),
  );
}

/// One continuous preview plane, without a card inside the search dialog.
/// The header may scroll at large text sizes; the renderer stays bounded and
/// at a constant element depth through resizes.
class CommandPalettePreviewSurface extends StatelessWidget {
  const CommandPalettePreviewSurface({
    super.key,
    required this.header,
    required this.child,
  });

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: WorkspacePalette.of(context).elevatedSurface,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.45,
                ),
                child: SingleChildScrollView(
                  primary: false,
                  child: header,
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      );
}
