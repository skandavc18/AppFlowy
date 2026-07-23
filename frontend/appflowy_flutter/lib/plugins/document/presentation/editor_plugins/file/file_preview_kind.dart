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

FilePreviewKind? filePreviewKindFromName(String name) {
  final extension = name.split('.').last.toLowerCase();
  return switch (extension) {
    'pdf' => FilePreviewKind.pdf,
    'html' || 'htm' => FilePreviewKind.html,
    'md' || 'markdown' => FilePreviewKind.markdown,
    'zip' => FilePreviewKind.archive,
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
  };
  return extensions.contains(name.split('.').last.toLowerCase());
}

IconData fileIconForName(String? name) {
  if (name == null) {
    return Icons.insert_drive_file_outlined;
  }
  return switch (filePreviewKindFromName(name)) {
    FilePreviewKind.pdf => Icons.picture_as_pdf_outlined,
    FilePreviewKind.html => Icons.language_outlined,
    FilePreviewKind.markdown => Icons.article_outlined,
    FilePreviewKind.archive => Icons.folder_zip_outlined,
    FilePreviewKind.csv => Icons.table_chart_outlined,
    FilePreviewKind.json => Icons.data_object,
    FilePreviewKind.notebook => Icons.menu_book_outlined,
    FilePreviewKind.code => Icons.code,
    FilePreviewKind.text => Icons.description_outlined,
    null => Icons.insert_drive_file_outlined,
  };
}
