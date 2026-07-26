import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

/// The outcome of creating an account on the GoTrue service that backs
/// AppFlowy Cloud, both the hosted and the self-hosted deployments.
class SignUpResult {
  const SignUpResult({required this.hasSession});

  /// `true` when the server returned a session right away, which means the
  /// deployment doesn't require the email address to be confirmed first and
  /// the user can be signed in immediately.
  final bool hasSession;
}

/// Creates accounts through the GoTrue endpoint exposed by AppFlowy Cloud.
///
/// The Rust backend only exposes sign-in for server accounts, so the sign-up
/// request is made directly against `<cloud url>/gotrue/signup`, the same way
/// [PasswordHttpService] talks to the password endpoints.
class SignUpHttpService {
  SignUpHttpService({
    required this.baseUrl,
    http.Client? client,
  }) : client = client ?? http.Client();

  final String baseUrl;
  final http.Client client;

  Future<FlowyResult<SignUpResult, FlowyError>> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/gotrue/signup'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final body = _decodeBody(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final accessToken = body['access_token'];
        return FlowyResult.success(
          SignUpResult(
            hasSession: accessToken is String && accessToken.isNotEmpty,
          ),
        );
      }

      Log.info('sign up request failed with status ${response.statusCode}');

      return FlowyResult.failure(
        FlowyError(
          code: response.statusCode == 422
              ? ErrorCode.NewPasswordTooWeak
              : ErrorCode.Internal,
          msg: _errorMessage(body),
        ),
      );
    } catch (e) {
      Log.error('sign up request failed: $e');
      return FlowyResult.failure(
        FlowyError(msg: LocaleKeys.signUp_accountCreatedFailed.tr()),
      );
    }
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  String _errorMessage(Map<String, dynamic> body) {
    for (final key in const [
      'msg',
      'message',
      'error_description',
      'error',
    ]) {
      final value = body[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return LocaleKeys.signUp_accountCreatedFailed.tr();
  }
}
