import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_bridge.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('officeDocumentTypeFor', () {
    test('maps office extensions to the editor families', () {
      expect(officeDocumentTypeFor('a.docx'), OfficeDocumentType.word);
      expect(officeDocumentTypeFor('a.ODT'), OfficeDocumentType.word);
      expect(officeDocumentTypeFor('a.xlsx'), OfficeDocumentType.cell);
      expect(officeDocumentTypeFor('a.pptx'), OfficeDocumentType.slide);
      expect(officeDocumentTypeFor('a.png'), isNull);
    });
  });

  group('OfficeServerSettings', () {
    test('normalizes the server address', () {
      const settings = OfficeServerSettings(serverUrl: 'localhost:8080/');
      expect(settings.baseUri.toString(), 'http://localhost:8080');
      expect(settings.isConfigured, isTrue);
      expect(const OfficeServerSettings().isConfigured, isFalse);
    });

    test('routes the callback back through the docker host by default', () {
      const local = OfficeServerSettings(serverUrl: 'http://localhost:8080');
      expect(local.resolveBridgeHost(), 'host.docker.internal');

      const explicit = OfficeServerSettings(
        serverUrl: 'http://127.0.0.1:8080',
        bridgeHost: '192.168.1.20',
      );
      expect(explicit.resolveBridgeHost(), '192.168.1.20');
    });

    test('round trips through json', () {
      const settings = OfficeServerSettings(
        serverUrl: 'http://docs.local',
        jwtSecret: 'secret',
        bridgeHost: 'host',
      );
      expect(
        OfficeServerSettings.fromJson(
          Map<String, dynamic>.from(settings.toJson()),
        ),
        settings,
      );
    });
  });

  group('officeJwt', () {
    test('produces a three part token with the payload in the middle', () {
      final token = officeJwt(const {'a': 1}, 'secret');
      final parts = token.split('.');
      expect(parts, hasLength(3));
      expect(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))),
        {'a': 1},
      );
      expect(officeJwt(const {'a': 1}, 'other'), isNot(token));
    });
  });

  group('buildOfficeEditorHtml', () {
    const document = BridgedOfficeDocument(
      downloadUrl: 'http://host:1234/documents/tok/file.docx',
      callbackUrl: 'http://host:1234/documents/tok/callback',
      token: 'tok',
    );

    String render({bool editable = true, String secret = ''}) {
      return buildOfficeEditorHtml(
        serverOrigin: 'http://docs.local',
        document: document,
        fileName: 'Report.docx',
        documentKey: 'key-1',
        editable: editable,
        isDark: false,
        background: const Color(0xFFFFFFFF),
        secret: secret,
      );
    }

    test('loads the api from the configured server', () {
      expect(
        render(),
        contains('http://docs.local/web-apps/apps/api/documents/api.js'),
      );
    });

    test('passes the bridge urls and edit mode', () {
      final html = render();
      expect(html, contains(document.downloadUrl));
      expect(html, contains(document.callbackUrl));
      expect(html, contains('"mode":"edit"'));
      expect(html, contains('"documentType":"word"'));
      expect(html, contains('"fileType":"docx"'));
    });

    test('drops the callback when the file is read only', () {
      final html = render(editable: false);
      expect(html, contains('"mode":"view"'));
      expect(html, isNot(contains(document.callbackUrl)));
    });

    test('signs the configuration when a secret is set', () {
      expect(render(), isNot(contains('"token"')));
      expect(render(secret: 'shh'), contains('"token":"'));
    });
  });
}
