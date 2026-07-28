import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/shared/appflowy_cloud_auth.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

@immutable
class ManagedOfficeSession {
  const ManagedOfficeSession({
    required this.sessionId,
    required this.documentServerUrl,
    required this.editorConfig,
  });

  factory ManagedOfficeSession.fromJson(Map<String, dynamic> json) {
    final sessionId = json['session_id'];
    final documentServerUrl = json['document_server_url'];
    final editorConfig = json['editor_config'];
    final documentServerUri =
        documentServerUrl is String ? Uri.tryParse(documentServerUrl) : null;
    if (sessionId is! String ||
        sessionId.isEmpty ||
        documentServerUri == null ||
        !documentServerUri.hasAuthority ||
        documentServerUri.host.isEmpty ||
        (documentServerUri.scheme != 'http' &&
            documentServerUri.scheme != 'https') ||
        editorConfig is! Map) {
      throw const OfficeCloudException(
        'AppFlowy Cloud returned an invalid document editor session.',
      );
    }
    return ManagedOfficeSession(
      sessionId: sessionId,
      documentServerUrl: documentServerUrl,
      editorConfig: Map<String, dynamic>.from(editorConfig),
    );
  }

  final String sessionId;
  final String documentServerUrl;
  final Map<String, dynamic> editorConfig;
}

class OfficeCloudException implements Exception {
  const OfficeCloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class OfficeCloudSessionService {
  Future<UserProfilePB?> connectedCloudProfile();

  Future<ManagedOfficeSession> createSession({
    required UserProfilePB profile,
    required String storageUrl,
    required String fileName,
    required bool editable,
    required bool isDark,
    String? sessionId,
  });
}

bool usesManagedOfficeServer(UserProfilePB profile) =>
    profile.userAuthType == AuthTypePB.Server ||
    profile.workspaceType == WorkspaceTypePB.ServerW ||
    appFlowyCloudAuthHeaders(profile).isNotEmpty;

@visibleForTesting
Map<String, Object?> buildOfficeSessionRequest({
  required String storageUrl,
  required String fileName,
  required bool editable,
  required String userName,
  required bool isDark,
  String? sessionId,
}) =>
    {
      if (sessionId != null) 'session_id': sessionId,
      'storage_url': storageUrl,
      'file_name': fileName,
      'editable': editable,
      'user_name': userName,
      'is_dark': isDark,
    };

class AppFlowyCloudOfficeSessionService implements OfficeCloudSessionService {
  const AppFlowyCloudOfficeSessionService({this.client});

  final http.Client? client;

  @override
  Future<UserProfilePB?> connectedCloudProfile() async {
    final result = await UserBackendService.getCurrentUserProfile();
    return result.fold(
      (profile) => usesManagedOfficeServer(profile) ? profile : null,
      (error) => throw OfficeCloudException(
        'Unable to determine the current AppFlowy Cloud connection: '
        '${error.msg}',
      ),
    );
  }

  @override
  Future<ManagedOfficeSession> createSession({
    required UserProfilePB profile,
    required String storageUrl,
    required String fileName,
    required bool editable,
    required bool isDark,
    String? sessionId,
  }) async {
    final workspaceResult = await UserBackendService.getCurrentWorkspace();
    final workspace = workspaceResult.fold(
      (workspace) => workspace,
      (error) => throw OfficeCloudException(
        'Unable to find the current cloud workspace: ${error.msg}',
      ),
    );
    final baseUrl =
        getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url.trim();
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null || !baseUri.hasAuthority) {
      throw const OfficeCloudException(
        'The AppFlowy Cloud server address is invalid.',
      );
    }
    final authHeaders = appFlowyCloudAuthHeaders(profile);
    if (authHeaders.isEmpty) {
      throw const OfficeCloudException(
        'The AppFlowy Cloud session has expired. Sign in again.',
      );
    }
    final uri = baseUri.replace(
      path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}'
          '/api/office/${workspace.id}/session',
    );

    final ownedClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .post(
            uri,
            headers: {
              ...authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(
              buildOfficeSessionRequest(
                storageUrl: storageUrl,
                fileName: fileName,
                editable: editable,
                userName: profile.name,
                isDark: isDark,
                sessionId: sessionId,
              ),
            ),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _decodeResponse(response);
      return ManagedOfficeSession.fromJson(decoded);
    } finally {
      if (ownedClient) {
        httpClient.close();
      }
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw OfficeCloudException(
        'AppFlowy Cloud returned an unreadable response '
        '(${response.statusCode}).',
      );
    }
    final envelope = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    final data = envelope?['data'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        data is! Map) {
      final message = envelope?['message'];
      throw OfficeCloudException(
        message is String && message.isNotEmpty
            ? message
            : 'AppFlowy Cloud could not start the document editor '
                '(${response.statusCode}).',
      );
    }
    return Map<String, dynamic>.from(data);
  }
}
