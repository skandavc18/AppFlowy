import 'dart:convert';

import 'package:appflowy/shared/page_icon_size.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continuous numeric sizes round-trip; unset retains the host default',
      () {
    expect(IconSize.decode(''), isNull);
    expect(IconSize.decode('{}'), isNull);
    for (final size in [16.0, 16.125, 56.0, 91.375, 255.9, 320.0]) {
      expect(IconSize.decode(IconSize.merge('', size)), size);
    }
    expect(IconSize.decode('{"page_icon_size": 81}'), 81.0);
  });

  test('malformed and out-of-bounds values do not break a page header', () {
    for (final extra in [
      'broken',
      '[]',
      'null',
      '{"page_icon_size": "128"}',
      '{"page_icon_size": true}',
      '{"page_icon_size": {"width": 128}}',
      '{"page_icon_size": -10}',
      '{"page_icon_size": 15.9}',
      '{"page_icon_size": 320.1}',
      '{"page_icon_size": 1e999}',
    ]) {
      expect(IconSize.decode(extra), isNull, reason: extra);
    }
    expect(IconSize.clamp(-500), 16);
    expect(IconSize.clamp(500), 320);
    expect(() => IconSize.clamp(double.nan), throwsArgumentError);
    expect(() => IconSize.merge('', double.infinity), throwsArgumentError);
    expect(() => IconSize.merge('', 321), throwsArgumentError);
  });

  test('merge/reset changes only size and never discards unknown metadata', () {
    final metadata = {
      'cover': {'type': 'local_image', 'value': 'original.jpg'},
      'document_style': {'font': 'serif', 'width': 720},
      'collection': {
        'kind': 'album',
        'state': [1, 2, 3]
      },
      'dashboard': {
        'widgets': ['draft-widget']
      },
      'workspace_item': {'storage_url': 'original.pdf'},
      'future_key': {'nested': null},
    };
    final extra = jsonEncode(metadata);
    final resized = IconSize.merge(extra, 127.25);
    expect(jsonDecode(resized), {...metadata, IconSize.key: 127.25});
    expect(jsonDecode(IconSize.merge(resized, null)), metadata);
    for (final invalid in ['broken', '[]', 'null']) {
      expect(() => IconSize.merge(invalid, 100), throwsFormatException);
      expect(() => IconSize.merge(invalid, null), throwsFormatException);
    }
  });

  test('applying an ACK preserves the original view, icon bytes and color', () {
    final view = ViewPB(
      id: 'immutable',
      name: 'Original name',
      extra: '{"cover":{"type":"color","value":"warm"}}',
      icon: ViewIconPB(
        ty: ViewIconTypePB.Icon,
        value: '{"groupName":"custom","name":"leaf","color":"12345"}',
      ),
    )..freeze();
    final bytes = view.writeToBuffer();
    final updated = IconSize.applyTo(view, 113.75);
    expect(view.writeToBuffer(), bytes);
    expect(updated, isNot(same(view)));
    expect(updated.id, view.id);
    expect(updated.name, view.name);
    expect(updated.icon.writeToBuffer(), view.icon.writeToBuffer());
    expect(IconSize.decode(updated.extra), 113.75);
  });
}
