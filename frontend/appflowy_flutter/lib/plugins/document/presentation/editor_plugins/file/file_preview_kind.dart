import 'package:flutter/material.dart';

enum FilePreviewKind {
  pdf,
  html,
  markdown,
  archive,
  csv,
  json,
  notebook,
  code,
  text,
}

extension FilePreviewKindScrolling on FilePreviewKind {
  // WebView previews must claim trackpad input directly at their texture.
  bool get usesFrameScrollGuard => this == FilePreviewKind.pdf;
}

/// Metadata flag that puts a rendered preview into source editing mode.
const String filePreviewEditModeKey = 'edit_mode';

extension FilePreviewKindEditing on FilePreviewKind {
  /// Whether this kind can be edited as plain source inside the viewer.
  ///
  /// Code files are editable the moment they open. These kinds render a
  /// preview instead, so editing is an explicit mode rather than the default.
  bool get supportsSourceEditing => switch (this) {
        FilePreviewKind.markdown ||
        FilePreviewKind.html ||
        FilePreviewKind.text =>
          true,
        _ => false,
      };

  /// The highlight grammar used while editing the source.
  String get sourceLanguage => switch (this) {
        FilePreviewKind.markdown => 'markdown',
        FilePreviewKind.html => 'html',
        _ => 'text',
      };
}

/// Archive containers AppFlowy can open and edit in place.
///
/// 7-Zip and RAR are deliberately absent: nothing bundled with the app can
/// unpack them, so they stay ordinary attachments with an archive glyph.
const Set<String> browsableArchiveExtensions = {
  'zip',
  'jar',
  'cbz',
  'tar',
  'tgz',
  'taz',
  'tbz',
  'tbz2',
  'tb2',
  'txz',
  'gz',
  'gzip',
  'bz2',
  'bzip2',
  'xz',
};

/// Every archive extension, including the ones only shown as attachments.
const Set<String> archiveExtensions = {
  ...browsableArchiveExtensions,
  '7z',
  'rar',
  'iso',
  'lz',
  'lzma',
  'zst',
  'cab',
};

FilePreviewKind? filePreviewKindFromName(String name) {
  final extension = name.split('.').last.toLowerCase();
  if (browsableArchiveExtensions.contains(extension)) {
    return FilePreviewKind.archive;
  }
  return switch (extension) {
    'pdf' => FilePreviewKind.pdf,
    'html' || 'htm' => FilePreviewKind.html,
    'md' || 'markdown' => FilePreviewKind.markdown,
    'csv' || 'tsv' => FilePreviewKind.csv,
    'json' => FilePreviewKind.json,
    'ipynb' => FilePreviewKind.notebook,
    'txt' ||
    'log' ||
    'ini' ||
    'cfg' ||
    'conf' ||
    'yaml' ||
    'yml' ||
    'toml' ||
    'xml' =>
      FilePreviewKind.text,
    'dart' ||
    'py' ||
    'js' ||
    'jsx' ||
    'ts' ||
    'tsx' ||
    'c' ||
    'h' ||
    'cc' ||
    'cpp' ||
    'cxx' ||
    'hpp' ||
    'java' ||
    'kt' ||
    'kts' ||
    'rs' ||
    'go' ||
    'rb' ||
    'php' ||
    'swift' ||
    'sh' ||
    'ps1' ||
    'sql' ||
    'css' ||
    'scss' ||
    'sass' ||
    'less' =>
      FilePreviewKind.code,
    _ => null,
  };
}

bool isOfficeFile(String name) {
  const extensions = {
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'rtf',
    // The Office editor opens delimited text as a spreadsheet, which is a
    // better reading of a data file than a static table. The built-in table
    // stays as the fallback when no editor is reachable.
    'csv',
    'tsv',
  };
  return extensions.contains(name.split('.').last.toLowerCase());
}

bool supportsEmbeddedFilePreview(String name) =>
    filePreviewKindFromName(name) != null || isOfficeFile(name);

/// The glyph that stands for a file type.
///
/// Rounded Material symbols throughout, so an attachment chip, a sidebar row,
/// a menu entry and a viewer heading all name the same file with the same
/// shape.
IconData fileIconForName(String? name) {
  if (name == null) {
    return Icons.insert_drive_file_rounded;
  }
  return fileIconForExtension(name.split('.').last);
}

/// The same glyph as [fileIconForName], for callers that only know the
/// extension a type is written with.
IconData fileIconForExtension(String extension) {
  final normalized = extension.toLowerCase();
  if (archiveExtensions.contains(normalized)) {
    return Icons.folder_zip_rounded;
  }
  final kind = filePreviewKindFromName('file.$normalized');
  if (kind != null) {
    return switch (kind) {
      FilePreviewKind.pdf => Icons.picture_as_pdf_rounded,
      FilePreviewKind.html => Icons.language_rounded,
      FilePreviewKind.markdown => Icons.article_rounded,
      FilePreviewKind.archive => Icons.folder_zip_rounded,
      FilePreviewKind.csv => Icons.table_chart_rounded,
      FilePreviewKind.json => Icons.data_object_rounded,
      FilePreviewKind.notebook => Icons.menu_book_rounded,
      FilePreviewKind.code => Icons.code_rounded,
      FilePreviewKind.text => Icons.description_rounded,
    };
  }
  return switch (normalized) {
    'doc' || 'docx' || 'odt' || 'rtf' => Icons.text_snippet_rounded,
    'xls' || 'xlsx' || 'ods' => Icons.table_chart_rounded,
    'ppt' || 'pptx' || 'odp' => Icons.slideshow_rounded,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'tif' ||
    'tiff' ||
    'svg' =>
      Icons.image_rounded,
    'mp4' ||
    'mov' ||
    'mkv' ||
    'webm' ||
    'avi' ||
    'm4v' ||
    'mpeg' =>
      Icons.movie_rounded,
    'mp3' ||
    'wav' ||
    'm4a' ||
    'aac' ||
    'flac' ||
    'ogg' ||
    'wma' =>
      Icons.audiotrack_rounded,
    'ttf' || 'otf' || 'woff' || 'woff2' => Icons.font_download_rounded,
    'exe' ||
    'msi' ||
    'apk' ||
    'dmg' ||
    'deb' ||
    'rpm' =>
      Icons.terminal_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}
