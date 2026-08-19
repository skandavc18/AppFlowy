import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/encryption/block_encryption_action.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

/// What a sealed block looks like on the page.
///
/// It is deliberately quiet and deliberately honest: it says what kind of block
/// used to be here so the page still reads as a shape, and it says nothing at
/// all about what was in it. While the workspace is unlocked it offers to open
/// itself; while it is locked it offers the passphrase.
class EncryptedBlockComponentBuilder extends BlockComponentBuilder {
  EncryptedBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return EncryptedBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (_, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.attributes[EncryptedBlockKeys.sealed] is String;
}

class EncryptedBlockComponent extends BlockComponentStatefulWidget {
  const EncryptedBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<EncryptedBlockComponent> createState() =>
      EncryptedBlockComponentState();
}

class EncryptedBlockComponentState extends State<EncryptedBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  EncryptionVault get _vault => EncryptionVault.instance;

  EditorState get _editorState => context.read<EditorState>();

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onVaultChanged);
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    super.dispose();
  }

  void _onVaultChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Unlocking a block is decrypting it: the ciphertext node is replaced by the
  /// real one, so what comes back is the block itself and can be typed in.
  /// Locking it again is `Encrypt this block` on the ordinary block.
  Future<void> _unlock() async {
    await applyBlockEncryption(
      context: context,
      editorState: _editorState,
      node: node,
      seal: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final kind = node.encryptedBlockKind;

    Widget child = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: premium.mutedSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 17,
                color: premium.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleKeys.encryption_blockTitle.tr(),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: premium.textPrimary,
                      ),
                    ),
                    if (kind.isNotEmpty)
                      Text(
                        LocaleKeys.encryption_blockWas.tr(args: [kind]),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: premium.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (_editorState.editable)
                TextButton.icon(
                  onPressed: () => unawaited(_unlock()),
                  icon: const Icon(Icons.lock_open_rounded, size: 15),
                  label: Text(
                    LocaleKeys.encryption_unlockItem.tr(),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (UniversalPlatform.isMobile) {
      child = MobileBlockActionButtons(
        node: node,
        editorState: _editorState,
        child: child,
      );
    }

    return child;
  }
}
