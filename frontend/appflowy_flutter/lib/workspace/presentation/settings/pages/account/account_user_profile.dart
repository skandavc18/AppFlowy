import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/user/settings_user_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_input_field.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar_button.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Account name and account avatar
class AccountUserProfile extends StatefulWidget {
  const AccountUserProfile({
    super.key,
    required this.name,
    required this.iconUrl,
    this.onSave,
  });

  final String name;
  final String iconUrl;
  final void Function(String)? onSave;

  @override
  State<AccountUserProfile> createState() => _AccountUserProfileState();
}

class _AccountUserProfileState extends State<AccountUserProfile> {
  late final TextEditingController nameController =
      TextEditingController(text: widget.name);
  final FocusNode focusNode = FocusNode();
  bool isEditing = false;

  @override
  void initState() {
    super.initState();

    focusNode
      ..addListener(_handleFocusChange)
      ..onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    nameController.dispose();
    focusNode.removeListener(_handleFocusChange);
    focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(),
        const HSpace(16),
        Flexible(
          child: isEditing ? _buildEditingField() : _buildNameDisplay(),
        ),
      ],
    );
  }

  Widget _buildAvatar() {
    return BlocBuilder<SettingsUserViewBloc, SettingsUserState>(
      builder: (context, state) {
        final user = context.read<SettingsUserViewBloc>();
        final userId = state.userProfile.id;
        return UserAvatarButton(
          userProfile: state.userProfile,
          saveIcon: user.saveUserIcon,
          isCurrent: () =>
              !user.isClosed && user.state.userProfile.id == userId,
          size: AFAvatarSize.l,
        );
      },
    );
  }

  Widget _buildNameDisplay() {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyle.body.standard(
                color: theme.textColorScheme.primary,
              ),
            ),
          ),
          const HSpace(4),
          AFGhostButton.normal(
            size: AFButtonSize.s,
            padding: EdgeInsets.all(theme.spacing.xs),
            onTap: () => setState(() => isEditing = true),
            builder: (context, isHovering, disabled) => FlowySvg(
              FlowySvgs.toolbar_link_edit_m,
              size: const Size.square(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditingField() {
    return SettingsInputField(
      textController: nameController,
      value: widget.name,
      focusNode: focusNode..requestFocus(),
      onCancel: () => setState(() => isEditing = false),
      onSave: (_) => _saveChanges(),
    );
  }

  void _handleFocusChange() {
    if (!focusNode.hasFocus && isEditing && mounted) {
      _saveChanges();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        isEditing &&
        mounted) {
      setState(() => isEditing = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _saveChanges() {
    widget.onSave?.call(nameController.text);
    setState(() => isEditing = false);
  }
}
