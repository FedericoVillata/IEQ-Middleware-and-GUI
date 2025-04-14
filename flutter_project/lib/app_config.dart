import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class AppConfig {
  static Map<String, dynamic> _settings = {};

  static Future<void> load() async {
    final data = await rootBundle.loadString('assets/flutter_settings.json');
    _settings = json.decode(data);
  }

  static String get registryUrl => _settings["REGISTRY_URL"] as String;
  static String get adaptorUrl => _settings["ADAPTOR_URL"] as String;
  static String get plotServiceUrl => _settings["PLOT_SERVICE_URL"] as String;
}
