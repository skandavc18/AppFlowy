import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:universal_platform/universal_platform.dart';

import 'astrology_controls.dart';
import 'astrology_engine.dart';
import 'astrology_jhd.dart';
import 'astrology_location.dart';
import 'astrology_model.dart';
import 'astrology_pdf_report.dart';

/// A live horoscope (now / device location) as one fixed chart for export.
Future<AstrologyInput> resolveAstrologyExportInput(
  AstrologyInput input, {
  AstrologyLocationService? locations,
  DateTime? now,
}) async {
  input.validate();
  var resolved = input;
  if (resolved.place == null) {
    final place =
        await (locations ?? AstrologyLocationService.instance).current();
    resolved = resolved.copyWith(place: place);
  }
  if (resolved.utc == null) {
    final instant = (now ?? DateTime.now()).toUtc();
    resolved = resolved.copyWith(
      utc: DateTime.utc(
        instant.year,
        instant.month,
        instant.day,
        instant.hour,
        instant.minute,
        instant.second,
      ),
    );
  }
  return resolved;
}

Future<AstrologyPdfFonts>? _fonts;

/// Builds the PDF report of [input]'s (resolved) chart.
Future<(AstrologyInput, Uint8List)> buildAstrologyReport(
  AstrologyInput input,
) async {
  final resolved = await resolveAstrologyExportInput(input);
  final chart = await AstrologyEngine.instance.calculate(resolved);
  final pending = _fonts ??= AstrologyPdfFonts.load();
  AstrologyPdfFonts fonts;
  try {
    fonts = await pending;
  } on Object {
    _fonts = null;
    rethrow;
  }
  return (resolved, await buildAstrologyPdf(chart: chart, fonts: fonts));
}

/// Open/save Jagannatha Hora files and save/print the PDF report.
class AstrologyFileActions extends StatefulWidget {
  const AstrologyFileActions({
    super.key,
    required this.input,
    required this.enabled,
    required this.onImported,
  });

  /// The horoscope currently shown (draft or saved), read at press time.
  final AstrologyInput Function() input;
  final bool enabled;

  /// Receives a validated, calculable input read from a .jhd file.
  final Future<void> Function(AstrologyInput input) onImported;

  @override
  State<AstrologyFileActions> createState() => _AstrologyFileActionsState();
}

class _AstrologyFileActionsState extends State<AstrologyFileActions> {
  String? _busy;

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busy != null || !widget.enabled) return;
    setState(() => _busy = id);
    try {
      await action();
    } on Object catch (error) {
      showToastNotification(
        message: error is FormatException ? error.message : '$error',
        type: ToastificationType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _name(AstrologyInput input) =>
      input.name.trim().isEmpty ? 'Horoscope' : input.name.trim();

  Future<void> _openJhd() async {
    final picked = await FilePicker().pickFiles(
      dialogTitle: 'Open a Jagannatha Hora birth file',
      type: FileType.custom,
      allowedExtensions: const ['jhd'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      throw const FormatException('The file could not be read.');
    }
    final imported = parseJhd(
      bytes,
      fileName: file.name,
      settings: widget.input(),
    );
    await AstrologyEngine.instance.calculate(imported.input);
    await widget.onImported(imported.input);
    showToastNotification(
      message:
          'Opened “${_name(imported.input)}”. Review it, then save to keep it.',
      description:
          imported.warnings.isEmpty ? null : imported.warnings.join('\n'),
      type: imported.warnings.isEmpty
          ? ToastificationType.success
          : ToastificationType.warning,
    );
  }

  Future<void> _saveJhd() async {
    final input = await resolveAstrologyExportInput(widget.input());
    final saved = await _save(
      encodeJhd(input),
      astrologyFileName(_name(input), 'jhd'),
      'jhd',
    );
    if (saved) {
      showToastNotification(message: 'Saved the Jagannatha Hora file.');
    }
  }

  Future<void> _savePdf() async {
    final (input, bytes) = await buildAstrologyReport(widget.input());
    final saved = await _save(
      bytes,
      astrologyFileName('${_name(input)} horoscope', 'pdf'),
      'pdf',
    );
    if (saved) showToastNotification(message: 'Saved the horoscope PDF.');
  }

  Future<void> _print() async {
    final (input, bytes) = await buildAstrologyReport(widget.input());
    await Printing.layoutPdf(
      name: '${_name(input)} horoscope',
      onLayout: (_) async => bytes,
    );
  }

  Future<bool> _save(Uint8List bytes, String name, String extension) async {
    final mobile = UniversalPlatform.isMobile;
    final path = await FilePicker().saveFile(
      dialogTitle: 'Save $name',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: mobile ? bytes : null,
    );
    if (path == null || path.isEmpty) return false;
    if (!mobile) {
      final target = p.extension(path).toLowerCase() == '.$extension'
          ? path
          : '$path.$extension';
      await File(target).writeAsBytes(bytes, flush: true);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && _busy == null;
    Widget action(
      String id,
      IconData icon,
      String label,
      String tooltip,
      Future<void> Function() onPressed,
    ) =>
        AstrologyButton(
          id: 'astrology-file-$id',
          label: label,
          icon: icon,
          busy: _busy == id,
          tooltip: tooltip,
          onPressed: enabled ? () => unawaited(_run(id, onPressed)) : null,
        );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        action(
          'open-jhd',
          Icons.folder_open_rounded,
          'Open .jhd',
          'Open a Jagannatha Hora birth file',
          _openJhd,
        ),
        action(
          'save-jhd',
          Icons.save_alt_rounded,
          'Save .jhd',
          'Save these birth details for Jagannatha Hora',
          _saveJhd,
        ),
        action(
          'save-pdf',
          Icons.picture_as_pdf_rounded,
          'Save PDF',
          'Save the charts, dashas, Shadbala, Ashtakavarga and positions as a PDF',
          _savePdf,
        ),
        action(
          'print',
          Icons.print_rounded,
          'Print',
          'Print the horoscope report',
          _print,
        ),
      ],
    );
  }
}
