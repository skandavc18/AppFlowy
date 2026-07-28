import 'dart:io';
import 'dart:typed_data';

import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:universal_platform/universal_platform.dart';

Future<File> materializeMediaFile({
  required String source,
  required String name,
  Map<String, String> httpHeaders = const {},
}) async {
  final localFile = File(source);
  if (await localFile.exists()) {
    return localFile;
  }

  final uri = Uri.parse(source);
  if (uri.isScheme('file')) {
    final file = File.fromUri(uri);
    if (await file.exists()) {
      return file;
    }
  }

  final response = await http.get(uri, headers: httpHeaders);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Unable to download media (${response.statusCode})',
      uri: uri,
    );
  }

  final directory = Directory(
    p.join((await getTemporaryDirectory()).path, 'appflowy_media'),
  );
  await directory.create(recursive: true);
  final safeName = p.basename(name).replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final file = File(
    p.join(
      directory.path,
      safeName.isEmpty ? p.basename(uri.path) : safeName,
    ),
  );
  await file.writeAsBytes(response.bodyBytes, flush: true);
  return file;
}

Future<void> copyMedia({
  required String source,
  required String name,
  bool shareAsLink = false,
  Map<String, String> httpHeaders = const {},
}) async {
  if (shareAsLink) {
    await SystemClipboard.instance?.write([
      DataWriterItem()..add(Formats.plainText(source)),
    ]);
    return;
  }

  final file = await materializeMediaFile(
    source: source,
    name: name,
    httpHeaders: httpHeaders,
  );
  await SystemClipboard.instance?.write([
    DataWriterItem()
      ..add(Formats.fileUri(file.uri))
      ..add(Formats.plainText(file.path)),
  ]);
}

Future<void> shareMedia({
  required String source,
  required String name,
  bool shareAsLink = false,
  Map<String, String> httpHeaders = const {},
}) async {
  if (shareAsLink) {
    await Share.share(source);
    return;
  }

  final file = await materializeMediaFile(
    source: source,
    name: name,
    httpHeaders: httpHeaders,
  );
  await Share.shareXFiles(
    [XFile(file.path)],
    fileNameOverrides: [name],
  );
}

Future<bool> downloadMedia({
  required String source,
  required String name,
  Map<String, String> httpHeaders = const {},
}) async {
  final file = await materializeMediaFile(
    source: source,
    name: name,
    httpHeaders: httpHeaders,
  );
  return saveMediaBytes(bytes: await file.readAsBytes(), name: name);
}

Future<bool> saveMediaBytes({
  required Uint8List bytes,
  required String name,
}) async {
  final path = await FilePicker().saveFile(
    fileName: name,
    bytes: UniversalPlatform.isMobile ? bytes : null,
  );
  if (path != null && !UniversalPlatform.isMobile) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path != null;
}
