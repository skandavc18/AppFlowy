import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_cloud_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings_form.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class SettingsOfficeView extends StatefulWidget {
  const SettingsOfficeView({
    super.key,
    required this.userProfile,
    this.store = const OfficeServerStore(),
    this.probe = probeOfficeServer,
  });

  final UserProfilePB userProfile;
  final OfficeServerStore store;
  final OfficeServerProbe probe;

  @override
  State<SettingsOfficeView> createState() => _SettingsOfficeViewState();
}

class _SettingsOfficeViewState extends State<SettingsOfficeView> {
  OfficeServerSettings? _settings;
  OfficeServerStatus _status = OfficeServerStatus.unconfigured;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final usesCloud = usesManagedOfficeServer(widget.userProfile);
    final settings = _settings;
    return SettingsBody(
      title: 'Document editing',
      description:
          'Choose how AppFlowy opens Word, Excel and PowerPoint files.',
      children: [
        SettingsCategory(
          title: 'Connection priority',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  usesCloud
                      ? Icons.cloud_done_rounded
                      : Icons.computer_rounded,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    usesCloud
                        ? 'AppFlowy Cloud is connected. Office files always use '
                            'the document server managed by this Cloud deployment.'
                        : 'AppFlowy is in local mode. Office files use the direct '
                            'document server configured below.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 19 / 13,
                      color:
                          AppFlowyTheme.of(context).textColorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (settings == null)
          const Center(child: CircularProgressIndicator())
        else
          OfficeServerSettingsForm(
            settings: settings,
            status: _status,
            errorMessage: _errorMessage,
            title: 'Direct document server',
            description: usesCloud
                ? 'These settings are saved as a local fallback and are not '
                    'used while AppFlowy Cloud is connected.'
                : 'Connect directly to a self-hosted ONLYOFFICE Docs server. '
                    'AppFlowy Cloud will take priority whenever you sign in.',
            submitLabel: 'Save and test',
            showIcon: false,
            onSubmit: _saveAndTest,
          ),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final settings = await widget.store.read();
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = settings;
        _status = settings.isConfigured
            ? OfficeServerStatus.connecting
            : OfficeServerStatus.unconfigured;
      });
      if (settings.isConfigured) {
        await _test(settings);
      }
    } catch (error) {
      Log.error('Unable to load document server settings: $error');
      if (mounted) {
        setState(() {
          _settings = const OfficeServerSettings();
          _status = OfficeServerStatus.unreachable;
          _errorMessage = 'AppFlowy could not load these settings.';
        });
      }
    }
  }

  Future<void> _saveAndTest(OfficeServerSettings settings) async {
    setState(() {
      _settings = settings;
      _status = OfficeServerStatus.connecting;
      _errorMessage = null;
    });
    try {
      await widget.store.write(settings);
      await _test(settings);
    } catch (error) {
      Log.error('Unable to save document server settings: $error');
      if (mounted) {
        setState(() {
          _status = OfficeServerStatus.unreachable;
          _errorMessage = 'AppFlowy could not save these settings.';
        });
      }
    }
  }

  Future<void> _test(OfficeServerSettings settings) async {
    final reachable = await widget.probe(settings);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = reachable
          ? OfficeServerStatus.connected
          : OfficeServerStatus.unreachable;
      _errorMessage = reachable
          ? null
          : 'The document server did not answer. Check its address and status.';
    });
  }
}
