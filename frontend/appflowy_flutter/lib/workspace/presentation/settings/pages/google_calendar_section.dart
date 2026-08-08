import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/google_calendar_provider.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Which Google calendars are shown inside AppFlowy.
///
/// It appears only once an account is connected — an empty picker for a
/// service nobody has signed into is just noise.
class GoogleCalendarSection extends StatefulWidget {
  const GoogleCalendarSection({super.key});

  @override
  State<GoogleCalendarSection> createState() => _GoogleCalendarSectionState();
}

class _GoogleCalendarSectionState extends State<GoogleCalendarSection> {
  final Map<String, List<CalendarInfo>> _byConnection =
      <String, List<CalendarInfo>>{};
  final List<GoogleCalendarProvider> _probes = <GoogleCalendarProvider>[];

  List<GoogleCalendarSelection> _selections = const [];
  bool _loading = true;

  late final CalendarWorkspace _store = CalendarWorkspace(providers: const []);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final probe in _probes) {
      probe.dispose();
    }
    _store.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _selections = await _store.readGoogleSelection();
    await ProviderConnections.instance.ensureLoaded();

    // Ask each account for its calendars with nothing selected, so every
    // calendar is offered rather than only the ones already being shown.
    for (final connection in ProviderConnections.instance.all) {
      if (connection.service != ProviderService.googleCalendar) {
        continue;
      }
      final probe = GoogleCalendarProvider(
        connection: connection,
        selectedCalendarIds: const <String>{},
        onCalendarsDiscovered: (calendars) {
          if (!mounted) {
            return;
          }
          setState(() => _byConnection[connection.id] = calendars);
        },
      );
      _probes.add(probe);
      unawaited(probe.refresh());
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Set<String> _chosenFor(String connectionId) {
    for (final selection in _selections) {
      if (selection.connectionId == connectionId) {
        return selection.calendarIds;
      }
    }
    return const <String>{};
  }

  Future<void> _toggle(
    String connectionId,
    String calendarId,
    bool chosen,
  ) async {
    final chosenIds = Set<String>.from(_chosenFor(connectionId));
    final remote = GoogleCalendarProvider.remoteIdOf(calendarId);
    if (chosen) {
      chosenIds.add(remote);
    } else {
      chosenIds.remove(remote);
    }

    final updated = <GoogleCalendarSelection>[
      for (final selection in _selections)
        if (selection.connectionId != connectionId) selection,
      GoogleCalendarSelection(
        connectionId: connectionId,
        calendarIds: chosenIds,
      ),
    ];
    await _store.saveGoogleSelection(updated);
    if (mounted) {
      setState(() => _selections = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ProviderConnections.instance.all
        .where((c) => c.service == ProviderService.googleCalendar)
        .toList();
    if (accounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final palette = FolderExplorerPalette.of(context);
    return SettingsCategory(
      title: LocaleKeys.calendarView_google_chooseCalendars.tr(),
      description: LocaleKeys.calendarView_google_chooseCalendarsHint.tr(),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          for (final account in accounts) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                account.accountLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: palette.textMuted,
                  fontVariations: const [FontVariation.weight(600)],
                ),
              ),
            ),
            if ((_byConnection[account.id] ?? const []).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  LocaleKeys.calendarView_google_noCalendars.tr(),
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              )
            else
              for (final calendar in _byConnection[account.id]!)
                _CalendarRow(
                  calendar: calendar,
                  chosen: _chosenFor(account.id).contains(
                    GoogleCalendarProvider.remoteIdOf(calendar.id),
                  ),
                  onChanged: (value) => unawaited(
                    _toggle(account.id, calendar.id, value),
                  ),
                ),
          ],
      ],
    );
  }
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.calendar,
    required this.chosen,
    required this.onChanged,
  });

  final CalendarInfo calendar;
  final bool chosen;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          CalendarColorDot(color: calendar.color, size: 9),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  calendar.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textPrimary,
                    fontVariations: const [FontVariation.weight(570)],
                  ),
                ),
                if (calendar.isReadOnly)
                  Text(
                    LocaleKeys.calendarView_google_readOnly.tr(),
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
              ],
            ),
          ),
          Switch(
            value: chosen,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
