import 'dart:async';
import 'dart:convert';

import 'package:appflowy/startup/startup_profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _secretError = 'FAKE_STARTUP_SECRET_do_not_log';
const _secretStack = 'FAKE_STARTUP_STACK_do_not_log';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StartupProfile', () {
    late List<String> output;
    late List<String> events;
    late StartupProfile profile;

    setUp(() {
      output = [];
      events = [];
      profile = StartupProfile(
        write: (line) {
          output.add(line);
          events.add('write');
        },
      );
    });

    test('is disabled by default and ignores marks', () {
      expect(profile.enabled, isFalse);
      profile.mark('before_start');
      profile.mark('before_start');
      expect(output, isEmpty);
    });

    test('requires the exact opt-in argument', () {
      for (final arguments in <List<String>>[
        [],
        ['--verbose'],
        ['profile-startup'],
        ['--PROFILE-STARTUP'],
        ['--profile-startup=true'],
        ['--profile-startup=false'],
        [' --profile-startup'],
        ['--profile-startup '],
      ]) {
        profile.start(arguments);
        profile.mark('ignored');
        expect(profile.enabled, isFalse, reason: '$arguments');
        expect(output, isEmpty, reason: '$arguments');
      }
    });

    test('accepts the opt-in anywhere and records entry only once', () {
      for (final arguments in <List<String>>[
        ['--profile-startup'],
        ['--unrelated', '--profile-startup', 'document'],
        ['--profile-startup', '--profile-startup'],
      ]) {
        output.clear();
        profile.start(arguments);
        expect(profile.enabled, isTrue);
        _expectRecords(output, ['dart_entry']);
      }
    });

    test('deduplicates milestones within a run, not across phases', () {
      profile.start(const ['--profile-startup']);
      profile.mark('dart_entry');
      profile.mark('shell');
      profile.mark('shell');
      profile.mark('page');
      profile.mark('shell');
      _expectRecords(output, ['dart_entry', 'shell', 'page']);
    });

    test('start resets enablement and milestone deduplication for each run',
        () {
      for (final arguments in <List<String>>[
        ['--profile-startup'],
        ['--other', '--profile-startup'],
        [],
        ['--profile-startup=true'],
        ['--profile-startup'],
      ]) {
        output.clear();
        profile.start(arguments);
        profile.mark('dart_entry');
        profile.mark('ready');
        profile.mark('ready');
        final enabled = arguments.contains('--profile-startup');
        expect(profile.enabled, enabled);
        _expectRecords(output, enabled ? ['dart_entry', 'ready'] : []);
      }
    });

    // Exercise the same action contracts both before start() and after explicit
    // configuration. Only enabled instances may call the supplied writer.
    for (final mode in ['before start', 'disabled', 'enabled']) {
      final enabled = mode == 'enabled';

      group(mode, () {
        setUp(() {
          if (mode != 'before start') {
            profile.start(enabled ? const ['--profile-startup'] : const []);
          }
          output.clear();
          events.clear();
        });

        test('measureSync preserves identity and calls the action once', () {
          final value = Object();
          var calls = 0;
          final result = profile.measureSync<Object>('sync', () {
            calls++;
            events.add('action');
            return value;
          });
          events.add('returned');

          expect(result, same(value));
          expect(calls, 1);
          expect(
            events,
            enabled ? ['action', 'write', 'returned'] : ['action', 'returned'],
          );
          _expectRecords(output, enabled ? ['sync'] : [], succeeded: true);
        });

        test('measure accepts an immediate result without duplicating work',
            () async {
          final value = Object();
          var calls = 0;
          final pending = profile.measure<Object>('immediate', () {
            calls++;
            events.add('action');
            return value;
          });
          expect(calls, 1);
          events.add('called');
          expect(await pending, same(value));
          events.add('returned');

          expect(calls, 1);
          expect(
            events,
            enabled
                ? ['action', 'called', 'write', 'returned']
                : ['action', 'called', 'returned'],
          );
          _expectRecords(output, enabled ? ['immediate'] : [], succeeded: true);
        });

        test('measure waits for the action before recording and returning',
            () async {
          final value = Object();
          final gate = Completer<Object>();
          var calls = 0;
          final pending = profile.measure<Object>('async', () async {
            calls++;
            events.add('action');
            final result = await gate.future;
            events.add('completed');
            return result;
          });

          expect(calls, 1);
          expect(events, ['action']);
          expect(output, isEmpty);
          gate.complete(value);
          expect(await pending, same(value));
          events.add('returned');

          expect(calls, 1);
          expect(
            events,
            enabled
                ? ['action', 'completed', 'write', 'returned']
                : ['action', 'completed', 'returned'],
          );
          _expectRecords(output, enabled ? ['async'] : [], succeeded: true);
        });

        test('measureSync rethrows the identical error without logging it', () {
          final error = StateError(_secretError);
          var calls = 0;
          expect(
            () => profile.measureSync<Object>('sync_failure', () {
              calls++;
              events.add('action');
              throw error;
            }),
            throwsA(same(error)),
          );
          events.add('caught');

          expect(calls, 1);
          expect(
            events,
            enabled ? ['action', 'write', 'caught'] : ['action', 'caught'],
          );
          _expectRecords(
            output,
            enabled ? ['sync_failure'] : [],
            succeeded: false,
          );
        });

        test('measure propagates an identical synchronous callback error',
            () async {
          final error = StateError(_secretError);
          var calls = 0;
          await expectLater(
            profile.measure<Object>('immediate_failure', () {
              calls++;
              events.add('action');
              throw error;
            }),
            throwsA(same(error)),
          );
          events.add('caught');

          expect(calls, 1);
          expect(
            events,
            enabled ? ['action', 'write', 'caught'] : ['action', 'caught'],
          );
          _expectRecords(
            output,
            enabled ? ['immediate_failure'] : [],
            succeeded: false,
          );
        });

        test('measure awaits failure without logging error or stack payloads',
            () async {
          final error = StateError(_secretError);
          final gate = Completer<Object>();
          var calls = 0;
          final pending = profile.measure<Object>('async_failure', () async {
            calls++;
            events.add('action');
            try {
              return await gate.future;
            } finally {
              events.add('completed');
            }
          });
          // Attach the error handler before completing the failing future.
          final expectation = expectLater(pending, throwsA(same(error)));
          expect(calls, 1);
          expect(events, ['action']);
          expect(output, isEmpty);
          gate.completeError(error, StackTrace.fromString(_secretStack));
          await expectation;
          events.add('caught');

          expect(calls, 1);
          expect(
            events,
            enabled
                ? ['action', 'completed', 'write', 'caught']
                : ['action', 'completed', 'caught'],
          );
          _expectRecords(
            output,
            enabled ? ['async_failure'] : [],
            succeeded: false,
          );
        });

        test('supports nullable results and void startup actions', () async {
          expect(
            profile.measureSync<Object?>('null_sync', () => null),
            isNull,
          );
          expect(
            await profile.measure<Object?>('null_async', () => null),
            isNull,
          );
          var syncCalls = 0;
          var asyncCalls = 0;
          profile.measureSync<void>('void_sync', () {
            syncCalls++;
          });
          await profile.measure<void>('void_async', () async {
            asyncCalls++;
            await Future<void>.value();
          });

          expect(syncCalls, 1);
          expect(asyncCalls, 1);
          _expectRecords(
            output,
            enabled
                ? ['null_sync', 'null_async', 'void_sync', 'void_async']
                : [],
            succeeded: true,
          );
        });
      });
    }

    test('deduplicating a mark does not suppress measurements of that phase',
        () async {
      profile.start(const ['--profile-startup']);
      output.clear();
      profile.mark('stage');
      var calls = 0;
      profile.measureSync<void>('stage', () {
        calls++;
      });
      await profile.measure<void>('stage', () async {
        calls++;
      });
      profile.mark('stage');

      expect(calls, 2);
      _expectRecords(output.take(1).toList(), ['stage']);
      _expectRecords(
        output.skip(1).toList(),
        ['stage', 'stage'],
        succeeded: true,
      );
    });

    test('nested synchronous stages record from inner to outer', () {
      profile.start(const ['--profile-startup']);
      output.clear();
      events.clear();
      final value = Object();
      final result = profile.measureSync<Object>('outer', () {
        events.add('outer');
        final result = profile.measureSync<Object>('inner', () {
          events.add('inner');
          return value;
        });
        events.add('outer resumed');
        return result;
      });
      events.add('returned');

      expect(result, same(value));
      expect(
        events,
        ['outer', 'inner', 'write', 'outer resumed', 'write', 'returned'],
      );
      final records = _expectRecords(
        output,
        ['inner', 'outer'],
        succeeded: true,
      );
      expect(
        records.last['duration_us'],
        greaterThanOrEqualTo(records.first['duration_us']),
      );
    });

    test('nested sync and async stages preserve completion order and identity',
        () async {
      profile.start(const ['--profile-startup']);
      output.clear();
      final value = Object();
      final gate = Completer<Object>();
      final pending = profile.measure<Object>('outer', () async {
        final syncResult =
            profile.measureSync<Object>('sync_inner', () => value);
        expect(syncResult, same(value));
        final asyncResult =
            await profile.measure<Object>('async_inner', () => gate.future);
        _expectRecords(output, ['sync_inner', 'async_inner'], succeeded: true);
        return asyncResult;
      });

      _expectRecords(output, ['sync_inner'], succeeded: true);
      gate.complete(value);
      expect(await pending, same(value));
      final records = _expectRecords(
        output,
        ['sync_inner', 'async_inner', 'outer'],
        succeeded: true,
      );
      for (final inner in records.take(2)) {
        expect(
          records.last['duration_us'],
          greaterThanOrEqualTo(inner['duration_us']),
        );
      }
    });

    test('nested failures record each unwound stage without error payloads',
        () async {
      profile.start(const ['--profile-startup']);
      output.clear();
      final error = StateError(_secretError);
      await expectLater(
        profile.measure<Object>(
          'outer',
          () => profile.measure<Object>('middle', () async {
            await Future<void>.value();
            return profile.measureSync<Object>('inner', () => throw error);
          }),
        ),
        throwsA(same(error)),
      );
      _expectRecords(output, ['inner', 'middle', 'outer'], succeeded: false);
    });
  });

  // The global instance writes directly to stdout, not Zone.print. Keep it
  // disabled: instance tests above capture output without replacing production
  // globals, while these tests exercise the normal widget lifecycle.
  group('StartupProfileFrame with profiling disabled', () {
    setUp(() => startupProfile.start(const []));
    tearDown(() => startupProfile.start(const []));

    testWidgets('passes through the same visible, interactive child',
        (tester) async {
      var taps = 0;
      final child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox(
          width: 160,
          height: 48,
          child: Text('Startup child'),
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: StartupProfileFrame(phase: 'visible', child: child),
          ),
        ),
      );

      expect(
        tester
            .widget<StartupProfileFrame>(find.byType(StartupProfileFrame))
            .child,
        same(child),
      );
      expect(find.text('Startup child').hitTestable(), findsOneWidget);
      expect(tester.getSize(find.byWidget(child)), const Size(160, 48));
      await tester.tap(find.byWidget(child));
      await tester.pump();
      expect(taps, 1);
      _expectIdleDisabledFrame(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(find.byWidget(child), findsNothing);
      _expectIdleDisabledFrame(tester);
    });

    for (final key in <Key?>[null, const ValueKey('stable-frame')]) {
      testWidgets('preserves state and contexts on updates (key: $key)',
          (tester) async {
        await tester.pumpWidget(_frameHost(frameKey: key));
        final frameFinder = find.byType(StartupProfileFrame);
        final childFinder = find.byType(_StatefulChild);
        final frameState =
            tester.state<State<StartupProfileFrame>>(frameFinder);
        final childState = tester.state<_StatefulChildState>(childFinder);
        final frameContext = tester.element(frameFinder);
        final childContext = tester.element(childFinder);
        final dependencyChanges = childState.dependencyChanges;

        await tester.tap(childFinder);
        await tester.pump();
        expect(find.text('initial: 1'), findsOneWidget);

        await tester.pumpWidget(
          _frameHost(
            frameKey: key,
            phase: 'updated_phase',
            label: 'updated',
            direction: TextDirection.rtl,
          ),
        );
        expect(tester.state(frameFinder), same(frameState));
        expect(tester.state(childFinder), same(childState));
        expect(tester.element(frameFinder), same(frameContext));
        expect(tester.element(childFinder), same(childContext));
        expect(frameState.widget.phase, 'updated_phase');
        expect(childState.updates, 1);
        expect(childState.dependencyChanges, greaterThan(dependencyChanges));
        expect(Directionality.of(childContext), TextDirection.rtl);
        expect(childState.taps, 1);
        expect(childState.disposals, 0);
        expect(find.text('updated: 1').hitTestable(), findsOneWidget);
        expect(find.text('initial: 1'), findsNothing);
        await tester.pump();
        expect(childState.updates, 1);
        _expectIdleDisabledFrame(tester);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(frameState.mounted, isFalse);
        expect(childState.mounted, isFalse);
        expect(childState.disposals, 1);
        _expectIdleDisabledFrame(tester);
      });
    }

    testWidgets('a changed wrapper key follows normal remount semantics',
        (tester) async {
      await tester.pumpWidget(
        _frameHost(frameKey: const ValueKey('first')),
      );
      final frameFinder = find.byType(StartupProfileFrame);
      final childFinder = find.byType(_StatefulChild);
      final oldFrame = tester.state<State<StartupProfileFrame>>(frameFinder);
      final oldChild = tester.state<_StatefulChildState>(childFinder);
      await tester.tap(childFinder);
      await tester.pump();
      expect(oldChild.taps, 1);

      await tester.pumpWidget(
        _frameHost(frameKey: const ValueKey('second')),
      );
      final newChild = tester.state<_StatefulChildState>(childFinder);
      expect(tester.state(frameFinder), isNot(same(oldFrame)));
      expect(newChild, isNot(same(oldChild)));
      expect(oldFrame.mounted, isFalse);
      expect(oldChild.mounted, isFalse);
      expect(oldChild.disposals, 1);
      expect(newChild.taps, 0);
      expect(newChild.updates, 0);
      expect(find.text('initial: 0').hitTestable(), findsOneWidget);
      _expectIdleDisabledFrame(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(newChild.disposals, 1);
      _expectIdleDisabledFrame(tester);
    });

    testWidgets('nested and duplicate phases never hide their children',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              StartupProfileFrame(phase: 'same', child: Text('First child')),
              StartupProfileFrame(
                phase: 'same',
                child: StartupProfileFrame(
                  phase: 'same',
                  child: Text('Nested child'),
                ),
              ),
            ],
          ),
        ),
      );

      expect(find.byType(StartupProfileFrame), findsNWidgets(3));
      expect(find.text('First child').hitTestable(), findsOneWidget);
      expect(find.text('Nested child').hitTestable(), findsOneWidget);
      await tester.pump();
      _expectIdleDisabledFrame(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      _expectIdleDisabledFrame(tester);
    });
  });
}

List<Map<String, dynamic>> _expectRecords(
  List<String> output,
  List<String> phases, {
  bool? succeeded,
}) {
  const prefix = 'AF_STARTUP ';
  // Check the raw output as well as the exact schema, so an error cannot be
  // smuggled into an otherwise valid field or appended outside the JSON.
  expect(output.join('\n'), isNot(contains(_secretError)));
  expect(output.join('\n'), isNot(contains(_secretStack)));
  final records = output.map((line) {
    expect(line, startsWith(prefix));
    return jsonDecode(line.substring(prefix.length)) as Map<String, dynamic>;
  }).toList();
  expect(records.map((record) => record['phase']), orderedEquals(phases));

  var previousElapsed = 0;
  for (final record in records) {
    expect(
      record.keys,
      unorderedEquals(
        succeeded == null
            ? ['phase', 'elapsed_us']
            : ['phase', 'elapsed_us', 'duration_us', 'succeeded'],
      ),
    );
    final elapsed = _expectMicroseconds(record['elapsed_us']);
    expect(elapsed, greaterThanOrEqualTo(previousElapsed));
    previousElapsed = elapsed;
    if (succeeded != null) {
      _expectMicroseconds(record['duration_us']);
      expect(record['succeeded'], succeeded);
    }
  }
  return records;
}

int _expectMicroseconds(Object? value) {
  expect(value, isA<int>());
  final microseconds = value as int;
  expect(microseconds.isFinite, isTrue);
  // Fast actions and zero-time async continuations may legitimately take 0 us.
  expect(microseconds, greaterThanOrEqualTo(0));
  return microseconds;
}

void _expectIdleDisabledFrame(WidgetTester tester) {
  expect(startupProfile.enabled, isFalse);
  expect(tester.binding.hasScheduledFrame, isFalse);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

Widget _frameHost({
  Key? frameKey,
  String phase = 'initial_phase',
  String label = 'initial',
  TextDirection direction = TextDirection.ltr,
}) =>
    Directionality(
      textDirection: direction,
      child: Center(
        child: StartupProfileFrame(
          key: frameKey,
          phase: phase,
          child: _StatefulChild(key: const ValueKey('child'), label: label),
        ),
      ),
    );

class _StatefulChild extends StatefulWidget {
  const _StatefulChild({super.key, required this.label});

  final String label;

  @override
  State<_StatefulChild> createState() => _StatefulChildState();
}

class _StatefulChildState extends State<_StatefulChild> {
  int taps = 0;
  int updates = 0;
  int dependencyChanges = 0;
  int disposals = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Directionality.of(context);
    dependencyChanges++;
  }

  @override
  void didUpdateWidget(covariant _StatefulChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    updates++;
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => taps++),
        child: SizedBox(
          width: 160,
          height: 48,
          child: Text('${widget.label}: $taps'),
        ),
      );
}
