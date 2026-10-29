import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _AccessNative = Int32 Function(Pointer<Utf8> path, Int32 mode);
typedef _AccessDart = int Function(Pointer<Utf8> path, int mode);

/// `W_OK` has the same value on Linux and macOS.
const _writeOk = 2;

/// The owner write bit, which Windows clears for a read-only file.
const _ownerWrite = 0x80;

_AccessDart? _access;

/// Whether AppFlowy may save changes to [file].
///
/// This asks without opening the file for writing: such an open would create
/// the file if it had just been removed, and would tell anything watching it
/// that it had been written.
Future<bool> canWriteExternalFile(File file) async {
  try {
    if (Platform.isWindows) {
      final stat = await file.stat();
      return stat.type == FileSystemEntityType.file &&
          stat.mode & _ownerWrite != 0;
    }
    final access = _access ??= DynamicLibrary.process()
        .lookupFunction<_AccessNative, _AccessDart>('access');
    final path = file.path.toNativeUtf8();
    try {
      return access(path, _writeOk) == 0;
    } finally {
      malloc.free(path);
    }
  } catch (_) {
    // Saving would only fail later; showing the file read-only is safe.
    return false;
  }
}
