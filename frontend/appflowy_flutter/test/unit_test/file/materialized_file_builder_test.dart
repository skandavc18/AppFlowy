import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MaterializedFileBuilder', () {
    testWidgets('does not load or build until a parent admits its child',
        (tester) async {
      final loader = _RecordingLoader();
      var builds = 0;
      final preview = MaterializedFileBuilder(
        source: 'source-a',
        name: 'preview.txt',
        loader: loader.load,
        builder: (context, snapshot) {
          builds++;
          return _snapshotView(context, snapshot);
        },
      );

      expect(loader.requests, isEmpty);
      expect(builds, 0);
      await tester.pumpWidget(_gate(preview, admitted: false));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MaterializedFileBuilder), findsNothing);
      expect(loader.requests, isEmpty);
      expect(builds, 0);

      await tester.pumpWidget(_gate(preview, admitted: true));
      expect(loader.requests, hasLength(1));
      expect(builds, 1);
      expect(find.text('loading'), findsOneWidget);
      loader.requests.single.completer.complete(File('admitted.txt'));
      await tester.pumpAndSettle();
      expect(find.text('admitted.txt'), findsOneWidget);

      await tester.pumpWidget(_gate(preview, admitted: true));
      expect(loader.requests, hasLength(1));
    });

    testWidgets('only loads the latest inputs when admitted after updates',
        (tester) async {
      final original = _RecordingLoader();
      final replacement = _RecordingLoader();
      await tester.pumpWidget(
        _host(loader: original.load, admitted: false),
      );
      await tester.pumpWidget(
        _host(
          loader: replacement.load,
          source: 'source-b',
          name: 'renamed.txt',
          httpHeaders: const {'Authorization': 'Bearer test-b'},
          admitted: false,
        ),
      );
      expect(original.requests, isEmpty);
      expect(replacement.requests, isEmpty);

      await tester.pumpWidget(
        _host(
          loader: replacement.load,
          source: 'source-b',
          name: 'renamed.txt',
          httpHeaders: const {'Authorization': 'Bearer test-b'},
        ),
      );
      expect(original.requests, isEmpty);
      expect(replacement.requests, hasLength(1));
      final request = replacement.requests.single;
      expect(request.source, 'source-b');
      expect(request.name, 'renamed.txt');
      expect(request.httpHeaders, {'Authorization': 'Bearer test-b'});
    });

    testWidgets('reuses pending and completed futures for equal request values',
        (tester) async {
      final loader = _RecordingLoader();
      await tester.pumpWidget(
        _host(
          loader: loader.load,
          httpHeaders: const {
            'Authorization': 'Bearer test-a',
            'Accept': 'text/plain',
          },
        ),
      );
      final firstFuture = tester
          .widget<FutureBuilder<File>>(find.byType(FutureBuilder<File>))
          .future;

      for (var phase = 0; phase < 2; phase++) {
        for (var rebuild = 0; rebuild < 5; rebuild++) {
          await tester.pumpWidget(
            _host(
              loader: loader.load,
              // New map identity and insertion order, unchanged values.
              httpHeaders: {
                'Accept': 'text/plain',
                'Authorization': 'Bearer test-a',
              },
            ),
          );
          expect(loader.requests, hasLength(1));
          expect(
            tester
                .widget<FutureBuilder<File>>(find.byType(FutureBuilder<File>))
                .future,
            same(firstFuture),
          );
          expect(
            find.text(phase == 0 ? 'loading' : 'cached.txt'),
            findsOneWidget,
          );
        }
        if (phase == 0) {
          loader.requests.single.completer.complete(File('cached.txt'));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('updates the builder without restarting the request',
        (tester) async {
      final loader = _RecordingLoader();
      await tester.pumpWidget(_host(loader: loader.load));
      loader.requests.single.completer.complete(File('cached.txt'));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(FutureBuilder<File>));

      await tester.pumpWidget(
        _host(
          loader: loader.load,
          builder: (_, snapshot) => Text('updated: ${snapshot.data?.path}'),
        ),
      );
      expect(loader.requests, hasLength(1));
      expect(tester.element(find.byType(FutureBuilder<File>)), same(element));
      expect(find.text('updated: cached.txt'), findsOneWidget);
    });

    for (final change in ['source', 'name', 'headers', 'loader']) {
      testWidgets('starts a cold request when $change changes', (tester) async {
        final original = _RecordingLoader();
        final replacement = _RecordingLoader();
        const originalHeaders = {'Authorization': 'Bearer test-a'};
        await tester.pumpWidget(
          _host(loader: original.load, httpHeaders: originalHeaders),
        );
        final state = tester.state(find.byType(MaterializedFileBuilder));
        original.requests.single.completer.complete(File('old-path.txt'));
        await tester.pumpAndSettle();
        expect(find.text('old-path.txt'), findsOneWidget);

        final active = change == 'loader' ? replacement : original;
        final source = change == 'source' ? 'source-b' : 'source-a';
        final name = change == 'name' ? 'renamed.txt' : 'preview.txt';
        final headers = change == 'headers'
            ? const {'Authorization': 'Bearer test-b'}
            : originalHeaders;
        AsyncSnapshot<File>? latest;
        Widget builder(BuildContext context, AsyncSnapshot<File> snapshot) {
          latest = snapshot;
          // Like the preview call sites, trust data rather than connectionState.
          return Text('$name: ${snapshot.data?.path ?? 'loading'}');
        }

        await tester.pumpWidget(
          _host(
            loader: active.load,
            source: source,
            name: name,
            httpHeaders: headers,
            builder: builder,
          ),
        );
        expect(tester.state(find.byType(MaterializedFileBuilder)), same(state));
        expect(original.requests.length + replacement.requests.length, 2);
        final request = active.requests.last;
        expect(request.source, source);
        expect(request.name, name);
        expect(request.httpHeaders, headers);
        expect(latest?.connectionState, ConnectionState.waiting);
        expect(latest?.data, isNull);
        expect(latest?.error, isNull);
        expect(find.textContaining('old-path.txt'), findsNothing);
        expect(find.text('$name: loading'), findsOneWidget);

        request.completer.complete(File('new-path.txt'));
        await tester.pumpAndSettle();
        expect(find.text('$name: new-path.txt'), findsOneWidget);
        await tester.pumpWidget(
          _host(
            loader: active.load,
            source: source,
            name: name,
            httpHeaders: Map<String, String>.from(headers),
            builder: builder,
          ),
        );
        expect(original.requests.length + replacement.requests.length, 2);
      });
    }

    testWidgets('detects in-place auth changes and snapshots in-flight headers',
        (tester) async {
      final loader = _RecordingLoader();
      final headers = {
        'Authorization': 'Bearer test-a',
        'Accept': 'text/plain',
      };
      await tester.pumpWidget(
        _host(loader: loader.load, httpHeaders: headers),
      );
      final first = loader.requests.single;
      expect(first.httpHeaders, isNot(same(headers)));

      headers['Authorization'] = 'Bearer test-b';
      expect(first.httpHeaders['Authorization'], 'Bearer test-a');
      await tester.pumpWidget(
        _host(loader: loader.load, httpHeaders: headers),
      );
      expect(loader.requests, hasLength(2));
      final second = loader.requests.last;
      expect(second.httpHeaders['Authorization'], 'Bearer test-b');
      expect(first.httpHeaders['Authorization'], 'Bearer test-a');

      headers.remove('Authorization');
      await tester.pumpWidget(
        _host(loader: loader.load, httpHeaders: headers),
      );
      expect(loader.requests, hasLength(3));
      expect(loader.requests.last.httpHeaders, {'Accept': 'text/plain'});
      expect(second.httpHeaders['Authorization'], 'Bearer test-b');

      headers['Authorization'] = 'Bearer test-c';
      await tester.pumpWidget(
        _host(loader: loader.load, httpHeaders: headers),
      );
      expect(loader.requests, hasLength(4));
      expect(loader.requests.last.httpHeaders['Authorization'], 'Bearer test-c');
      expect(loader.requests[2].httpHeaders, {'Accept': 'text/plain'});
    });

    testWidgets('preserves failures on rebuild and clears them for a new request',
        (tester) async {
      final loader = _RecordingLoader();
      final error = StateError('load failed');
      final stack = StackTrace.current;
      AsyncSnapshot<File>? latest;
      Widget builder(BuildContext context, AsyncSnapshot<File> snapshot) {
        latest = snapshot;
        return _snapshotView(context, snapshot);
      }

      await tester.pumpWidget(_host(loader: loader.load, builder: builder));
      loader.requests.single.completer.completeError(error, stack);
      await tester.pumpAndSettle();
      expect(latest?.connectionState, ConnectionState.done);
      expect(latest?.error, same(error));
      expect(latest?.stackTrace, same(stack));
      expect(latest?.data, isNull);
      expect(find.text('error: $error'), findsOneWidget);

      await tester.pumpWidget(_host(loader: loader.load, builder: builder));
      expect(loader.requests, hasLength(1));
      expect(latest?.error, same(error));

      await tester.pumpWidget(
        _host(loader: loader.load, source: 'source-b', builder: builder),
      );
      expect(loader.requests, hasLength(2));
      expect(latest?.connectionState, ConnectionState.waiting);
      expect(latest?.error, isNull);
      expect(latest?.data, isNull);
      expect(find.text('loading'), findsOneWidget);
      loader.requests.last.completer.complete(File('recovered.txt'));
      await tester.pumpAndSettle();
      expect(find.text('recovered.txt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('delivers a synchronous loader exception as a cached snapshot',
        (tester) async {
      var calls = 0;
      final error = StateError('synchronous failure');
      Future<File> loader({
        required String source,
        required String name,
        required Map<String, String> httpHeaders,
      }) {
        calls++;
        throw error;
      }

      await tester.pumpWidget(_host(loader: loader));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('error: $error'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_host(loader: loader));
      expect(calls, 1);
      expect(find.text('error: $error'), findsOneWidget);
    });

    testWidgets('ignores obsolete success and error while the latest waits',
        (tester) async {
      final loader = _RecordingLoader();
      for (var request = 0; request < 3; request++) {
        await tester.pumpWidget(
          _host(loader: loader.load, source: 'source-$request'),
        );
      }
      expect(loader.requests, hasLength(3));
      loader.requests[0].completer.complete(File('obsolete.txt'));
      loader.requests[1].completer.completeError(StateError('obsolete error'));
      await tester.pumpAndSettle();
      expect(find.text('loading'), findsOneWidget);
      expect(find.textContaining('obsolete'), findsNothing);
      expect(tester.takeException(), isNull);

      loader.requests[2].completer.complete(File('latest.txt'));
      await tester.pumpAndSettle();
      expect(find.text('latest.txt'), findsOneWidget);
    });

    for (final fails in [false, true]) {
      testWidgets('ignores a late ${fails ? 'error' : 'file'} after latest success',
          (tester) async {
        final loader = _RecordingLoader();
        await tester.pumpWidget(_host(loader: loader.load));
        final obsolete = loader.requests.single;
        await tester.pumpWidget(
          _host(loader: loader.load, source: 'source-b'),
        );
        loader.requests.last.completer.complete(File('latest.txt'));
        await tester.pumpAndSettle();
        expect(find.text('latest.txt'), findsOneWidget);

        if (fails) {
          obsolete.completer.completeError(StateError('obsolete error'));
        } else {
          obsolete.completer.complete(File('obsolete.txt'));
        }
        await tester.pumpAndSettle();
        expect(find.text('latest.txt'), findsOneWidget);
        expect(find.textContaining('obsolete'), findsNothing);
        expect(loader.requests, hasLength(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ignores completion after disposal and reloads on remount',
        (tester) async {
      final loader = _RecordingLoader();
      await tester.pumpWidget(_host(loader: loader.load));
      await tester.pumpWidget(const SizedBox.shrink());
      loader.requests.single.completer.completeError(StateError('disposed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_host(loader: loader.load));
      expect(loader.requests, hasLength(2));
      expect(find.text('loading'), findsOneWidget);
      loader.requests.last.completer.complete(File('remounted.txt'));
      await tester.pumpAndSettle();
      expect(find.text('remounted.txt'), findsOneWidget);
    });

    testWidgets('keeps mounted instances and their credentials independent',
        (tester) async {
      final loader = _RecordingLoader();
      const tokens = ['Bearer test-a', 'Bearer test-b', 'Bearer test-a'];
      await tester.pumpWidget(
        _gate(
          Column(
            children: [
              for (final token in tokens)
                MaterializedFileBuilder(
                  source: 'same-source',
                  name: 'same-name.txt',
                  httpHeaders: {'Authorization': token},
                  loader: loader.load,
                  builder: _snapshotView,
                ),
            ],
          ),
          admitted: true,
        ),
      );
      expect(loader.requests, hasLength(3));
      expect(
        loader.requests.map((request) => request.httpHeaders['Authorization']),
        tokens,
      );
      for (var index = 0; index < loader.requests.length; index++) {
        loader.requests[index].completer.complete(File('instance-$index.txt'));
      }
      await tester.pumpAndSettle();
      for (var index = 0; index < loader.requests.length; index++) {
        expect(find.text('instance-$index.txt'), findsOneWidget);
      }
    });
  });
}

Widget _host({
  required MaterializedFileLoader loader,
  String source = 'source-a',
  String name = 'preview.txt',
  Map<String, String> httpHeaders = const {},
  AsyncWidgetBuilder<File> builder = _snapshotView,
  bool admitted = true,
}) {
  return _gate(
    MaterializedFileBuilder(
      source: source,
      name: name,
      httpHeaders: httpHeaders,
      loader: loader,
      builder: builder,
    ),
    admitted: admitted,
  );
}

// Tests mount admission only, independently of the page's viewport/idle policy.
Widget _gate(Widget child, {required bool admitted}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Visibility(visible: admitted, child: child),
  );
}

Widget _snapshotView(BuildContext context, AsyncSnapshot<File> snapshot) {
  if (snapshot.hasError) {
    return Text('error: ${snapshot.error}');
  }
  return Text(snapshot.data?.path ?? 'loading');
}

class _RecordingLoader {
  final requests = <_Request>[];
  // Keep callback identity stable even on runtimes that recreate tear-offs.
  late final MaterializedFileLoader load = _load;

  Future<File> _load({
    required String source,
    required String name,
    required Map<String, String> httpHeaders,
  }) {
    final request = _Request(
      source: source,
      name: name,
      httpHeaders: httpHeaders,
    );
    requests.add(request);
    return request.completer.future;
  }
}

class _Request {
  _Request({
    required this.source,
    required this.name,
    required this.httpHeaders,
  });

  final String source;
  final String name;
  // Deliberately retain the loader argument to detect unsnapshotted mutations.
  final Map<String, String> httpHeaders;
  final completer = Completer<File>();
}
