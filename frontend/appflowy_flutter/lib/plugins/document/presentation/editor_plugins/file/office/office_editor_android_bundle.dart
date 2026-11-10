import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'office_embedded_host.dart';

/// The channel MainActivity answers on (see OfficeEditorBundle.kt).
const kOfficeEditorBundleChannel = 'io.appflowy.appflowy/office_editor_bundle';

/// [bytes] in whole megabytes, rounded up.
int officeEditorMegabytes(int bytes) => (bytes / (1024 * 1024)).ceil();

/// Unpacks the editor Android builds carry inside the APK.
///
/// The loopback server can only serve real files, so the first use copies
/// `assets/office_editor` into the app's files. Later sessions reuse that
/// copy for as long as it matches the APK's bundle; an update that brings a
/// different editor replaces it. The copying itself happens off the main
/// thread on the Android side, which reports progress back here.
class AndroidOfficeEditorBundle implements OfficeEditorBundleInstaller {
  AndroidOfficeEditorBundle({
    MethodChannel channel = const MethodChannel(kOfficeEditorBundleChannel),
    Future<Directory> Function() storage = getApplicationSupportDirectory,
  })  : _channel = channel,
        _storage = storage {
    _channel.setMethodCallHandler(_handle);
  }

  static final AndroidOfficeEditorBundle instance = AndroidOfficeEditorBundle();

  final MethodChannel _channel;
  final Future<Directory> Function() _storage;
  final ValueNotifier<OfficeEditorInstallProgress?> _progress =
      ValueNotifier(null);
  Future<Directory>? _installing;
  Directory? _installed;

  @override
  ValueListenable<OfficeEditorInstallProgress?> get progress => _progress;

  @override
  Directory? get installed => _installed;

  /// Where the editor is unpacked: `office_editor` in the app's files.
  Future<Directory> get target async =>
      Directory(p.join((await _storage()).path, kOfficeEditorFolderName));

  @override
  Future<bool> isPackaged() async =>
      await _channel.invokeMethod<bool>('packaged') ?? false;

  @override
  Future<OfficeEditorInstallStatus> status() async {
    final target = await this.target;
    final result = await _channel.invokeMapMethod<String, Object?>(
      'status',
      {'target': target.path},
    );
    final bytes = result?['bytes'];
    return OfficeEditorInstallStatus(
      packaged: result?['packaged'] == true,
      installed:
          result?['installed'] == true && isCompleteOfficeEditorBundle(target),
      bytes: bytes is int ? bytes : null,
    );
  }

  @override
  Future<Directory> install() {
    final installed = _installed;
    if (installed != null && isCompleteOfficeEditorBundle(installed)) {
      return Future.value(installed);
    }
    // Every view opening a document meanwhile waits for the same copy.
    return _installing ??= _install().whenComplete(() => _installing = null);
  }

  Future<Directory> _install() async {
    final target = await this.target;
    final started = DateTime.now();
    try {
      var result = await _extract(target, force: false);
      if (!isCompleteOfficeEditorBundle(target)) {
        // The copy passed its own checks, yet files the editor needs are
        // gone, so it is made again from scratch.
        result = await _extract(target, force: true);
      }
      if (result?['extracted'] == true) {
        final bytes = result?['bytes'];
        Log.info(
          'Unpacked the office editor (${result?['files']} files, '
          '${bytes is int ? officeEditorMegabytes(bytes) : '?'} MB) in '
          '${DateTime.now().difference(started).inMilliseconds} ms.',
        );
      }
    } on PlatformException catch (error) {
      Log.error(
        'Unable to unpack the office editor: ${error.code} ${error.message}',
      );
      throw _describe(error);
    } on MissingPluginException {
      throw const OfficeEditorInstallException(
        'This build of AppFlowy cannot unpack its document editor.',
      );
    } finally {
      _progress.value = null;
    }
    if (!isCompleteOfficeEditorBundle(target)) {
      throw const OfficeEditorInstallException(
        'The document editor in this build of AppFlowy is incomplete.',
      );
    }
    _installed = target;
    return target;
  }

  Future<Map<String, Object?>?> _extract(
    Directory target, {
    required bool force,
  }) =>
      _channel.invokeMapMethod<String, Object?>(
        'extract',
        {'target': target.path, 'force': force},
      );

  Future<Object?> _handle(MethodCall call) async {
    final arguments = call.arguments;
    if (call.method != 'progress' || arguments is! Map) {
      return null;
    }
    if (_installing == null) {
      return null;
    }
    final copied = arguments['copied'];
    final total = arguments['total'];
    _progress.value = OfficeEditorInstallProgress(
      copiedBytes: copied is int ? copied : 0,
      totalBytes: total is int ? total : 0,
    );
    return null;
  }

  OfficeEditorInstallException _describe(PlatformException error) {
    switch (error.code) {
      case 'no_space':
        final details = error.details;
        final required = details is Map ? details['required'] : null;
        return OfficeEditorInstallException(
          required is int
              ? 'There is not enough free storage to prepare the document '
                  'editor. It needs about ${officeEditorMegabytes(required)} '
                  'MB.'
              : 'There is not enough free storage to prepare the document '
                  'editor.',
        );
      case 'not_packaged':
        return const OfficeEditorInstallException(
          'This build of AppFlowy does not include the document editor.',
        );
      default:
        return const OfficeEditorInstallException(
          'AppFlowy could not prepare its document editor.',
        );
    }
  }
}
