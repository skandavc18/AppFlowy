import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_document.dart';
import 'package:archive/archive.dart';

import 'workspace_file_kind.dart';

/// Builds the bytes of a blank document for [kind].
///
/// Office documents are assembled as minimal but valid OOXML packages so a new
/// spreadsheet or presentation opens in the document server without shipping
/// binary templates in the bundle.
Uint8List blankFileContent(WorkspaceFileKind kind) {
  return switch (kind) {
    WorkspaceFileKind.markdown => _utf8('# Untitled\n\n'),
    WorkspaceFileKind.html => _utf8(_blankHtml),
    WorkspaceFileKind.notebook => _utf8(NotebookDocument.blank().encode()),
    WorkspaceFileKind.archive => _zip(const {}),
    WorkspaceFileKind.word => _zip(_wordParts),
    WorkspaceFileKind.excel => _zip(_excelParts),
    WorkspaceFileKind.powerpoint => _zip(_powerpointParts),
    _ => _utf8(''),
  };
}

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  for (final entry in parts.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('Unable to build the blank office document.');
  }
  return Uint8List.fromList(encoded);
}

const _xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

const _blankHtml = '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Untitled</title>
  </head>
  <body>
    <h1>Untitled</h1>
  </body>
</html>
''';

String _relationships(String body) =>
    '$_xmlHeader<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$body</Relationships>';

String _relationship(String id, String type, String target) =>
    '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/$type" Target="$target"/>';

const _defaultContentTypes =
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>';

String _contentTypes(String overrides) =>
    '$_xmlHeader<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '$_defaultContentTypes$overrides</Types>';

final Map<String, String> _wordParts = {
  '[Content_Types].xml': _contentTypes(
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>',
  ),
  '_rels/.rels': _relationships(
    _relationship('rId1', 'officeDocument', 'word/document.xml'),
  ),
  'word/document.xml': '$_xmlHeader'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body><w:p/>'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="709" w:footer="709" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>',
};

final Map<String, String> _excelParts = {
  '[Content_Types].xml': _contentTypes(
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
  ),
  '_rels/.rels': _relationships(
    _relationship('rId1', 'officeDocument', 'xl/workbook.xml'),
  ),
  'xl/workbook.xml': '$_xmlHeader'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
  'xl/_rels/workbook.xml.rels': _relationships(
    _relationship('rId1', 'worksheet', 'worksheets/sheet1.xml'),
  ),
  'xl/worksheets/sheet1.xml': '$_xmlHeader'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData/></worksheet>',
};

const _pptNamespaces =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';

const _emptyShapeTree = '<p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr/></p:spTree>';

final Map<String, String> _powerpointParts = {
  '[Content_Types].xml': _contentTypes(
    '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
    '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
    '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
    '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
    '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>',
  ),
  '_rels/.rels': _relationships(
    _relationship('rId1', 'officeDocument', 'ppt/presentation.xml'),
  ),
  'ppt/presentation.xml': '$_xmlHeader'
      '<p:presentation $_pptNamespaces>'
      '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
      '<p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>'
      '<p:sldSz cx="12192000" cy="6858000"/>'
      '<p:notesSz cx="6858000" cy="9144000"/>'
      '</p:presentation>',
  'ppt/_rels/presentation.xml.rels': _relationships(
    _relationship('rId1', 'slideMaster', 'slideMasters/slideMaster1.xml') +
        _relationship('rId2', 'slide', 'slides/slide1.xml') +
        _relationship('rId3', 'theme', 'theme/theme1.xml'),
  ),
  'ppt/slideMasters/slideMaster1.xml': '$_xmlHeader'
      '<p:sldMaster $_pptNamespaces>'
      '<p:cSld>$_emptyShapeTree</p:cSld>'
      '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
      'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
      'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
      '</p:sldMaster>',
  'ppt/slideMasters/_rels/slideMaster1.xml.rels': _relationships(
    _relationship('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml') +
        _relationship('rId2', 'theme', '../theme/theme1.xml'),
  ),
  'ppt/slideLayouts/slideLayout1.xml': '$_xmlHeader'
      '<p:sldLayout $_pptNamespaces type="blank" preserve="1">'
      '<p:cSld name="Blank">$_emptyShapeTree</p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sldLayout>',
  'ppt/slideLayouts/_rels/slideLayout1.xml.rels': _relationships(
    _relationship('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml'),
  ),
  'ppt/slides/slide1.xml': '$_xmlHeader'
      '<p:sld $_pptNamespaces>'
      '<p:cSld>$_emptyShapeTree</p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
      '</p:sld>',
  'ppt/slides/_rels/slide1.xml.rels': _relationships(
    _relationship('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml'),
  ),
  'ppt/theme/theme1.xml': _officeTheme,
};

const _officeTheme = '$_xmlHeader'
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">'
    '<a:themeElements>'
    '<a:clrScheme name="Office">'
    '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
    '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="44546A"/></a:dk2>'
    '<a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
    '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
    '<a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
    '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>'
    '<a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
    '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>'
    '<a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
    '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
    '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
    '</a:clrScheme>'
    '<a:fontScheme name="Office">'
    '<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
    '</a:fontScheme>'
    '<a:fmtScheme name="Office">'
    '<a:fillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:fillStyleLst>'
    '<a:lnStyleLst>'
    '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    '<a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
    '</a:lnStyleLst>'
    '<a:effectStyleLst>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '</a:effectStyleLst>'
    '<a:bgFillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:bgFillStyleLst>'
    '</a:fmtScheme>'
    '</a:themeElements>'
    '</a:theme>';
