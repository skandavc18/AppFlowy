import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/html_preview_resource_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late HtmlPreviewResourceHost host;
  late HttpClient client;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('af_preview_resources_');
    host = HtmlPreviewResourceHost(directory: root.path);
    client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    await File('${root.path}/local image.svg').writeAsString('<svg/>');
    await File('${root.path}/private.md')
        .writeAsString('Do not serve documents.');
  });

  tearDown(() async {
    client.close(force: true);
    await host.dispose();
    await root.delete(recursive: true);
  });

  Future<({int status, String body, HttpHeaders headers})> get(
    Uri uri, {
    String method = 'GET',
    String? origin,
    String? hostHeader,
  }) async {
    final request = await client.openUrl(method, uri);
    if (origin != null) request.headers.set('Origin', origin);
    if (hostHeader != null) {
      request.headers.set(HttpHeaders.hostHeader, hostHeader);
    }
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
      headers: response.headers
    );
  }

  test('provides a real base for encoded local images and nested CSS assets',
      () async {
    final url = await host.load('<img src="local%20image.svg">');
    expect(url.host, '127.0.0.1');
    final document = await get(url);
    expect(document.status, 200);
    expect(document.body, '<img src="local%20image.svg">');
    expect(document.headers.value('Referrer-Policy'), 'no-referrer');
    expect(
      document.headers.value('Content-Security-Policy'),
      contains("script-src 'none'"),
    );
    final image = await get(url.resolve('local%20image.svg'));
    expect(image.status, 200);
    expect(image.body, '<svg/>');
    expect(image.headers.contentType?.mimeType, 'image/svg+xml');
    await Directory('${root.path}/styles').create();
    await File('${root.path}/styles/reader.css')
        .writeAsString('body { background: url(../local%20image.svg); }');
    final stylesheet = await get(url.resolve('styles/reader.css'));
    expect(stylesheet.status, 200);
    expect(stylesheet.headers.contentType?.mimeType, 'text/css');
    final nestedImage =
        url.resolve('styles/reader.css').resolve('../local%20image.svg');
    expect((await get(nestedImage)).status, 200);
  });

  test(
      'blocks traversal, foreign origins, host rebinding and non-resource files',
      () async {
    final url = await host.load('<p>Preview</p>');
    final image = url.resolve('local%20image.svg');
    for (final target in [
      url.resolve('../local%20image.svg'),
      url.resolve('private.md'),
      url.resolve('missing.svg'),
      url.replace(path: '/wrong-token/local%20image.svg'),
      url.resolve('%2e%2e%5clocal%20image.svg'),
      url.resolve('C%3a%5cWindows%5cimage.svg'),
      url.resolve('.env'),
      url.resolve('./'),
    ]) {
      expect((await get(target)).status, 404);
    }
    expect((await get(image, origin: 'https://unrelated.example')).status, 404);
    expect((await get(image, hostHeader: 'unrelated.example')).status, 404);
    expect((await get(image, method: 'POST')).status, 405);
    final head = await get(image, method: 'HEAD');
    expect(head.status, 200);
    expect(head.body, isEmpty);
  });

  test('document revisions and independent previews never reuse stale HTML',
      () async {
    final first = await host.load('<p>First</p>');
    final second = await host.load('<p>Second</p>');
    expect(first, isNot(second));
    expect((await get(first)).status, 404);
    expect((await get(second)).body, '<p>Second</p>');
    final other = HtmlPreviewResourceHost(directory: root.path);
    try {
      final third = await other.load('<p>Other viewer</p>');
      expect(third.port, isNot(second.port));
      expect(third.pathSegments.first, isNot(second.pathSegments.first));
      expect((await get(third.replace(path: second.path))).status, 404);
    } finally {
      await other.dispose();
    }
  });

  test(
      'disposing during startup closes the pending listener and rejects later loads',
      () async {
    final pending = host.load('<p>Do not keep this alive</p>');
    final expected = expectLater(pending, throwsStateError);
    await host.dispose();
    await expected;
    await expectLater(host.load('<p>Closed</p>'), throwsStateError);
    await host.dispose();
  });

  test('closing a live preview stops serving its resources', () async {
    final url = await host.load('<p>Preview</p>');
    expect((await get(url)).status, 200);
    await host.dispose();
    await expectLater(
      get(url),
      throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
    );
  });
}
