import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Opt-in, process-local startup measurements. Records only fixed phase names,
/// elapsed times and success flags; never settings, paths, account identifiers,
/// document contents or exception messages. No preferences are read or written.
class StartupProfile {
  StartupProfile({void Function(String)? write})
      : _write = write ?? ((String line) => stdout.writeln(line));

  final void Function(String) _write;
  final Stopwatch _clock = Stopwatch();
  final Set<String> _milestones = {};
  bool _enabled = false;

  bool get enabled => _enabled;

  void start(List<String> arguments) {
    _enabled = arguments.contains('--profile-startup');
    _milestones.clear();
    _clock
      ..reset()
      ..start();
    mark('dart_entry');
  }

  void mark(String phase) {
    if (!_enabled || !_milestones.add(phase)) return;
    _record(phase);
  }

  Future<T> measure<T>(String phase, FutureOr<T> Function() action) async {
    if (!_enabled) return action();
    final watch = Stopwatch()..start();
    var succeeded = false;
    try {
      final result = await action();
      succeeded = true;
      return result;
    } finally {
      _record(phase, duration: watch.elapsedMicroseconds, succeeded: succeeded);
    }
  }

  T measureSync<T>(String phase, T Function() action) {
    if (!_enabled) return action();
    final watch = Stopwatch()..start();
    var succeeded = false;
    try {
      final result = action();
      succeeded = true;
      return result;
    } finally {
      _record(phase, duration: watch.elapsedMicroseconds, succeeded: succeeded);
    }
  }

  void _record(String phase, {int? duration, bool? succeeded}) {
    if (!_enabled) return;
    _write('AF_STARTUP ${jsonEncode({
          'phase': phase,
          'elapsed_us': _clock.elapsedMicroseconds,
          if (duration != null) 'duration_us': duration,
          if (succeeded != null) 'succeeded': succeeded,
        })}');
  }
}

final startupProfile = StartupProfile();

/// Marks the frame in which this host is mounted, not the completion of every
/// asynchronous renderer inside it. Used to distinguish shell/page-host paint
/// from the engine's first raster and the pre-runApp initialization tasks.
class StartupProfileFrame extends StatefulWidget {
  const StartupProfileFrame({
    super.key,
    required this.phase,
    required this.child,
  });

  final String phase;
  final Widget child;

  @override
  State<StartupProfileFrame> createState() => _StartupProfileFrameState();
}

class _StartupProfileFrameState extends State<StartupProfileFrame> {
  @override
  void initState() {
    super.initState();
    if (startupProfile.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) startupProfile.mark(widget.phase);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
