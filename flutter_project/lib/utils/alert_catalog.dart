import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class AlertCatalog {
  static final List<_AlertTemplate> _templates = [];
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/alerts_catalog.json');
    final json = jsonDecode(raw);

    for (var item in json['tenant_alerts']) {
      final pattern = item['pattern'] as String;
      final texts = <String, String>{
  'en': (item['text'] ?? '').toString(),
  'it': (item['testo'] ?? '').toString(),
};

      final variables = _extractVariables(texts['en']!);

      _templates.add(_AlertTemplate(
        id: item['alertId'],
        pattern: RegExp(pattern),
        texts: texts,
        variableNames: variables,
      ));
    }

    _loaded = true;
  }

  static String translate(String message, Locale locale) {
    for (final template in _templates) {
      final match = template.pattern.firstMatch(message);
      if (match != null) {
        String translated = template.texts[locale.languageCode] ?? template.texts['en']!;
        for (int i = 0; i < template.variableNames.length; i++) {
          final placeholder = template.variableNames[i];
          final value = match.group(i + 1) ?? '';
          translated = translated.replaceAll('{$placeholder}', value);
        }
        return translated;
      }
    }
    return message; // fallback se non c'è match
  }

  static List<String> _extractVariables(String text) {
    final matches = RegExp(r'\{(\w+)\}').allMatches(text);
    return matches.map((m) => m.group(1)!).toList();
  }
}

class _AlertTemplate {
  final String id;
  final RegExp pattern;
  final Map<String, String> texts;
  final List<String> variableNames;

  _AlertTemplate({
    required this.id,
    required this.pattern,
    required this.texts,
    required this.variableNames,
  });
}
