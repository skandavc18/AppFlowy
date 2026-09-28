import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Load the actual English source before widget fake time starts. Generated
/// assets intentionally need not have been synced for this repair's fixtures.
class BookmarkReaderTestLocalizations extends AssetLoader {
  const BookmarkReaderTestLocalizations();

  static late Map<String, dynamic> translations;

  static Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    translations = jsonDecode(await File(
      '../resources/translations/en-US.json',
    ).readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(translations);

  static Widget wrap({required Widget home, ThemeData? theme}) =>
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        startLocale: const Locale('en', 'US'),
        fallbackLocale: const Locale('en', 'US'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const BookmarkReaderTestLocalizations(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: home,
          ),
        ),
      );
}
