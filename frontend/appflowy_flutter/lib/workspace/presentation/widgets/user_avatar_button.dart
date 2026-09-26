import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';

/// The same account-avatar action in Settings and the personal sidebar.
/// The injected write is the account's UserBackendService boundary, not a
/// fire-and-forget bloc event. Only backend notifications refresh the avatar.
class UserAvatarButton extends StatelessWidget {
  const UserAvatarButton({
    super.key,
    required this.userProfile,
    required this.saveIcon,
    required this.isCurrent,
    required this.size,
    this.decoration,
  });

  final UserProfilePB userProfile;
  final Future<FlowyResult<void, FlowyError>> Function(String) saveIcon;
  final bool Function() isCurrent;
  final AFAvatarSize size;
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    final workspace = context.read<UserWorkspaceBloc?>();
    final userId = userProfile.id;
    return AvatarPickerButton(
      key: ValueKey(userId),
      identity: userId,
      label: LocaleKeys.settings_accountPage_general_changeProfilePicture.tr(),
      icon: userIconData(userProfile.iconUrl),
      documentId: userId.toString(),
      dimension: size.size,
      isCurrent: () =>
          isCurrent() &&
          (workspace == null ||
              (!workspace.isClosed &&
                  workspace.state.userProfile.id == userId)),
      onSelected: (icon) async {
        // Profile iconUrl has historically stored the raw emoji, icon JSON or
        // image URL/path. Keep that format (including '' for Remove).
        final result = await saveIcon(icon.emoji);
        result.fold((_) {}, (error) => throw error);
      },
      child: UserAvatar(
        iconUrl: userProfile.iconUrl,
        name: userProfile.name,
        size: size,
        decoration: decoration,
      ),
    );
  }
}

/// Picker interaction shared by user and workspace identity buttons. The
/// caller owns storage/permissions; this owns keyboard access and save UI.
class AvatarPickerButton extends StatefulWidget {
  const AvatarPickerButton({
    super.key,
    required this.identity,
    required this.label,
    required this.icon,
    required this.documentId,
    required this.dimension,
    required this.onSelected,
    required this.child,
    this.isCurrent,
  });

  final Object identity;
  final String label;
  final EmojiIconData icon;
  final String? documentId;
  final double dimension;
  final FutureOr<void> Function(EmojiIconData) onSelected;
  final bool Function()? isCurrent;
  final Widget child;

  @override
  State<AvatarPickerButton> createState() => _AvatarPickerButtonState();
}

class _AvatarPickerButtonState extends State<AvatarPickerButton> {
  final _popover = PopoverController();
  final _status = ValueNotifier<({bool saving, String? error})>(
    (saving: false, error: null),
  );
  int _generation = 0;
  int _operation = 0;
  bool _active = true;
  bool _busy = false;

  bool _isCurrent(int generation) =>
      mounted &&
      _active &&
      generation == _generation &&
      widget.isCurrent?.call() != false;

  @override
  void didUpdateWidget(covariant AvatarPickerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.documentId != widget.documentId) {
      final generation = ++_generation;
      _operation++;
      _busy = false;
      // Parent rebinding can occur during layout; close the old overlay after
      // the frame, but reject its callbacks immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation) return;
        _popover.close();
        _status.value = (saving: false, error: null);
      });
    }
  }

  @override
  void deactivate() {
    _active = false;
    _generation++;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _generation++;
    _operation++;
    _status.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy || !_isCurrent(_generation)) return;
    _popover.close();
    final generation = ++_generation;
    _status.value = (saving: false, error: null);
    if (UniversalPlatform.isDesktopOrWeb) {
      _popover.show();
      return;
    }
    final result = await context.push<EmojiIconData>(
      Uri(
        path: MobileEmojiPickerScreen.routeName,
        queryParameters: {
          MobileEmojiPickerScreen.pageTitle: widget.label,
          MobileEmojiPickerScreen.selectTabs:
              kAllIconPickerTabs.map((tab) => tab.name).toList(),
          MobileEmojiPickerScreen.iconSelectedType:
              widget.icon.toPickerTabType()?.name,
          MobileEmojiPickerScreen.uploadDocumentId: widget.documentId,
        },
      ).toString(),
    );
    if (result != null && _isCurrent(generation)) {
      await _save(result.toSelectedResult(), generation);
    }
  }

  Future<void> _save(SelectedEmojiIconResult result, int generation) async {
    if (_busy || !_isCurrent(generation)) return;
    final operation = ++_operation;
    setState(() => _busy = true);
    _status.value = (saving: true, error: null);
    try {
      await widget.onSelected(result.data);
      if (_isCurrent(generation) && !result.keepOpen) _popover.close();
    } catch (_) {
      if (_isCurrent(generation)) {
        // Backend/transport errors may contain credentials or local paths.
        // Keep both the desktop picker and mobile snackbar safe to display.
        final message = LocaleKeys.workspaceFolderExplorer_operationFailed.tr();
        _status.value = (saving: true, error: message);
        if (!UniversalPlatform.isDesktopOrWeb && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    } finally {
      // A dismissed picker can finish saving, but cannot close a newer picker,
      // report a stale failure, or clear another identity's busy state.
      if (mounted && _active && operation == _operation) {
        setState(() => _busy = false);
        _status.value = (saving: false, error: _status.value.error);
      }
    }
  }

  Widget _picker() {
    final generation = _generation;
    if (!_isCurrent(generation)) return const SizedBox.shrink();
    final picker = FlowyIconEmojiPicker(
      tabs: kAllIconPickerTabs,
      initialType: widget.icon.toPickerTabType(),
      documentId: widget.documentId,
      onSelectedEmoji: (result) => unawaited(_save(result, generation)),
    );
    return ValueListenableBuilder(
      valueListenable: _status,
      child: picker,
      builder: (context, status, child) => Column(
        children: [
          if (status.saving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ExcludeFocus(
              excluding: status.saving,
              child: AbsorbPointer(absorbing: status.saving, child: child),
            ),
          ),
          if (status.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  status.error!,
                  key: const ValueKey('avatar-save-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      child: SizedBox.square(
        dimension: widget.dimension,
        child: IconButton(
          onPressed: _busy ? null : () => unawaited(_open()),
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.square(widget.dimension),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Semantics(
            label: widget.label,
            excludeSemantics: true,
            child: widget.child,
          ),
        ),
      ),
    );
    if (!UniversalPlatform.isDesktopOrWeb) return button;
    return AppFlowyPopover(
      controller: _popover,
      triggerActions: PopoverTriggerFlags.none,
      offset: const Offset(0, 8),
      direction: PopoverDirection.bottomWithLeftAligned,
      constraints: BoxConstraints.loose(const Size(364, 380)),
      margin: EdgeInsets.zero,
      onClose: () => _generation++,
      popupBuilder: (_) => _picker(),
      child: button,
    );
  }
}
