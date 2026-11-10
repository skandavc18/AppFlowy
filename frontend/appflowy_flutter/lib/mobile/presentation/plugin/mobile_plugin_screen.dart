import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/app_bar.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A desktop plugin that is not a workspace page (templates, extensions,
/// workflows, trash, page library, a file from disk...), full screen on mobile.
class MobilePluginScreen extends StatefulWidget {
  const MobilePluginScreen({
    super.key,
    required this.pluginType,
    this.plugin,
  });

  static const routeName = '/plugin';
  static const typeArgument = 'type';

  static String location(PluginType type) => Uri(
        path: routeName,
        queryParameters: {typeArgument: type.name},
      ).toString();

  static PluginType? typeFromName(String? name) =>
      PluginType.values.where((type) => type.name == name).firstOrNull;

  final PluginType pluginType;

  /// An already built plugin, such as a file opened from disk. The screen
  /// takes ownership of it. Without one, the registered builder makes one.
  final Plugin? plugin;

  @override
  State<MobilePluginScreen> createState() => _MobilePluginScreenState();
}

class _MobilePluginScreenState extends State<MobilePluginScreen> {
  late final Plugin _plugin =
      widget.plugin ?? makePlugin(pluginType: widget.pluginType);
  late final Future<FlowyResult<UserProfilePB, FlowyError>> _user =
      getIt<AuthService>().getUser();

  @override
  void initState() {
    super.initState();
    _plugin.init();
  }

  @override
  void dispose() {
    _plugin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builder = _plugin.widgetBuilder;
    return FutureBuilder(
      future: _user,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: FlowyAppBar(title: builder.leftBarItem),
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final userProfile = snapshot.data!.toNullable();
        final body = Scaffold(
          appBar: FlowyAppBar(title: builder.leftBarItem),
          body: SafeArea(
            top: false,
            child: builder.buildWidget(
              context: PluginContext(userProfile: userProfile),
              shrinkWrap: false,
            ),
          ),
        );
        if (userProfile == null) return body;
        // Plugins that create pages read the workspace they belong to.
        return BlocProvider(
          create: (_) => UserWorkspaceBloc(
            userProfile: userProfile,
            repository: RustWorkspaceRepositoryImpl(userId: userProfile.id),
          )..add(UserWorkspaceEvent.initialize()),
          child: body,
        );
      },
    );
  }
}
