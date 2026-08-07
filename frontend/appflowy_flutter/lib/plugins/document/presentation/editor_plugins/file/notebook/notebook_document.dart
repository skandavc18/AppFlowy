// Reading and writing `.ipynb` files (nbformat 4).
//
// The format is plain JSON, so nothing is guessed: a notebook is a list of
// cells, each holding its source and — for code cells — the outputs of the
// last time it ran. Everything the file carries that AppFlowy does not
// understand is kept and written back untouched, so opening a notebook here
// never costs a person the metadata their tools rely on.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Thrown when a file cannot be read as a notebook.
class NotebookFormatException implements Exception {
  const NotebookFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The three kinds of cell nbformat defines.
enum NotebookCellType {
  code,
  markdown,
  raw;

  static NotebookCellType parse(Object? value) => switch (value) {
        'code' => NotebookCellType.code,
        'raw' => NotebookCellType.raw,
        _ => NotebookCellType.markdown,
      };

  String get id => switch (this) {
        NotebookCellType.code => 'code',
        NotebookCellType.markdown => 'markdown',
        NotebookCellType.raw => 'raw',
      };

  String get label => switch (this) {
        NotebookCellType.code => 'Code',
        NotebookCellType.markdown => 'Markdown',
        NotebookCellType.raw => 'Raw',
      };
}

/// What an output is: printed text, the value of the last expression, a rich
/// display, or a failure.
enum NotebookOutputKind {
  stream,
  result,
  display,
  error;

  static NotebookOutputKind parse(Object? value) => switch (value) {
        'stream' => NotebookOutputKind.stream,
        'execute_result' => NotebookOutputKind.result,
        'error' => NotebookOutputKind.error,
        _ => NotebookOutputKind.display,
      };

  String get id => switch (this) {
        NotebookOutputKind.stream => 'stream',
        NotebookOutputKind.result => 'execute_result',
        NotebookOutputKind.display => 'display_data',
        NotebookOutputKind.error => 'error',
      };
}

/// One result produced by running a cell.
@immutable
class NotebookOutput {
  const NotebookOutput({
    required this.kind,
    this.name = '',
    this.text = '',
    this.data = const {},
    this.metadata = const {},
    this.executionCount,
    this.errorName = '',
    this.errorValue = '',
    this.traceback = const [],
  });

  /// Printed output, as it arrives from the running program.
  factory NotebookOutput.stream({required String name, required String text}) =>
      NotebookOutput(kind: NotebookOutputKind.stream, name: name, text: text);

  factory NotebookOutput.fromJson(Map<String, dynamic> json) {
    final kind = NotebookOutputKind.parse(json['output_type']);
    final rawData = json['data'];
    return NotebookOutput(
      kind: kind,
      name: json['name'] as String? ?? 'stdout',
      text: joinNotebookText(json['text']),
      data: rawData is Map
          ? {
              for (final entry in rawData.entries)
                entry.key.toString(): joinNotebookText(entry.value),
            }
          : const {},
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      executionCount: json['execution_count'] is int
          ? json['execution_count'] as int
          : null,
      errorName: json['ename'] as String? ?? '',
      errorValue: json['evalue'] as String? ?? '',
      traceback: json['traceback'] is List
          ? (json['traceback'] as List).map((line) => line.toString()).toList()
          : const [],
    );
  }

  final NotebookOutputKind kind;

  /// `stdout` or `stderr`, for a stream output.
  final String name;

  /// The printed text, for a stream output.
  final String text;

  /// Mime bundle, for a result or a display: `text/plain`, `text/html`,
  /// `image/png` (base64), `text/markdown`, `image/svg+xml`.
  final Map<String, String> data;

  final Map<String, dynamic> metadata;
  final int? executionCount;

  final String errorName;
  final String errorValue;
  final List<String> traceback;

  bool get isError => kind == NotebookOutputKind.error;

  bool get isStandardError =>
      kind == NotebookOutputKind.stream && name == 'stderr';

  String? get html => data['text/html'];
  String? get markdown => data['text/markdown'];
  String? get svg => data['image/svg+xml'];
  String? get latex => data['text/latex'];
  String? get plainText => data['text/plain'];

  /// The richest bitmap in the bundle, with the mime type it was declared as.
  MapEntry<String, String>? get image {
    for (final mime in const ['image/png', 'image/jpeg', 'image/gif']) {
      final encoded = data[mime];
      if (encoded != null && encoded.trim().isNotEmpty) {
        return MapEntry(mime, encoded);
      }
    }
    return null;
  }

  /// The traceback with the terminal colour codes removed.
  String get errorText {
    final body = traceback.map(stripAnsiEscapes).join('\n').trimRight();
    if (body.isNotEmpty) {
      return body;
    }
    return [errorName, errorValue].where((part) => part.isNotEmpty).join(': ');
  }

  /// Whether this output carries nothing worth drawing.
  bool get isEmpty => switch (kind) {
        NotebookOutputKind.stream => text.isEmpty,
        NotebookOutputKind.error => errorText.isEmpty,
        _ => data.values.every((value) => value.trim().isEmpty),
      };

  NotebookOutput appendText(String more) =>
      NotebookOutput(kind: kind, name: name, text: '$text$more');

  Map<String, dynamic> toJson() => switch (kind) {
        NotebookOutputKind.stream => {
            'output_type': kind.id,
            'name': name,
            'text': splitNotebookLines(text),
          },
        NotebookOutputKind.error => {
            'output_type': kind.id,
            'ename': errorName,
            'evalue': errorValue,
            'traceback': traceback,
          },
        NotebookOutputKind.result => {
            'output_type': kind.id,
            'data': _encodeData(),
            'metadata': metadata,
            'execution_count': executionCount,
          },
        NotebookOutputKind.display => {
            'output_type': kind.id,
            'data': _encodeData(),
            'metadata': metadata,
          },
      };

  Map<String, dynamic> _encodeData() {
    final encoded = <String, dynamic>{};
    for (final entry in data.entries) {
      // A bitmap is one base64 blob; text is stored line by line, exactly as
      // every other notebook tool writes it.
      final isBitmap =
          entry.key.startsWith('image/') && entry.key != 'image/svg+xml';
      encoded[entry.key] =
          isBitmap ? entry.value : splitNotebookLines(entry.value);
    }
    return encoded;
  }
}

/// One cell of a notebook.
@immutable
class NotebookCell {
  const NotebookCell({
    required this.id,
    required this.type,
    required this.source,
    this.outputs = const [],
    this.executionCount,
    this.metadata = const {},
    this.attachments,
    this.extra = const {},
  });

  factory NotebookCell.fromJson(Map<String, dynamic> json, int index) {
    final type = NotebookCellType.parse(json['cell_type']);
    final known = {
      'id',
      'cell_type',
      'source',
      'outputs',
      'execution_count',
      'metadata',
      'attachments',
    };
    return NotebookCell(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : 'cell-$index-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      source: joinNotebookText(json['source']),
      outputs: json['outputs'] is List
          ? (json['outputs'] as List)
              .whereType<Map>()
              .map(
                (output) => NotebookOutput.fromJson(
                  Map<String, dynamic>.from(output),
                ),
              )
              .toList()
          : const [],
      executionCount: json['execution_count'] is int
          ? json['execution_count'] as int
          : null,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      attachments: json['attachments'] is Map
          ? Map<String, dynamic>.from(json['attachments'] as Map)
          : null,
      extra: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// A new, empty cell.
  factory NotebookCell.blank(NotebookCellType type) => NotebookCell(
        id: newNotebookCellId(),
        type: type,
        source: '',
      );

  final String id;
  final NotebookCellType type;
  final String source;
  final List<NotebookOutput> outputs;
  final int? executionCount;
  final Map<String, dynamic> metadata;

  /// Images pasted into a markdown cell, keyed by the name the source refers
  /// to with `attachment:`.
  final Map<String, dynamic>? attachments;

  /// Anything else the file carried on this cell, kept so a round trip does
  /// not quietly drop it.
  final Map<String, dynamic> extra;

  bool get isCode => type == NotebookCellType.code;

  bool get hasOutputs => outputs.any((output) => !output.isEmpty);

  NotebookCell copyWith({
    NotebookCellType? type,
    String? source,
    List<NotebookOutput>? outputs,
    int? executionCount,
    bool clearExecutionCount = false,
  }) =>
      NotebookCell(
        id: id,
        type: type ?? this.type,
        source: source ?? this.source,
        outputs: outputs ?? this.outputs,
        executionCount:
            clearExecutionCount ? null : executionCount ?? this.executionCount,
        metadata: metadata,
        attachments: attachments,
        extra: extra,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'cell_type': type.id,
        'id': id,
        'metadata': metadata,
        if (attachments != null) 'attachments': attachments,
        if (type == NotebookCellType.code) ...{
          'execution_count': executionCount,
          'outputs': [for (final output in outputs) output.toJson()],
        },
        'source': splitNotebookLines(source),
      };
}

/// A whole notebook, as read from disk.
@immutable
class NotebookDocument {
  const NotebookDocument({
    required this.cells,
    this.metadata = const {},
    this.nbformat = 4,
    this.nbformatMinor = 5,
  });

  /// Reads a `.ipynb` file.
  factory NotebookDocument.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw NotebookFormatException(
        'This file is not valid JSON, so it cannot be read as a notebook '
        '(${error.message}).',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const NotebookFormatException(
        'This file does not hold a notebook document.',
      );
    }
    final cells = decoded['cells'];
    if (cells is! List) {
      throw const NotebookFormatException(
        'This notebook has no cells; the "cells" list is missing.',
      );
    }
    final parsed = <NotebookCell>[];
    for (var index = 0; index < cells.length; index++) {
      final cell = cells[index];
      if (cell is Map) {
        parsed.add(
          NotebookCell.fromJson(Map<String, dynamic>.from(cell), index),
        );
      }
    }
    return NotebookDocument(
      cells: parsed,
      metadata: decoded['metadata'] is Map
          ? Map<String, dynamic>.from(decoded['metadata'] as Map)
          : const {},
      nbformat: decoded['nbformat'] is int ? decoded['nbformat'] as int : 4,
      nbformatMinor: decoded['nbformat_minor'] is int
          ? decoded['nbformat_minor'] as int
          : 5,
    );
  }

  /// A new notebook holding one empty code cell.
  factory NotebookDocument.blank({String language = 'python'}) =>
      NotebookDocument(
        cells: [NotebookCell.blank(NotebookCellType.code)],
        metadata: {
          'kernelspec': {
            'display_name': language == 'python' ? 'Python 3' : language,
            'language': language,
            'name': language == 'python' ? 'python3' : language,
          },
          'language_info': {'name': language},
        },
      );

  final List<NotebookCell> cells;
  final Map<String, dynamic> metadata;
  final int nbformat;
  final int nbformatMinor;

  /// The language the code cells are written in.
  String get language {
    final info = metadata['language_info'];
    if (info is Map && info['name'] is String) {
      final name = (info['name'] as String).trim();
      if (name.isNotEmpty) {
        return name.toLowerCase();
      }
    }
    final spec = metadata['kernelspec'];
    if (spec is Map) {
      for (final key in const ['language', 'name']) {
        final value = spec[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim().toLowerCase().replaceAll(RegExp(r'\d+$'), '');
        }
      }
    }
    return 'python';
  }

  /// What the notebook says its kernel is called, for the status line.
  String get kernelName {
    final spec = metadata['kernelspec'];
    if (spec is Map && spec['display_name'] is String) {
      final name = (spec['display_name'] as String).trim();
      if (name.isNotEmpty) {
        return name;
      }
    }
    return language.isEmpty ? 'Kernel' : language;
  }

  int get codeCellCount => cells.where((cell) => cell.isCode).length;

  NotebookDocument copyWith({List<NotebookCell>? cells}) => NotebookDocument(
        cells: cells ?? this.cells,
        metadata: metadata,
        nbformat: nbformat,
        nbformatMinor: nbformatMinor,
      );

  /// Replaces one cell, keeping every other cell as it is.
  NotebookDocument withCell(int index, NotebookCell cell) {
    if (index < 0 || index >= cells.length) {
      return this;
    }
    final next = [...cells];
    next[index] = cell;
    return copyWith(cells: next);
  }

  NotebookDocument withCellInserted(int index, NotebookCell cell) {
    final next = [...cells];
    next.insert(index.clamp(0, cells.length), cell);
    return copyWith(cells: next);
  }

  NotebookDocument withCellRemoved(int index) {
    if (index < 0 || index >= cells.length) {
      return this;
    }
    final next = [...cells]..removeAt(index);
    return copyWith(cells: next);
  }

  NotebookDocument withCellMoved(int index, int delta) {
    final target = index + delta;
    if (index < 0 ||
        index >= cells.length ||
        target < 0 ||
        target >= cells.length) {
      return this;
    }
    final next = [...cells];
    next.insert(target, next.removeAt(index));
    return copyWith(cells: next);
  }

  int indexOfCell(String id) => cells.indexWhere((cell) => cell.id == id);

  /// Writes the notebook back out.
  ///
  /// Jupyter writes `.ipynb` with a one space indent and a trailing newline;
  /// matching that keeps a file edited here from showing up as a whole-file
  /// change in version control.
  String encode() {
    final document = {
      'cells': [for (final cell in cells) cell.toJson()],
      'metadata': metadata,
      'nbformat': nbformat,
      'nbformat_minor': nbformatMinor,
    };
    return '${const JsonEncoder.withIndent(' ').convert(document)}\n';
  }
}

/// Notebook text is stored either as one string or as a list of lines.
String joinNotebookText(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is List) {
    return value.map((line) => line?.toString() ?? '').join();
  }
  return '';
}

/// Splits text the way nbformat stores it: every line keeps its newline
/// except the last.
List<String> splitNotebookLines(String value) {
  if (value.isEmpty) {
    return const [];
  }
  final lines = <String>[];
  var start = 0;
  for (var index = 0; index < value.length; index++) {
    if (value[index] == '\n') {
      lines.add(value.substring(start, index + 1));
      start = index + 1;
    }
  }
  if (start < value.length) {
    lines.add(value.substring(start));
  }
  return lines;
}

final RegExp _ansiPattern = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

/// Removes the terminal colour codes a traceback is printed with.
String stripAnsiEscapes(String value) =>
    value.contains('\x1B') ? value.replaceAll(_ansiPattern, '') : value;

int _cellCounter = 0;

/// A cell id in the shape nbformat 4.5 asks for: short, unique, and stable
/// for the lifetime of the file.
String newNotebookCellId() {
  _cellCounter = (_cellCounter + 1) & 0xFFFF;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'af${stamp.substring(stamp.length - 6)}${_cellCounter.toRadixString(36)}';
}
