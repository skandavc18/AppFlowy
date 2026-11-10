import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:universal_platform/universal_platform.dart';

import 'theme_audit.dart';

/// One place the audit opens: a workspace view or a system page.
class AuditPage {
  AuditPage(this.name, {this.view, this.plugin, this.document = false});

  final String name;
  final ViewPB? view;
  final Plugin Function()? plugin;

  /// Long documents are captured a viewport at a time.
  final bool document;
}

/// Fills an empty workspace with one of everything a person can make, so the
/// audit sees every block, page kind, collection and file preview.
class ThemeAuditSeed {
  ThemeAuditSeed(this.tester, this.audit, this.scratch);

  final WidgetTester tester;
  final ThemeAudit audit;
  final Directory scratch;

  late final String workspaceId;

  Future<List<AuditPage>> seed({bool Function(String name)? wants}) async {
    bool want(String name) => wants?.call(name) ?? true;
    workspaceId = (await UserBackendService.getCurrentWorkspace())
        .fold((workspace) => workspace.id, (error) => throw error);
    final files = await _sampleFiles();
    final pages = <AuditPage>[];

    final sections = <SlashMenuSection>[
      for (final section in SlashMenuSection.values)
        if (section != SlashMenuSection.suggestions) section,
    ];
    for (final section in sections) {
      if (!want('doc-${section.name}')) {
        continue;
      }
      final view = await _create('Blocks · ${section.name}');
      await fillWithSlashSection(view, section);
      pages.add(AuditPage('doc-${section.name}', view: view, document: true));
    }

    if (want('doc-rich-and-files')) {
      final rich = await _create('Rich text and files');
      await _fillRichText(rich, files);
      pages.add(AuditPage('doc-rich-and-files', view: rich, document: true));
    }

    for (final kind in WorkspaceTableKind.values) {
      if (!want('table-${kind.name}')) {
        continue;
      }
      final view = await createWorkspaceDatabase(
        parentViewId: workspaceId,
        kind: kind,
        section: ViewSectionPB.Public,
      );
      if (view != null) {
        pages.add(AuditPage('table-${kind.name}', view: view));
      }
    }

    for (final (name, layout, extra) in [
      ('canvas', ViewLayoutPB.Document, CanvasMetadata.newExtra()),
      ('dashboard', ViewLayoutPB.Document, DashboardMetadata.newExtra()),
      ('chat', ViewLayoutPB.Chat, null),
    ]) {
      if (want(name)) {
        pages.add(
          AuditPage(
            name,
            view: await _create(name, layout: layout, extra: extra),
          ),
        );
      }
    }

    for (final kind in CollectionKind.values) {
      if (!want('collection-${kind.name}')) {
        continue;
      }
      final view = (await const CollectionService().createCollection(
        parentViewId: workspaceId,
        kind: kind,
        name: 'Collection · ${kind.name}',
        section: ViewSectionPB.Public,
      ))
          .fold((view) => view, (error) => null);
      if (view != null) {
        pages.add(AuditPage('collection-${kind.name}', view: view));
      }
    }

    if (want('folder')) {
      const items = WorkspaceItemService();
      final folder = (await items.createFolder(
        parentViewId: workspaceId,
        name: 'Folder',
        section: ViewSectionPB.Public,
      ))
          .fold((view) => view, (error) => throw error);
      for (final (name, content) in [
        (
          'notes.md',
          '# Notes\n\nSome *markdown* with `code` and a [link](https://appflowy.io).\n'
        ),
        ('todo.txt', 'buy milk\nwrite audit\n'),
      ]) {
        await items.createTextFile(
          parentViewId: folder.id,
          name: name,
          content: content,
        );
      }
      pages.add(AuditPage('folder', view: folder));
    }

    for (final file in files.where(_opensStandalone)) {
      final name = 'file-${p.extension(file.path).substring(1)}';
      if (!want(name)) {
        continue;
      }
      pages.add(
        AuditPage(
          name,
          plugin: () => makePlugin(
            pluginType: PluginType.externalFile,
            data: file.path,
          ),
        ),
      );
    }

    for (final type in const [
      PluginType.blank,
      PluginType.recents,
      PluginType.favorites,
      PluginType.pageLibrary,
      PluginType.templates,
      PluginType.extensions,
      PluginType.workflows,
      PluginType.trash,
    ]) {
      if (!want('system-${type.name}')) {
        continue;
      }
      pages.add(
        AuditPage(
          'system-${type.name}',
          plugin: () => makePlugin(pluginType: type),
        ),
      );
    }
    return pages;
  }

  static bool _opensStandalone(File file) => const {
        '.md',
        '.txt',
        '.html',
        '.pdf',
        '.csv',
        '.json',
        '.py',
        '.docx',
        '.xlsx',
      }.contains(p.extension(file.path));

  Future<ViewPB> _create(
    String name, {
    ViewLayoutPB layout = ViewLayoutPB.Document,
    String? extra,
  }) async =>
      (await ViewBackendService.createView(
        layoutType: layout,
        parentViewId: workspaceId,
        name: name,
        section: ViewSectionPB.Public,
        extra: extra,
      ))
          .fold((view) => view, (error) => throw error);

  Future<void> open(AuditPage page) async {
    final view = page.view;
    final plugin = page.plugin?.call() ?? view!.plugin();
    // On mobile the tabs hand this to the mobile router, which pushes the
    // page as a route; going through it covers that path too.
    getIt<TabsBloc>().add(TabsEvent.openPlugin(plugin: plugin, view: view));
    await audit.pumpFor(
      Duration(milliseconds: UniversalPlatform.isMobile ? 3000 : 1500),
    );
    await audit.settle();
  }

  /// Pumps until [finder] matches or [timeout] passes; whether it matched.
  Future<bool> waitFor(Finder finder, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (finder.evaluate().isNotEmpty) {
        return true;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    return finder.evaluate().isNotEmpty;
  }

  /// The editor of the page most recently opened: on mobile pages are
  /// stacked routes, and the newest one is built last.
  EditorState get _currentEditor => tester
      .widget<AppFlowyEditor>(find.byType(AppFlowyEditor).last)
      .editorState;

  Future<EditorState> _editorOf(ViewPB view) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await home();
      await open(AuditPage(view.name, view: view));
      if (await waitFor(
        find.byType(AppFlowyEditor),
        const Duration(seconds: 15),
      )) {
        await audit.pumpFor(const Duration(milliseconds: 500));
        return _currentEditor;
      }
    }
    final navigator = _rootNavigator;
    var route = 'no navigator';
    navigator?.popUntil((r) {
      route = '${r.settings.name} (${r.runtimeType})';
      return true;
    });
    throw StateError(
      '${view.name} never showed an editor; top route: $route; '
      'opener installed: ${TabsBloc.mobileOpener != null}; '
      'plugin: ${view.plugin().pluginType}; '
      'on screen: ${find.byType(Scaffold).evaluate().map((e) => e.widget.key).toList()}',
    );
  }

  /// The router's own navigator, which every page and dialog is pushed on; the
  /// first [Navigator] in the tree is not always it.
  NavigatorState? get _rootNavigator {
    final router = AppGlobals.rootNavKey.currentState;
    if (router != null) {
      return router;
    }
    final navigator = find.byType(Navigator);
    return navigator.evaluate().isEmpty
        ? null
        : Navigator.of(tester.element(navigator.first), rootNavigator: true);
  }

  /// Closes menus, dialogs and sheets, leaving the page underneath open.
  Future<void> dismissOverlays() async {
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 120));
    }
    _rootNavigator?.popUntil((route) => route is! PopupRoute);
    await audit.settle(timeout: const Duration(seconds: 1));
  }

  /// Back to the first screen: on mobile every page is a pushed route.
  Future<void> home() async {
    await dismissOverlays();
    _rootNavigator?.popUntil((route) => route.isFirst);
    await audit.settle(timeout: const Duration(seconds: 2));
  }

  /// Inserts every `/` entry of [section] into [view] through the entry's own
  /// handler — what picking it from the menu does — under a caption naming it.
  Future<void> fillWithSlashSection(
    ViewPB view,
    SlashMenuSection section,
  ) async {
    var editorState = await _editorOf(view);
    final context = tester.element(find.byType(AppFlowyEditor).last);
    final entries = slashMenuSections(
      isLocalMode: true,
      documentBloc: context.read<DocumentBloc>(),
      editorState: editorState,
      view: view,
    )
        .where((entry) => entry.section == section)
        .expand((entry) => entry.items)
        .where((item) => !_needsAi(item.name))
        .toList();
    for (final item in entries) {
      final index = editorState.document.root.children.length;
      await editorState.apply(
        editorState.transaction
          ..insertNodes(
            [index],
            // What a person types: a line holding "/", which the entry's
            // handler removes before it inserts its block.
            [paragraphNode(text: '▸ ${item.name}'), paragraphNode(text: '/')],
          ),
      );
      editorState.selection = Selection.collapsed(
        Position(path: [index + 1], offset: 1),
      );
      try {
        item.handler(
          editorState,
          _AuditMenu(),
          tester.element(find.byType(AppFlowyEditor).last),
        );
      } on Object catch (error) {
        audit.note('slash "${item.name}" threw: $error');
      }
      await audit.pumpFor(const Duration(milliseconds: 700));
      await dismissOverlays();
      if (find.byType(AppFlowyEditor).evaluate().isEmpty ||
          _currentEditor != editorState) {
        // The entry navigated somewhere (a new sub-page); come back.
        editorState = await _editorOf(view);
      }
    }
  }

  static bool _needsAi(String name) {
    final lower = name.toLowerCase();
    return lower.contains('ai writer') ||
        lower.contains('continue writing') ||
        RegExp(r'\bai\b').hasMatch(lower);
  }

  Future<void> _fillRichText(ViewPB view, List<File> files) async {
    final editorState = await _editorOf(view);
    Delta marked(String text, Map<String, dynamic> attributes) =>
        Delta()..insert(text, attributes: attributes);
    final nodes = <Node>[
      headingNode(level: 1, text: 'Heading one'),
      headingNode(level: 2, text: 'Heading two'),
      headingNode(level: 3, text: 'Heading three'),
      paragraphNode(
        delta: Delta()
          ..insert('Plain, ')
          ..insert('bold', attributes: {'bold': true})
          ..insert(', ')
          ..insert('italic', attributes: {'italic': true})
          ..insert(', ')
          ..insert('underline', attributes: {'underline': true})
          ..insert(', ')
          ..insert('strike', attributes: {'strikethrough': true})
          ..insert(', ')
          ..insert('inline code', attributes: {'code': true})
          ..insert(' and a ')
          ..insert('link', attributes: {'href': 'https://appflowy.io'})
          ..insert('.'),
      ),
      for (final tint in const [
        'appflowy_them_color_tint1',
        'appflowy_them_color_tint4',
        'appflowy_them_color_tint7',
      ])
        paragraphNode(
          delta: marked('Highlighted with $tint', {'bg_color': tint}),
        ),
      for (final color in const ['0xffe8533c', '0xff2f80ed', '0xff000000'])
        paragraphNode(
          delta: marked('Text coloured $color', {'font_color': color}),
        ),
      bulletedListNode(text: 'Bulleted item'),
      numberedListNode(delta: Delta()..insert('Numbered item')),
      todoListNode(checked: true, text: 'Done item'),
      todoListNode(checked: false, text: 'Open item'),
      quoteNode(delta: Delta()..insert('A quotation worth keeping.')),
      if (files.where((f) => f.path.endsWith('.png')).firstOrNull
          case final File png)
        customImageNode(url: png.path),
      for (final file in files)
        Node(
          type: FileBlockKeys.type,
          attributes: {
            ...fileNode(url: file.path, name: p.basename(file.path)).attributes,
            FileBlockKeys.displayMode: 'preview',
          },
        ),
      for (final file in files.take(3))
        fileNode(url: file.path, name: p.basename(file.path)),
    ];
    await editorState.apply(
      editorState.transaction..insertNodes([0], nodes),
    );
    await audit.pumpFor(const Duration(milliseconds: 1500));
  }

  Future<List<File>> _sampleFiles() async {
    final dir = await Directory(p.join(scratch.path, 'samples'))
        .create(recursive: true);
    Future<File> write(String name, Object content) async {
      final file = File(p.join(dir.path, name));
      if (content is String) {
        await file.writeAsString(content);
      } else {
        await file.writeAsBytes(content as List<int>);
      }
      return file;
    }

    return [
      await write(
        'readme.md',
        '# Audit readme\n\nA paragraph with **bold**, `code` and a list:\n\n'
            '- one\n- two\n\n```dart\nvoid main() => print("hi");\n```\n\n'
            '> A quote.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n',
      ),
      await write('notes.txt', 'Plain text notes.\nSecond line.\n'),
      await write(
        'table.csv',
        'name,kind,count\nalpha,letter,1\nbeta,letter,2\ngamma,letter,3\n',
      ),
      await write(
        'data.json',
        const JsonEncoder.withIndent('  ').convert({
          'name': 'audit',
          'values': [1, 2, 3],
          'nested': {'ok': true, 'none': null},
        }),
      ),
      await write(
        'script.py',
        '# A comment\nimport math\n\n\ndef area(r: float) -> float:\n'
            '    """Circle area."""\n    return math.pi * r ** 2\n',
      ),
      await write(
        'page.html',
        '<!doctype html><html><body><h1>Audit page</h1>'
            '<p>Some <b>HTML</b> with a <a href="#">link</a>.</p></body></html>',
      ),
      await write(
        'shape.svg',
        '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">'
            '<rect width="120" height="80" rx="12" fill="#6366F1"/>'
            '<circle cx="60" cy="40" r="22" fill="#FDE68A"/></svg>',
      ),
      await write('picture.png', await _png()),
      await write('document.pdf', _pdf()),
      await write('letter.docx', _docx()),
      await write('sheet.xlsx', _xlsx()),
      await write('bundle.zip', _zip({'inside.txt': 'zipped text'})),
    ];
  }

  static Future<List<int>> _png() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(480, 300);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const [Color(0xFF0EA5A4), Color(0xFF6366F1), Color(0xFFE0475F)],
          const [0, .5, 1],
        ),
    );
    final image = await recorder
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static List<int> _pdf() {
    const stream = 'BT /F1 24 Tf 72 700 Td (AppFlowy theme audit) Tj ET';
    final objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
      '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];
    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(out.length);
      out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = out.length;
    out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets) {
      out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
    return ascii.encode(out.toString());
  }

  static List<int> _zip(Map<String, String> entries) {
    final archive = Archive();
    for (final MapEntry(key: name, value: text) in entries.entries) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    return ZipEncoder().encode(archive)!;
  }

  static const _rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="%s"/>'
      '</Relationships>';

  static List<int> _docx() => _zip({
        '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '</Types>',
        '_rels/.rels': _rels.replaceFirst('%s', 'word/document.xml'),
        'word/document.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            '<w:body><w:p><w:r><w:t>AppFlowy theme audit letter.</w:t></w:r></w:p>'
            '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold paragraph.</w:t></w:r></w:p>'
            '</w:body></w:document>',
      });

  static List<int> _xlsx() => _zip({
        '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '</Types>',
        '_rels/.rels': _rels.replaceFirst('%s', 'xl/workbook.xml'),
        'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Audit" sheetId="1" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
                '</Relationships>',
        'xl/worksheets/sheet1.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
            '<row r="1"><c r="A1" t="inlineStr"><is><t>Item</t></is></c><c r="B1" t="inlineStr"><is><t>Count</t></is></c></row>'
            '<row r="2"><c r="A2" t="inlineStr"><is><t>Apples</t></is></c><c r="B2"><v>4</v></c></row>'
            '<row r="3"><c r="A3" t="inlineStr"><is><t>Pears</t></is></c><c r="B3"><v>7</v></c></row>'
            '</sheetData></worksheet>',
      });
}

class _AuditMenu extends SelectionMenuService {
  @override
  Offset get offset => const Offset(200, 200);

  @override
  Alignment get alignment => Alignment.topLeft;

  @override
  SelectionMenuStyle get style => SelectionMenuStyle.light;

  @override
  Future<void> show() async {}

  @override
  void dismiss() {}

  @override
  (double?, double?, double?, double?) getPosition() => (200, 200, null, null);
}
