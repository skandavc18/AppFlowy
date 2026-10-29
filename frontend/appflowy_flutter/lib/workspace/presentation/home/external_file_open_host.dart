import 'package:appflowy/plugins/external_file/external_file_plugin.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/external_file/external_file_open_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows each file the system asks AppFlowy to open in a tab of its own while
/// the home screen is up. A file that is already open is selected and read
/// again from disk.
class ExternalFileOpenHost extends StatefulWidget {
  const ExternalFileOpenHost({super.key, required this.child});

  final Widget child;

  @override
  State<ExternalFileOpenHost> createState() => _ExternalFileOpenHostState();
}

class _ExternalFileOpenHostState extends State<ExternalFileOpenHost> {
  late final ExternalFileOpener _opener = _open;

  ExternalFileOpenService get _service => ExternalFileOpenService.instance;

  @override
  void initState() {
    super.initState();
    // Files that launched AppFlowy open once the shell has built its tabs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _service.attach(_opener);
    });
  }

  @override
  void dispose() {
    _service.detach(_opener);
    super.dispose();
  }

  void _open(List<String> paths) {
    if (!mounted) return;
    final tabs = context.read<TabsBloc>();
    for (final path in paths) {
      final open = tabs.state.pageManagers
          .map((manager) => manager.plugin)
          .whereType<ExternalFilePlugin>()
          .firstWhereOrNull((plugin) => plugin.path == path);
      open?.reload();
      tabs.add(
        TabsEvent.openStandaloneTab(
          plugin: open ??
              makePlugin(pluginType: PluginType.externalFile, data: path),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
