import 'dart:convert';

import 'package:appflowy/shared/appflowy_cloud_auth.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds an authorization header from a cloud profile', () {
    final profile = UserProfilePB()
      ..token = jsonEncode({'access_token': 'test-token'});

    expect(
      appFlowyCloudAuthHeaders(profile),
      {'Authorization': 'Bearer test-token'},
    );
  });

  test('omits authorization when the profile token is unavailable', () {
    expect(appFlowyCloudAuthHeaders(null), isEmpty);
    expect(appFlowyCloudAuthHeaders(UserProfilePB()), isEmpty);
  });
}
