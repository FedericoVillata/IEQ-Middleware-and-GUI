import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class FeedbackMqttPublisher {
  static final FeedbackMqttPublisher _instance = FeedbackMqttPublisher._();
  late final MqttClient _client;
  bool _connected = false;

  FeedbackMqttPublisher._();

  static FeedbackMqttPublisher get instance => _instance;

  Future<void> init({required String broker, required int port}) async {
    if (_connected) return;

    final clientId = 'feedback_pub_${DateTime.now().millisecondsSinceEpoch}';
    if (kIsWeb) {
  _client = MqttBrowserClient('wss://$broker:$port/mqtt', clientId)
    ..websocketProtocols = const ['mqtt'];
} else {
  _client = MqttServerClient(broker, clientId);
}

// Ora è sicuro usare:
_client
  ..port = port
  ..logging(on: true)
  ..keepAlivePeriod = 20
  ..connectionMessage = MqttConnectMessage()
      .withClientIdentifier(clientId)
      .startClean()
      .withWillQos(MqttQos.atLeastOnce);


    try {
      await _client.connect();
      if (_client.connectionStatus?.state == MqttConnectionState.connected) {
        _connected = true;
      } else {
        throw Exception('Connection failed');
      }
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  Future<void> publish(String topic, Map<String, dynamic> json) async {
    if (!_connected) return;

    final payloadStr = jsonEncode(json);
    final builder = MqttClientPayloadBuilder()..addString(payloadStr);

    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void disconnect() {
    _client.disconnect();
    _connected = false;
  }
}
