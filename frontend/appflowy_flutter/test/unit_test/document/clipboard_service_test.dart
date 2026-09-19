import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TargetPlatform? previousPlatform;
  setUp(() {
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    ClipboardService.mockSetData(null);
  });
  tearDown(() {
    ClipboardService.mockSetData(null);
    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  group('compatibility', () {
    test('legacy data constructor keeps an empty file list and image tuple',
        () {
      const empty = ClipboardServiceData(plainText: 'legacy');
      final bytes = Uint8List.fromList([0, 255, 17]);
      final image = ('png', bytes);
      final data = ClipboardServiceData(image: image);

      expect(empty.plainText, 'legacy');
      expect(empty.files, isEmpty);
      expect(() => empty.files.clear(), throwsUnsupportedError);
      expect(data.image?.$1, 'png');
      expect(data.image?.$2, same(bytes));
      expect(data.files, isEmpty);
    });

    test('an unavailable reader produces empty data', () async {
      final data =
          await ClipboardService(readClipboard: () async => null).getData();

      _expectEmpty(data);
    });

    test('an unsupported clipboard read produces empty data', () async {
      final data = await ClipboardService(
        readClipboard: () async =>
            throw UnsupportedError('Clipboard unavailable'),
      ).getData();

      _expectEmpty(data);
    });

    test('an actual empty ClipboardReader produces empty data', () async {
      _expectEmpty(await _service([]).getData());
    });

    test('mockSetData still bypasses both default and injected readers',
        () async {
      var reads = 0;
      final service = ClipboardService(
        readClipboard: () async {
          reads++;
          return ClipboardReader([]);
        },
      );
      final mock = ClipboardServiceData(
        plainText: 'mock',
        files: [Uri.file(r'C:\clipboard\mock.pdf', windows: true)],
      );
      ClipboardService.mockSetData(mock);

      expect(await ClipboardService().getData(), same(mock));
      expect(await service.getData(), same(mock));
      expect(reads, 0);

      ClipboardService.mockSetData(null);
      _expectEmpty(await service.getData());
      expect(reads, 1);
    });

    test('each read obtains a fresh reader from the factory', () async {
      var reads = 0;
      final service = ClipboardService(
        readClipboard: () async => ClipboardReader([
          _ClipboardItem({'NativeShell_CF_13': 'read ${++reads}'}),
        ]),
      );

      expect((await service.getData()).plainText, 'read 1');
      expect((await service.getData()).plainText, 'read 2');
    });
  });

  group('native files', () {
    test('collects mixed CF_HDROP items in order without extension filtering',
        () async {
      final paths = [
        for (final name in [
          'photo.png',
          'photo.jpeg',
          'animation.gif',
          'picture.webp',
          'vector.svg',
          'photo.heic',
          'document.pdf',
          'notes.txt',
          'table.csv',
          'document.docx',
          'audio.mp3',
          'movie.mp4',
          'archive.zip',
          'arbitrary.unknown',
          'no-extension',
          'Original # 100% 文.pdf',
          'photo.png',
        ])
          'C:\\clipboard\\$name',
      ];
      final items = <_ClipboardItem>[
        _ClipboardItem({'NativeShell_CF_13': 'not a native file'}),
        for (final path in paths) _ClipboardItem({'NativeShell_CF_15': path}),
      ];

      final data = await _service(items).getData();

      expect(
        data.files,
        paths.map((path) => Uri.file(path, windows: true)),
      );
      expect(data.files.first, data.files.last);
      expect(data.plainText, 'not a native file');
      expect(data.image, isNull);
      expect(items.every((item) => item.rawReader == null), isTrue);
      expect(items.every((item) => item.fileReads.isEmpty), isTrue);
    });

    test('returns an unmodifiable file snapshot detached from reader items',
        () async {
      final item = _ClipboardItem({
        'NativeShell_CF_15': r'C:\clipboard\original.pdf',
      });
      final items = <ClipboardDataReader>[item];
      final data = await _service(items).getData();
      final original = Uri.file(r'C:\clipboard\original.pdf', windows: true);

      items.clear();
      item.values['NativeShell_CF_15'] = r'C:\clipboard\changed.pdf';

      expect(data.files, [original]);
      expect(() => data.files.add(original), throwsUnsupportedError);
      expect(() => data.files[0] = original, throwsUnsupportedError);
      expect(() => data.files.clear(), throwsUnsupportedError);
    });

    test('file URIs win over both earlier raw and synthesized raster items',
        () async {
      final bitmap = _ClipboardItem(
        {},
        files: {Formats.png: _FileFailure.synchronous},
      );
      final nativeFile = _ClipboardItem(
        {'NativeShell_CF_15': r'C:\clipboard\photo.png'},
        files: {Formats.png: _FileFailure.readAll},
        synthesized: {Formats.png},
      );

      final data = await _service([bitmap, nativeFile]).getData();

      expect(data.files, [Uri.file(r'C:\clipboard\photo.png', windows: true)]);
      expect(data.image, isNull);
      expect(bitmap.fileReads, isEmpty);
      expect(nativeFile.fileReads, isEmpty);
    });

    test('optional decoding failures cannot discard valid native files',
        () async {
      final item = _ClipboardItem({
        'NativeShell_CF_15': r'C:\clipboard\report.pdf',
        'NativeShell_CF_13': 42,
        'HTML Format': utf8.encode('StartFragment:not-a-number'),
        'io.appflowy.InAppJsonType': '%',
        'io.appflowy.TableJsonType': const _ReadFailure(),
        'UniformResourceLocatorW': 42,
      });

      final data = await _service([item]).getData();

      expect(data.files, [Uri.file(r'C:\clipboard\report.pdf', windows: true)]);
      expect(data.plainText, isNull);
      expect(data.html, isNull);
      expect(data.inAppJson, isNull);
      expect(data.tableJson, isNull);
      expect(data.image, isNull);
    });

    test('unsupported availability on one item does not hide later files',
        () async {
      final unsupported = _ClipboardItem(
        {},
        unsupported: {Formats.fileUri, Formats.htmlText, inAppJsonFormat},
      );
      final valid = _ClipboardItem({
        'NativeShell_CF_15': r'C:\clipboard\report.pdf',
      });

      final data = await _service([unsupported, valid]).getData();

      expect(data.files, [Uri.file(r'C:\clipboard\report.pdf', windows: true)]);
    });

    final unusableNativePaths = <String, Object?>{
      'null': null,
      'empty': '',
      'relative': 'relative.png',
      'unsupported type': 42,
      'read failure': const _ReadFailure(),
    };
    for (final entry in unusableNativePaths.entries) {
      test('${entry.key} file item does not hide a later valid file', () async {
        final data = await _service([
          _ClipboardItem({'NativeShell_CF_15': entry.value}),
          _ClipboardItem({'NativeShell_CF_15': r'C:\clipboard\valid.bin'}),
        ]).getData();

        expect(
          data.files,
          [Uri.file(r'C:\clipboard\valid.bin', windows: true)],
        );
      });
    }

    for (final text in [
      'https://example.invalid/photo.png',
      r'C:\clipboard\photo.png',
      '/clipboard/photo.png',
      'file:///C:/clipboard/photo.png',
    ]) {
      test('plain text is never promoted to a native file: $text', () async {
        final data = await _service([
          _ClipboardItem({'NativeShell_CF_13': text}),
        ]).getData();

        expect(data.plainText, text);
        expect(data.files, isEmpty);
        expect(data.image, isNull);
      });
    }

    test('a file-scheme ordinary URI remains text, not a native file',
        () async {
      const uri = 'file:///C:/clipboard/photo.png';
      final data = await _service([
        _ClipboardItem({'UniformResourceLocatorW': uri}),
      ]).getData();

      expect(data.plainText, uri);
      expect(data.files, isEmpty);
    });

    test('the non-Windows file-URI codec also preserves native files',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final uri = Uri.file('/clipboard/Original # 100% 文.pdf', windows: false);
      final data = await _service([
        _ClipboardItem({'text/uri-list': uri.toString()}),
      ]).getData();

      expect(data.files, [uri]);
    });
  });

  group('text and structured data', () {
    test('preserves actual plain, HTML, in-app JSON and table JSON codecs',
        () async {
      const plain = 'Plain text 文';
      const html = '<p>Rich <strong>text</strong> 文</p>';
      const inApp = '{"document":{"type":"page","children":[]}}';
      const table = '{"rows":[["one","two"]]}';
      final item = await _encodedItem([
        Formats.uri(NamedUri(Uri.parse('https://example.invalid/other'))),
        Formats.plainText(plain),
        Formats.htmlText(html),
        inAppJsonFormat(inApp),
        tableJsonFormat(table),
      ]);
      // Exercise the real CF_HTML header/fragment decoder, not only text/html.
      item.values.remove('text/html');

      final data = await _service([item]).getData();

      expect(data.plainText, plain);
      expect(data.html, html);
      expect(data.inAppJson, inApp);
      expect(data.tableJson, table);
      expect(data.files, isEmpty);
      expect(data.image, isNull);
    });

    test('an ordinary native URL remains the plain-text fallback', () async {
      const url = 'https://example.invalid/document';
      final data = await _service([
        _ClipboardItem({'UniformResourceLocatorW': url}),
      ]).getData();

      expect(data.plainText, url);
      expect(data.files, isEmpty);
    });

    test('empty plain text is preserved ahead of an ordinary URI', () async {
      final data = await _service([
        _ClipboardItem({
          'NativeShell_CF_13': '',
          'UniformResourceLocatorW': 'https://example.invalid/document',
        }),
      ]).getData();

      expect(data.plainText, '');
    });

    test('null and failing advertised values fall through to later items',
        () async {
      final data = await _service([
        _ClipboardItem({
          'NativeShell_CF_13': null,
          'io.appflowy.InAppJsonType': null,
        }),
        _ClipboardItem({
          'NativeShell_CF_13': const _ReadFailure(),
          'io.appflowy.InAppJsonType': '%',
        }),
        _ClipboardItem({
          'NativeShell_CF_13': 'usable text',
          'io.appflowy.InAppJsonType': utf8.encode('{"children":[]}'),
        }),
      ]).getData();

      expect(data.plainText, 'usable text');
      expect(data.inAppJson, '{"children":[]}');
    });

    test('independent formats on different items are all preserved', () async {
      final data = await _service([
        _ClipboardItem({'NativeShell_CF_13': 'plain'}),
        _ClipboardItem({'text/html': '<p>html</p>'}),
        _ClipboardItem({'io.appflowy.InAppJsonType': '%7B%7D'}),
        _ClipboardItem({'io.appflowy.TableJsonType': utf8.encode('[]')}),
      ]).getData();

      expect(data.plainText, 'plain');
      expect(data.html, '<p>html</p>');
      expect(data.inAppJson, '{}');
      expect(data.tableJson, '[]');
    });
  });

  group('raster fallback', () {
    for (final (name, format) in [
      ('png', Formats.png),
      ('jpeg', Formats.jpeg),
      ('gif', Formats.gif),
      ('webp', Formats.webp),
    ]) {
      test('raw $name bytes retain the original image tuple', () async {
        final bytes = Uint8List.fromList([0, 255, 17, 42]);
        final item = _ClipboardItem(
          {},
          files: {format: bytes},
          // Windows DIB-to-PNG conversion is synthesized but is not a file URI.
          synthesized: name == 'png' ? {format} : {},
        );

        final data = await _service([item]).getData();

        expect(data.files, isEmpty);
        expect(data.image?.$1, name);
        expect(data.image?.$2, same(bytes));
        expect(item.fileReads, [format]);
        expect(item.uriSynthesisRequests, [false]);
      });
    }

    test('optional decoding failures cannot block raw bitmap data', () async {
      final bytes = Uint8List.fromList([0, 255, 17]);
      final data = await _service([
        _ClipboardItem(
          {
            'NativeShell_CF_13': const _ReadFailure(),
            'HTML Format': utf8.encode('StartFragment:not-a-number'),
            'io.appflowy.InAppJsonType': '%',
            'io.appflowy.TableJsonType': const _ReadFailure(),
            'UniformResourceLocatorW': 42,
          },
          files: {Formats.png: bytes},
        ),
      ]).getData();

      expect(data.files, isEmpty);
      expect(data.image?.$1, 'png');
      expect(data.image?.$2, bytes);
    });

    for (final value in <Object?>[
      null,
      '',
      'relative.png',
      42,
      const _ReadFailure(),
    ]) {
      test('unusable CF_HDROP value $value retains bitmap fallback', () async {
        final bytes = Uint8List.fromList([1, 2, 255]);
        final item = _ClipboardItem(
          {'NativeShell_CF_15': value},
          files: {Formats.png: bytes},
        );

        final data = await _service([item]).getData();

        expect(data.files, isEmpty);
        expect(data.image?.$1, 'png');
        expect(data.image?.$2, bytes);
        expect(item.uriSynthesisRequests, [false]);
      });
    }

    for (final uri in [
      'https://example.invalid/photo.png',
      'file:///clipboard/invalid%FFname.png',
      'file:///clipboard/photo.png?query=value',
      'file:///clipboard/photo.png#fragment',
      'file:///clipboard/invalid%00name.png',
      'file:///clipboard/invalid%2Fname.png',
      'file://[invalid',
    ]) {
      test('unusable URI $uri does not suppress bitmap fallback', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final bytes = Uint8List.fromList([1, 2, 255]);
        final data = await _service([
          _ClipboardItem(
            {'text/uri-list': uri},
            files: {Formats.png: bytes},
          ),
        ]).getData();

        expect(data.files, isEmpty);
        expect(data.image?.$1, 'png');
        expect(data.image?.$2, bytes);
      });
    }

    final failures = <String, Object?>{
      'null progress': null,
      'empty bytes': Uint8List(0),
      'synchronous exception': _FileFailure.synchronous,
      'callback error': _FileFailure.callback,
      'readAll exception': _FileFailure.readAll,
    };
    for (final entry in failures.entries) {
      test('first PNG ${entry.key} falls back to JPEG on the same item',
          () async {
        final bytes = Uint8List.fromList([255, 216, 255, 217]);
        final item = _ClipboardItem(
          {},
          files: {Formats.png: entry.value, Formats.jpeg: bytes},
        );

        final data = await _service([item]).getData();

        expect(data.image?.$1, 'jpeg');
        expect(data.image?.$2, bytes);
        expect(item.fileReads, [Formats.png, Formats.jpeg]);
      });

      test('first PNG ${entry.key} falls back to PNG on a later item',
          () async {
        final bytes = Uint8List.fromList([0, 255, 17]);
        final data = await _service([
          _ClipboardItem({}, files: {Formats.png: entry.value}),
          _ClipboardItem({}, files: {Formats.png: bytes}),
        ]).getData();

        expect(data.image?.$1, 'png');
        expect(data.image?.$2, bytes);
      });
    }

    test('unsupported format availability still permits another raster format',
        () async {
      final bytes = Uint8List.fromList([7, 9, 11]);
      final data = await _service([
        _ClipboardItem(
          {},
          unsupported: {Formats.fileUri, Formats.png, Formats.htmlText},
          files: {Formats.jpeg: bytes},
        ),
      ]).getData();

      expect(data.files, isEmpty);
      expect(data.image?.$1, 'jpeg');
      expect(data.image?.$2, bytes);
    });

    test('keeps existing PNG preference even if an earlier item has JPEG',
        () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final jpeg = _ClipboardItem({}, files: {Formats.jpeg: Uint8List(1)});
      final data = await _service([
        jpeg,
        _ClipboardItem({}, files: {Formats.png: bytes}),
      ]).getData();

      expect(data.image?.$1, 'png');
      expect(data.image?.$2, bytes);
      expect(jpeg.fileReads, isEmpty);
    });

    test('exhausted raster failures leave plain text usable', () async {
      final data = await _service([
        _ClipboardItem(
          {'NativeShell_CF_13': 'still usable'},
          files: {
            Formats.png: null,
            Formats.jpeg: _FileFailure.callback,
            Formats.gif: Uint8List(0),
            Formats.webp: _FileFailure.readAll,
          },
        ),
      ]).getData();

      expect(data.plainText, 'still usable');
      expect(data.files, isEmpty);
      expect(data.image, isNull);
    });
  });
}

ClipboardService _service(List<ClipboardDataReader> items) => ClipboardService(
      readClipboard: () async => ClipboardReader(items),
    );

void _expectEmpty(ClipboardServiceData data) {
  expect(data.plainText, isNull);
  expect(data.html, isNull);
  expect(data.inAppJson, isNull);
  expect(data.tableJson, isNull);
  expect(data.image, isNull);
  expect(data.files, isEmpty);
}

Future<_ClipboardItem> _encodedItem(
  List<FutureOr<EncodedData>> representations,
) async {
  final values = <String, Object?>{};
  for (final pending in representations) {
    final encoded = await pending;
    for (final representation in encoded.representations) {
      final serialized = representation.serialize() as Map;
      expect(serialized['type'], 'simple');
      values[representation.format] = serialized['data'];
    }
  }
  return _ClipboardItem(values);
}

/// Uses real format codecs at the platform-data boundary, without native handles.
/// Inheriting ClipboardDataReader also deliberately leaves rawReader null.
class _ClipboardItem extends ClipboardDataReader
    implements PlatformDataProvider {
  _ClipboardItem(
    this.values, {
    this.files = const {},
    this.unsupported = const {},
    this.synthesized = const {},
  });

  final Map<String, Object?> values;
  final Map<FileFormat, Object?> files;
  final Set<DataFormat> unsupported;
  final Set<DataFormat> synthesized;
  final fileReads = <FileFormat?>[];
  final uriSynthesisRequests = <bool>[];

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) {
    final formats = <DataFormat>[];
    for (final format in allFormats) {
      if (unsupported.contains(format)) {
        throw UnsupportedError('Format unavailable');
      }
      if (files.containsKey(format) ||
          (format is ValueFormat &&
              format.codec.decodingFormats.any(values.containsKey))) {
        formats.add(format);
      }
    }
    return formats;
  }

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async {
    for (final platformFormat in format.codec.decodingFormats) {
      if (values.containsKey(platformFormat)) {
        return format.codec.decode(this, platformFormat);
      }
    }
    return null;
  }

  @override
  ReadProgress? getValue<T extends Object>(
    ValueFormat<T> format,
    AsyncValueChanged<T?> onValue, {
    ValueChanged<Object>? onError,
  }) {
    throw UnimplementedError('Clipboard tests use readValue');
  }

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    ValueChanged<Object>? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    fileReads.add(format);
    uriSynthesisRequests.add(synthesizeFilesFromURIs);
    final value = files[format];
    if (value == null) {
      return null;
    }
    if (value == _FileFailure.synchronous) {
      throw const _ReadFailure();
    }
    if (value == _FileFailure.callback) {
      scheduleMicrotask(() => onError!(const _ReadFailure()));
    } else {
      final file = value == _FileFailure.readAll
          ? _MemoryFile(Uint8List(0), failRead: true)
          : _MemoryFile(value as Uint8List);
      unawaited(Future<void>.sync(() => onFile(file)));
    }
    return _ReadProgress();
  }

  @override
  Future<Object?> getData(String format) async {
    final value = values[format];
    if (value is _ReadFailure) {
      throw value;
    }
    return value;
  }

  @override
  List<String> getAllFormats() => values.keys.toList();

  @override
  List<PlatformFormat> get platformFormats => getAllFormats();

  @override
  bool isSynthesized(DataFormat format) => synthesized.contains(format);

  @override
  bool isVirtual(DataFormat format) => false;

  @override
  Future<String?> getSuggestedName() async => null;

  @override
  Future<VirtualFileReceiver?> getVirtualFileReceiver({
    FileFormat? format,
  }) async =>
      null;
}

enum _FileFailure { synchronous, callback, readAll }

class _ReadFailure implements Exception {
  const _ReadFailure();
}

class _ReadProgress extends Fake implements ReadProgress {}

class _MemoryFile extends Fake implements DataReaderFile {
  _MemoryFile(this.bytes, {this.failRead = false});

  final Uint8List bytes;
  final bool failRead;

  @override
  Future<Uint8List> readAll() async {
    if (failRead) {
      throw const _ReadFailure();
    }
    return bytes;
  }
}
