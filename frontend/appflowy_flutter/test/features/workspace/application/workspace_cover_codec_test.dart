import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips workspace cover metadata', () {
    const cover = PageStyleCover(
      type: PageStyleCoverImageType.builtInImage,
      value: '4',
    );

    final encoded = WorkspaceCoverCodec.encode(cover);

    expect(WorkspaceCoverCodec.decode(encoded), cover);
  });

  test('preserves an explicit removed workspace cover', () {
    final encoded = WorkspaceCoverCodec.encode(const PageStyleCover.none());

    expect(encoded, isNotEmpty);
    expect(WorkspaceCoverCodec.decode(encoded)?.isNone, isTrue);
    expect(WorkspaceCoverCodec.decode(''), isNull);
  });

  test('ignores malformed workspace cover metadata', () {
    expect(WorkspaceCoverCodec.decode('not-json'), isNull);
  });
}
