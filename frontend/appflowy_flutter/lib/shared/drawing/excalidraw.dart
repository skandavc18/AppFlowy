/// The Excalidraw scene format, and a painter for it.
///
/// Editing is done by the real open-source Excalidraw component, which the
/// block starts only when somebody opens a drawing. Reading is done here: the
/// document model is the `.excalidraw` schema itself — elements, app state and
/// files, with unknown fields carried through untouched — and the painter
/// draws it natively, so a page full of drawings costs pictures rather than
/// browsers. Nothing is ever flattened on save.
library;

export 'excalidraw_export.dart';
export 'excalidraw_painter.dart';
export 'excalidraw_rough.dart';
export 'excalidraw_scene.dart';
export 'excalidraw_theme.dart';
