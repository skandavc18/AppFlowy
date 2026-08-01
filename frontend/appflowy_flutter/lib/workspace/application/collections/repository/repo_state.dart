import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How a repository listing is ordered.
enum RepoSort {
  name,
  modified,
  size,
  type;

  static RepoSort fromValue(Object? value) {
    for (final sort in RepoSort.values) {
      if (sort.name == value) {
        return sort;
      }
    }
    return RepoSort.name;
  }
}

/// How the dependency graph arranges its nodes.
enum RepoGraphLayout {
  force,
  radial,
  layered;

  static RepoGraphLayout fromValue(Object? value) {
    for (final layout in RepoGraphLayout.values) {
      if (layout.name == value) {
        return layout;
      }
    }
    return RepoGraphLayout.force;
  }
}

@immutable
class RepoSettings {
  const RepoSettings({
    this.sort = RepoSort.name,
    this.showHidden = false,
    this.showIgnored = false,
    this.showOutline = true,
    this.wrapLines = false,
    this.graphLayout = RepoGraphLayout.force,
    this.showExternalDependencies = true,
  });

  final RepoSort sort;

  /// Whether dotfiles are listed.
  final bool showHidden;

  /// Whether build output and vendored code are listed.
  final bool showIgnored;

  /// Whether the tree explorer keeps an outline beside the file.
  final bool showOutline;
  final bool wrapLines;
  final RepoGraphLayout graphLayout;
  final bool showExternalDependencies;

  RepoSettings copyWith({
    RepoSort? sort,
    bool? showHidden,
    bool? showIgnored,
    bool? showOutline,
    bool? wrapLines,
    RepoGraphLayout? graphLayout,
    bool? showExternalDependencies,
  }) =>
      RepoSettings(
        sort: sort ?? this.sort,
        showHidden: showHidden ?? this.showHidden,
        showIgnored: showIgnored ?? this.showIgnored,
        showOutline: showOutline ?? this.showOutline,
        wrapLines: wrapLines ?? this.wrapLines,
        graphLayout: graphLayout ?? this.graphLayout,
        showExternalDependencies:
            showExternalDependencies ?? this.showExternalDependencies,
      );

  Map<String, Object?> toJson() => {
        'sort': sort.name,
        'show_hidden': showHidden,
        'show_ignored': showIgnored,
        'show_outline': showOutline,
        'wrap_lines': wrapLines,
        'graph_layout': graphLayout.name,
        'show_external': showExternalDependencies,
      };

  static RepoSettings fromJson(Object? value) {
    if (value is! Map) {
      return const RepoSettings();
    }
    final values = Map<String, dynamic>.from(value);
    return RepoSettings(
      sort: RepoSort.fromValue(values['sort']),
      showHidden: values['show_hidden'] == true,
      showIgnored: values['show_ignored'] == true,
      showOutline: values['show_outline'] != false,
      wrapLines: values['wrap_lines'] == true,
      graphLayout: RepoGraphLayout.fromValue(values['graph_layout']),
      showExternalDependencies: values['show_external'] != false,
    );
  }
}

/// Everything a repository remembers between visits.
@immutable
class RepoState {
  const RepoState({
    this.settings = const RepoSettings(),
    this.expandedPaths = const <String>{},
    this.activeFileId,
    this.activeDocId,
    this.browserPath = '',
  });

  final RepoSettings settings;

  /// The folders left open in the tree, by repository path.
  final Set<String> expandedPaths;

  /// The file last opened in the tree explorer, by view id.
  final String? activeFileId;

  /// The document last read in the documentation view, by view id.
  final String? activeDocId;

  /// The folder the browser was last looking at.
  final String browserPath;

  bool isExpanded(String path) => expandedPaths.contains(path);

  RepoState copyWith({
    RepoSettings? settings,
    Set<String>? expandedPaths,
    String? activeFileId,
    String? activeDocId,
    String? browserPath,
  }) =>
      RepoState(
        settings: settings ?? this.settings,
        expandedPaths: expandedPaths ?? this.expandedPaths,
        activeFileId: activeFileId ?? this.activeFileId,
        activeDocId: activeDocId ?? this.activeDocId,
        browserPath: browserPath ?? this.browserPath,
      );

  RepoState toggleExpanded(String path) {
    final next = Set<String>.from(expandedPaths);
    if (!next.remove(path)) {
      next.add(path);
    }
    return copyWith(expandedPaths: next);
  }

  /// Forgets files and folders that are no longer in the repository.
  RepoState prunedTo({
    required Set<String> paths,
    required Set<String> ids,
  }) {
    final nextExpanded = expandedPaths.intersection(paths);
    final fileSurvives = activeFileId == null || ids.contains(activeFileId);
    final docSurvives = activeDocId == null || ids.contains(activeDocId);
    final browserSurvives = browserPath.isEmpty || paths.contains(browserPath);
    if (nextExpanded.length == expandedPaths.length &&
        fileSurvives &&
        docSurvives &&
        browserSurvives) {
      return this;
    }
    return RepoState(
      settings: settings,
      expandedPaths: nextExpanded,
      activeFileId: fileSurvives ? activeFileId : null,
      activeDocId: docSurvives ? activeDocId : null,
      browserPath: browserSurvives ? browserPath : '',
    );
  }

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'expanded': expandedPaths.toList(),
        if (activeFileId != null) 'active_file': activeFileId,
        if (activeDocId != null) 'active_doc': activeDocId,
        if (browserPath.isNotEmpty) 'browser_path': browserPath,
      };

  static RepoState fromJson(Map<String, dynamic> value) {
    final expanded = value['expanded'];
    return RepoState(
      settings: RepoSettings.fromJson(value['settings']),
      expandedPaths: expanded is List
          ? {
              for (final path in expanded)
                if (path is String) path,
            }
          : const <String>{},
      activeFileId: value['active_file'] as String?,
      activeDocId: value['active_doc'] as String?,
      browserPath: value['browser_path'] as String? ?? '',
    );
  }
}

/// How much of a repository one language accounts for.
@immutable
class RepoLanguageShare {
  const RepoLanguageShare({
    required this.languageId,
    required this.label,
    required this.color,
    required this.files,
    required this.bytes,
    required this.fraction,
  });

  final String languageId;
  final String label;
  final Color color;
  final int files;
  final int bytes;

  /// 0..1 of the repository's source bytes.
  final double fraction;

  int get percent => (fraction * 100).round();
}

/// What a repository holds, at a glance.
@immutable
class RepoStats {
  const RepoStats({
    this.fileCount = 0,
    this.folderCount = 0,
    this.sourceCount = 0,
    this.docCount = 0,
    this.assetCount = 0,
    this.byteSize = 0,
    this.lineCount = 0,
    this.languages = const [],
  });

  final int fileCount;
  final int folderCount;
  final int sourceCount;
  final int docCount;
  final int assetCount;
  final int byteSize;

  /// Lines counted in the files that have been read so far.
  final int lineCount;
  final List<RepoLanguageShare> languages;

  bool get isEmpty => fileCount == 0 && folderCount == 0;
}
