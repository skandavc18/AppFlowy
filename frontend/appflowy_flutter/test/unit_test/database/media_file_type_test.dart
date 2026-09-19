import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('file inference', () {
    for (final name in [
      'photo.JPG',
      'photo.JPEG',
      'photo.JpEg',
      'photo.JFIF',
      'photo.jFiF',
      'photo.PNG',
      'photo.GIF',
      'photo.WEBP',
      'photo.BMP',
      'photo.TIFF',
    ]) {
      test('recognises $name with absent or generic MIME', () {
        expect(imgExtensionRegex.hasMatch(name), isTrue);
        for (final mime in [
          null,
          '',
          'application/octet-stream',
          'APPLICATION/OCTET-STREAM; charset=binary',
          'application/x-unknown',
        ]) {
          expect(inferFileType(name, mimeType: mime), FileType.image);
          expect(XFile(name, mimeType: mime).fileType, FileType.image);
        }
      });
    }

    final sources = <String, FileType>{
      r'C:\photos\June #1\100% real.JPG': FileType.image,
      r'C:\photos\photo.JPG#notes.txt': FileType.text,
      r'\\server\photos\June #1.JFIF': FileType.image,
      'C:/photos/June #1/photo.JPEG': FileType.image,
      '/tmp/June #1/photo.JPG': FileType.image,
      'photo.JPG#notes.txt': FileType.text,
      'file:///C:/photos/June%20%231.JFIF': FileType.image,
      'file:///tmp/photo%2EJPG': FileType.image,
      'https://example.invalid/photo.JPG?download=1#preview': FileType.image,
      'HTTPS://example.invalid/photo.JFIF?name=readme.txt': FileType.image,
      'https://example.invalid/photo%2EJPG?signature=x': FileType.image,
      '//example.invalid/photo.PNG?download=1': FileType.image,
      'https://example.invalid/download?file=photo.JPG': FileType.other,
      'https://example.invalid/document.PDF?preview=photo.JPG':
          FileType.document,
      'https://example.invalid/page#photo.JPG': FileType.other,
      'https://photo.JPG': FileType.other,
      'https://example.invalid/photo.JPG/': FileType.other,
      'data:text/plain,not-a-photo.JPG': FileType.other,
      'blob:https://example.invalid/photo.JPG': FileType.other,
      'https://[invalid/photo.JPG': FileType.other,
      'movie.MP4': FileType.video,
      'voice.WAV': FileType.audio,
      'report.PDF': FileType.document,
      'files.ZIP': FileType.archive,
      'notes.TXT': FileType.text,
    };
    for (final entry in sources.entries) {
      test('matches only the file path: ${entry.key}', () {
        expect(inferFileType(entry.key), entry.value);
        expect(XFile(entry.key).fileType, entry.value);
      });
    }

    test('raw local path spelling is unchanged', () {
      for (final path in [
        r'C:\a # b\100%25.JPG',
        r'\\host\a # b\photo.JPG',
        'C:/a # b/photo.JPG',
        '/tmp/a # b/photo.JPG',
        'a # b.JPG',
      ]) {
        expect(fileTypePath(path), path);
      }
    });

    test('MIME is case-insensitive, ignores parameters and wins over suffix',
        () {
      final mimeTypes = <String, FileType>{
        ' IMAGE/JPEG ; name=anything.pdf': FileType.image,
        'image/pjpeg': FileType.image,
        'VIDEO/MP4': FileType.video,
        'AuDiO/MPEG': FileType.audio,
        'TEXT/PLAIN; charset=UTF-8': FileType.text,
        'APPLICATION/PDF': FileType.document,
        'application/msword': FileType.document,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
            FileType.document,
        'application/vnd.oasis.opendocument.text': FileType.document,
        'APPLICATION/X-ZIP-COMPRESSED': FileType.archive,
        'application/java-archive': FileType.archive,
        'application/vnd.rar': FileType.archive,
        'application/rtf': FileType.text,
        'application/json': FileType.text,
      };
      for (final entry in mimeTypes.entries) {
        expect(
          inferFileType('misleading.JPG', mimeType: entry.key),
          entry.value,
        );
        expect(
          XFile('misleading.JPG', mimeType: entry.key).fileType,
          entry.value,
        );
      }
      expect(
        inferFileType('unknown', mimeType: 'application/not-image'),
        FileType.other,
      );
    });

    test('HEIC and AVIF extensions do not promise an installed codec', () {
      for (final extension in ['HEIC', 'HEIF', 'AVIF']) {
        expect(inferFileType('photo.$extension'), FileType.other);
        // Keep MIME-based classification, which has always accepted image/*.
        expect(
          inferFileType('photo.$extension', mimeType: 'image/$extension'),
          FileType.image,
        );
      }
    });
  });

  group('saved media resolution', () {
    for (final type in [MediaFileTypePB.Other, MediaFileTypePB.Link]) {
      for (final name in ['old.JPG', 'old.JFIF']) {
        test('$type $name resolves without mutating the saved attachment', () {
          final file = MediaFilePB(
            id: 'original-id',
            name: name,
            url: 'https://example.invalid/opaque-storage-id?signature=value',
            uploadType: FileUploadTypePB.CloudFile,
            fileType: type,
          );
          final before = file.writeToBuffer();
          file.freeze();
          expect(file.effectiveFileType, MediaFileTypePB.Image);
          expect(file.isImage, isTrue);
          expect(file.writeToBuffer(), orderedEquals(before));
          expect(file.fileType, type);
          expect(file.id, 'original-id');
        });
      }
    }

    test('URL path recovers a photo whose saved name has no extension', () {
      for (final url in [
        r'C:\photos\old #1.JPG',
        'file:///C:/photos/old%20%231.JFIF',
        'https://example.invalid/old.JPG?signature=value',
      ]) {
        expect(MediaFilePB(name: 'Holiday', url: url).isImage, isTrue);
      }
    });

    test('explicit known non-image types cannot be coerced by photo names', () {
      for (final type in [
        MediaFileTypePB.Document,
        MediaFileTypePB.Text,
        MediaFileTypePB.Audio,
        MediaFileTypePB.Video,
        MediaFileTypePB.Archive,
      ]) {
        final file = MediaFilePB(
          name: 'looks-like.JPG',
          url: 'photo.JFIF',
          fileType: type,
        );
        expect(file.effectiveFileType, type);
        expect(file.isImage, isFalse);
      }
    });

    test('non-image names and query suffixes stay non-images', () {
      for (final file in [
        MediaFilePB(
          name: 'report.PDF',
          url: 'https://example.invalid/photo.JPG',
        ),
        MediaFilePB(
          name: 'download',
          url: 'https://example.invalid/?file=photo.JPG',
        ),
        MediaFilePB(
          name: 'site',
          url: 'https://example.invalid/#photo.JPG',
          fileType: MediaFileTypePB.Link,
        ),
        MediaFilePB(name: 'photo.JPG.txt', url: 'opaque'),
      ]) {
        expect(file.isImage, isFalse);
      }
    });

    test('an explicit image stays an image without a filename extension', () {
      expect(
        MediaFilePB(
          name: 'Holiday',
          url: 'opaque',
          fileType: MediaFileTypePB.Image,
        ).isImage,
        isTrue,
      );
    });

    test('viewer projection retains order, identity and ID-based selection',
        () {
      final first = MediaFilePB(id: 'first', name: 'one.JPG', url: 'one');
      final document = MediaFilePB(
        id: 'pdf',
        name: 'report.pdf',
        fileType: MediaFileTypePB.Document,
      );
      final second = MediaFilePB(
        id: 'second',
        name: 'two.JFIF',
        url: 'two',
        fileType: MediaFileTypePB.Link,
      );
      final files = [first, document, second];
      final provider =
          MediaFileImageProvider(files: files, initialFileId: second.id);
      expect(provider.files, orderedEquals([first, second]));
      expect(provider.files.first, same(first));
      expect(provider.imageCount, 2);
      expect(provider.initialIndex, 1);
      expect(provider.getImage(1).url, second.url);
      final reordered = MediaFileImageProvider(
        files: files.reversed,
        initialFileId: second.id,
      );
      expect(
        reordered.files.map((file) => file.id),
        orderedEquals(['second', 'first']),
      );
      expect(reordered.initialIndex, 0);
      expect(files, orderedEquals([first, document, second]));
    });
  });
}
