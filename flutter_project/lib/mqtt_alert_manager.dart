import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:http/http.dart' as http;



class AlertMessage {
  final String apartmentId;
  final String roomId;
  final String message;
  final DateTime timestamp;

  AlertMessage({
    required this.apartmentId,
    required this.roomId,
    required this.message,
    required this.timestamp,
  });
}

class MqttAlertManager extends ChangeNotifier {
  final List<AlertMessage> _alerts = [];

  List<AlertMessage> get allAlerts => List.unmodifiable(_alerts);
  AlertMessage? latestAlert;

  late final MqttClient _client;
  bool _initialized = false;
  final Set<String> _subscribed = {};

  bool _isDisposed = false;

@override
void dispose() {
  _isDisposed = true;
  super.dispose();
}

void _safeNotifyListeners() {
  if (!_isDisposed) {
    notifyListeners();
  }
}


  Future<void> syncFromRest(String restUrl, List<String> apartments) async {
  try {
    final res = await http.get(Uri.parse(restUrl));
    if (res.statusCode != 200) {
      debugPrint('[ALERT REST] Unexpected status ${res.statusCode}');
      return;
    }

    if (res.body.trim().isEmpty) {
      debugPrint('[ALERT REST] Empty response body');
      return;
    }

    final Map<String, dynamic> json = jsonDecode(res.body);

    for (final apt in apartments) {
      final aptData = json[apt];
      if (aptData == null || aptData['alerts'] == null) continue;

      final alertsMap = Map<String, dynamic>.from(aptData['alerts']);

      for (final entry in alertsMap.entries) {
        final roomId = entry.key;
        final alerts = entry.value as List<dynamic>;

        for (final a in alerts) {
          final msg   = a['text']?.toString() ?? '';
          final tsSec = (a['ts'] ?? 0).toDouble();

          final alert = AlertMessage(
            apartmentId: apt,
            roomId: roomId,
            message: msg,
            timestamp: DateTime.fromMillisecondsSinceEpoch((tsSec * 1000).round()),
          );

          final normalized = _normalizeMessage(alert.message);
final existingIndex = _alerts.indexWhere((x) =>
  x.apartmentId == alert.apartmentId &&
  x.roomId == alert.roomId &&
  _normalizeMessage(x.message) == normalized,
);

if (existingIndex != -1) {
  _alerts[existingIndex] = alert;
} else {
  _alerts.add(alert);
}

        }
      }
    }

    _safeNotifyListeners();

    debugPrint('[ALERT REST] Bootstrap completed with ${_alerts.length} items');
  } catch (e) {
    debugPrint('[ALERT REST] Error while fetching initial alerts → $e');
  }
}



  Future<void> init({
    required String broker,
    required int port,
    required String topicBase,
    required List<String> apartments,
  }) async {
    if (_initialized) return;
    _initialized = true;

    final clientId = 'alert_${DateTime.now().millisecondsSinceEpoch}';

    if (kIsWeb) {
      final scheme = port == 443 ? 'wss' : 'ws';
      _client = MqttBrowserClient('$scheme://$broker:$port/mqtt', clientId);
    } else {
      _client = MqttServerClient(broker, clientId);
    }

    _client
      ..port = port
      ..logging(on: false)
      ..keepAlivePeriod = 20
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

    try {
      await _client.connect();
    } catch (e) {
      debugPrint('[MQTT ALERT] connection failed: $e');
      return;
    }

    _client.updates?.listen((events) {
      if (events.isEmpty) return;
      final rec = events.first;
      final topic = rec.topic;
      final payloadStr = MqttPublishPayload.bytesToStringAsString(
        (rec.payload as MqttPublishMessage).payload.message,
      );

      final aptId = topic.split('/').elementAtOrNull(1) ?? '';
      try {
        final json = jsonDecode(payloadStr) as Map<String, dynamic>;
        final eList = json['e'] as List<dynamic>;
        for (final e in eList) {
          final roomId = e['n']?.toString() ?? '';
          final msg  = e['v']?.toString() ?? '';
          final ts   = DateTime.now(); // or use `e['t']` if desired

          final alert = AlertMessage(
  apartmentId: aptId,
  roomId: roomId,
  message: msg,
  timestamp: ts,
);

// ✅ evita duplicati identici (apt + room + message)
final normalized = _normalizeMessage(alert.message);
final existingIndex = _alerts.indexWhere((a) =>
  a.apartmentId == alert.apartmentId &&
  a.roomId == alert.roomId &&
  _normalizeMessage(a.message) == normalized,
);

if (existingIndex != -1) {
  _alerts[existingIndex] = alert; // aggiornamento (sovrascrive timestamp e messaggio)
} else {
  latestAlert = alert;
  _alerts.add(alert);
}
_safeNotifyListeners();



        }
      } catch (e) {
        debugPrint('[MQTT ALERT] parse error: $e');
      }
    });

    for (final apt in apartments) {
    final topic = '$topicBase/$apt/alert';
    if (_subscribed.add(topic)) {
      _client.subscribe(topic, MqttQos.atLeastOnce);
      debugPrint('[MQTT] subscribed → $topic');
    }
  }

  }

  void clearLatestAlert() {
    latestAlert = null;
    _safeNotifyListeners();

  }
  void removeAlert(AlertMessage alert) {
  _alerts.remove(alert);
  _safeNotifyListeners();

}
String _normalizeMessage(String message) {
  return message
      // Rende omogenee tutte le liste di sensori "No X, Y, Z data received for NN h"
      .replaceAll(
        RegExp(r'No ((?:Temperature|Humidity|Pressure|CO2|VOC|PM10)(?:, )?)+data received for \d+h(?: \d+min)?'),
        'Missing sensor data received recently',
      )

      // Rimuove messaggi singoli come "VOC data received for 34h 8min"
      .replaceAll(
        RegExp(r'(?:Temperature|Humidity|Pressure|CO2|VOC|PM10) data received for \d+h(?: \d+min)?'),
        'Sensor data delay',
      )

      // Rende omogenee le mac address
      .replaceAll(RegExp(r'\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b'), '[DEVICE]')

      // Rimuove spazi multipli
      .replaceAll(RegExp(r'\s+'), ' ')

      .trim();
}


}
