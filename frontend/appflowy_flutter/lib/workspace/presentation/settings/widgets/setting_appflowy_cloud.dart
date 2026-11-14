import 'package:appflowy/user/application/billing_policy.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

class BillingGateGuard extends StatelessWidget {
  const BillingGateGuard({required this.builder, super.key});

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: isBillingEnabled(),
      builder: (context, snapshot) {
        final isBillingEnabled = snapshot.data ?? false;
        if (isBillingEnabled &&
            snapshot.connectionState == ConnectionState.done) {
          return builder(context);
        }

        // If the billing is not enabled, show nothing
        return const SizedBox.shrink();
      },
    );
  }
}

Future<bool> isBillingEnabled() async {
  final result = await UserEventGetCloudConfig().send();
  return result.fold(
    (cloudSetting) {
      final isWhiteListed =
          BillingPolicy.supportsServer(cloudSetting.serverUrl);
      if (!isWhiteListed) {
        Log.warn("Billing is not enabled for server ${cloudSetting.serverUrl}");
      }
      return isWhiteListed;
    },
    (err) {
      Log.error("Failed to get cloud config: $err");
      return false;
    },
  );
}
