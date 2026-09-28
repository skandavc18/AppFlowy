import 'package:appflowy/shared/page_icon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit_test/shared/page_icon_test_support.dart';

/// Header tests that do not resize still mount real icon controllers. Replace
/// only their new metadata boundary, and prove they perform no eager IO.
class PassivePageIconTestScope extends StatefulWidget {
  const PassivePageIconTestScope({super.key, required this.child});

  final Widget child;

  @override
  State<PassivePageIconTestScope> createState() =>
      _PassivePageIconTestScopeState();
}

class _PassivePageIconTestScopeState extends State<PassivePageIconTestScope> {
  final backend = PageIconMemoryBackend([]);

  @override
  void initState() {
    super.initState();
    addTearDown(() {
      expect(backend.reads, isEmpty,
          reason: 'Mounting must not read icon metadata');
      expect(backend.writes, isEmpty,
          reason: 'Header actions must not resize icons');
      expect(backend.activeListeners, 0,
          reason: 'Icon subscriptions must detach');
    });
  }

  @override
  Widget build(BuildContext context) => PageIconBackendScope(
        backend: backend,
        child: widget.child,
      );
}
