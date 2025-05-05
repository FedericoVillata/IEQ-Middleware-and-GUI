import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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

          latestAlert = alert;
          _alerts.add(alert);
          notifyListeners();
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
    notifyListeners();
  }
  void removeAlert(AlertMessage alert) {
  _alerts.remove(alert);
  notifyListeners();
}

}
