import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes video files from names and URLs', () {
    expect(fileMediaKind('Demo.MP4', null), FileMediaKind.video);
    expect(
      fileMediaKind(null, 'https://example.com/demo.webm?token=123'),
      FileMediaKind.video,
    );
  });

  test('recognizes audio files from names and URLs', () {
    expect(fileMediaKind('recording.mp3', null), FileMediaKind.audio);
    expect(
      fileMediaKind(null, 'https://example.com/music.flac?token=123'),
      FileMediaKind.audio,
    );
  });

  test('ignores unsupported file types', () {
    expect(fileMediaKind('document.pdf', null), isNull);
  });
}
