import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// What a chapter is made of, which decides the renderer it is read with.
enum BookChapterKind {
  page,
  markdown,
  html,
  pdf,
  text,
  code,

  /// A container inside the book — a part, a section, a set of appendices.
  part,
  unsupported;

  /// Whether the chapter is read in a flowing text column rather than in a
  /// renderer that paginates itself.
  bool get flowsAsText => switch (this) {
        BookChapterKind.page ||
        BookChapterKind.markdown ||
        BookChapterKind.html ||
        BookChapterKind.text ||
        BookChapterKind.code =>
          true,
        BookChapterKind.pdf ||
        BookChapterKind.part ||
        BookChapterKind.unsupported =>
          false,
      };

  bool get isReadable => this != BookChapterKind.unsupported;
}

/// One entry in a book, in reading order.
@immutable
class BookChapter {
  const BookChapter({
    required this.view,
    required this.kind,
    required this.index,
  });

  final ViewPB view;
  final BookChapterKind kind;

  /// Position in reading order, counting only readable entries.
  final int index;

  String get id => view.id;
  String get name => view.name;
  bool get isPart => kind == BookChapterKind.part;
}

BookChapterKind bookChapterKindOf(ViewPB view) {
  if (view.isCollection || view.isWorkspaceFolder) {
    return BookChapterKind.part;
  }
  if (!view.isWorkspaceFile) {
    return view.layout == ViewLayoutPB.Document
        ? BookChapterKind.page
        : BookChapterKind.unsupported;
  }
  return switch (filePreviewKindFromName(view.name)) {
    FilePreviewKind.markdown => BookChapterKind.markdown,
    FilePreviewKind.html => BookChapterKind.html,
    FilePreviewKind.pdf => BookChapterKind.pdf,
    FilePreviewKind.text => BookChapterKind.text,
    FilePreviewKind.code => BookChapterKind.code,
    _ => BookChapterKind.unsupported,
  };
}

/// The readable entries of [views], in the order the backend stores them.
///
/// Parts keep their place so the contents page can show the structure, but
/// they carry no reading position of their own.
List<BookChapter> bookChaptersFrom(Iterable<ViewPB> views) {
  final chapters = <BookChapter>[];
  var index = 0;
  for (final view in views) {
    final kind = bookChapterKindOf(view);
    if (!kind.isReadable) {
      continue;
    }
    chapters.add(
      BookChapter(
        view: view,
        kind: kind,
        index: kind == BookChapterKind.part ? -1 : index,
      ),
    );
    if (kind != BookChapterKind.part) {
      index += 1;
    }
  }
  return chapters;
}
