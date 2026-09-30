import 'package:flutter/material.dart';

/// Physical-right action gutter, independent of the text's reading direction.
/// Responsive publishers receive a finite width BEFORE any overflow viewport.
/// Natural publishers (PDF and image controls) keep their intrinsic row width.
class FileActionBand extends StatelessWidget {
  const FileActionBand({
    super.key,
    required this.builder,
    this.responsive = false,
    this.hug = false,
    this.controller,
    this.scrollKey,
    this.padding = EdgeInsets.zero,
  });

  final WidgetBuilder builder;
  final bool responsive;

  /// Sizes the band to its controls instead of the whole pane, so a host can
  /// seat it beside other content. Controls wider than the pane still scroll.
  final bool hug;
  final ScrollController? controller;
  final Key? scrollKey;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          assert(constraints.hasBoundedWidth);
          final width = constraints.maxWidth;
          if (hug) {
            final inner = (width - padding.horizontal).clamp(0.0, width);
            return SingleChildScrollView(
              key: scrollKey,
              padding: padding,
              controller: controller,
              primary: false,
              scrollDirection: Axis.horizontal,
              reverse: Directionality.of(context) == TextDirection.ltr,
              child: responsive
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: inner),
                      child: Builder(builder: builder),
                    )
                  : Builder(builder: builder),
            );
          }
          return SingleChildScrollView(
            key: scrollKey,
            padding: padding,
            controller: controller,
            primary: false,
            scrollDirection: Axis.horizontal,
            reverse: Directionality.of(context) == TextDirection.ltr,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: width),
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: 1,
                child: responsive
                    ? SizedBox(width: width, child: Builder(builder: builder))
                    : Builder(builder: builder),
              ),
            ),
          );
        },
      );
}

/// End-align every wrapped run physically right without changing text direction.
WrapAlignment fileActionRunAlignment(BuildContext context) =>
    Directionality.of(context) == TextDirection.ltr
        ? WrapAlignment.end
        : WrapAlignment.start;
