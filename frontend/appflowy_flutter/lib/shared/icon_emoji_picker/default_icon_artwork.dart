/// Purpose-drawn defaults shared by navigation and the icon picker. A 24px
/// grid, 1.75px stroke and round caps/joins keep every symbol optically related.
/// These artwork keys retain the sidebar's original compatibility identities;
/// selected defaults use the separate namespaced catalogue in default_icons.dart.
String? defaultIconSvg(String name) => _defaultIconSvgs[name];

final _defaultIconSvgs = _bodies.map(
  (name, body) => MapEntry(
    name,
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.75" '
    'stroke-linecap="round" stroke-linejoin="round">$body</svg>',
  ),
);

// A rounded sheet and folded corner shared by all file types. Simple marks
// stay legible at navigation size, unlike tiny PDF/DOC/XLS lettering.
const _sheet = '<path d="M13.5 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12'
    'a2 2 0 0 0 2-2V9.5L13.5 3Z"/>'
    '<path d="M13.5 3v4.5a2 2 0 0 0 2 2H20"/>';

const _bodies = <String, String>{
  'magnifying-glass': '<circle cx="10.5" cy="10.5" r="6.5"/>'
      '<path d="m15.5 15.5 5 5"/>',
  'note-pencil': '<path d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12'
      'a2 2 0 0 0 2-2v-6M15.5 4.5l4 4M9 16l1-5 8-8a2.8 2.8 0 0 1 4 4'
      'l-8 8-5 1Z"/>',
  'house': '<path d="m3 10 7.8-6.4a2 2 0 0 1 2.4 0L21 10'
      'M5 9v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9'
      'M9 21v-7a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v7"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'dots-three': '<g fill="currentColor" stroke="none">'
      '<circle cx="5" cy="12" r="1.35"/>'
      '<circle cx="12" cy="12" r="1.35"/>'
      '<circle cx="19" cy="12" r="1.35"/></g>',
  'caret-right': '<path d="m9 5 7 7-7 7"/>',
  'caret-down': '<path d="m5 9 7 7 7-7"/>',
  'caret-up-down': '<path d="m8 8 4-4 4 4m-8 8 4 4 4-4"/>',
  'sidebar-simple': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M9 4v16"/>',
  'trash': '<path d="M4 7h16M9 7V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v3'
      'M6 7l.8 12.1A2 2 0 0 0 8.8 21h6.4a2 2 0 0 0 2-1.9L18 7'
      'M10 11v6M14 11v6"/>',
  'layout': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M3 9h18M9 9v11"/>',
  'puzzle-piece': '<path d="M9 4H5a1 1 0 0 0-1 1v4a3 3 0 1 0 0 6v4'
      'a1 1 0 0 0 1 1h4a3 3 0 1 1 6 0h4a1 1 0 0 0 1-1v-4'
      'a3 3 0 1 0 0-6V5a1 1 0 0 0-1-1h-4a3 3 0 1 0-6 0Z"/>',
  'push-pin': '<path d="M8 3h8l-1 6 3 4v2H6v-2l3-4-1-6ZM12 15v6"/>',
  'gear': '<path d="m10 3-.5 2.2-2 .9-2-.7-2 3.4L5 10.5v3'
      'l-1.5 1.7 2 3.4 2-.7 2 .9.5 2.2h4l.5-2.2 2-.9 2 .7 2-3.4'
      '-1.5-1.7v-3l1.5-1.7-2-3.4-2 .7-2-.9L14 3h-4Z"/>'
      '<circle cx="12" cy="12" r="3"/>',
  'bell': '<path d="M18 8a6 6 0 0 0-12 0v5l-2 4h16l-2-4V8'
      'M9.5 20a2.8 2.8 0 0 0 5 0"/>',
  'file-text': '$_sheet<path d="M8 12h3M8 16h8"/>',
  'folder': '<path d="M3 8V6a2 2 0 0 1 2-2h4.2a2 2 0 0 1 1.5.7L12.8 7H19'
      'a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8Z"/>',
  'folder-open': '<path d="M3 17V6a2 2 0 0 1 2-2h4l3 3h6a2 2 0 0 1 2 2v2'
      'M5 20h13a2 2 0 0 0 1.9-1.4l2-6A1.2 1.2 0 0 0 20.8 11H8'
      'a2 2 0 0 0-1.9 1.4l-2 6A1.2 1.2 0 0 0 5 20Z"/>',
  'table': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M3 9h18M3 14h18M9 9v11"/>',
  'kanban': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M8 8v7M12 8v4M16 8v9"/>',
  'calendar-blank': '<rect x="3" y="5" width="18" height="16" rx="2.5"/>'
      '<path d="M7 3v4M17 3v4M3 10h18M8 14h2M14 14h2M8 17h2"/>',
  'chat-circle': '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5'
      ' 9 9 0 0 1-4-.9L3 21l1.9-5.5a9 9 0 0 1-.9-4A8.5 8.5 0 0 1 21 11.5Z"/>',
  'chart-bar': '<path d="M4 3v16a1 1 0 0 0 1 1h16M9 15v-5M14 15V5'
      'M19 15V8"/>',
  'map-trifold': '<path d="m9 4-6 3v13l6-3 6 3 6-3V4l-6 3-6-3Z'
      'M9 4v13M15 7v13"/>',
  'presentation-chart': '<rect x="3" y="4" width="18" height="13" rx="2"/>'
      '<path d="M12 17v4M8 22l4-2 4 2M7 12l3-3 3 3 4-5"/>',
  'graph': '<path d="M4 5h8M10 12h10M4 19h10M7 3v4M16 10v4M9 17v4"/>',
  'article': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M7 8h10M7 12h10M7 16h6"/>',
  'list-checks': '<path d="m3 6 1.5 1.5L7 4M11 6h10'
      'm-18 6 1.5 1.5L7 10M11 12h10m-18 6 1.5 1.5L7 16M11 18h7"/>',
  'squares-four': '<rect x="3" y="3" width="7" height="7" rx="2"/>'
      '<rect x="14" y="3" width="7" height="7" rx="2"/>'
      '<rect x="3" y="14" width="7" height="7" rx="2"/>'
      '<rect x="14" y="14" width="7" height="7" rx="2"/>',
  'envelope-simple': '<rect x="3" y="5" width="18" height="14" rx="2.5"/>'
      '<path d="m4 7 6.8 5.1a2 2 0 0 0 2.4 0L20 7"/>',
  // Closed cover, bound spine and the curved page edge along the bottom.
  'book-open': '<path d="M7.5 3H18a1.5 1.5 0 0 1 1.5 1.5V21h-12'
      'A2.5 2.5 0 0 1 5 18.5v-13A2.5 2.5 0 0 1 7.5 3Z"/>'
      '<path d="M5 18.5A2.5 2.5 0 0 1 7.5 16h12M9 3v13"/>',
  'images': '<rect x="6" y="3" width="15" height="15" rx="2.5"/>'
      '<path d="M17 18v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9'
      'a2 2 0 0 1 2-2h1m0 7 4-4 4 4 3-3 4 4"/>'
      '<circle cx="16.5" cy="7.5" r="1" fill="currentColor" stroke="none"/>',
  // A repository is a collection of code, not an isolated branch diagram.
  'git-branch': '<path d="M3 8V6a2 2 0 0 1 2-2h4.2a2 2 0 0 1 1.5.7L12.8 7H19'
      'a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8Z"/>'
      '<path d="m9.5 11.5-2.5 2.5 2.5 2.5m5-5 2.5 2.5-2.5 2.5"/>',
  'database': '<ellipse cx="12" cy="5.5" rx="8" ry="3"/>'
      '<path d="M4 5.5v13c0 4 16 4 16 0v-13M4 12c0 4 16 4 16 0"/>',
  'link-simple': '<path d="m10 8 3-3a4.3 4.3 0 0 1 6 6l-3 3'
      'M14 16l-3 3a4.3 4.3 0 0 1-6-6l3-3M8.5 15.5l7-7"/>',
  'file': _sheet,
  'file-pdf': '$_sheet<path d="M8 13h8M8 17h5"/>',
  'file-doc': '$_sheet<path d="M8 12h3M8 15.5h8M8 19h6"/>',
  'file-xls': '$_sheet<rect x="7.5" y="12" width="9" height="6.5" rx="1"/>'
      '<path d="M7.5 15.3h9M12 12v6.5"/>',
  'file-ppt': '$_sheet<rect x="7.5" y="12" width="9" height="5" rx="1"/>'
      '<path d="M12 17v2.5M10 19.5h4"/>',
  'file-zip': '$_sheet<path d="M9 3v3h2v3H9v3h2v3"/>'
      '<rect x="8.5" y="15" width="3" height="4" rx="1"/>',
  'file-code': '$_sheet<path d="m10 12.5-2.5 3 2.5 3m4-6 2.5 3-2.5 3"/>',
  'file-csv': '$_sheet<path d="M8 12h8M8 15.5h8M8 19h8M11 12v7"/>',
  'image': '<rect x="3" y="3" width="18" height="18" rx="3"/>'
      '<path d="m3 16 5-5 5 5 3-3 5 5"/>'
      '<circle cx="15.5" cy="7.5" r="1" fill="currentColor" stroke="none"/>',
  'film-strip': '<rect x="3" y="4" width="18" height="16" rx="2.5"/>'
      '<path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
  'music-note': '<path d="M9 18V6l11-3v12M9 10l11-3"/>'
      '<ellipse cx="6" cy="18" rx="3" ry="2.5"/>'
      '<ellipse cx="17" cy="15" rx="3" ry="2.5"/>',
};
