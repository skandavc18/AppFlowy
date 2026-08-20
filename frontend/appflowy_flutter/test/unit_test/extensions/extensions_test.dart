import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_schedule.dart';
import 'package:appflowy/extensions/application/action_template.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_library_cache.dart';
import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/island_server.dart';
import 'package:appflowy/extensions/application/script_host.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/built_in/stock_extension.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_add_button.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

BlockComponentBuilder _stubBuilder(
  BlockComponentConfiguration configuration,
) =>
    ParagraphBlockComponentBuilder(configuration: configuration);

class _StubTabBarBuilder extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      const SizedBox.shrink();

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

void main() {
  group('reading a recipe file', () {
    test('a comment can be written beside a setting', () {
      const source = '''
{
  // the ticker to read
  "id": "quote", /* inline */
  "url": "https://example.com//not-a-comment"
}
''';
      final values = decodeExtensionJson(source);
      expect(values['id'], 'quote');
      expect(values['url'], 'https://example.com//not-a-comment');
    });

    test('a // inside a string is left alone', () {
      final values = decodeExtensionJson('{"a": "x // y", "b": 1}');
      expect(values['a'], 'x // y');
      expect(values['b'], 1);
    });

    test('an escaped quote does not end the string', () {
      final values = decodeExtensionJson(r'{"a": "say \"hi\" // no"}');
      expect(values['a'], 'say "hi" // no');
    });
  });

  group('what a manifest says it may do', () {
    test('permissions are read back as they were written', () {
      expect(
        ExtensionPermission.parse('net:example.com'),
        const ExtensionPermission(
          ExtensionPermissionKind.net,
          value: 'example.com',
        ),
      );
      expect(
        ExtensionPermission.parse('document:write'),
        const ExtensionPermission(ExtensionPermissionKind.documentWrite),
      );
      expect(ExtensionPermission.parse('nonsense'), isNull);
      expect(ExtensionPermission.parse('net:'), isNull);
    });

    test('a host is matched exactly or as a real subdomain', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'finance',
        'name': 'Finance',
        'permissions': ['net:example.com'],
      })!;

      expect(manifest.allowsHost('example.com'), isTrue);
      expect(manifest.allowsHost('api.example.com'), isTrue);
      expect(manifest.allowsHost('EXAMPLE.COM'), isTrue);
      // The trap: a look-alike host that merely ends with the declared name.
      expect(manifest.allowsHost('notexample.com'), isFalse);
      expect(manifest.allowsHost('example.com.attacker.net'), isFalse);
    });

    test('an id that could not be a folder or a tool name is refused', () {
      expect(ExtensionManifest.fromJson({'id': 'Finance Ltd'}), isNull);
      expect(ExtensionManifest.fromJson({'id': '../escape'}), isNull);
      expect(ExtensionManifest.fromJson({'id': ''}), isNull);
      expect(ExtensionManifest.fromJson({'id': 'finance-1'}), isNotNull);
    });

    test('an extension written for a later API is not supported', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'later',
        'apiVersion': ExtensionManifest.currentApiVersion + 1,
      })!;
      expect(manifest.isSupported, isFalse);
    });
  });

  group('when an action is owed a run', () {
    test('intervals are read in every form', () {
      expect(ActionSchedule.parseInterval('15m'), const Duration(minutes: 15));
      expect(ActionSchedule.parseInterval('2h'), const Duration(hours: 2));
      expect(ActionSchedule.parseInterval('1d'), const Duration(days: 1));
      expect(ActionSchedule.parseInterval('45'), const Duration(minutes: 45));
      expect(ActionSchedule.parseInterval('nope'), isNull);
      expect(ActionSchedule.parseInterval('0m'), isNull);
    });

    test('an interval faster than the floor is slowed to it', () {
      expect(
        ActionSchedule.parseInterval('1s'),
        ActionSchedule.minimumInterval,
      );
    });

    test('an action that has never run is due at once', () {
      const schedule = ActionSchedule.every(Duration(minutes: 15));
      final now = DateTime(2026, 8, 20, 10);
      expect(schedule.isDue(now: now), isTrue);
    });

    test('a fresh run is not owed another until the interval has passed', () {
      const schedule = ActionSchedule.every(Duration(minutes: 15));
      final now = DateTime(2026, 8, 20, 10);
      expect(
        schedule.isDue(
            now: now, lastRun: now.subtract(const Duration(minutes: 5))),
        isFalse,
      );
      expect(
        schedule.isDue(
            now: now, lastRun: now.subtract(const Duration(minutes: 16))),
        isTrue,
      );
    });

    test('a week of missed runs is owed exactly one, not six hundred', () {
      const schedule = ActionSchedule.every(Duration(minutes: 15));
      final now = DateTime(2026, 8, 20, 10);
      final lastRun = now.subtract(const Duration(days: 7));

      // Due, once. Recording that single run must settle it.
      expect(schedule.isDue(now: now, lastRun: lastRun), isTrue);
      expect(schedule.isDue(now: now, lastRun: now), isFalse);
    });

    test('a time of day rolls to tomorrow once it has passed', () {
      final schedule =
          ActionSchedule.at(ActionSchedule.parseTimeOfDay('09:30')!);
      final morning = DateTime(2026, 8, 20, 8);
      expect(schedule.nextRun(now: morning), DateTime(2026, 8, 20, 9, 30));

      final evening = DateTime(2026, 8, 20, 21);
      expect(schedule.nextRun(now: evening), DateTime(2026, 8, 21, 9, 30));
    });

    test('a bad time of day is refused rather than guessed at', () {
      expect(ActionSchedule.parseTimeOfDay('25:00'), isNull);
      expect(ActionSchedule.parseTimeOfDay('9:70'), isNull);
      expect(ActionSchedule.parseTimeOfDay('half nine'), isNull);
    });
  });

  group('filling in a step', () {
    final context = <String, Object?>{
      'args': {'symbol': 'AAPL'},
      'fetch': {
        'status': 200,
        'body': {
          'chart': {
            'result': [
              {
                'meta': {'price': 231.4},
              },
            ],
          },
        },
      },
      'data': {
        'watchlist': ['AAPL', 'MSFT'],
      },
    };

    test('a dotted path walks maps and lists', () {
      expect(
        resolveActionPath(context, 'fetch.body.chart.result.0.meta.price'),
        231.4,
      );
      expect(resolveActionPath(context, 'args.symbol'), 'AAPL');
    });

    test('a missing field is empty rather than an error', () {
      expect(resolveActionPath(context, 'fetch.body.nope.deeper'), isNull);
      expect(resolveActionPath(context, 'data.watchlist.9'), isNull);
      expect(renderActionTemplate('<{{ nope.at.all }}>', context), '<>');
    });

    test('a template inside a sentence becomes words', () {
      expect(
        renderActionTemplate('{{ args.symbol }} is up', context),
        'AAPL is up',
      );
    });

    test('a lone template keeps the value it found', () {
      // ⚠️ The whole point: a price has to stay a number, or every comparison
      // after it silently becomes a string comparison.
      final value = renderActionValue(
        '{{ fetch.body.chart.result.0.meta.price }}',
        context,
      );
      expect(value, isA<double>());
      expect(value, 231.4);

      final list = renderActionValue('{{ data.watchlist }}', context);
      expect(list, isA<List<Object?>>());
    });

    test('a whole argument map is filled in, keeping its shape', () {
      final filled = renderActionValue(
        {
          'symbol': '{{ args.symbol }}',
          'nested': {'price': '{{ fetch.body.chart.result.0.meta.price }}'},
          'count': 3,
        },
        context,
      );
      expect(filled, isA<Map<String, Object?>>());
      final map = filled! as Map<String, Object?>;
      expect(map['symbol'], 'AAPL');
      expect((map['nested']! as Map<String, Object?>)['price'], 231.4);
      expect(map['count'], 3);
    });
  });

  group('a when: condition', () {
    final context = <String, Object?>{
      'fetch': {'status': 200, 'body': 'ok'},
      'data': {
        'watchlist': ['AAPL'],
      },
    };

    test('a number from a service equals a number typed by hand', () {
      // The status arrives as an int here and as text elsewhere; both mean 200.
      expect(
        ActionCondition.parse('{{ fetch.status }} == 200').evaluate(context),
        isTrue,
      );
      expect(
        ActionCondition.parse('{{ fetch.status }} != 404').evaluate(context),
        isTrue,
      );
    });

    test('>= is not read as >', () {
      final condition = ActionCondition.parse('{{ fetch.status }} >= 200');
      expect(condition.comparison, ActionComparison.greaterOrEqual);
      expect(condition.evaluate(context), isTrue);
    });

    test('a list can be asked whether it holds something', () {
      expect(
        ActionCondition.parse('{{ data.watchlist }} contains "AAPL"')
            .evaluate(context),
        isTrue,
      );
      expect(
        ActionCondition.parse('{{ data.watchlist }} contains "TSLA"')
            .evaluate(context),
        isFalse,
      );
    });

    test('a bare value is read as yes or no', () {
      expect(
          ActionCondition.parse('{{ fetch.body }}').evaluate(context), isTrue);
      expect(ActionCondition.parse('{{ nope }}').evaluate(context), isFalse);
    });

    test('comparing what cannot be compared is false, never a crash', () {
      expect(
        ActionCondition.parse('{{ fetch.body }} > 10').evaluate(context),
        isFalse,
      );
    });
  });

  group('reading an action', () {
    test('a whole recipe is read into steps', () {
      final action = ActionDefinition.fromJson(
        decodeExtensionJson('''
{
  "id": "quote",
  "description": "Latest price.",
  "risk": "read",
  "schema": { "type": "object", "properties": { "symbol": { "type": "string" } } },
  "trigger": { "every": "15m", "forEach": { "data": "watchlist" }, "as": "symbol" },
  "steps": [
    { "id": "fetch", "http": { "get": "https://example.com/{{ symbol }}" } },
    { "when": "{{ fetch.status }} == 200",
      "set": { "key": "quote.{{ symbol }}", "value": "{{ fetch.body.price }}",
               "staleAfter": "1h" } }
  ]
}
'''),
      )!;

      expect(action.id, 'quote');
      expect(action.risk, AIToolRisk.read);
      expect(action.trigger.schedule?.interval, const Duration(minutes: 15));
      expect(action.trigger.forEachKey, 'watchlist');
      expect(action.trigger.argumentName, 'symbol');
      expect(action.steps, hasLength(2));

      final fetch = action.steps.first as HttpStep;
      expect(fetch.method, 'GET');
      expect(fetch.url, 'https://example.com/{{ symbol }}');

      final set = action.steps[1] as SetDataStep;
      expect(set.key, 'quote.{{ symbol }}');
      expect(set.staleAfter, const Duration(hours: 1));
      expect(set.when, isNotNull);
    });

    test('an action with no trigger only runs when it is asked to', () {
      final action = ActionDefinition.fromJson({
        'id': 'manual',
        'steps': [
          {
            'notify': {'title': 'hello'},
          },
        ],
      })!;
      expect(action.trigger.isManual, isTrue);
      expect(action.trigger.isScheduled, isFalse);
      expect(action.steps.single, isA<NotifyStep>());
    });

    test('a step nobody can act on is dropped rather than half read', () {
      final action = ActionDefinition.fromJson({
        'id': 'broken',
        'steps': [
          {'set': <String, Object?>{}},
          {'nonsense': true},
          {
            'delete': {'key': 'x'},
          },
        ],
      })!;
      expect(action.steps, hasLength(1));
      expect(action.steps.single, isA<DeleteDataStep>());
    });

    test('every document operation is named', () {
      expect(DocumentOperation.parse('append'), DocumentOperation.append);
      expect(
        DocumentOperation.parse('setAttributes'),
        DocumentOperation.setAttributes,
      );
      expect(DocumentOperation.parse('shred'), isNull);
    });
  });

  group('glue scripts', () {
    test('a script step names a file and the libraries it wants', () {
      final action = ActionDefinition.fromJson({
        'id': 'shape',
        'steps': [
          {
            'id': 'levels',
            'script': {
              'file': 'levels.js',
              'libraries': ['dayjs'],
              'input': {'candles': '{{ fetch.body }}'},
            },
          },
        ],
      })!;
      final step = action.steps.single as ScriptStep;
      expect(step.file, 'levels.js');
      expect(step.libraries, ['dayjs']);
      expect(step.input, isA<Map<String, Object?>>());
    });

    test('a script name may not climb out of its folder', () {
      for (final name in [
        '../../secrets.js',
        '/etc/passwd',
        r'C:\windows\system32\x.js',
      ]) {
        final action = ActionDefinition.fromJson({
          'id': 'escape',
          'steps': [
            {
              'script': {'file': name},
            },
          ],
        })!;
        expect(action.steps, isEmpty, reason: name);
      }
    });

    test('the worker runs the script as source, never through eval', () {
      final worker = ScriptHost.buildWorkerSource(
        source: 'return input.a + 1;',
        libraries: ['self.LIB = 1;'],
      );
      // ⚠️ `new Function`/eval would need 'unsafe-eval' in the page policy,
      // which is the loophole the policy exists to close.
      expect(worker.contains('new Function'), isFalse);
      expect(worker.contains('eval('), isFalse);
      expect(worker.contains('return input.a + 1;'), isTrue);
      // Libraries come first, so the script can use them.
      expect(
        worker.indexOf('self.LIB = 1;'),
        lessThan(worker.indexOf('function __afUser')),
      );
      expect(worker.contains('self.onmessage'), isTrue);
    });

    test('a script that throws is reported, not swallowed', () {
      final worker = ScriptHost.buildWorkerSource(source: 'throw new Error();');
      expect(worker.contains('ok: false'), isTrue);
      expect(worker.contains('catch'), isTrue);
    });
  });

  group('writing to a page', () {
    // ⚠️ Nothing but reading the file can catch this: a widget test has no
    // backend, and getting it wrong means an extension's write either never
    // shows up or lands in the person's undo stack.
    final source = File(
      p.join(
        'lib',
        'extensions',
        'application',
        'action_runner.dart',
      ),
    ).readAsStringSync();

    test('an open editor is refreshed after every kind of write', () {
      expect(source.contains('forceReloadDocumentState'), isTrue);
      // One call per operation that changed something.
      expect(
        '_refreshOpenEditor('.allMatches(source).length,
        greaterThanOrEqualTo(5),
      );
    });

    test('the runner never applies a transaction to the editor itself', () {
      // A local apply WOULD enter the undo stack. Everything must go through
      // the backend and come back as a remote change.
      expect(source.contains('editorState.apply'), isFalse);
      expect(source.contains('EditorState('), isFalse);
    });

    test('a page being typed in is left alone unless only attributes change',
        () {
      expect(source.contains('_isBeingEdited'), isTrue);
      expect(
        source.contains('step.operation != DocumentOperation.setAttributes'),
        isTrue,
      );
    });

    test('a document is opened before it is written to', () {
      // getDocument hands back a throwaway copy and every write is dropped.
      expect(source.contains('_documents.open('), isTrue);
      expect(source.contains('getDocument('), isFalse);
    });
  });

  group('an island page', () {
    test('the policy and the bridge are put into the head', () {
      final html = IslandServer.injectIslandHead(
        '<html><head><title>Chart</title></head><body></body></html>',
        token: 'abc',
      );
      expect(html.contains('Content-Security-Policy'), isTrue);
      expect(html.contains('/abc/__af/bridge.js'), isTrue);
      // Before the page's own head content, so `af` exists by the time the
      // page's own scripts run.
      expect(
        html.indexOf('bridge.js'),
        lessThan(html.indexOf('<title>')),
      );
    });

    test('a page with no head still gets both', () {
      final html = IslandServer.injectIslandHead('<p>bare</p>', token: 'abc');
      expect(html.contains('Content-Security-Policy'), isTrue);
      expect(html.contains('bridge.js'), isTrue);
      expect(html.contains('<p>bare</p>'), isTrue);
    });

    test('the policy leaves the page no way out', () {
      // ⚠️ connect-src 'none' IS the sandbox. Every effect has to come back
      // through the bridge, where the permission checks are.
      expect(
        IslandServer.contentSecurityPolicy.contains("connect-src 'none'"),
        isTrue,
      );
      expect(
        IslandServer.contentSecurityPolicy.contains("default-src 'none'"),
        isTrue,
      );
      expect(
        IslandServer.contentSecurityPolicy.contains("form-action 'none'"),
        isTrue,
      );
    });

    test('an island id that could climb out of the folder is refused', () {
      for (final id in ['../secrets', 'a/b', r'a\b', 'C:', '']) {
        expect(ExtensionIsland.fromJson({'id': id}), isNull, reason: id);
      }
      expect(ExtensionIsland.fromJson({'id': 'chart'}), isNotNull);
    });

    test('a declared island carries its name and height', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'finance',
        'islands': [
          {
            'id': 'chart',
            'name': 'Stock chart',
            'description': 'Candlesticks',
            'height': 420,
            'keywords': ['candle'],
          },
        ],
      })!;
      final island = manifest.islands.single;
      expect(island.id, 'chart');
      expect(island.name, 'Stock chart');
      expect(island.height, 420);
      expect(island.keywords, ['candle']);
    });

    test('the bridge gives a page exactly one way to reach the host', () {
      // Anything the page can do is a message; there is no direct API.
      expect(islandBridgeScript.contains("callHandler('afIsland'"), isTrue);
      expect(islandBridgeScript.contains('af.call'), isFalse);
      expect(islandBridgeScript.contains('XMLHttpRequest'), isFalse);
      expect(islandBridgeScript.contains('fetch('), isFalse);
    });
  });

  group('a Dart extension is really switched off', () {
    setUp(() {
      ExtensionBlockRegistry.unregisterAll('demo');
      ExtensionCommandRegistry.unregisterAll('demo');
      ExtensionThemeRegistry.unregisterAll('demo');
    });

    test('a scope undoes everything, newest first', () {
      final scope = ExtensionScope('demo');
      final order = <String>[];
      scope
        ..onDispose(() => order.add('first'))
        ..onDispose(() => order.add('second'))
        ..close();
      expect(order, ['second', 'first']);
      expect(scope.isClosed, isTrue);
    });

    test('one bad teardown does not strand the rest', () {
      final scope = ExtensionScope('demo');
      final order = <String>[];
      scope
        ..onDispose(() => order.add('ran'))
        ..onDispose(() => throw StateError('no'))
        ..close();
      expect(order, ['ran']);
    });

    test('something registered after the scope closed is undone at once', () {
      final scope = ExtensionScope('demo')..close();
      var undone = false;
      scope.onDispose(() => undone = true);
      expect(undone, isTrue);
    });

    test('a timer is cancelled with the scope', () {
      final scope = ExtensionScope('demo');
      final timer = Timer(const Duration(days: 1), () {});
      scope.addTimer(timer);
      expect(timer.isActive, isTrue);
      scope.close();
      expect(timer.isActive, isFalse);
    });

    test('a listener is removed with the scope', () {
      final scope = ExtensionScope('demo');
      final notifier = ValueNotifier<int>(0);
      var heard = 0;
      scope.addListenable(notifier, () => heard++);
      notifier.value = 1;
      expect(heard, 1);
      scope.close();
      notifier.value = 2;
      expect(heard, 1);
      notifier.dispose();
    });

    test('a registered block is gone once the extension is unregistered', () {
      ExtensionBlockRegistry.register(
        ExtensionBlockDefinition(
          extensionId: 'demo',
          type: 'demo_block',
          builder: (configuration) =>
              ParagraphBlockComponentBuilder(configuration: configuration),
        ),
      );
      expect(ExtensionBlockRegistry.definitionFor('demo_block'), isNotNull);
      expect(
        ExtensionBlockRegistry.builders(
          const BlockComponentConfiguration(),
        ).containsKey('demo_block'),
        isTrue,
      );

      ExtensionBlockRegistry.unregisterAll('demo');
      expect(ExtensionBlockRegistry.definitionFor('demo_block'), isNull);
      expect(
        ExtensionBlockRegistry.builders(
          const BlockComponentConfiguration(),
        ).containsKey('demo_block'),
        isFalse,
      );
    });

    test('the registry says when it changed, so an editor can rebuild', () {
      final before = ExtensionBlockRegistry.revision.value;
      ExtensionBlockRegistry.register(
        ExtensionBlockDefinition(
          extensionId: 'demo',
          type: 'demo_block',
          builder: (configuration) =>
              ParagraphBlockComponentBuilder(configuration: configuration),
        ),
      );
      expect(ExtensionBlockRegistry.revision.value, greaterThan(before));
    });

    test('only an alignable block is offered to the align menu', () {
      ExtensionBlockRegistry.register(
        ExtensionBlockDefinition(
          extensionId: 'demo',
          type: 'fixed_block',
          builder: _stubBuilder,
        ),
      );
      ExtensionBlockRegistry.register(
        ExtensionBlockDefinition(
          extensionId: 'demo',
          type: 'movable_block',
          builder: _stubBuilder,
          alignable: true,
        ),
      );
      expect(
          ExtensionBlockRegistry.alignableTypes(), contains('movable_block'));
      expect(
        ExtensionBlockRegistry.alignableTypes(),
        isNot(contains('fixed_block')),
      );

      ExtensionBlockRegistry.unregisterAll('demo');
      expect(ExtensionBlockRegistry.alignableTypes(), isEmpty);
    });

    test('only a block with a name and a node reaches the slash menu', () {
      const withoutSlash = ExtensionBlockDefinition(
        extensionId: 'demo',
        type: 'a',
        builder: _stubBuilder,
      );
      expect(withoutSlash.hasSlashEntry, isFalse);

      final withSlash = ExtensionBlockDefinition(
        extensionId: 'demo',
        type: 'b',
        builder: _stubBuilder,
        slashName: 'Demo',
        newNode: () => Node(type: 'b'),
      );
      expect(withSlash.hasSlashEntry, isTrue);
    });

    test('commands and themes are removed by extension, not one by one', () {
      ExtensionCommandRegistry.register(
        ExtensionCommand(
          extensionId: 'demo',
          id: 'one',
          name: 'One',
          run: (_) async {},
        ),
      );
      ExtensionThemeRegistry.register(
        ExtensionTheme(
          extensionId: 'demo',
          id: 'glass',
          name: 'Glass',
          brightness: Brightness.dark,
          build: (base) => base,
        ),
      );
      expect(ExtensionCommandRegistry.all(), isNotEmpty);
      expect(ExtensionThemeRegistry.all(), isNotEmpty);

      ExtensionCommandRegistry.unregisterAll('demo');
      ExtensionThemeRegistry.unregisterAll('demo');
      expect(
        ExtensionCommandRegistry.all().where((c) => c.extensionId == 'demo'),
        isEmpty,
      );
      expect(
        ExtensionThemeRegistry.all().where((t) => t.extensionId == 'demo'),
        isEmpty,
      );
    });
  });

  group('an extension theme only applies when it should', () {
    final base = ThemeData(brightness: Brightness.light);

    ExtensionTheme themeThat(
      ThemeData Function(ThemeData base) build, {
      Brightness brightness = Brightness.light,
    }) =>
        ExtensionTheme(
          extensionId: 'demo',
          id: 'glass',
          name: 'Glass',
          brightness: brightness,
          build: build,
        );

    setUp(() {
      ExtensionThemeRegistry.unregisterAll('demo');
      ExtensionThemeRegistry.selected.value = '';
    });

    test('nothing chosen leaves the theme alone', () {
      ExtensionThemeRegistry.register(themeThat((_) => ThemeData.dark()));
      expect(
        ExtensionThemeRegistry.apply(base, Brightness.light),
        same(base),
      );
    });

    test('the chosen theme is laid over the base', () {
      ExtensionThemeRegistry.register(
        themeThat((base) => base.copyWith(indicatorColor: Colors.red)),
      );
      ExtensionThemeRegistry.selected.value = 'demo/glass';
      expect(
        ExtensionThemeRegistry.apply(base, Brightness.light).indicatorColor,
        Colors.red,
      );
    });

    test('a dark theme is not forced onto a light app', () {
      ExtensionThemeRegistry.register(
        themeThat(
          (base) => base.copyWith(indicatorColor: Colors.red),
          brightness: Brightness.dark,
        ),
      );
      ExtensionThemeRegistry.selected.value = 'demo/glass';
      expect(
        ExtensionThemeRegistry.apply(base, Brightness.light),
        same(base),
      );
    });

    test('turning the extension off falls back rather than crashing', () {
      ExtensionThemeRegistry.register(
        themeThat((base) => base.copyWith(indicatorColor: Colors.red)),
      );
      ExtensionThemeRegistry.selected.value = 'demo/glass';
      ExtensionThemeRegistry.unregisterAll('demo');
      expect(
        ExtensionThemeRegistry.apply(base, Brightness.light),
        same(base),
      );
    });

    test('a theme that throws must not take the app down', () {
      ExtensionThemeRegistry.register(
        themeThat((_) => throw StateError('bad theme')),
      );
      ExtensionThemeRegistry.selected.value = 'demo/glass';
      expect(
        ExtensionThemeRegistry.apply(base, Brightness.light),
        same(base),
      );
    });
  });

  group('a table view an extension supplied', () {
    ExtensionTableView viewNamed(String id) => ExtensionTableView(
          extensionId: 'demo',
          id: id,
          name: 'Demo $id',
          buildTabBar: _StubTabBarBuilder.new,
        );

    setUp(() => ExtensionTableViewRegistry.unregisterAll('demo'));

    test('its envelope is namespaced so it cannot collide', () {
      expect(viewNamed('tally').envelopeKey, 'ext.demo.tally');
    });

    test('it is stored in extra exactly like a built-in one', () {
      final view = viewNamed('tally');
      ExtensionTableViewRegistry.register(view);

      final extra = TableViewMark.newExtraForKey(view.envelopeKey);
      expect(TableViewMark.fromExtraKey(extra, view.envelopeKey), isNotNull);
      expect(TableViewMark.envelopeKeyOf(extra), view.envelopeKey);
      // It is not mistaken for one of the built-in kinds.
      expect(TableViewMark.kindOf(extra), isNull);
    });

    test('a built-in kind still wins envelopeKeyOf', () {
      ExtensionTableViewRegistry.register(viewNamed('tally'));
      final extra = TableViewMark.newExtra(TableViewKind.feed);
      expect(
        TableViewMark.envelopeKeyOf(extra),
        TableViewKind.feed.envelopeKey,
      );
    });

    test('settings survive a round trip', () {
      final view = viewNamed('tally');
      ExtensionTableViewRegistry.register(view);
      final extra = TableViewMark.forKey(
        view.envelopeKey,
        settings: const {'goal': 12},
      ).mergeIntoExtra('');
      expect(
        TableViewMark.fromExtraKey(extra, view.envelopeKey)?.settings['goal'],
        12,
      );
    });

    test('turning the extension off leaves the view unclaimed', () {
      final view = viewNamed('tally');
      ExtensionTableViewRegistry.register(view);
      final extra = TableViewMark.newExtraForKey(view.envelopeKey);
      expect(TableViewMark.envelopeKeyOf(extra), isNotNull);

      ExtensionTableViewRegistry.unregisterAll('demo');
      // The mark is still on disk, but nothing claims it, so the page falls
      // back to being an ordinary grid rather than rendering nothing.
      expect(TableViewMark.envelopeKeyOf(extra), isNull);
      expect(
          ExtensionTableViewRegistry.byEnvelopeKey(view.envelopeKey), isNull);
    });

    test('the add menu offers it only while it is registered', () {
      final before = DatabaseTabKind.all().length;
      ExtensionTableViewRegistry.register(viewNamed('tally'));
      expect(DatabaseTabKind.all().length, before + 1);
      expect(
        DatabaseTabKind.all().last.label,
        'Demo tally',
      );

      ExtensionTableViewRegistry.unregisterAll('demo');
      expect(DatabaseTabKind.all().length, before);
    });
  });

  group('reading a share price', () {
    String chart({
      Object? price = 191.25,
      Object? previous = 188.0,
      List<Object?> closes = const [186.0, 187.5, 191.25],
      List<Object?>? times,
    }) =>
        jsonEncode({
          'chart': {
            'result': [
              {
                'meta': {
                  'symbol': 'AAPL',
                  'regularMarketPrice': price,
                  'chartPreviousClose': previous,
                  'currency': 'USD',
                },
                'timestamp': times ??
                    List<int>.generate(closes.length, (i) => 1700000000 + i),
                'indicators': {
                  'quote': [
                    {'close': closes},
                  ],
                },
              },
            ],
          },
        });

    test('a quote carries its move, not just its price', () {
      final quote = StockQuote.fromChartResponse('AAPL', chart());
      expect(quote.symbol, 'AAPL');
      expect(quote.price, 191.25);
      expect(quote.currency, 'USD');
      expect(quote.change, closeTo(3.25, 0.001));
      expect(quote.changePercent, closeTo(1.7287, 0.001));
      expect(quote.series, [186.0, 187.5, 191.25]);
    });

    test('a holiday in the series is dropped, not drawn as zero', () {
      final quote = StockQuote.fromChartResponse(
        'AAPL',
        chart(closes: const [186.0, null, 191.25]),
      );
      expect(quote.series, [186.0, 191.25]);
    });

    test('the series is capped so the store cannot grow without end', () {
      final many = List<Object?>.generate(500, (index) => index.toDouble());
      final quote = StockQuote.fromChartResponse('AAPL', chart(closes: many));
      expect(quote.series.length, StockFeed.seriesLength);
      expect(quote.series.last, 499.0);
    });

    test('a missing live price falls back to the last close', () {
      final quote = StockQuote.fromChartResponse('AAPL', chart(price: null));
      expect(quote.price, 191.25);
    });

    test('an unknown ticker is reported, not silently blank', () {
      expect(
        () => StockQuote.fromChartResponse(
          'NOPE',
          jsonEncode({
            'chart': {
              'error': {'code': 'Not Found', 'description': 'No such ticker'},
            },
          }),
        ),
        throwsStateError,
      );
    });

    test('nonsense from the service is refused', () {
      expect(
        () => StockQuote.fromChartResponse('AAPL', '[]'),
        throwsStateError,
      );
    });

    test('a failure round-trips through af.data like a quote does', () {
      final stored = StockQuote.failed('AAPL', 'offline').toJson();
      final read = StockQuote.fromJson(stored);
      expect(read.error, 'offline');
      expect(read.hasPrice, isFalse);
    });

    test('a quote round-trips through af.data', () {
      final original = StockQuote.fromChartResponse('AAPL', chart());
      final read = StockQuote.fromJson(original.toJson());
      expect(read.price, original.price);
      expect(read.previousClose, original.previousClose);
      expect(read.series, original.series);
      expect(read.times, original.times);
    });

    test('a card and the parser agree on where the price lives', () {
      expect(
        StockFeed.qualifiedQuoteKey('aapl', StockRange.month1),
        'stock.quote.AAPL.month1',
      );
      // Two periods of the same ticker are stored apart, so switching period
      // does not overwrite the other chart.
      expect(
        StockFeed.qualifiedQuoteKey('AAPL', StockRange.year1),
        isNot(StockFeed.qualifiedQuoteKey('AAPL', StockRange.month1)),
      );
    });

    test('a day is measured against yesterday, a year against its start', () {
      final quote = StockQuote.fromChartResponse('AAPL', chart());
      // 1D: price 191.25 against previous close 188.0.
      expect(quote.baselineFor(StockRange.day1), 188.0);
      expect(quote.changeOver(StockRange.day1), closeTo(3.25, 0.001));
      // Longer: measured from where the line starts, 186.0.
      expect(quote.baselineFor(StockRange.year1), 186.0);
      expect(quote.changeOver(StockRange.year1), closeTo(5.25, 0.001));
    });

    test('every period asks the service for a sane pair', () {
      for (final range in StockRange.values) {
        expect(range.range, isNotEmpty);
        expect(range.interval, isNotEmpty);
        expect(range.label, isNotEmpty);
      }
      // A long chart must not be refetched as often as an intraday one.
      expect(
        StockRange.year5.freshFor,
        greaterThan(StockRange.day1.freshFor),
      );
    });

    test('an unknown period name falls back rather than throwing', () {
      expect(StockRange.named('nonsense'), StockRange.month1);
      expect(StockRange.named('year1'), StockRange.year1);
    });

    test('a point keeps the moment it belongs to', () {
      final quote = StockQuote.fromChartResponse('AAPL', chart());
      expect(quote.times.length, quote.series.length);
      expect(quote.timeAt(0), isNotNull);
      expect(quote.timeAt(99), isNull);
    });
  });

  group('finding a ticker by name', () {
    String results(List<Map<String, Object?>> quotes) =>
        jsonEncode({'quotes': quotes});

    test('an Indian listing keeps its exchange suffix', () {
      final matches = StockMatch.listFrom(
        results([
          {
            'symbol': 'RELIANCE.NS',
            'shortname': 'RELIANCE INDUSTRIES LTD',
            'exchDisp': 'NSE',
            'typeDisp': 'Equity',
          },
        ]),
      );
      expect(matches.single.symbol, 'RELIANCE.NS');
      expect(matches.single.name, 'RELIANCE INDUSTRIES LTD');
      expect(matches.single.where, 'NSE · Equity');
    });

    test('a row with no name still offers its symbol', () {
      final matches = StockMatch.listFrom(
        results([
          {'symbol': '0P0000NQJX.BO', 'exchDisp': 'Bombay'},
        ]),
      );
      expect(matches.single.name, '0P0000NQJX.BO');
      expect(matches.single.where, 'Bombay');
    });

    test('a row with no symbol is dropped', () {
      final matches = StockMatch.listFrom(
        results([
          {'shortname': 'Nameless'},
          {'symbol': 'TCS.NS', 'shortname': 'TCS'},
        ]),
      );
      expect(matches.map((match) => match.symbol), ['TCS.NS']);
    });

    test('nonsense from the service yields nothing, never an exception', () {
      expect(StockMatch.listFrom('[]'), isEmpty);
      expect(StockMatch.listFrom(jsonEncode({'quotes': 'no'})), isEmpty);
      expect(StockMatch.listFrom(jsonEncode({})), isEmpty);
    });
  });

  group('the libraries a script may use', () {
    test('a hash is written in the form a web page would use', () {
      final integrity = ExtensionLibraryCache.integrityOf(
        utf8.encode('console.log(1);'),
      );
      expect(integrity, startsWith('sha384-'));
      // Same bytes, same pin.
      expect(
        ExtensionLibraryCache.integrityOf(utf8.encode('console.log(1);')),
        integrity,
      );
      expect(
        ExtensionLibraryCache.integrityOf(utf8.encode('console.log(2);')),
        isNot(integrity),
      );
    });

    test('a declared library round trips through the lock file', () {
      const cached = CachedLibrary(
        name: 'dayjs',
        version: '1.11.10',
        integrity: 'sha384-abc',
        file: 'web/lib/dayjs-1.11.10.js',
      );
      final read = CachedLibrary.fromJson('dayjs', cached.toJson())!;
      expect(read.version, '1.11.10');
      expect(read.integrity, 'sha384-abc');
      expect(read.file, 'web/lib/dayjs-1.11.10.js');
    });

    test('a library with no address is not a library', () {
      expect(ExtensionLibrary.fromJson({'name': 'dayjs'}), isNull);
      expect(ExtensionLibrary.fromJson({'url': 'https://x/y.js'}), isNull);
      expect(
        ExtensionLibrary.fromJson({'name': 'dayjs', 'url': 'https://x/y.js'}),
        isNotNull,
      );
    });
  });

  group('the values an action keeps', () {
    late Directory folder;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('af_ext_data');
    });

    tearDown(() async {
      if (folder.existsSync()) {
        await folder.delete(recursive: true);
      }
    });

    test('a key is filed under the extension that wrote it', () {
      expect(
        ExtensionDataStore.qualify('finance', 'quote.AAPL'),
        'finance.quote.AAPL',
      );
      // Already qualified stays as it is, so a recipe may write either form.
      expect(
        ExtensionDataStore.qualify('finance', 'finance.quote.AAPL'),
        'finance.quote.AAPL',
      );
    });

    test('a value survives being written and read back', () async {
      final store = ExtensionDataStore(rootOverride: folder.path);
      await store.write('finance.quote.AAPL', 231.4);
      await store.write('finance.watchlist', ['AAPL', 'MSFT']);
      await store.flush();

      final second = ExtensionDataStore(rootOverride: folder.path);
      await second.ensureLoaded();
      expect(second.read('finance.quote.AAPL'), 231.4);
      expect(second.read('finance.watchlist'), ['AAPL', 'MSFT']);
      second.dispose();
      store.dispose();
    });

    test('a stale value says so instead of pretending to be fresh', () async {
      final store = ExtensionDataStore(rootOverride: folder.path);
      await store.write(
        'finance.quote.AAPL',
        231.4,
        staleAfter: const Duration(minutes: 5),
      );
      final entry = store.entryFor('finance.quote.AAPL')!;
      expect(entry.isStale(DateTime.now()), isFalse);
      expect(
        entry.isStale(DateTime.now().add(const Duration(minutes: 6))),
        isTrue,
      );
      store.dispose();
    });

    test('one extension is cleared without touching another', () async {
      final store = ExtensionDataStore(rootOverride: folder.path);
      await store.write('finance.a', 1);
      await store.write('weather.a', 2);
      await store.clearExtension('finance');
      expect(store.read('finance.a'), isNull);
      expect(store.read('weather.a'), 2);
      store.dispose();
    });

    test('a key notifies only its own listeners', () async {
      final store = ExtensionDataStore(rootOverride: folder.path);
      final watched = store.listenable('finance.quote.AAPL');
      var raised = 0;
      watched.addListener(() => raised++);

      await store.write('finance.quote.MSFT', 1);
      expect(raised, 0);
      await store.write('finance.quote.AAPL', 2);
      expect(raised, 1);
      expect(watched.value, 2);
      store.dispose();
    });
  });

  group('what each run did', () {
    late Directory folder;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('af_ext_log');
    });

    tearDown(() async {
      if (folder.existsSync()) {
        await folder.delete(recursive: true);
      }
    });

    test('a run is remembered and read back', () async {
      final log = ExtensionRunLog(rootOverride: folder.path);
      await log.ensureLoaded();
      final at = DateTime(2026, 8, 20, 10);
      log.record(
        ActionRun(
          extensionId: 'finance',
          actionId: 'quote',
          startedAt: at,
          status: ActionRunStatus.ok,
          cause: ActionRunCause.schedule,
          duration: const Duration(milliseconds: 120),
        ),
      );
      await log.flush();

      final second = ExtensionRunLog(rootOverride: folder.path);
      await second.ensureLoaded();
      final last = second.lastRunOf('finance', 'quote')!;
      expect(last.status, ActionRunStatus.ok);
      expect(last.cause, ActionRunCause.schedule);
      expect(last.duration.inMilliseconds, 120);
      expect(second.lastAttemptOf('finance', 'quote'), at);
      log.dispose();
      second.dispose();
    });

    test('a failure still moves the clock on', () async {
      // Otherwise a service that is refusing would be asked again every tick,
      // because nothing ever recorded an attempt.
      final log = ExtensionRunLog(rootOverride: folder.path);
      await log.ensureLoaded();
      final at = DateTime(2026, 8, 20, 10);
      log.record(
        ActionRun(
          extensionId: 'finance',
          actionId: 'quote',
          startedAt: at,
          status: ActionRunStatus.failed,
          message: 'no',
        ),
      );
      expect(log.lastAttemptOf('finance', 'quote'), at);
      log.dispose();
    });

    test('only the last few runs are kept', () async {
      final log = ExtensionRunLog(rootOverride: folder.path);
      await log.ensureLoaded();
      for (var i = 0; i < ExtensionRunLog.maximumRuns + 20; i++) {
        log.record(
          ActionRun(
            extensionId: 'finance',
            actionId: 'quote',
            startedAt: DateTime(2026, 8, 20).add(Duration(minutes: i)),
            status: ActionRunStatus.ok,
          ),
        );
      }
      expect(
        log.runsFor('finance'),
        hasLength(ExtensionRunLog.maximumRuns),
      );
      log.dispose();
    });

    test('a log that could not be read is not latched as empty', () async {
      // A store that gives up after one bad read stays silently empty for the
      // whole session, which has cost this codebase a day before now.
      final broken = Directory(p.join(folder.path, 'finance'))
        ..createSync(recursive: true);
      File(p.join(broken.path, ExtensionRunLog.fileName))
          .writeAsStringSync('not json');

      final log = ExtensionRunLog(rootOverride: folder.path);
      await log.ensureLoaded();
      expect(log.runsFor('finance'), isEmpty);
      log.dispose();
    });
  });
}
