import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Stands between the application and the workspace while it is locked.
///
/// When the whole workspace is gated, nothing behind this is built at all —
/// not the sidebar, not the last page somebody had open, not a preview in a
/// tab. A cover that merely paints over the workspace would still have read it.
///
/// It also keeps the idle clock: any pointer or key press means somebody is
/// still here, so the countdown to locking again starts over.
class WorkspaceEncryptionGate extends StatefulWidget {
  const WorkspaceEncryptionGate({super.key, required this.child});

  final Widget child;

  @override
  State<WorkspaceEncryptionGate> createState() =>
      _WorkspaceEncryptionGateState();
}

class _WorkspaceEncryptionGateState extends State<WorkspaceEncryptionGate> {
  EncryptionVault get _vault => EncryptionVault.instance;

  /// Whether the stored policy has been read yet.
  ///
  /// ⚠️ The child must NOT be built before this is known. Building the
  /// workspace and then swapping it for the lock screen a frame later tears
  /// down every bloc under it mid-initialisation — `UserWorkspaceBloc` then
  /// dies with "Cannot add new events after calling close" — and it renders
  /// the workspace for a frame that was supposed to be closed.
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onChanged);
    // ⚠️ A `Focus` wrapped round the whole workspace to catch key presses puts
    // a node in everyone's focus chain for the sake of a timer. A handler is
    // outside the focus tree entirely and cannot affect text editing.
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(
      _vault.ensureLoaded().whenComplete(() {
        if (mounted) {
          setState(() => _resolved = true);
        }
      }),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _vault.removeListener(_onChanged);
    super.dispose();
  }

  /// Never handles anything — it only says somebody is still here.
  bool _onKey(KeyEvent event) {
    _vault.touch();
    return false;
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return const _GateLoading();
    }

    if (_vault.policy.gateWholeWorkspace && _vault.isLocked) {
      return const WorkspaceLockScreen();
    }

    // Only worth listening while there is a key that could be dropped.
    if (!_vault.isUnlocked || !_vault.policy.locksOnIdle) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _vault.touch(),
      onPointerSignal: (_) => _vault.touch(),
      child: widget.child,
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PremiumThemeExtension.of(context).canvas,
        body: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

/// The one screen shown while the workspace waits for its passphrase.
class WorkspaceLockScreen extends StatefulWidget {
  const WorkspaceLockScreen({super.key});

  @override
  State<WorkspaceLockScreen> createState() => _WorkspaceLockScreenState();
}

class _WorkspaceLockScreenState extends State<WorkspaceLockScreen> {
  final TextEditingController _passphrase = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _working = false;
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_working) {
      return;
    }
    setState(() {
      _working = true;
      _refused = false;
    });

    final opened = await EncryptionVault.instance.unlock(_passphrase.text);
    if (!mounted) {
      return;
    }
    if (opened) {
      _passphrase.clear();
      // The gate rebuilds itself from the vault's own notification.
      return;
    }
    setState(() {
      _working = false;
      _refused = true;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final hint = EncryptionVault.instance.hint;

    return Scaffold(
      backgroundColor: premium.canvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: premium.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 26,
                  color: premium.accent,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                LocaleKeys.encryption_lockedTitle.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: premium.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                LocaleKeys.encryption_lockedBody.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 26),
              // ⚠️ A bare TextField loses Backspace here: the editing keys are
              // claimed above it, and only restating them next to the field
              // wins, because Shortcuts resolves from the focused node upward.
              TextEntryShortcuts(
                child: TextField(
                  controller: _passphrase,
                  focusNode: _focus,
                  obscureText: true,
                  enabled: !_working,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => unawaited(_unlock()),
                  decoration: InputDecoration(
                    hintText: LocaleKeys.encryption_passphrase.tr(),
                    filled: true,
                    fillColor: premium.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(color: premium.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide(
                        color: _refused
                            ? const Color(0xFFD1454B)
                            : premium.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide:
                          BorderSide(color: premium.accent, width: 1.4),
                    ),
                  ),
                ),
              ),
              if (_refused) ...[
                const SizedBox(height: 8),
                Text(
                  LocaleKeys.encryption_wrongPassphrase.tr(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFD1454B),
                  ),
                ),
              ],
              if (hint.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  LocaleKeys.encryption_hintIs.tr(args: [hint]),
                  style: TextStyle(fontSize: 12, color: premium.textMuted),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: _working ? null : () => unawaited(_unlock()),
                  child: _working
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(LocaleKeys.encryption_unlockConfirm.tr()),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                LocaleKeys.encryption_noRecovery.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: premium.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a protected page, table, folder or file shows instead of itself.
class LockedContentPlacard extends StatelessWidget {
  const LockedContentPlacard({super.key, this.name = '', this.viewId = ''});

  final String name;

  /// What Unlock opens. Empty asks only for the workspace key.
  final String viewId;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 30,
              color: premium.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              name.isEmpty
                  ? LocaleKeys.encryption_itemLockedTitle.tr()
                  : LocaleKeys.encryption_itemLockedNamed.tr(args: [name]),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: premium.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              LocaleKeys.encryption_itemLockedBody.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: premium.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: () => unawaited(
                viewId.isEmpty
                    ? ensureWorkspaceUnlocked(context)
                    : unlockProtectedItem(context, viewId),
              ),
              child: Text(LocaleKeys.encryption_unlockConfirm.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
