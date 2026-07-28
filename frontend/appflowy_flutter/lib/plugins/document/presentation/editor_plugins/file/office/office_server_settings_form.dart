import 'dart:async';

import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

import 'office_server_settings.dart';

class OfficeServerSettingsForm extends StatefulWidget {
  const OfficeServerSettingsForm({
    super.key,
    required this.settings,
    required this.status,
    required this.onSubmit,
    this.title = 'Set up document editing',
    this.description =
        'Connect your self-hosted ONLYOFFICE Docs server to edit '
            'Word, Excel and PowerPoint files without leaving AppFlowy.',
    this.submitLabel = 'Connect server',
    this.showIcon = true,
    this.errorMessage,
  });

  final OfficeServerSettings settings;
  final OfficeServerStatus status;
  final Future<void> Function(OfficeServerSettings settings) onSubmit;
  final String title;
  final String description;
  final String submitLabel;
  final bool showIcon;
  final String? errorMessage;

  @override
  State<OfficeServerSettingsForm> createState() =>
      _OfficeServerSettingsFormState();
}

class _OfficeServerSettingsFormState extends State<OfficeServerSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url =
      TextEditingController(text: widget.settings.serverUrl);
  late final TextEditingController _secret =
      TextEditingController(text: widget.settings.jwtSecret);
  late final TextEditingController _bridge =
      TextEditingController(text: widget.settings.bridgeHost);
  late bool _showAdvanced;
  bool _showSecret = false;

  bool get _isConnecting => widget.status == OfficeServerStatus.connecting;

  @override
  void initState() {
    super.initState();
    _showAdvanced = widget.settings.jwtSecret.isNotEmpty ||
        widget.settings.bridgeHost.isNotEmpty;
  }

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showIcon) ...[
            const _OfficeIcon(icon: Icons.description_outlined),
            const SizedBox(height: 14),
          ],
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.description,
            style: TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: theme.textColorScheme.secondary,
            ),
          ),
          if (widget.status == OfficeServerStatus.unreachable) ...[
            const SizedBox(height: 16),
            _ConnectionNotice(
              message: widget.errorMessage ??
                  'We could not reach that server. Confirm the address and '
                      'make sure ONLYOFFICE Docs is running.',
              isError: true,
            ),
          ] else if (widget.status == OfficeServerStatus.connected) ...[
            const SizedBox(height: 16),
            const _ConnectionNotice(
              message: 'The direct document server is reachable.',
              isError: false,
            ),
          ],
          const SizedBox(height: 20),
          _Field(
            controller: _url,
            label: 'Document server address',
            hint: 'http://localhost:8080',
            prefixIcon: Icons.dns_outlined,
            validator: validateOfficeServerUrl,
            enabled: !_isConnecting,
            keyboardType: TextInputType.url,
            onFieldSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _isConnecting
                ? null
                : () => setState(() => _showAdvanced = !_showAdvanced),
            icon: AnimatedRotation(
              turns: _showAdvanced ? 0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: const Icon(Icons.chevron_right_rounded, size: 18),
            ),
            label: const Text('Advanced settings'),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 8),
            _Field(
              controller: _secret,
              label: 'JWT secret',
              hint: 'Must match the server JWT_SECRET',
              prefixIcon: Icons.key_outlined,
              obscure: !_showSecret,
              enabled: !_isConnecting,
              suffixIcon: IconButton(
                tooltip: _showSecret ? 'Hide JWT secret' : 'Show JWT secret',
                onPressed: _isConnecting
                    ? null
                    : () => setState(() => _showSecret = !_showSecret),
                icon: Icon(
                  _showSecret
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _bridge,
              label: 'Callback host',
              hint: 'host.docker.internal',
              prefixIcon: Icons.swap_horiz_rounded,
              enabled: !_isConnecting,
            ),
            const SizedBox(height: 7),
            Text(
              'Leave this empty for the recommended Docker setup. AppFlowy '
              'will choose it automatically.',
              style: TextStyle(
                fontSize: 12,
                height: 17 / 12,
                color: theme.textColorScheme.secondary,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isConnecting ? null : () => unawaited(_submit()),
              icon: _isConnecting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(
                _isConnecting ? 'Connecting...' : widget.submitLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_isConnecting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.onSubmit(
      OfficeServerSettings(
        serverUrl: _url.text.trim(),
        jwtSecret: _secret.text.trim(),
        bridgeHost: _bridge.text.trim(),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscure = false,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscure;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.textColorScheme.secondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          validator: validator,
          keyboardType: keyboardType,
          onFieldSubmitted: onFieldSubmitted,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: TextStyle(fontSize: 13, color: theme.textColorScheme.primary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(
                    prefixIcon,
                    size: 18,
                    color: theme.iconColorScheme.secondary,
                  ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 42,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _officeControlColor(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 13,
            ),
            border: _fieldBorder(context),
            enabledBorder: _fieldBorder(context),
            disabledBorder: _fieldBorder(context),
            focusedBorder: _fieldBorder(context, focused: true),
            errorBorder: _fieldBorder(context, error: true),
            focusedErrorBorder:
                _fieldBorder(context, focused: true, error: true),
          ),
        ),
      ],
    );
  }
}

class _OfficeIcon extends StatelessWidget {
  const _OfficeIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _officeControlColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EditorSurfaceStyle.embedBorder(context)),
      ),
      child: Icon(
        icon,
        size: 23,
        color: theme.iconColorScheme.primary,
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _officeControlColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EditorSurfaceStyle.embedBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: isError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 17 / 12,
                color: theme.textColorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _officeControlColor(BuildContext context) {
  return EditorSurfaceStyle.codeBlockBackgroundFor(
    Theme.of(context).brightness,
    Theme.of(context).colorScheme.surfaceContainerLow,
    isPaper: PaperTheme.isEnabled(context),
  );
}

OutlineInputBorder _fieldBorder(
  BuildContext context, {
  bool focused = false,
  bool error = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final color = error
      ? colorScheme.error
      : focused
          ? PaperTheme.isEnabled(context)
              ? PaperTheme.accent
              : colorScheme.primary
          : EditorSurfaceStyle.embedBorder(context);
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(
      color: color,
      width: focused || error ? 1.4 : 1,
    ),
  );
}
