import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/menu/menu_user_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_button.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar_button.dart';
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
    this.showUtilities = true,
    this.createUserBloc,
  });

  final UserProfilePB userProfile;
  final bool showUtilities;
  final MenuUserBloc Function(UserProfilePB, String)? createUserBloc;

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
      key: ValueKey((widget.userProfile.id, workspaceId)),
      // Without this the bloc never starts its listener, so a name changed in
      // settings never reaches the sidebar.
      create: (_) =>
          (widget.createUserBloc?.call(widget.userProfile, workspaceId) ??
              MenuUserBloc(widget.userProfile, workspaceId))
            ..add(const MenuUserEvent.initial()),
      child: BlocBuilder<MenuUserBloc, MenuUserState>(
        builder: (context, state) {
          final palette = SidebarPalette.of(context);
          final user = context.read<MenuUserBloc>();
          final userId = state.userProfile.id;
          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: WorkspaceTokens.motion(context, SidebarMetrics.hover),
              curve: SidebarMetrics.curve,
              decoration: BoxDecoration(
                color: _isHovered ? palette.hover : palette.hoverAtRest,
                borderRadius: BorderRadius.circular(SidebarMetrics.rowRadius),
              ),
              child: Row(
                children: [
                  const HSpace(SidebarMetrics.space1),
                  UserAvatarButton(
                    userProfile: state.userProfile,
                    saveIcon: user.saveUserIcon,
                    isCurrent: () =>
                        !user.isClosed && user.state.userProfile.id == userId,
                    size: AFAvatarSize.s,
                    decoration: ShapeDecoration(
                      color: palette.selected,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const HSpace(SidebarMetrics.space2),
                  Expanded(child: _buildUserName(context, state)),
                  if (widget.showUtilities)
                    AnimatedOpacity(
                      duration: WorkspaceTokens.motion(
                        context,
                        SidebarMetrics.reveal,
                      ),
                      curve: SidebarMetrics.curve,
                      opacity: _isHovered ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_isHovered,
                        child: Row(
                          children: [
                            UserSettingButton(isHover: _isHovered),
                            const HSpace(SidebarMetrics.space1),
                            NotificationButton(
                              isHover: _isHovered,
                              key: ValueKey(widget.userProfile.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const HSpace(SidebarMetrics.space1),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserName(BuildContext context, MenuUserState state) {
    final String name = _userName(state.userProfile);
    return SidebarText.heading(
      name,
      overflow: TextOverflow.ellipsis,
      color: SidebarPalette.of(context).textPrimary,
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
