import 'package:flutter/material.dart';

/// How a new workspace file gets its initial content.
enum WorkspaceFileCreation {
  /// AppFlowy authors a blank document for the kind.
  blank,

  /// The person picks an existing file from disk.
  imported,
}

/// The file types that can be added from the sidebar and the folder explorer.
///
/// This mirrors the file entries of the `/` slash menu so the same documents
/// can live as standalone workspace files instead of embeds inside a page.
enum WorkspaceFileKind {
  file,
  text,
  code,
  markdown,
  html,
  pdf,
  image,
  video,
  audio,
  word,
  excel,
  powerpoint;

  static WorkspaceFileKind? fromName(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'md' || 'markdown' => WorkspaceFileKind.markdown,
      'html' || 'htm' => WorkspaceFileKind.html,
      'pdf' => WorkspaceFileKind.pdf,
      'doc' || 'docx' || 'odt' || 'rtf' => WorkspaceFileKind.word,
      'xls' || 'xlsx' || 'ods' => WorkspaceFileKind.excel,
      'ppt' || 'pptx' || 'odp' => WorkspaceFileKind.powerpoint,
      _ => null,
    };
  }
}

extension WorkspaceFileKindInfo on WorkspaceFileKind {
  String get label => switch (this) {
        WorkspaceFileKind.file => 'File',
        WorkspaceFileKind.text => 'Text file',
        WorkspaceFileKind.code => 'Code file',
        WorkspaceFileKind.markdown => 'Markdown',
        WorkspaceFileKind.html => 'HTML',
        WorkspaceFileKind.pdf => 'PDF',
        WorkspaceFileKind.image => 'Image',
        WorkspaceFileKind.video => 'Video',
        WorkspaceFileKind.audio => 'Audio',
        WorkspaceFileKind.word => 'Word document',
        WorkspaceFileKind.excel => 'Excel spreadsheet',
        WorkspaceFileKind.powerpoint => 'PowerPoint presentation',
      };

  IconData get icon => switch (this) {
        WorkspaceFileKind.file => Icons.note_add_outlined,
        WorkspaceFileKind.text => Icons.description_outlined,
        WorkspaceFileKind.code => Icons.code,
        WorkspaceFileKind.markdown => Icons.article_outlined,
        WorkspaceFileKind.html => Icons.language_outlined,
        WorkspaceFileKind.pdf => Icons.picture_as_pdf_outlined,
        WorkspaceFileKind.image => Icons.image_outlined,
        WorkspaceFileKind.video => Icons.movie_outlined,
        WorkspaceFileKind.audio => Icons.audiotrack_outlined,
        WorkspaceFileKind.word => Icons.text_snippet_outlined,
        WorkspaceFileKind.excel => Icons.table_chart_outlined,
        WorkspaceFileKind.powerpoint => Icons.slideshow_outlined,
      };

  WorkspaceFileCreation get creation => switch (this) {
        WorkspaceFileKind.text ||
        WorkspaceFileKind.code ||
        WorkspaceFileKind.markdown ||
        WorkspaceFileKind.html ||
        WorkspaceFileKind.word ||
        WorkspaceFileKind.excel ||
        WorkspaceFileKind.powerpoint =>
          WorkspaceFileCreation.blank,
        WorkspaceFileKind.file ||
        WorkspaceFileKind.pdf ||
        WorkspaceFileKind.image ||
        WorkspaceFileKind.video ||
        WorkspaceFileKind.audio =>
          WorkspaceFileCreation.imported,
      };

  bool get isBlankCreatable => creation == WorkspaceFileCreation.blank;

  /// The extension, without the leading dot, used for blank documents.
  String get fileExtension => switch (this) {
        WorkspaceFileKind.file => 'txt',
        WorkspaceFileKind.text => 'txt',
        WorkspaceFileKind.code => 'py',
        WorkspaceFileKind.markdown => 'md',
        WorkspaceFileKind.html => 'html',
        WorkspaceFileKind.pdf => 'pdf',
        WorkspaceFileKind.image => 'png',
        WorkspaceFileKind.video => 'mp4',
        WorkspaceFileKind.audio => 'mp3',
        WorkspaceFileKind.word => 'docx',
        WorkspaceFileKind.excel => 'xlsx',
        WorkspaceFileKind.powerpoint => 'pptx',
      };

  String get defaultFileName => switch (this) {
        WorkspaceFileKind.text => 'Untitled.txt',
        WorkspaceFileKind.code => 'Untitled.py',
        WorkspaceFileKind.markdown => 'Untitled.md',
        WorkspaceFileKind.html => 'Untitled.html',
        WorkspaceFileKind.word => 'Untitled.docx',
        WorkspaceFileKind.excel => 'Untitled.xlsx',
        WorkspaceFileKind.powerpoint => 'Untitled.pptx',
        _ => 'Untitled.$fileExtension',
      };

  String get mimeType => switch (this) {
        WorkspaceFileKind.file => 'application/octet-stream',
        WorkspaceFileKind.text => 'text/plain',
        WorkspaceFileKind.code => 'text/plain',
        WorkspaceFileKind.markdown => 'text/markdown',
        WorkspaceFileKind.html => 'text/html',
        WorkspaceFileKind.pdf => 'application/pdf',
        WorkspaceFileKind.image => 'image/png',
        WorkspaceFileKind.video => 'video/mp4',
        WorkspaceFileKind.audio => 'audio/mpeg',
        WorkspaceFileKind.word =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        WorkspaceFileKind.excel =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        WorkspaceFileKind.powerpoint =>
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      };

  /// Extensions offered by the picker. An empty list accepts any file.
  List<String> get pickerExtensions => switch (this) {
        WorkspaceFileKind.file => const [],
        WorkspaceFileKind.text => const [
            'txt',
            'log',
            'ini',
            'cfg',
            'conf',
            'yaml',
            'yml',
            'toml',
            'xml',
            'csv',
            'tsv',
            'json',
          ],
        WorkspaceFileKind.code => const [
            'py',
            'js',
            'jsx',
            'ts',
            'tsx',
            'dart',
            'rs',
            'go',
            'java',
            'kt',
            'c',
            'h',
            'cc',
            'cpp',
            'hpp',
            'cs',
            'rb',
            'php',
            'swift',
            'sh',
            'ps1',
            'sql',
            'css',
            'scss',
            'less',
          ],
        WorkspaceFileKind.markdown => const ['md', 'markdown'],
        WorkspaceFileKind.html => const ['html', 'htm'],
        WorkspaceFileKind.pdf => const ['pdf'],
        WorkspaceFileKind.image => const [
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'bmp',
            'svg',
          ],
        WorkspaceFileKind.video => const [
            'mp4',
            'mov',
            'mkv',
            'webm',
            'avi',
            'm4v',
          ],
        WorkspaceFileKind.audio => const [
            'mp3',
            'wav',
            'm4a',
            'aac',
            'flac',
            'ogg',
          ],
        WorkspaceFileKind.word => const ['doc', 'docx', 'odt', 'rtf'],
        WorkspaceFileKind.excel => const ['xls', 'xlsx', 'ods'],
        WorkspaceFileKind.powerpoint => const ['ppt', 'pptx', 'odp'],
      };
}

/// Whether the menu entry authors a blank document or takes one from disk.
enum WorkspaceFileSource {
  create,
  upload;

  String get heading => switch (this) {
        WorkspaceFileSource.create => 'Create',
        WorkspaceFileSource.upload => 'Upload from computer',
      };
}

/// One row of the "New file" menu.
@immutable
class WorkspaceFileMenuAction {
  const WorkspaceFileMenuAction(this.kind, this.source);

  final WorkspaceFileKind kind;
  final WorkspaceFileSource source;

  String get label =>
      kind == WorkspaceFileKind.text && source == WorkspaceFileSource.create
          ? 'Blank text file'
          : kind.label;
  IconData get icon => kind.icon;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceFileMenuAction &&
      other.kind == kind &&
      other.source == source;

  @override
  int get hashCode => Object.hash(kind, source);
}

/// Every entry of the "New file" menu, in order.
///
/// Anything AppFlowy can author blank is offered first, then the same list of
/// types can be taken from disk instead.
const List<WorkspaceFileMenuAction> workspaceFileMenuActions = [
  WorkspaceFileMenuAction(WorkspaceFileKind.text, WorkspaceFileSource.create),
  WorkspaceFileMenuAction(WorkspaceFileKind.code, WorkspaceFileSource.create),
  WorkspaceFileMenuAction(
    WorkspaceFileKind.markdown,
    WorkspaceFileSource.create,
  ),
  WorkspaceFileMenuAction(WorkspaceFileKind.html, WorkspaceFileSource.create),
  WorkspaceFileMenuAction(WorkspaceFileKind.word, WorkspaceFileSource.create),
  WorkspaceFileMenuAction(WorkspaceFileKind.excel, WorkspaceFileSource.create),
  WorkspaceFileMenuAction(
    WorkspaceFileKind.powerpoint,
    WorkspaceFileSource.create,
  ),
  WorkspaceFileMenuAction(WorkspaceFileKind.file, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(WorkspaceFileKind.code, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(WorkspaceFileKind.pdf, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(WorkspaceFileKind.image, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(WorkspaceFileKind.video, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(WorkspaceFileKind.audio, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(
    WorkspaceFileKind.markdown,
    WorkspaceFileSource.upload,
  ),
  WorkspaceFileMenuAction(WorkspaceFileKind.word, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(WorkspaceFileKind.excel, WorkspaceFileSource.upload),
  WorkspaceFileMenuAction(
    WorkspaceFileKind.powerpoint,
    WorkspaceFileSource.upload,
  ),
];
