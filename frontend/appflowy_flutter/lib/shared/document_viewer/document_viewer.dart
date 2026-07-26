/// The shared document viewer chrome.
///
/// Every document type — Markdown, HTML, PDF, images, code, video — is mounted
/// inside the same viewport. Renderers keep sole responsibility for drawing
/// the document; this library only supplies the surface around it.
library;

export 'document_scroll.dart';
export 'document_viewport.dart';
export 'document_viewport_style.dart';
