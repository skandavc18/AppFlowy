import 'dart:io';

import 'package:appflowy/ai/skills/ai_skill.dart';
import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/ai/tools/mcp_server_config.dart';
import 'package:appflowy/ai/tools/tool_permissions.dart';
import 'package:appflowy/ai/tools/workspace_tools.dart';
import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('naming a tool', () {
    test('a qualified name survives a round trip', () {
      const tool = AITool(
        serverId: 'appflowy',
        serverLabel: 'AppFlowy',
        name: 'create_page',
        description: '',
        schema: {},
      );

      expect(tool.qualifiedName, 'appflowy__create_page');
      expect(AITool.split(tool.qualifiedName), ('appflowy', 'create_page'));
    });

    test('a name with nothing either side is refused', () {
      expect(AITool.split('create_page'), isNull);
      expect(AITool.split('__create_page'), isNull);
      expect(AITool.split('appflowy__'), isNull);
    });
  });

  group('what the workspace offers', () {
    test('every tool declares an object schema and a risk', () async {
      final tools = await WorkspaceToolServer().listTools();

      expect(tools, isNotEmpty);
      for (final tool in tools) {
        expect(tool.serverId, WorkspaceToolServer.serverId);
        expect(tool.description, isNotEmpty);
        expect(tool.schema['type'], 'object');
      }
    });

    test('reading is never asked about and deleting always is', () async {
      final tools = await WorkspaceToolServer().listTools();
      final byName = {for (final tool in tools) tool.name: tool};

      expect(byName['list_pages']!.risk, AIToolRisk.read);
      expect(byName['read_page']!.risk, AIToolRisk.read);
      expect(byName['describe_table']!.risk, AIToolRisk.read);
      expect(byName['list_blocks']!.risk, AIToolRisk.read);
      expect(byName['read_row_page']!.risk, AIToolRisk.read);
      expect(byName['read_file']!.risk, AIToolRisk.read);
      expect(byName['list_reminders']!.risk, AIToolRisk.read);
      expect(byName['delete_item']!.risk, AIToolRisk.destructive);
      expect(byName['delete_block']!.risk, AIToolRisk.destructive);
      expect(byName['delete_reminder']!.risk, AIToolRisk.destructive);
      expect(byName['create_page']!.risk, AIToolRisk.write);
    });

    test('there is a tool for every part of a workspace', () async {
      final tools = await WorkspaceToolServer().listTools();
      final names = tools.map((tool) => tool.name).toSet();

      expect(
        names,
        containsAll([
          // pages and their contents
          'create_page', 'append_to_page', 'list_blocks', 'insert_block',
          'update_block', 'move_block', 'delete_block',
          // tables, their readings and their row pages
          'create_table', 'create_table_view', 'add_column', 'add_row',
          'update_cell', 'read_row_page', 'write_row_page',
          // everything else a workspace holds
          'create_folder', 'create_file', 'create_collection',
          'create_dashboard', 'set_page_decoration', 'read_file',
          'add_reminder',
        ]),
      );
    });

    test('every page a tool writes to is opened first', () {
      // The backend hands back a throwaway copy for getDocument and only lets
      // an *opened* document be edited, so a page that reads perfectly well
      // refuses every write with "Call open document first". That failure
      // arrives as a block silently never appearing, so it is pinned here.
      final toolkit = File(
        'lib/ai/tools/document_toolkit.dart',
      ).readAsStringSync();
      expect(toolkit, contains('openDocument(documentId: pageId)'));
      expect(toolkit, isNot(contains('getDocument(documentId: pageId)')));

      final tools =
          File('lib/ai/tools/workspace_tools.dart').readAsStringSync();
      expect(tools, isNot(contains('getDocument(')));
    });

    test('the block tool names the types it can insert', () async {
      final tools = await WorkspaceToolServer().listTools();
      final insert = tools.firstWhere((tool) => tool.name == 'insert_block');

      // An agent cannot guess a block type, so they are spelled out.
      for (final type in const [
        'heading',
        'code',
        'image',
        'video',
        'mermaid',
        'mind_map',
        'drawing',
        'spreadsheet',
        'grid',
        'page',
      ]) {
        expect(insert.description, contains(type));
      }
    });

    test('a tool nobody has heard of is refused, not guessed at', () async {
      final result = await WorkspaceToolServer().call('summon_a_pony', {});

      expect(result.isError, isTrue);
      expect(result.text, contains('summon_a_pony'));
    });
  });

  group('who may do what', () {
    late AIToolPermissionStore permissions;

    const reader = AITool(
      serverId: 'appflowy',
      serverLabel: 'AppFlowy',
      name: 'list_pages',
      description: '',
      schema: {},
      risk: AIToolRisk.read,
    );
    const remover = AITool(
      serverId: 'appflowy',
      serverLabel: 'AppFlowy',
      name: 'delete_item',
      description: '',
      schema: {},
      risk: AIToolRisk.destructive,
    );

    setUp(() {
      permissions = AIToolPermissionStore(storage: _MemoryKeyValue());
    });

    test('reading never has to ask', () {
      expect(
        permissions.isAllowedWithoutAsking(reader, chatId: 'c1'),
        isTrue,
      );
    });

    test('deleting asks until it is answered', () async {
      expect(
        permissions.isAllowedWithoutAsking(remover, chatId: 'c1'),
        isFalse,
      );

      await permissions.remember(remover, AIToolPermission.allow);
      expect(
        permissions.isAllowedWithoutAsking(remover, chatId: 'c1'),
        isTrue,
      );

      await permissions.remember(remover, AIToolPermission.deny);
      expect(
        permissions.isAllowedWithoutAsking(remover, chatId: 'c1'),
        isFalse,
      );
    });

    test('allowing everything applies to that chat only', () {
      permissions.grantForChat('c1');

      expect(permissions.isAllowedWithoutAsking(remover, chatId: 'c1'), isTrue);
      expect(
        permissions.isAllowedWithoutAsking(remover, chatId: 'c2'),
        isFalse,
      );

      permissions.endChat('c1');
      expect(
        permissions.isAllowedWithoutAsking(remover, chatId: 'c1'),
        isFalse,
      );
    });

    test('a refusal outlasts a chat-wide yes', () async {
      await permissions.remember(remover, AIToolPermission.deny);
      permissions.grantForChat('c1');

      expect(
        permissions.isAllowedWithoutAsking(remover, chatId: 'c1'),
        isFalse,
      );
    });
  });

  group('describing an MCP server', () {
    test('a command line splits, keeping a quoted path whole', () {
      final (command, args) = McpServerConfig.parseCommandLine(
        'npx -y server "C:\\My Notes"',
      );

      expect(command, 'npx');
      expect(args, ['-y', 'server', r'C:\My Notes']);
    });

    test('an empty command line yields nothing rather than a blank name', () {
      final (command, args) = McpServerConfig.parseCommandLine('   ');

      expect(command, isEmpty);
      expect(args, isEmpty);
    });

    test('a stranger tool is treated as a change unless it was named', () {
      const config = McpServerConfig(
        id: 's1',
        name: 'Files',
        readOnlyTools: ['read_file'],
        destructiveTools: ['remove_file'],
      );

      expect(config.riskFor('read_file'), AIToolRisk.read);
      expect(config.riskFor('remove_file'), AIToolRisk.destructive);
      expect(config.riskFor('write_file'), AIToolRisk.write);
    });

    test('a server survives being written down and read back', () {
      const config = McpServerConfig(
        id: 's1',
        name: 'Files',
        command: 'npx',
        args: ['-y', 'server'],
        env: {'TOKEN': 'x'},
        destructiveTools: ['remove_file'],
      );

      final restored = McpServerConfig.fromJson(config.toJson());

      expect(restored.name, 'Files');
      expect(restored.command, 'npx');
      expect(restored.args, ['-y', 'server']);
      expect(restored.env, {'TOKEN': 'x'});
      expect(restored.destructiveTools, ['remove_file']);
      expect(restored.transport, McpTransport.stdio);
    });
  });

  group('skills', () {
    test('one with no keywords always applies', () {
      const skill = AISkill(
        id: 's',
        name: 'Always',
        description: '',
        instructions: 'be careful',
      );

      expect(skill.matches('anything at all'), isTrue);
    });

    test('one with keywords waits to be asked for', () {
      const skill = AISkill(
        id: 's',
        name: 'Tables',
        description: '',
        instructions: 'build tables',
        keywords: ['table', 'track'],
      );

      expect(skill.matches('make me a TABLE of costs'), isTrue);
      expect(skill.matches('write a poem'), isFalse);
    });

    test('the built-in skills are complete enough to be followed', () {
      expect(builtInSkills, isNotEmpty);
      for (final skill in builtInSkills) {
        expect(skill.isBuiltIn, isTrue);
        expect(skill.name, isNotEmpty);
        expect(skill.description, isNotEmpty);
        expect(skill.instructions.trim(), isNotEmpty);
      }
    });

    test('only the skills that suit the request are laid out', () async {
      final store = AISkillStore(storage: _MemoryKeyValue());
      await store.ensureLoaded();

      final forTables = store.instructionsFor('make a table of expenses');
      expect(forTables, contains('Build a table'));
      expect(forTables, isNot(contains('Report on a table')));

      // A skill with no keywords is always there to hold the rest in check.
      expect(
        store.instructionsFor('hello'),
        contains('Change things carefully'),
      );
    });

    test('a built-in skill can be turned off and stays off', () async {
      final store = AISkillStore(storage: _MemoryKeyValue());
      await store.ensureLoaded();
      final careful = store.skills.firstWhere(
        (skill) => skill.id == 'builtin_careful_changes',
      );

      await store.setEnabled(careful, false);

      expect(
        store.enabledSkills.map((skill) => skill.id),
        isNot(contains('builtin_careful_changes')),
      );
      expect(store.instructionsFor('hello'), isEmpty);
    });

    test('a skill written by hand joins the built-in ones', () async {
      final store = AISkillStore(storage: _MemoryKeyValue());
      final saved = await store.upsert(
        const AISkill(
          id: '',
          name: 'House style',
          description: 'How we write',
          instructions: 'Short sentences.',
        ),
      );

      expect(saved.id, isNotEmpty);
      expect(store.skills.last.name, 'House style');
      expect(store.instructionsFor('anything'), contains('House style'));
    });

    test('the table skill explains that a row has a page of its own', () {
      final table = builtInSkills.firstWhere(
        (skill) => skill.id == 'builtin_build_table',
      );

      // A row page does not exist until it is written in, which read as a
      // permission failure until it was said out loud.
      expect(table.instructions, contains('write_row_page'));
      expect(table.instructions, contains('is not an error'));
    });
  });

  group('what is selected in the chat', () {
    setUp(() => ChatTextSelection.instance.report(''));

    test('nothing selected means nothing to copy', () async {
      expect(ChatTextSelection.instance.hasSelection, isFalse);
      expect(await ChatTextSelection.instance.copy(), isFalse);
    });

    test('whitespace alone is not a selection', () {
      ChatTextSelection.instance.report('   \n ');
      expect(ChatTextSelection.instance.hasSelection, isFalse);
    });

    test('the last thing selected is the one that would be copied', () {
      // The question and the answer use different selection systems; whichever
      // was used last is what Ctrl+C means.
      ChatTextSelection.instance.report('from the question');
      ChatTextSelection.instance.report('from the answer');

      expect(ChatTextSelection.instance.text, 'from the answer');
      expect(ChatTextSelection.instance.hasSelection, isTrue);
    });

    test('it tells its listeners only when the selection really changed', () {
      var notified = 0;
      void count() => notified++;
      ChatTextSelection.instance.addListener(count);

      ChatTextSelection.instance.report('hello');
      ChatTextSelection.instance.report('hello');
      ChatTextSelection.instance.report('goodbye');

      ChatTextSelection.instance.removeListener(count);
      expect(notified, 2);
    });
  });
}

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = await get(key);
    return value == null ? null : formatter(value);
  }
}
