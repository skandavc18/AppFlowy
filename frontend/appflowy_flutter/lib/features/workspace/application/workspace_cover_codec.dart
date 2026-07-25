import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';

class WorkspaceCoverCodec {
  const WorkspaceCoverCodec._();

  static PageStyleCover? decode(String data) {
    try {
      return ViewCoverCodec.decodeCover(data);
    } on FormatException {
      return null;
    }
  }

  static String encode(PageStyleCover cover) {
    return ViewCoverCodec.mergeCover('', cover);
  }
}
