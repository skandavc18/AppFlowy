import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_cloud_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings_form.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Whether this device opens office files in the bundled editor.
enum BuiltInOfficeEditorState {
  checking,
  available,

  /// The editor ships with this build, but WebKitGTK is not installed.
  needsWebKit,
  unavailable,
}

class SettingsOfficeView extends StatefulWidget {
  const SettingsOfficeView({
    super.key,
    required this.userProfile,
    this.store = const OfficeServerStore(),
    this.probe = probeOfficeServer,
    this.embeddedEditor,
  });

  final UserProfilePB userProfile;
  final OfficeServerStore store;
  final OfficeServerProbe probe;

  /// The bundled editor; desktop builds default to the shared instance.
  final EmbeddedOfficeEditor? embeddedEditor;

  @override
  State<SettingsOfficeView> createState() => _SettingsOfficeViewState();
}

class _SettingsOfficeViewState extends State<SettingsOfficeView> {
  OfficeServerSettings? _settings;
  OfficeServerStatus _status = OfficeServerStatus.unconfigured;
  String? _errorMessage;
  BuiltInOfficeEditorState _builtIn = BuiltInOfficeEditorState.checking;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_checkBuiltIn());
  }

  Future<void> _checkBuiltIn() async {
    final editor =
        widget.embeddedEditor ?? EmbeddedOfficeEditor.forCurrentPlatform();
    var state = BuiltInOfficeEditorState.unavailable;
    try {
      if (editor != null && await editor.host.isAvailable) {
        state = await editor.webViewSupported()
            ? BuiltInOfficeEditorState.available
            : BuiltInOfficeEditorState.needsWebKit;
      }
    } catch (error) {
      Log.error('Unable to check the built-in office editor: $error');
    }
    if (mounted) {
      setState(() => _builtIn = state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usesCloud = usesManagedOfficeServer(widget.userProfile);
    final settings = _settings;
    final builtIn = _builtIn == BuiltInOfficeEditorState.available;
    return SettingsBody(
      title: 'Document editing',
      description:
          'Choose how AppFlowy opens Word, Excel and PowerPoint files.',
      children: [
        SettingsCategory(
          title: 'Connection priority',
          children: [
            _PriorityNote(
              icon: builtIn
                  ? Icons.verified_rounded
                  : usesCloud
                      ? Icons.cloud_done_rounded
                      : Icons.computer_rounded,
              text: _priorityText(usesCloud),
            ),
            if (_builtIn == BuiltInOfficeEditorState.needsWebKit)
              const _PriorityNote(
                icon: Icons.download_rounded,
                text: 'Install WebKitGTK (the libwebkit2gtk-4.1-0 package) '
                    'to edit office files in the built-in editor, without '
                    'a document server.',
              ),
          ],
        ),
        if (builtIn || _builtIn == BuiltInOfficeEditorState.checking)
          const SizedBox.shrink()
        else if (settings == null)
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

  String _priorityText(bool usesCloud) {
    if (_builtIn == BuiltInOfficeEditorState.available) {
      return usesCloud
          ? 'Office files on this computer open in AppFlowy\'s built-in '
              'editor, without a document server. Files stored in AppFlowy '
              'Cloud use the document server managed by your Cloud '
              'deployment, so changes reach cloud storage.'
          : 'Office files open in AppFlowy\'s built-in editor and save '
              'straight back to the file. No document server is needed.';
    }
    return usesCloud
        ? 'AppFlowy Cloud is connected. Office files always use '
            'the document server managed by this Cloud deployment.'
        : 'AppFlowy is in local mode. Office files use the direct '
            'document server configured below.';
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

class _PriorityNote extends StatelessWidget {
  const _PriorityNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: AppFlowyTheme.of(context).textColorScheme.secondary,
            ),
          ),
        ),
      ],
    );
  }
}
