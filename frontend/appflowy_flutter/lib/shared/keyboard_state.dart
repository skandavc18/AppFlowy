import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_platform/universal_platform.dart';

/// Keeps Flutter's idea of which modifier keys are held down honest.
///
/// Windows keeps the key *up* of a modifier to itself whenever the shell claims
/// the combination — Win+Shift+S to take a screenshot, Win+D, Win+arrow to snap
/// a window, Alt+Tab, or any globally registered hotkey. The application then
/// believes that modifier is still down for the rest of the session, and
/// `HardwareKeyboard.syncKeyboardState` cannot mend it because it only ever
/// *adds* pressed keys.
///
/// The damage is out of all proportion to the cause: `SingleActivator` matches
/// modifiers exactly, and Flutter's Windows text-editing map has no Meta
/// variant of Backspace at all, so one stale Meta silently stops Backspace,
/// Enter, the arrows and every editor command in every text field at once.
/// Typing still works, because characters arrive over the input connection
/// rather than through the shortcut tree — which is what makes the failure look
/// like "Backspace is broken everywhere" rather than "a key is stuck".
class KeyboardStateReconciler {
  KeyboardStateReconciler._();

  static final KeyboardStateReconciler instance = KeyboardStateReconciler._();

  static final _modifiers = <PhysicalKeyboardKey>{
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
  };

  /// Long enough that holding a real chord costs one platform call, short
  /// enough that a stuck modifier is gone before the next keystroke.
  static const _throttle = Duration(milliseconds: 400);

  final _observer = _LifecycleObserver();

  bool _started = false;
  bool _checking = false;
  bool _unsupported = false;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (_started || !UniversalPlatform.isDesktop) {
      return;
    }
    _started = true;
    _observer.onResumed = () => unawaited(reconcile(force: true));
    WidgetsBinding.instance.addObserver(_observer);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && _staleCandidates().isNotEmpty) {
      unawaited(reconcile());
    }
    // Never claim the key: this only watches.
    return false;
  }

  Set<PhysicalKeyboardKey> _staleCandidates() =>
      HardwareKeyboard.instance.physicalKeysPressed
          .where(_modifiers.contains)
          .toSet();

  /// Asks the platform which modifiers are really down and releases the rest.
  Future<void> reconcile({bool force = false}) async {
    if (_checking || _unsupported) {
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastCheck) < _throttle) {
      return;
    }
    final held = _staleCandidates();
    if (held.isEmpty) {
      return;
    }

    _checking = true;
    _lastCheck = now;
    try {
      final state = await SystemChannels.keyboard
          .invokeMapMethod<int, int>('getKeyboardState');
      if (state == null) {
        return;
      }
      final actuallyDown = state.keys.map(PhysicalKeyboardKey.new).toSet();
      for (final key in held) {
        if (actuallyDown.contains(key)) {
          continue;
        }
        // The real key up may have landed while the answer was in flight.
        final logicalKey = HardwareKeyboard.instance.lookUpLayout(key);
        if (logicalKey == null) {
          continue;
        }
        Log.info('Releasing ${key.debugName}: the system says it is not held.');
        HardwareKeyboard.instance.handleKeyEvent(
          KeyUpEvent(
            physicalKey: key,
            logicalKey: logicalKey,
            timeStamp: Duration.zero,
            synthesized: true,
          ),
        );
      }
    } on MissingPluginException {
      _unsupported = true;
    } on PlatformException catch (error) {
      _unsupported = true;
      Log.warn('The keyboard state could not be read: $error');
    } finally {
      _checking = false;
    }
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  VoidCallback? onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed?.call();
    }
  }
}
