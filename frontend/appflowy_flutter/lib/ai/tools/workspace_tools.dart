import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/ai/tools/file_reader.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_service.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show Node;
import 'package:nanoid/nanoid.dart';

import 'ai_tool.dart';

/// The tools AppFlowy itself answers.
///
/// This is an MCP server in everything but transport: it declares tools with a
/// name, a sentence and a JSON Schema, and runs them. Nothing here talks to a
/// network — every call goes to the workspace through the same services the
/// user interface uses, so an agent can do exactly what a person could.
class WorkspaceToolServer implements AIToolServer {
  WorkspaceToolServer();

  static const serverId = 'appflowy';

  @override
  String get id => serverId;

  @override
  String get label => 'AppFlowy workspace';

  @override
  bool get isAvailable => true;

  @override
  Future<void> dispose() async {}

  final WorkspaceItemService _items = const WorkspaceItemService();
  final DocumentToolkit _blocks = DocumentToolkit();

  static const _pageIdArgument = {
    'type': 'string',
    'description': 'The id of the page, table, folder or file.',
  };

  @override
  Future<List<AITool>> listTools() async => _tools;

  late final List<AITool> _tools = [
    _tool(
      'list_pages',
      'List the pages, tables, folders and files in the workspace. Start here '
          'to find the id of something before changing it.',
      risk: AIToolRisk.read,
      properties: {
        'parent_id': {
          'type': 'string',
          'description':
              'Only list what is directly inside this page or folder. Omit to '
                  'list everything in the workspace.',
        },
        'query': {
          'type': 'string',
          'description': 'Only return items whose name contains this text.',
        },
      },
    ),
    _tool(
      'read_page',
      'Read the text of a page as Markdown.',
      risk: AIToolRisk.read,
      properties: {'page_id': _pageIdArgument},
      required: ['page_id'],
    ),
    _tool(
      'create_page',
      'Create a page. The body is written in Markdown and may be left out.',
      properties: {
        'parent_id': {
          'type': 'string',
          'description':
              'Where to put it. Omit to put it at the top of the workspace.',
        },
        'name': {'type': 'string', 'description': 'The page title.'},
        'content': {
          'type': 'string',
          'description': 'The body of the page, written in Markdown.',
        },
      },
      required: ['name'],
    ),
    _tool(
      'append_to_page',
      'Add Markdown to the end of an existing page.',
      properties: {
        'page_id': _pageIdArgument,
        'content': {
          'type': 'string',
          'description': 'The Markdown to add.',
        },
      },
      required: ['page_id', 'content'],
    ),
    _tool(
      'rename_item',
      'Rename a page, table, folder or file.',
      properties: {
        'page_id': _pageIdArgument,
        'name': {'type': 'string', 'description': 'The new name.'},
      },
      required: ['page_id', 'name'],
    ),
    _tool(
      'move_item',
      'Move a page, table, folder or file into another folder or page.',
      properties: {
        'page_id': _pageIdArgument,
        'parent_id': {
          'type': 'string',
          'description': 'The page or folder to move it into.',
        },
      },
      required: ['page_id', 'parent_id'],
    ),
    _tool(
      'delete_item',
      'Move a page, table, folder or file to the trash.',
      risk: AIToolRisk.destructive,
      properties: {'page_id': _pageIdArgument},
      required: ['page_id'],
    ),
    _tool(
      'create_folder',
      'Create a folder.',
      properties: {
        'parent_id': {
          'type': 'string',
          'description': 'Where to put it. Omit for the top of the workspace.',
        },
        'name': {'type': 'string', 'description': 'The folder name.'},
      },
      required: ['name'],
    ),
    _tool(
      'create_file',
      'Create a file in the workspace, optionally with its text contents.',
      properties: {
        'parent_id': {
          'type': 'string',
          'description': 'Where to put it. Omit for the top of the workspace.',
        },
        'name': {
          'type': 'string',
          'description': 'The file name, with its extension.',
        },
        'kind': {
          'type': 'string',
          'description': 'One of: ${WorkspaceFileKind.values.map((k) => k.name).join(', ')}.',
        },
        'content': {
          'type': 'string',
          'description': 'The text to write into it.',
        },
      },
      required: ['name'],
    ),
    _tool(
      'create_table',
      'Create a table (a database). The reading can be a grid, a board or a '
          'calendar.',
      properties: {
        'parent_id': {
          'type': 'string',
          'description': 'Where to put it. Omit for the top of the workspace.',
        },
        'name': {'type': 'string', 'description': 'The table name.'},
        'layout': {
          'type': 'string',
          'enum': ['grid', 'board', 'calendar'],
          'description': 'How the table is read. Defaults to grid.',
        },
      },
      required: ['name'],
    ),
    _tool(
      'create_table_view',
      'Add another reading of an existing table: a chart, a map, slides, a '
          'timeline, a feed, a form, a gallery or a mailbox.',
      properties: {
        'table_id': {
          'type': 'string',
          'description': 'The table to read.',
        },
        'name': {'type': 'string', 'description': 'The name of the reading.'},
        'kind': {
          'type': 'string',
          'enum': [
            'grid',
            'board',
            'calendar',
            ...WorkspaceToolServer._markedViewKinds.keys,
          ],
          'description': 'Which reading to add.',
        },
      },
      required: ['table_id', 'kind'],
    ),
    _tool(
      'describe_table',
      'List the columns of a table and read its rows.',
      risk: AIToolRisk.read,
      properties: {
        'table_id': {'type': 'string', 'description': 'The table to read.'},
        'limit': {
          'type': 'integer',
          'description': 'How many rows to read. Defaults to 20.',
        },
      },
      required: ['table_id'],
    ),
    _tool(
      'add_column',
      'Add a column to a table.',
      properties: {
        'table_id': {'type': 'string', 'description': 'The table to change.'},
        'name': {'type': 'string', 'description': 'The column name.'},
        'type': {
          'type': 'string',
          'enum': [
            'text',
            'number',
            'date',
            'select',
            'multi_select',
            'checkbox',
            'url',
            'checklist',
          ],
          'description': 'What the column holds. Defaults to text.',
        },
      },
      required: ['table_id', 'name'],
    ),
    _tool(
      'add_row',
      'Add a row to a table. Cells are given by column NAME.',
      properties: {
        'table_id': {'type': 'string', 'description': 'The table to change.'},
        'cells': {
          'type': 'object',
          'description':
              'The values to write, keyed by column name. Everything is '
                  'written as text.',
          'additionalProperties': {'type': 'string'},
        },
      },
      required: ['table_id'],
    ),
    _tool(
      'update_cell',
      'Change one cell of a table.',
      properties: {
        'table_id': {'type': 'string', 'description': 'The table to change.'},
        'row_id': {'type': 'string', 'description': 'The row to change.'},
        'column': {'type': 'string', 'description': 'The column name.'},
        'value': {'type': 'string', 'description': 'The value to write.'},
      },
      required: ['table_id', 'row_id', 'column', 'value'],
    ),
    _tool(
      'create_dashboard',
      'Create a dashboard page.',
      properties: {
        'parent_id': {
          'type': 'string',
          'description': 'Where to put it. Omit for the top of the workspace.',
        },
        'name': {'type': 'string', 'description': 'The dashboard name.'},
      },
      required: ['name'],
    ),
    _tool(
      'create_collection',
      'Create a collection: a folder with a purpose, such as a book, an album, '
          'a repository, a bookmark library, a database or a mailbox.',
      properties: {
        'parent_id': {
          'type': 'string',
          'description': 'Where to put it. Omit for the top of the workspace.',
        },
        'name': {'type': 'string', 'description': 'The collection name.'},
        'kind': {
          'type': 'string',
          'enum': ['book', 'album', 'repository', 'database', 'bookmark', 'email'],
          'description': 'What the collection holds.',
        },
      },
      required: ['name', 'kind'],
    ),
    _tool(
      'list_blocks',
      'List the blocks of a page with their ids, so they can be changed, moved '
          'or removed. Do this before editing anything in a page.',
      risk: AIToolRisk.read,
      properties: {'page_id': _pageIdArgument},
      required: ['page_id'],
    ),
    _tool(
      'insert_block',
      'Insert one block into a page. This is how every kind of content is '
          'added: headings, lists, quotes, callouts, code, pictures, video, '
          'files, bookmarks, mind maps, drawings, diagrams, equations, '
          'spreadsheets, embedded pages, tables, charts, maps and slides.\n'
          'Known types: $_blockTypeList.\n'
          'Attributes worth knowing: image/video/file take "url"; code takes '
          '"language"; heading takes "level" (1-6); todo_list takes "checked"; '
          'callout takes "icon"; math_equation takes "formula"; mermaid takes '
          '"content"; mind_map takes "content"; drawing takes "scene"; '
          'grid/board/calendar and workspace_folder take "view_id"; '
          'page_preview takes "view_id"; bookmark and link_preview take "url"; '
          'map takes "view_id"; every text block takes "align" '
          '(left/center/right/justify) and "bgColor".',
      properties: {
        'page_id': _pageIdArgument,
        'type': {
          'type': 'string',
          'description': 'The block type. See the list above.',
        },
        'text': {
          'type': 'string',
          'description': 'The words in the block, for a text block.',
        },
        'attributes': {
          'type': 'object',
          'description': 'Everything else the block needs.',
        },
        'after_block_id': {
          'type': 'string',
          'description':
              'Put it after this block. Omit to put it at the end of the page.',
        },
      },
      required: ['page_id', 'type'],
    ),
    _tool(
      'update_block',
      'Change a block: its words, its type, or how it is set out. Use it to '
          'reformat text, align it, tick a to-do, change a code block\'s '
          'language, or point an embed somewhere else.',
      properties: {
        'page_id': _pageIdArgument,
        'block_id': {'type': 'string', 'description': 'The block to change.'},
        'text': {'type': 'string', 'description': 'New words for the block.'},
        'type': {
          'type': 'string',
          'description': 'Turn it into another type. See insert_block.',
        },
        'attributes': {
          'type': 'object',
          'description':
              'Attributes to set, merged over the ones already there.',
        },
      },
      required: ['page_id', 'block_id'],
    ),
    _tool(
      'move_block',
      'Move a block up or down a page.',
      properties: {
        'page_id': _pageIdArgument,
        'block_id': {'type': 'string', 'description': 'The block to move.'},
        'after_block_id': {
          'type': 'string',
          'description':
              'Put it after this block. Omit to put it first on the page.',
        },
      },
      required: ['page_id', 'block_id'],
    ),
    _tool(
      'delete_block',
      'Remove a block from a page.',
      risk: AIToolRisk.destructive,
      properties: {
        'page_id': _pageIdArgument,
        'block_id': {'type': 'string', 'description': 'The block to remove.'},
      },
      required: ['page_id', 'block_id'],
    ),
    _tool(
      'read_row_page',
      'Read the page attached to a table row. Every row has one.',
      risk: AIToolRisk.read,
      properties: {
        'table_id': {'type': 'string', 'description': 'The table.'},
        'row_id': {'type': 'string', 'description': 'The row.'},
      },
      required: ['table_id', 'row_id'],
    ),
    _tool(
      'write_row_page',
      'Write Markdown into the page attached to a table row. The page is '
          'created if the row has never been written in.',
      properties: {
        'table_id': {'type': 'string', 'description': 'The table.'},
        'row_id': {'type': 'string', 'description': 'The row.'},
        'content': {
          'type': 'string',
          'description': 'The Markdown to add.',
        },
      },
      required: ['table_id', 'row_id', 'content'],
    ),
    _tool(
      'set_page_decoration',
      'Set or clear a page\'s cover and icon.',
      properties: {
        'page_id': _pageIdArgument,
        'cover_type': {
          'type': 'string',
          'enum': ['none', 'color', 'url', 'builtin'],
          'description': 'What kind of cover to use.',
        },
        'cover_value': {
          'type': 'string',
          'description':
              'A colour name for "color", an address for "url", or a built-in '
                  'name such as n1..n6 for "builtin".',
        },
        'icon': {
          'type': 'string',
          'description': 'An emoji to use as the page icon.',
        },
      },
      required: ['page_id'],
    ),
    _tool(
      'read_file',
      'Read the text of a workspace file: a Word, Excel or PowerPoint '
          'document, a PDF, or any plain text, Markdown, CSV or code file.',
      risk: AIToolRisk.read,
      properties: {
        'page_id': _pageIdArgument,
        'limit': {
          'type': 'integer',
          'description': 'How many characters to read. Defaults to 8000.',
        },
      },
      required: ['page_id'],
    ),
    _tool(
      'list_reminders',
      'List the reminders that have been set.',
      risk: AIToolRisk.read,
      properties: {
        'include_done': {
          'type': 'boolean',
          'description': 'Include the ones already done. Defaults to false.',
        },
      },
    ),
    _tool(
      'add_reminder',
      'Set a reminder.',
      properties: {
        'title': {'type': 'string', 'description': 'What it is about.'},
        'when': {
          'type': 'string',
          'description': 'When to be reminded, as an ISO 8601 date and time.',
        },
        'message': {'type': 'string', 'description': 'Anything to add.'},
        'page_id': {
          'type': 'string',
          'description': 'A page the reminder is about.',
        },
      },
      required: ['title', 'when'],
    ),
    _tool(
      'complete_reminder',
      'Mark a reminder as done.',
      properties: {
        'reminder_id': {'type': 'string', 'description': 'The reminder.'},
      },
      required: ['reminder_id'],
    ),
    _tool(
      'delete_reminder',
      'Remove a reminder.',
      risk: AIToolRisk.destructive,
      properties: {
        'reminder_id': {'type': 'string', 'description': 'The reminder.'},
      },
      required: ['reminder_id'],
    ),
  ];

  /// The block types a page can hold, named for the model.
  static const _blockTypeList =
      'paragraph, heading, bulleted_list, numbered_list, todo_list, quote, '
      'callout, toggle_list, divider, code, math_equation, image, '
      'multi_image, video, file, link_preview, bookmark, mermaid, mind_map, '
      'drawing, spreadsheet, simple_table, page, grid, board, calendar, '
      'workspace_folder, chart, map, sticky_note, interactive_button, '
      'interactive_progress, interactive_counter, interactive_reminder';

  static AITool _tool(
    String name,
    String description, {
    AIToolRisk risk = AIToolRisk.write,
    Map<String, dynamic> properties = const {},
    List<String> required = const [],
  }) =>
      AITool(
        serverId: serverId,
        serverLabel: 'AppFlowy workspace',
        name: name,
        description: description,
        risk: risk,
        schema: {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
        },
      );

  static const _markedViewKinds = {
    'chart': 'appflowy_chart',
    'map': 'appflowy_map',
    'slides': 'appflowy_slide',
    'timeline': 'appflowy_timeline',
    'feed': 'appflowy_feed',
    'form': 'appflowy_form',
    'gallery': 'appflowy_gallery',
    'mailbox': 'appflowy_mailbox',
  };

  @override
  Future<AIToolResult> call(String name, Map<String, dynamic> arguments) async {
    try {
      return switch (name) {
        'list_pages' => await _listPages(arguments),
        'read_page' => await _readPage(arguments),
        'create_page' => await _createPage(arguments),
        'append_to_page' => await _appendToPage(arguments),
        'rename_item' => await _rename(arguments),
        'move_item' => await _move(arguments),
        'delete_item' => await _delete(arguments),
        'create_folder' => await _createFolder(arguments),
        'create_file' => await _createFile(arguments),
        'create_table' => await _createTable(arguments),
        'create_table_view' => await _createTableView(arguments),
        'describe_table' => await _describeTable(arguments),
        'add_column' => await _addColumn(arguments),
        'add_row' => await _addRow(arguments),
        'update_cell' => await _updateCell(arguments),
        'create_dashboard' => await _createDashboard(arguments),
        'create_collection' => await _createCollection(arguments),
        'list_blocks' => await _listBlocks(arguments),
        'insert_block' => await _insertBlock(arguments),
        'update_block' => await _updateBlock(arguments),
        'move_block' => await _moveBlock(arguments),
        'delete_block' => await _deleteBlock(arguments),
        'read_row_page' => await _readRowPage(arguments),
        'write_row_page' => await _writeRowPage(arguments),
        'set_page_decoration' => await _setDecoration(arguments),
        'read_file' => await _readFile(arguments),
        'list_reminders' => await _listReminders(arguments),
        'add_reminder' => await _addReminder(arguments),
        'complete_reminder' => await _completeReminder(arguments),
        'delete_reminder' => await _deleteReminder(arguments),
        _ => AIToolResult.error('AppFlowy has no tool called "$name".'),
      };
    } catch (error) {
      return AIToolResult.error('That did not work: $error');
    }
  }

  // ---------------------------------------------------------------- helpers

  static String? _string(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value == null) {
      return null;
    }
    final text = value is String ? value : '$value';
    return text.trim().isEmpty ? null : text.trim();
  }

  Future<String> _resolveParent(Map<String, dynamic> arguments) async {
    final stated = _string(arguments, 'parent_id');
    if (stated != null) {
      return stated;
    }
    final workspace = await FolderEventReadCurrentWorkspace().send();
    return workspace.fold((value) => value.id, (_) => '');
  }

  Future<ViewPB?> _view(String viewId) async {
    final result = await ViewBackendService.getView(viewId);
    return result.fold((view) => view, (_) => null);
  }

  static String _describeView(ViewPB view) {
    final kind = view.isCollection
        ? 'collection'
        : view.isWorkspaceFolder
            ? 'folder'
            : view.isWorkspaceFile
                ? 'file'
                : view.layout.name.toLowerCase();
    return '- ${view.nameOrDefault} (id: ${view.id}, $kind)';
  }

  // ------------------------------------------------------------------ tools

  Future<AIToolResult> _listPages(Map<String, dynamic> arguments) async {
    final parent = _string(arguments, 'parent_id');
    final query = _string(arguments, 'query')?.toLowerCase();

    final result = parent == null
        ? await ViewBackendService.getAllViews()
            .then((r) => r.fold((list) => list.items, (_) => <ViewPB>[]))
        : await ViewBackendService.getChildViews(viewId: parent)
            .then((r) => r.fold((list) => list, (_) => <ViewPB>[]));

    final matching = result
        .where(
          (view) =>
              query == null ||
              view.nameOrDefault.toLowerCase().contains(query),
        )
        .take(200)
        .toList();

    if (matching.isEmpty) {
      return const AIToolResult('Nothing there.');
    }
    return AIToolResult(matching.map(_describeView).join('\n'));
  }

  Future<AIToolResult> _readPage(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    if (pageId == null) {
      return const AIToolResult.error('page_id is needed.');
    }

    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be read.');
    }
    final parsed = data.toDocument();
    if (parsed == null) {
      return const AIToolResult.error('That page could not be read.');
    }
    final markdown = await customDocumentToMarkdown(parsed);
    return AIToolResult(
      markdown.trim().isEmpty ? 'That page is empty.' : markdown,
    );
  }

  Future<AIToolResult> _createPage(Map<String, dynamic> arguments) async {
    final name = _string(arguments, 'name') ?? 'Untitled';
    final content = _string(arguments, 'content');
    final parent = await _resolveParent(arguments);

    Uint8List? initial;
    if (content != null) {
      final document = customMarkdownToDocument(content);
      initial = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    }

    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parent,
      name: name,
      initialDataBytes: initial,
    );
    return result.fold(
      (view) => AIToolResult('Created the page "$name" (id: ${view.id}).'),
      (error) => AIToolResult.error('The page was not created: ${error.msg}'),
    );
  }

  Future<AIToolResult> _appendToPage(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final content = _string(arguments, 'content');
    if (pageId == null || content == null) {
      return const AIToolResult.error('page_id and content are needed.');
    }

    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be opened.');
    }

    final nodes = _blocks.parseMarkdown(content).root.children;
    if (nodes.isEmpty) {
      return const AIToolResult.error(
        'There was nothing to add — the content was empty.',
      );
    }

    final written = await _blocks.insert(
      pageId: pageId,
      nodes: nodes,
      parentId: data.pageId,
      previousId: _blocks.lastTopLevelBlockId(data),
    );
    return written == 0
        ? const AIToolResult.error('That page would not take the new blocks.')
        : AIToolResult('Added $written blocks to that page.');
  }

  Future<AIToolResult> _rename(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final name = _string(arguments, 'name');
    if (pageId == null || name == null) {
      return const AIToolResult.error('page_id and name are needed.');
    }
    final result =
        await ViewBackendService.updateView(viewId: pageId, name: name);
    return result.fold(
      (_) => AIToolResult('Renamed it to "$name".'),
      (error) => AIToolResult.error('It was not renamed: ${error.msg}'),
    );
  }

  Future<AIToolResult> _move(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final parentId = _string(arguments, 'parent_id');
    if (pageId == null || parentId == null) {
      return const AIToolResult.error('page_id and parent_id are needed.');
    }
    final result = await ViewBackendService.moveViewV2(
      viewId: pageId,
      newParentId: parentId,
      prevViewId: null,
    );
    return result.fold(
      (_) => const AIToolResult('Moved it.'),
      (error) => AIToolResult.error('It was not moved: ${error.msg}'),
    );
  }

  Future<AIToolResult> _delete(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    if (pageId == null) {
      return const AIToolResult.error('page_id is needed.');
    }
    final view = await _view(pageId);
    final result = await ViewBackendService.deleteView(viewId: pageId);
    return result.fold(
      (_) => AIToolResult(
        'Moved "${view?.nameOrDefault ?? pageId}" to the trash.',
      ),
      (error) => AIToolResult.error('It was not deleted: ${error.msg}'),
    );
  }

  Future<AIToolResult> _createFolder(Map<String, dynamic> arguments) async {
    final name = _string(arguments, 'name') ?? 'New folder';
    final parent = await _resolveParent(arguments);
    final result =
        await _items.createFolder(parentViewId: parent, name: name);
    return result.fold(
      (view) => AIToolResult('Created the folder "$name" (id: ${view.id}).'),
      (error) => AIToolResult.error('The folder was not created: ${error.msg}'),
    );
  }

  Future<AIToolResult> _createFile(Map<String, dynamic> arguments) async {
    final name = _string(arguments, 'name') ?? 'Untitled';
    final parent = await _resolveParent(arguments);
    final kind = WorkspaceFileKind.values.firstWhere(
      (value) => value.name == _string(arguments, 'kind'),
      orElse: () =>
          WorkspaceFileKind.fromName(name) ?? WorkspaceFileKind.markdown,
    );
    final content = _string(arguments, 'content');

    final result = await _items.createBlankFile(
      parentViewId: parent,
      kind: kind,
      name: name,
      content: content == null
          ? null
          : Uint8List.fromList(utf8.encode(content)),
    );
    return result.fold(
      (view) => AIToolResult('Created the file "$name" (id: ${view.id}).'),
      (error) => AIToolResult.error('The file was not created: ${error.msg}'),
    );
  }

  Future<AIToolResult> _createTable(Map<String, dynamic> arguments) async {
    final name = _string(arguments, 'name') ?? 'Untitled';
    final parent = await _resolveParent(arguments);
    final layout = switch (_string(arguments, 'layout')) {
      'board' => ViewLayoutPB.Board,
      'calendar' => ViewLayoutPB.Calendar,
      _ => ViewLayoutPB.Grid,
    };

    final result = await ViewBackendService.createView(
      layoutType: layout,
      parentViewId: parent,
      name: name,
    );
    return result.fold(
      (view) => AIToolResult('Created the table "$name" (id: ${view.id}).'),
      (error) => AIToolResult.error('The table was not created: ${error.msg}'),
    );
  }

  Future<AIToolResult> _createTableView(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    final kind = _string(arguments, 'kind') ?? 'grid';
    if (tableId == null) {
      return const AIToolResult.error('table_id is needed.');
    }

    final source = await _view(tableId);
    if (source == null) {
      return const AIToolResult.error('That table could not be found.');
    }

    final databaseId = await DatabaseViewBackendService(viewId: tableId)
        .getDatabaseId()
        .then((r) => r.fold((id) => id, (_) => null));
    if (databaseId == null) {
      return const AIToolResult.error('That page is not a table.');
    }

    // Every marked reading IS a grid wearing an envelope in the view's extra,
    // so only the envelope changes between them.
    final envelope = _markedViewKinds[kind];
    final layout = switch (kind) {
      'board' => ViewLayoutPB.Board,
      'calendar' => ViewLayoutPB.Calendar,
      _ => ViewLayoutPB.Grid,
    };

    final result = await ViewBackendService.createDatabaseLinkedView(
      parentViewId: source.parentViewId,
      databaseId: databaseId,
      layoutType: layout,
      name: _string(arguments, 'name') ?? '${source.nameOrDefault} $kind',
      extra: envelope == null
          ? null
          : jsonEncode({
              envelope: {'version': 1},
            }),
    );
    return result.fold(
      (view) => AIToolResult('Added a $kind reading (id: ${view.id}).'),
      (error) => AIToolResult.error('It was not added: ${error.msg}'),
    );
  }

  Future<List<FieldPB>> _fields(String tableId) async {
    final result = await DatabaseViewBackendService(viewId: tableId).getFields();
    return result.fold((fields) => fields, (_) => <FieldPB>[]);
  }

  Future<AIToolResult> _describeTable(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    if (tableId == null) {
      return const AIToolResult.error('table_id is needed.');
    }
    final limit = (arguments['limit'] is num)
        ? (arguments['limit'] as num).toInt().clamp(1, 200)
        : 20;

    final fields = await _fields(tableId);
    if (fields.isEmpty) {
      return const AIToolResult.error(
        'That table could not be read. Is the id right?',
      );
    }

    final buffer = StringBuffer()
      ..writeln('Columns:')
      ..writeAll(
        fields.map(
          (field) => '- ${field.name} (${field.fieldType.name})',
        ),
        '\n',
      )
      ..writeln();

    final rows = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB(value: tableId),
    ).send();

    rows.fold(
      (list) {
        final names = list.fieldIds
            .map(
              (id) => fields
                  .firstWhere(
                    (field) => field.id == id,
                    orElse: () => FieldPB(name: id),
                  )
                  .name,
            )
            .toList();
        buffer.writeln('\nRows (${list.rows.length}):');
        for (final row in list.rows.take(limit)) {
          final cells = [
            for (var i = 0; i < names.length; i++)
              '${names[i]}: ${row.cells.length > i ? row.cells[i] : ''}',
          ];
          buffer.writeln('- (row id: ${row.rowId}) ${cells.join(' | ')}');
        }
      },
      (error) => buffer.writeln('\nThe rows could not be read: ${error.msg}'),
    );

    return AIToolResult(buffer.toString());
  }

  Future<AIToolResult> _addColumn(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    final name = _string(arguments, 'name');
    if (tableId == null || name == null) {
      return const AIToolResult.error('table_id and name are needed.');
    }

    final type = switch (_string(arguments, 'type')) {
      'number' => FieldType.Number,
      'date' => FieldType.DateTime,
      'select' => FieldType.SingleSelect,
      'multi_select' => FieldType.MultiSelect,
      'checkbox' => FieldType.Checkbox,
      'url' => FieldType.URL,
      'checklist' => FieldType.Checklist,
      _ => FieldType.RichText,
    };

    final result = await FieldBackendService.createField(
      viewId: tableId,
      fieldType: type,
      fieldName: name,
    );
    return result.fold(
      (field) => AIToolResult('Added the column "$name".'),
      (error) => AIToolResult.error('The column was not added: ${error.msg}'),
    );
  }

  Future<AIToolResult> _addRow(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    if (tableId == null) {
      return const AIToolResult.error('table_id is needed.');
    }

    final created = await RowBackendService.createRow(viewId: tableId);
    final row = created.fold((meta) => meta, (_) => null);
    if (row == null) {
      return const AIToolResult.error('The row was not added.');
    }

    final cells = arguments['cells'];
    if (cells is! Map || cells.isEmpty) {
      return AIToolResult('Added an empty row (row id: ${row.id}).');
    }

    final written = await _writeCells(tableId, row.id, cells.cast());
    return AIToolResult(
      'Added a row (row id: ${row.id}) and wrote $written cells.',
    );
  }

  Future<int> _writeCells(
    String tableId,
    String rowId,
    Map<dynamic, dynamic> cells,
  ) async {
    final fields = await _fields(tableId);
    var written = 0;
    for (final entry in cells.entries) {
      final column = '${entry.key}'.trim().toLowerCase();
      final field = fields.where(
        (candidate) => candidate.name.trim().toLowerCase() == column,
      );
      if (field.isEmpty) {
        continue;
      }
      final result = await CellBackendService.updateCell(
        viewId: tableId,
        cellContext: CellContext(fieldId: field.first.id, rowId: rowId),
        data: '${entry.value}',
      );
      if (result.isSuccess) {
        written++;
      }
    }
    return written;
  }

  Future<AIToolResult> _updateCell(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    final rowId = _string(arguments, 'row_id');
    final column = _string(arguments, 'column');
    final value = _string(arguments, 'value') ?? '';
    if (tableId == null || rowId == null || column == null) {
      return const AIToolResult.error(
        'table_id, row_id and column are needed.',
      );
    }

    final written = await _writeCells(tableId, rowId, {column: value});
    return written == 0
        ? AIToolResult.error('There is no column called "$column".')
        : const AIToolResult('Wrote that cell.');
  }

  Future<AIToolResult> _createDashboard(Map<String, dynamic> arguments) async {
    final name = _string(arguments, 'name') ?? 'Dashboard';
    final parent = await _resolveParent(arguments);
    final view = await DashboardService.create(
      parentViewId: parent,
      name: name,
    );
    return view == null
        ? const AIToolResult.error('The dashboard was not created.')
        : AIToolResult('Created the dashboard "$name" (id: ${view.id}).');
  }

  // ------------------------------------------------------------- collections

  Future<AIToolResult> _createCollection(Map<String, dynamic> arguments) async {
    final name = _string(arguments, 'name') ?? 'Collection';
    final kindName = _string(arguments, 'kind') ?? 'book';
    final kind = CollectionKind.values.where((k) => k.name == kindName);
    if (kind.isEmpty) {
      return AIToolResult.error('There is no collection kind "$kindName".');
    }

    final parent = await _resolveParent(arguments);
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parent,
      name: name,
      extra: CollectionMetadata.newExtra(kind.first),
    );
    return result.fold(
      (view) =>
          AIToolResult('Created the $kindName "$name" (id: ${view.id}).'),
      (error) =>
          AIToolResult.error('The collection was not created: ${error.msg}'),
    );
  }

  // ------------------------------------------------------------------ blocks

  Future<AIToolResult> _listBlocks(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    if (pageId == null) {
      return const AIToolResult.error('page_id is needed.');
    }
    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be opened.');
    }
    final outline = _blocks.outline(data);
    if (outline.isEmpty) {
      return AIToolResult('That page is empty. Its page block is ${data.pageId}.');
    }
    return AIToolResult(outline.map((block) => block.describe()).join('\n'));
  }

  Future<AIToolResult> _insertBlock(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final type = _string(arguments, 'type');
    if (pageId == null || type == null) {
      return const AIToolResult.error('page_id and type are needed.');
    }

    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be opened.');
    }

    final attributes = <String, dynamic>{
      if (arguments['attributes'] is Map)
        ...(arguments['attributes'] as Map).cast<String, dynamic>(),
    };
    final text = _string(arguments, 'text');
    final node = Node(
      type: type,
      attributes: {
        ...attributes,
        if (text != null)
          'delta': [
            {'insert': text},
          ],
      },
    );

    final after = _string(arguments, 'after_block_id') ??
        _blocks.lastTopLevelBlockId(data);

    final written = await _blocks.insert(
      pageId: pageId,
      nodes: [node],
      parentId: data.pageId,
      previousId: after,
    );
    return written == 0
        ? const AIToolResult.error('The block was not added.')
        : AIToolResult('Added a $type block (id: ${node.id}).');
  }

  Future<AIToolResult> _updateBlock(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final blockId = _string(arguments, 'block_id');
    if (pageId == null || blockId == null) {
      return const AIToolResult.error('page_id and block_id are needed.');
    }

    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be opened.');
    }

    final changed = await _blocks.update(
      pageId: pageId,
      data: data,
      blockId: blockId,
      type: _string(arguments, 'type'),
      text: _string(arguments, 'text'),
      attributes: arguments['attributes'] is Map
          ? (arguments['attributes'] as Map).cast<String, dynamic>()
          : null,
    );
    return changed
        ? const AIToolResult('Changed that block.')
        : const AIToolResult.error('That block could not be changed.');
  }

  Future<AIToolResult> _moveBlock(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final blockId = _string(arguments, 'block_id');
    if (pageId == null || blockId == null) {
      return const AIToolResult.error('page_id and block_id are needed.');
    }
    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be opened.');
    }
    final moved = await _blocks.move(
      pageId: pageId,
      data: data,
      blockId: blockId,
      afterBlockId: _string(arguments, 'after_block_id'),
    );
    return moved
        ? const AIToolResult('Moved that block.')
        : const AIToolResult.error('That block could not be moved.');
  }

  Future<AIToolResult> _deleteBlock(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    final blockId = _string(arguments, 'block_id');
    if (pageId == null || blockId == null) {
      return const AIToolResult.error('page_id and block_id are needed.');
    }
    final data = await _blocks.open(pageId);
    if (data == null) {
      return const AIToolResult.error('That page could not be opened.');
    }
    final removed =
        await _blocks.delete(pageId: pageId, data: data, blockId: blockId);
    return removed
        ? const AIToolResult('Removed that block.')
        : const AIToolResult.error('That block could not be removed.');
  }

  // --------------------------------------------------------------- row pages

  /// The id of the page attached to a row.
  ///
  /// ⚠️ The row only carries the id its page WOULD have; the page itself is
  /// made the first time anybody writes in it.
  Future<String?> _rowPageId(String tableId, String rowId) async {
    final meta = await RowBackendService(viewId: tableId).getRowMeta(rowId);
    return meta.fold(
      (value) => value.documentId.isEmpty ? null : value.documentId,
      (_) => null,
    );
  }

  Future<AIToolResult> _readRowPage(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    final rowId = _string(arguments, 'row_id');
    if (tableId == null || rowId == null) {
      return const AIToolResult.error('table_id and row_id are needed.');
    }

    final pageId = await _rowPageId(tableId, rowId);
    if (pageId == null) {
      return const AIToolResult.error('That row could not be found.');
    }
    return _readPage({'page_id': pageId});
  }

  Future<AIToolResult> _writeRowPage(Map<String, dynamic> arguments) async {
    final tableId = _string(arguments, 'table_id');
    final rowId = _string(arguments, 'row_id');
    final content = _string(arguments, 'content');
    if (tableId == null || rowId == null || content == null) {
      return const AIToolResult.error(
        'table_id, row_id and content are needed.',
      );
    }

    final pageId = await _rowPageId(tableId, rowId);
    if (pageId == null) {
      return const AIToolResult.error('That row could not be found.');
    }

    final result = await _appendToPage({
      'page_id': pageId,
      'content': content,
    });
    if (result.isError) {
      return result;
    }
    // The row remembers whether its page has anything in it.
    await RowBackendService(viewId: tableId)
        .updateMeta(rowId: rowId, isDocumentEmpty: false);
    return const AIToolResult('Wrote into that row\'s page.');
  }

  // -------------------------------------------------------------- decoration

  Future<AIToolResult> _setDecoration(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    if (pageId == null) {
      return const AIToolResult.error('page_id is needed.');
    }
    final view = await _view(pageId);
    if (view == null) {
      return const AIToolResult.error('That page could not be found.');
    }

    var extra = view.extra;
    final coverType = _string(arguments, 'cover_type');
    if (coverType != null) {
      final value = _string(arguments, 'cover_value') ?? '';
      final cover = switch (coverType) {
        'color' => PageStyleCover(
            type: PageStyleCoverImageType.pureColor,
            value: value,
          ),
        'url' => PageStyleCover(
            type: PageStyleCoverImageType.customImage,
            value: value,
          ),
        'builtin' => PageStyleCover(
            type: PageStyleCoverImageType.builtInImage,
            value: value,
          ),
        _ => const PageStyleCover.none(),
      };
      extra = ViewCoverCodec.mergeCover(extra, cover);
    }

    final updated =
        await ViewBackendService.updateView(viewId: pageId, extra: extra);
    if (updated.isFailure) {
      return const AIToolResult.error('The cover was not changed.');
    }

    final icon = _string(arguments, 'icon');
    if (icon != null) {
      await ViewBackendService.updateViewIcon(
        view: view,
        viewIcon: EmojiIconData.emoji(icon),
      );
    }
    return const AIToolResult('Changed how that page is decorated.');
  }

  // ------------------------------------------------------------------- files

  Future<AIToolResult> _readFile(Map<String, dynamic> arguments) async {
    final pageId = _string(arguments, 'page_id');
    if (pageId == null) {
      return const AIToolResult.error('page_id is needed.');
    }
    final limit = (arguments['limit'] is num)
        ? (arguments['limit'] as num).toInt().clamp(200, 60000)
        : 8000;

    final view = await _view(pageId);
    final source = view?.workspaceItem?.storageUrl ?? '';
    if (view == null || source.isEmpty) {
      return const AIToolResult.error(
        'That is not a file. Use read_page for a page.',
      );
    }

    final text = await readWorkspaceFileText(
      source: source,
      name: view.nameOrDefault,
      limit: limit,
    );
    if (text == null) {
      return AIToolResult.error(
        'AppFlowy cannot read the text of "${view.nameOrDefault}".',
      );
    }
    return AIToolResult(text.isEmpty ? 'That file has no text in it.' : text);
  }

  // --------------------------------------------------------------- reminders

  Future<AIToolResult> _listReminders(Map<String, dynamic> arguments) async {
    final store = ReminderStore.instance;
    await store.refresh();
    final includeDone = arguments['include_done'] == true;

    final reminders = store.reminders
        .where((reminder) => includeDone || !reminder.isDone)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    if (reminders.isEmpty) {
      return const AIToolResult('There are no reminders.');
    }
    return AIToolResult(
      reminders
          .map(
            (reminder) => '- ${reminder.title} '
                '(id: ${reminder.id}, ${reminder.scheduledAt.toIso8601String()}'
                '${reminder.isDone ? ', done' : ''})',
          )
          .join('\n'),
    );
  }

  Future<AIToolResult> _addReminder(Map<String, dynamic> arguments) async {
    final title = _string(arguments, 'title');
    final when = DateTime.tryParse(_string(arguments, 'when') ?? '');
    if (title == null || when == null) {
      return const AIToolResult.error(
        'title and an ISO 8601 "when" are needed.',
      );
    }

    final created = await ReminderStore.instance.create(
      AppReminder(
        id: nanoid(10),
        title: title,
        message: _string(arguments, 'message') ?? '',
        scheduledAt: when,
        objectId: _string(arguments, 'page_id') ?? '',
        pageId: _string(arguments, 'page_id') ?? '',
      ),
    );
    return created == null
        ? const AIToolResult.error('The reminder was not set.')
        : AIToolResult('Set a reminder for ${when.toIso8601String()}.');
  }

  Future<AIToolResult> _completeReminder(Map<String, dynamic> arguments) async {
    final id = _string(arguments, 'reminder_id');
    if (id == null) {
      return const AIToolResult.error('reminder_id is needed.');
    }
    final store = ReminderStore.instance;
    await store.refresh();
    final reminder = store.reminders.where((entry) => entry.id == id);
    if (reminder.isEmpty) {
      return const AIToolResult.error('There is no reminder with that id.');
    }
    await store.complete(reminder.first);
    return const AIToolResult('Marked it done.');
  }

  Future<AIToolResult> _deleteReminder(Map<String, dynamic> arguments) async {
    final id = _string(arguments, 'reminder_id');
    if (id == null) {
      return const AIToolResult.error('reminder_id is needed.');
    }
    final removed = await ReminderStore.instance.remove(id);
    return removed
        ? const AIToolResult('Removed that reminder.')
        : const AIToolResult.error('That reminder could not be removed.');
  }
}
