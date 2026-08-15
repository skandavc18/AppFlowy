import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Who said one line of a conversation held by AppFlowy itself.
enum CustomAIChatRole { user, assistant }

@immutable
class CustomAIChatEntry {
  const CustomAIChatEntry({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.model = '',
  });

  factory CustomAIChatEntry.fromJson(Map<String, dynamic> json) =>
      CustomAIChatEntry(
        id: json['id'] as String? ?? '',
        role: json['role'] == 'assistant'
            ? CustomAIChatRole.assistant
            : CustomAIChatRole.user,
        text: json['text'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['at'] as int? ?? 0,
          isUtc: true,
        ),
        model: json['model'] as String? ?? '',
      );

  final String id;
  final CustomAIChatRole role;
  final String text;
  final DateTime createdAt;
  final String model;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role == CustomAIChatRole.assistant ? 'assistant' : 'user',
        'text': text,
        'at': createdAt.toUtc().millisecondsSinceEpoch,
        if (model.isNotEmpty) 'model': model,
      };
}

/// Where a conversation held with a configured provider is kept.
///
/// The AppFlowy backend stores the chats it answered itself; it knows nothing
/// about a conversation this side streamed from Gemini or a local server, so
/// without this the answers would be gone the moment the page was closed.
class CustomAIChatTranscript {
  const CustomAIChatTranscript._();

  /// A transcript is a conversation, not an archive.
  static const maximumEntries = 400;

  @visibleForTesting
  static Directory? rootOverride;

  static Future<Directory?> _directory({required bool create}) async {
    try {
      final root = rootOverride ?? await getApplicationSupportDirectory();
      final directory = Directory(p.join(root.path, 'ai_provider_chats'));
      if (!directory.existsSync()) {
        if (!create) {
          return null;
        }
        await directory.create(recursive: true);
      }
      return directory;
    } catch (error) {
      Log.warn('Could not open the AI transcript folder: $error');
      return null;
    }
  }

  static Future<File?> _fileFor(String chatId, {bool create = false}) async {
    final directory = await _directory(create: create);
    if (directory == null) {
      return null;
    }
    // A chat id is a uuid, but it is not this file's job to trust that.
    final safe = chatId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    if (safe.isEmpty) {
      return null;
    }
    return File(p.join(directory.path, '$safe.json'));
  }

  static Future<List<CustomAIChatEntry>> read(String chatId) async {
    try {
      final file = await _fileFor(chatId);
      if (file == null || !file.existsSync()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map((entry) => CustomAIChatEntry.fromJson(entry.cast()))
          .where((entry) => entry.id.isNotEmpty)
          .toList();
    } catch (error) {
      Log.warn('Could not read the AI transcript for $chatId: $error');
      return const [];
    }
  }

  static Future<void> write(
    String chatId,
    List<CustomAIChatEntry> entries,
  ) async {
    try {
      final file = await _fileFor(chatId, create: true);
      if (file == null) {
        return;
      }
      final kept = entries.length > maximumEntries
          ? entries.sublist(entries.length - maximumEntries)
          : entries;
      await file.writeAsString(
        jsonEncode(kept.map((entry) => entry.toJson()).toList()),
      );
    } catch (error) {
      Log.warn('Could not save the AI transcript for $chatId: $error');
    }
  }

  static Future<void> upsert(String chatId, CustomAIChatEntry entry) async {
    final entries = List<CustomAIChatEntry>.from(await read(chatId));
    final index = entries.indexWhere((existing) => existing.id == entry.id);
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await write(chatId, entries);
  }

  static Future<void> removeFrom(String chatId, Set<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final entries = await read(chatId);
    await write(
      chatId,
      entries.where((entry) => !ids.contains(entry.id)).toList(),
    );
  }
}
