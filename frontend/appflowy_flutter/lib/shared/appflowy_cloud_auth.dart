import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

Map<String, String> appFlowyCloudAuthHeaders(UserProfilePB? userProfile) {
  final token = userProfile?.token;
  if (token == null || token.isEmpty) {
    return const {};
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(token);
  } on FormatException catch (error) {
    Log.error('Unable to decode the AppFlowy Cloud token: $error');
    return const {};
  }

  final accessToken = decoded is Map ? decoded['access_token'] : null;
  if (accessToken is! String || accessToken.isEmpty) {
    Log.error('The AppFlowy Cloud token does not contain an access token.');
    return const {};
  }
  return {'Authorization': 'Bearer $accessToken'};
}
