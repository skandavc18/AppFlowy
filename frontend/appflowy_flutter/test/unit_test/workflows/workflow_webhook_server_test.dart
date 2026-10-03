import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workflows/application/workflow_scheduler.dart';
import 'package:appflowy/workflows/application/workflow_webhook_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WorkflowWebhookServer server;
  late HttpClient client;
  late int port;
  final calls = <(String, String, Map<String, Object?>)>[];

  setUp(() async {
    calls.clear();
    server = WorkflowWebhookServer(
      preferredPort: 0,
      handler: (workflowId, token, payload) async {
        calls.add((workflowId, token, payload));
        return const WorkflowWebhookAnswer(
          202,
          {'ok': true, 'status': 'queued'},
        );
      },
    );
    port = (await server.start())!;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<(int, String)> send(
    String method,
    String path, {
    String? body,
    ContentType? type,
    Map<String, String> headers = const {},
  }) async {
    final request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (type != null) {
      request.headers.contentType = type;
    }
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  }

  test('listens on loopback only', () {
    expect(server.isRunning, isTrue);
    expect(server.addressFor('w1', 't1'), 'http://127.0.0.1:$port/hooks/w1/t1');
  });

  test('hands a JSON request to the workflow, without credentials', () async {
    final (status, text) = await send(
      'POST',
      '/hooks/w1/secret?source=test',
      body: jsonEncode({
        'name': 'Ada',
        'items': [1, 2],
      }),
      type: ContentType.json,
      headers: {'authorization': 'Bearer hidden', 'x-custom': 'yes'},
    );
    expect(status, 202);
    expect(jsonDecode(text), {'ok': true, 'status': 'queued'});
    final (workflowId, token, payload) = calls.single;
    expect(workflowId, 'w1');
    expect(token, 'secret');
    expect(payload['method'], 'POST');
    expect(payload['query'], {'source': 'test'});
    expect(payload['body'], {
      'name': 'Ada',
      'items': [1, 2],
    });
    final headers = payload['headers'] as Map;
    expect(headers['x-custom'], 'yes');
    expect(headers.containsKey('authorization'), isFalse);
  });

  test('reads forms and plain text too', () async {
    await send(
      'POST',
      '/hooks/w1/t',
      body: 'a=1&b=two+words',
      type: ContentType('application', 'x-www-form-urlencoded'),
    );
    await send('PUT', '/hooks/w1/t', body: 'just text', type: ContentType.text);
    await send('GET', '/hooks/w1/t?only=query');
    expect(calls[0].$3['body'], {'a': '1', 'b': 'two words'});
    expect(calls[1].$3['body'], 'just text');
    expect(calls[2].$3['body'], <String, Object?>{});
    expect(calls[2].$3['query'], {'only': 'query'});
  });

  test('refuses other paths, other methods and oversized bodies', () async {
    expect((await send('POST', '/elsewhere')).$1, 404);
    expect((await send('POST', '/hooks/w1')).$1, 404);
    expect((await send('OPTIONS', '/hooks/w1/t')).$1, 405);
    final large = 'x' * (WorkflowWebhookServer.maximumBodyBytes + 10);
    expect(
      (await send('POST', '/hooks/w1/t', body: large, type: ContentType.text))
          .$1,
      413,
    );
    expect(calls, isEmpty);
  });
}
