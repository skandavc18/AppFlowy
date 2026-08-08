import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/menu/menu_user_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_button.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// keep this widget in case we need to roll back (lucas.xu)
class SidebarUser extends StatefulWidget {
  const SidebarUser({
    super.key,
    required this.userProfile,
  });

  final UserProfilePB userProfile;

  @override
  State<SidebarUser> createState() => _SidebarUserState();
}

class _SidebarUserState extends State<SidebarUser> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    return BlocProvider<MenuUserBloc>(
      // Without this the bloc never starts its listener, so a name changed in
      // settings never reaches the sidebar.
      create: (_) => MenuUserBloc(widget.userProfile, workspaceId)
        ..add(const MenuUserEvent.initial()),
      child: BlocBuilder<MenuUserBloc, MenuUserState>(
        builder: (context, state) => MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _isHovered
                  ? Theme.of(context).colorScheme.secondary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const HSpace(4),
                UserAvatar(
                  iconUrl: state.userProfile.iconUrl,
                  name: state.userProfile.name,
                  size: AFAvatarSize.s,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFFBE8FB),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(
                        width: 0.50,
                        color: Color(0x19171717),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const HSpace(8),
                Expanded(child: _buildUserName(context, state)),
                _hoverAction(
                  UserSettingButton(isHover: _isHovered),
                ),
                const HSpace(4.0),
                _hoverAction(
                  NotificationButton(
                    isHover: _isHovered,
                    key: ValueKey(widget.userProfile.id),
                  ),
                ),
                const HSpace(4.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hoverAction(Widget child) {
    return Visibility(
      visible: _isHovered,
      maintainAnimation: true,
      maintainSize: true,
      maintainState: true,
      child: child,
    );
  }

  Widget _buildUserName(BuildContext context, MenuUserState state) {
    final String name = _userName(state.userProfile);
    return SidebarText(
      name,
      overflow: TextOverflow.ellipsis,
      color: Theme.of(context).colorScheme.tertiary,
    );
  }

  /// Return the user name, if the user name is empty, return the default user name.
  String _userName(UserProfilePB userProfile) {
    String name = userProfile.name;
    if (name.isEmpty) {
      name = LocaleKeys.defaultUsername.tr();
    }
    return name;
  }
}
