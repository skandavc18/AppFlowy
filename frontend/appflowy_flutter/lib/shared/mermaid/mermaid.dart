/// A native Mermaid renderer.
///
/// Source is read, laid out and painted entirely in Dart — there is no web
/// view and no JavaScript engine — so a diagram wears the application's own
/// colours, exports as SVG or PNG from the same scene it draws, and costs one
/// repaint rather than a browser.
library;

export 'mermaid_export.dart';
export 'mermaid_layout.dart';
export 'mermaid_model.dart';
export 'mermaid_painter.dart';
export 'mermaid_parser.dart';
export 'mermaid_scene.dart';
export 'mermaid_theme.dart';
export 'mermaid_view.dart';
