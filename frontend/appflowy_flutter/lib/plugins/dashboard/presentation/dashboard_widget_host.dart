import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_panel.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_standalone_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A dashboard of exactly one widget, for [spec].
///
/// This is how a widget lives anywhere that is not a dashboard — a page, a
/// canvas — while still being drawn and edited by the dashboard's own code.
DashboardDocument dashboardDocumentFor(DashboardWidgetSpec spec) =>
    DashboardDocument(
      sections: [
        DashboardSection(id: 'standalone-${spec.id}', widgets: [spec]),
      ],
      settings: const DashboardSettings(
        showHeader: false,
        showControlBar: false,
      ),
    );

/// One dashboard widget, hosted outside a dashboard.
///
/// The widget gets a dashboard of its own — a private controller holding just
/// this spec — so whatever it does on a dashboard (a note being written, a
/// list ticked, a chart pointed at a table) it does here too, through the very
/// same builder. Every change is handed to [onChanged], and the host keeps the
/// spec wherever the widget lives: in a block's attributes, on a canvas card.
///
/// A [spec] that arrives changed from outside — an undo in the page, a
/// collaborator — is adopted without being reported back.
class DashboardWidgetHost extends StatefulWidget {
  const DashboardWidgetHost({
    super.key,
    required this.spec,
    this.onChanged,
    this.editable = true,
    this.keyPrefix = 'dashboard-widget-host',
  });

  final DashboardWidgetSpec spec;
  final ValueChanged<DashboardWidgetSpec>? onChanged;

  /// Whether the widget may be typed into and configured.
  final bool editable;

  /// Keys inside the host start with this, so each surface can be told apart.
  final String keyPrefix;

  @override
  State<DashboardWidgetHost> createState() => _DashboardWidgetHostState();
}

class _DashboardWidgetHostState extends State<DashboardWidgetHost> {
  late final DashboardController _controller;

  /// The spec last seen on either side, so neither echoes the other.
  late DashboardWidgetSpec _known;

  @override
  void initState() {
    super.initState();
    _known = widget.spec;
    _controller = DashboardController(
      // No view: a hosted widget is kept by its host, never written on its own.
      viewId: '',
      document: dashboardDocumentFor(widget.spec),
      mode: _modeFor(widget.editable),
      persistDebounce: Duration.zero,
    )..addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DashboardWidgetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editable != oldWidget.editable) {
      _controller.setMode(_modeFor(widget.editable));
    }
    if (widget.spec != _known) {
      _known = widget.spec;
      // Adopted, not remembered: the host's own history already has it.
      _controller.replace(dashboardDocumentFor(widget.spec), remember: false);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  static DashboardMode _modeFor(bool editable) =>
      editable ? DashboardMode.edit : DashboardMode.presentation;

  DashboardWidgetSpec get _current =>
      _controller.document.widgetById(widget.spec.id) ?? widget.spec;

  void _onControllerChanged() {
    final current = _controller.document.widgetById(widget.spec.id);
    if (current == null || current == _known) {
      return;
    }
    _known = current;
    widget.onChanged?.call(current);
  }

  Future<void> _openSettings() async {
    if (!widget.editable) return;
    _controller.configure(widget.spec.id);
    await showDashboardWidgetSettings(
      context,
      controller: _controller,
      widgetId: widget.spec.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return PreviewToolbarRegion(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final spec = _current;
          final definition = DashboardWidgetRegistry.definitionFor(spec.type);
          final configurable = widget.editable && definition != null;
          return Stack(
            children: [
              Positioned.fill(
                // A field in any widget keeps its editing keys: the page or
                // canvas around it must not take Backspace or the arrows.
                child: TextEntryShortcuts(
                  child: DashboardStandaloneCard(
                    controller: _controller,
                    spec: spec,
                    palette: palette,
                    keyPrefix: widget.keyPrefix,
                  ),
                ),
              ),
              if (configurable)
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: PreviewToolbar(
                    child: _SettingsPill(
                      key: ValueKey('${widget.keyPrefix}-settings-${spec.id}'),
                      palette: palette,
                      onPressed: () => unawaited(_openSettings()),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The one control a hosted widget needs from the dashboard: its settings.
class _SettingsPill extends StatelessWidget {
  const _SettingsPill({
    super.key,
    required this.palette,
    required this.onPressed,
  });

  final DashboardPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.raised.withValues(alpha: palette.isDark ? 0.94 : 0.96),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: palette.shadowColor.withValues(
              alpha: palette.isDark ? 0.4 : 0.14,
            ),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DashboardIconButton(
          icon: Icons.tune_rounded,
          palette: palette,
          size: 26,
          iconSize: 15,
          tooltip: LocaleKeys.dashboard_card_configure.tr(),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Shows a hosted widget's settings at the side, exactly as a dashboard does.
///
/// The sheet follows [controller]: closing the settings from inside the panel
/// puts the sheet away, and putting the sheet away closes the settings.
Future<void> showDashboardWidgetSettings(
  BuildContext context, {
  required DashboardController controller,
  required String widgetId,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, __) => _SettingsSheet(
      controller: controller,
      widgetId: widgetId,
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
  controller.closeSettings();
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller, required this.widgetId});

  final DashboardController controller;
  final String widgetId;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  var _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_follow);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    if (_closing || !mounted) return;
    final gone =
        widget.controller.document.widgetById(widget.widgetId) == null ||
            widget.controller.configuringWidgetId == null;
    if (gone) {
      _closing = true;
      Navigator.of(context).maybePop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.controller.document.widgetById(widget.widgetId);
    if (spec == null) return const SizedBox.shrink();
    final palette = DashboardPalette.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: DashboardEditingScope(
            controller: widget.controller,
            child: DashboardConfigPanel(
              key: ValueKey('dashboard-widget-host-panel-${spec.id}'),
              controller: widget.controller,
              palette: palette,
              spec: spec,
              standalone: true,
            ),
          ),
        ),
      ),
    );
  }
}
