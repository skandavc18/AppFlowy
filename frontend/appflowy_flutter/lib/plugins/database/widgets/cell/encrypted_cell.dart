import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What a cell of a sealed column shows.
///
/// The value really is ciphertext where it is stored, so the editable field is
/// taken away entirely and the cell shows dots. Unlocking the column decrypts
/// it, which is what gives the cells back — writing a plain value into a sealed
/// column would leave one row readable and the rest not.
class EncryptedCellGuard extends StatefulWidget {
  const EncryptedCellGuard({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.controller,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final String fieldId;

  /// Holds the value as it is stored, which for a sealed column is ciphertext.
  final TextEditingController controller;

  final Widget child;
  final EdgeInsets padding;

  @override
  State<EncryptedCellGuard> createState() => _EncryptedCellGuardState();
}

class _EncryptedCellGuardState extends State<EncryptedCellGuard> {
  EncryptionVault get _vault => EncryptionVault.instance;

  EncryptedColumnRegistry get _registry => EncryptedColumnRegistry.instance;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onChanged);
    _registry.revision.addListener(_onChanged);
    widget.controller.addListener(_onChanged);
    // Makes sure this view's marks have been read at least once.
    _registry.listenable(widget.viewId);
  }

  @override
  void didUpdateWidget(EncryptedCellGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _registry.revision.removeListener(_onChanged);
    _vault.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.controller.text;
    // Also guards a value that is already ciphertext but whose column has not
    // been marked yet, so sealing a column never flashes `af1.…` at anybody.
    final sealed = _registry.isEncrypted(widget.viewId, widget.fieldId) ||
        looksSealed(stored);
    if (!sealed) {
      return widget.child;
    }

    final premium = PremiumThemeExtension.of(context);

    return Padding(
      padding: widget.padding,
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: premium.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: LocaleKeys.encryption_columnLockedHint.tr(),
              child: Text(
                '••••••••',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: premium.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
