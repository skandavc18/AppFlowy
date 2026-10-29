import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/external_file/external_file_open_service.dart';

/// Listens for files the system asks AppFlowy to open, including those that
/// launched it.
class ExternalFileOpenTask extends LaunchTask {
  const ExternalFileOpenTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    await ExternalFileOpenService.instance.start();
  }
}
