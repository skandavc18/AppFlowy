import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:nanoid/nanoid.dart';

/// A named way of working that the assistant can be told to follow.
///
/// A skill is instructions, not code: it says how to do something well and
/// which tools it should reach for. Built-in skills ship with AppFlowy; anybody
/// can write more.
@immutable
class AISkill {
  const AISkill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    this.keywords = const [],
    this.enabled = true,
    this.isBuiltIn = false,
  });

  factory AISkill.fromJson(Map<String, dynamic> json) => AISkill(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        keywords: (json['keywords'] as List?)?.whereType<String>().toList() ??
            const [],
        enabled: json['enabled'] != false,
        isBuiltIn: json['built_in'] == true,
      );

  final String id;
  final String name;
  final String description;

  /// What the assistant is told to do when this skill applies.
  final String instructions;

  /// Words that suggest this skill is wanted. Empty means always offered.
  final List<String> keywords;

  final bool enabled;
  final bool isBuiltIn;

  bool matches(String request) {
    if (keywords.isEmpty) {
      return true;
    }
    final text = request.toLowerCase();
    return keywords.any((word) => text.contains(word.toLowerCase()));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'instructions': instructions,
        if (keywords.isNotEmpty) 'keywords': keywords,
        if (!enabled) 'enabled': false,
        if (isBuiltIn) 'built_in': true,
      };

  AISkill copyWith({
    String? id,
    String? name,
    String? description,
    String? instructions,
    List<String>? keywords,
    bool? enabled,
  }) =>
      AISkill(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        instructions: instructions ?? this.instructions,
        keywords: keywords ?? this.keywords,
        enabled: enabled ?? this.enabled,
        isBuiltIn: isBuiltIn,
      );
}

/// The skills AppFlowy ships with.
///
/// Each one is a short piece of craft knowledge about this application: which
/// tool to reach for, and what a good answer looks like.
const List<AISkill> builtInSkills = [
  AISkill(
    id: 'builtin_write_page',
    name: 'Write a page',
    description: 'Draft or extend a page in the workspace.',
    isBuiltIn: true,
    keywords: ['write', 'draft', 'note', 'page', 'document', 'summar'],
    instructions: '''
When asked to write something down:
- Put it in the workspace with create_page rather than only answering in chat.
- Write the body in Markdown: a short title line, then headings and lists.
- Ask where it should live only if it matters; otherwise create it at the top
  level and say where it went.
- To extend something that already exists, read_page first so you do not repeat
  what is already there, then append_to_page.''',
  ),
  AISkill(
    id: 'builtin_build_table',
    name: 'Build a table',
    description: 'Create a table with the right columns and fill it in.',
    isBuiltIn: true,
    keywords: ['table', 'database', 'track', 'list of', 'spreadsheet', 'grid'],
    instructions: '''
When asked to track something:
- create_table, then add_column for each column BEFORE adding rows.
- Choose column types deliberately: dates as date, amounts as number, states as
  select, done/not done as checkbox.
- The first column is the title; do not add another column for the name.
- Add the rows with add_row, giving cells keyed by column name.
- Every row also has a PAGE of its own for anything that does not fit in a
  cell. Write it with write_row_page and read it with read_row_page; describe_table
  gives you the row ids. The page is made the first time you write in it, so a
  row that has never been written in is not an error.
- Finish by saying how many columns and rows were created.''',
  ),
  AISkill(
    id: 'builtin_organise',
    name: 'Organise the workspace',
    description: 'Find, rename, move and tidy pages and folders.',
    isBuiltIn: true,
    keywords: [
      'organis',
      'organiz',
      'tidy',
      'move',
      'rename',
      'folder',
      'sort'
    ],
    instructions: '''
When tidying up:
- list_pages first and work from the ids it gives you; never guess an id.
- Say what you are about to move or rename before doing it.
- Prefer moving things to deleting them. If something really should go, delete
  it one item at a time so each is asked about separately.''',
  ),
  AISkill(
    id: 'builtin_report',
    name: 'Report on a table',
    description: 'Read a table and write up what it says.',
    isBuiltIn: true,
    keywords: ['report', 'analys', 'analyz', 'chart', 'dashboard', 'summar'],
    instructions: '''
When asked what a table says:
- describe_table first, and quote real figures from it rather than estimating.
- For a picture of the numbers, create_table_view with kind "chart"; for
  several readings at once, create_dashboard.
- Write the findings into a page so they can be kept.''',
  ),
  AISkill(
    id: 'builtin_page_contents',
    name: 'Build a page out of blocks',
    description: 'Add, change, move and remove the blocks inside a page.',
    isBuiltIn: true,
    keywords: [
      'block',
      'image',
      'picture',
      'photo',
      'video',
      'code',
      'diagram',
      'mermaid',
      'mind map',
      'drawing',
      'embed',
      'callout',
      'heading',
      'bullet',
      'align',
      'format',
      'reorder',
      'move',
    ],
    instructions: '''
Everything inside a page is a block, so one set of tools covers all of it:
- list_blocks FIRST. It gives the block ids that every other call needs, and
  shows you what is already there.
- insert_block adds anything: a heading, a picture, a code block, a mind map, a
  drawing, an embedded page or table, a chart, a bookmark. Give it the type and
  whatever that type needs — a url for a picture, a language for code, a view_id
  for an embed.
- update_block changes words, type and layout: use it to turn a paragraph into
  a heading, align text, tick a to-do, or point an embed somewhere else.
- move_block reorders; delete_block removes.
- When adding several blocks of prose at once, append_to_page with Markdown is
  quicker than one insert_block each.''',
  ),
  AISkill(
    id: 'builtin_careful_changes',
    name: 'Change things carefully',
    description: 'How to behave when a request would alter or remove work.',
    isBuiltIn: true,
    instructions: '''
Before anything is changed or removed:
- Read first. Never delete something you have not looked at.
- Do one thing at a time so each can be judged on its own.
- Never delete something that was not asked about, however tidy it would be.
- If a call is refused, stop and say what you were trying to do. Do not look for
  another way round it.''',
  ),
];

/// Every skill, built in and written by hand.
class AISkillStore extends ChangeNotifier {
  AISkillStore({KeyValueStorage? storage}) : _storage = storage;

  static final AISkillStore instance = AISkillStore();

  static const skillsKey = 'appflowy_ai_skills';
  static const disabledKey = 'appflowy_ai_skills_disabled';

  final KeyValueStorage? _storage;
  final List<AISkill> _custom = [];
  final Set<String> _disabled = {};
  Future<void>? _loading;
  bool _loaded = false;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  /// Built-in skills first, then the person's own.
  List<AISkill> get skills => List.unmodifiable([
        for (final skill in builtInSkills)
          skill.copyWith(enabled: !_disabled.contains(skill.id)),
        ..._custom,
      ]);

  List<AISkill> get enabledSkills =>
      skills.where((skill) => skill.enabled).toList();

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _kv?.get(skillsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final skill = AISkill.fromJson(entry.cast());
            if (skill.id.isNotEmpty &&
                !_custom.any((existing) => existing.id == skill.id)) {
              _custom.add(skill);
            }
          }
        }
      }
      final off = await _kv?.get(disabledKey);
      if (off != null && off.isNotEmpty) {
        final decoded = jsonDecode(off);
        if (decoded is List) {
          _disabled.addAll(decoded.whereType<String>());
        }
      }
    } catch (error) {
      Log.warn('Could not read the AI skills: $error');
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  Future<AISkill> upsert(AISkill skill) async {
    await ensureLoaded();
    final resolved =
        skill.id.isEmpty ? skill.copyWith(id: 'skill_${nanoid(8)}') : skill;
    final index = _custom.indexWhere((entry) => entry.id == resolved.id);
    if (index == -1) {
      _custom.add(resolved);
    } else {
      _custom[index] = resolved;
    }
    await _persist();
    notifyListeners();
    return resolved;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _custom.removeWhere((skill) => skill.id == id);
    _disabled.remove(id);
    await _persist();
    notifyListeners();
  }

  Future<void> setEnabled(AISkill skill, bool enabled) async {
    await ensureLoaded();
    if (skill.isBuiltIn) {
      if (enabled) {
        _disabled.remove(skill.id);
      } else {
        _disabled.add(skill.id);
      }
    } else {
      final index = _custom.indexWhere((entry) => entry.id == skill.id);
      if (index != -1) {
        _custom[index] = _custom[index].copyWith(enabled: enabled);
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _kv?.set(
      skillsKey,
      jsonEncode(_custom.map((skill) => skill.toJson()).toList()),
    );
    await _kv?.set(disabledKey, jsonEncode(_disabled.toList()));
  }

  /// The instructions to put in front of the assistant for [request].
  ///
  /// A skill with no keywords always applies; one with keywords only joins in
  /// when the request sounds like its subject, so a long list of skills does not
  /// crowd out the actual question.
  String instructionsFor(String request) {
    final chosen = enabledSkills.where((skill) => skill.matches(request));
    if (chosen.isEmpty) {
      return '';
    }
    return chosen
        .map((skill) => '## ${skill.name}\n${skill.instructions.trim()}')
        .join('\n\n');
  }
}
