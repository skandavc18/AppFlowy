import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview mode preserves existing view metadata', () {
    final extra = ViewCoverCodec.mergeCover(
      '',
      const PageStyleCover(
        type: PageStyleCoverImageType.pureColor,
        value: '#D9C7A4',
      ),
    );
    final merged = ViewPreviewModeCodec.merge(
      extra,
      ViewPreviewMode.content,
    );
    final view = ViewPB(extra: merged);

    expect(view.previewMode, ViewPreviewMode.content);
    expect(ViewCoverCodec.decodeCover(merged)?.value, '#D9C7A4');
  });

  test('missing and future preview modes prefer the cover', () {
    expect(ViewPB().previewMode, ViewPreviewMode.cover);
    expect(ViewPreviewMode.fromValue('future-mode'), ViewPreviewMode.cover);
  });
}
