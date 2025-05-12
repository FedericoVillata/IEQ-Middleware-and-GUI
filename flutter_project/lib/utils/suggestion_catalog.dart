// lib/utils/suggestion_catalog.dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class SuggestionCatalog {
  static final Map<String, Map<String, String>> _localized = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/suggestions_catalog.json');
    final json = jsonDecode(raw);

    for (var item in json['tenant_suggestions']) {
      final id = item['suggestionId'];
      _localized[id] = {
        'en': item['text'] ?? '',
        'it': item['testo'] ?? '',
      };
    }

    _loaded = true;
  }

  static String translate(String id, Locale locale) {
    return _localized[id]?[locale.languageCode] ??
           _localized[id]?['en'] ?? // fallback
           id;
  }
}
