import 'package:appflowy/workspace/application/settings/plan/workspace_subscription_ext.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

/// Billing capabilities follow the account and configured server, not the
/// compiler configuration. The backend still authorizes every billing request.
abstract final class BillingPolicy {
  static bool supportsServer(String serverUrl) => const {
        'https://beta.appflowy.cloud',
        'https://test.appflowy.cloud',
      }.contains(serverUrl);

  static bool canManageWorkspace(
    WorkspaceTypePB workspaceType,
    AFRolePB? role,
  ) =>
      workspaceType == WorkspaceTypePB.ServerW && role == AFRolePB.Owner;

  static String paymentSuccessUrl(
    String baseWebDomain,
    SubscriptionPlanPB plan,
  ) {
    final base = Uri.parse(baseWebDomain);
    final uri = base.hasScheme ? base : Uri.parse('https://$baseWebDomain');
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError('Payment return URL requires an HTTP(S) web domain');
    }
    return uri
        .replace(
          path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/after-payment',
          queryParameters: {'plan': plan.toRecognizable()},
        )
        .removeFragment()
        .toString();
  }
}
