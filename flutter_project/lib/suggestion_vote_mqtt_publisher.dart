import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class SuggestionVoteMqttPublisher {
  static final SuggestionVoteMqttPublisher _instance = SuggestionVoteMqttPublisher._();
  late final MqttClient _client;
  bool _connected = false;

  SuggestionVoteMqttPublisher._();

  static SuggestionVoteMqttPublisher get instance => _instance;

  Future<void> init({required String broker, required int port}) async {
    if (_connected) return;

    final clientId = 'vote_pub_${DateTime.now().millisecondsSinceEpoch}';
    if (kIsWeb) {
      _client = MqttBrowserClient('wss://$broker:$port/mqtt', clientId)
        ..websocketProtocols = const ['mqtt'];
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

  Future<void> publishVote({
    required String apartmentId,
    required String suggestionId,
    required String roomId,
    required String username,
    required int score,
  }) async {
    if (!_connected) return;

    final topic = 'IEQmidAndGUI/$apartmentId/tenant_suggestion_votes';
    final payload = {
      'bn': topic,
      'e': [
        {
          'n': 'score/tenant_suggestion_votes/${suggestionId}_$roomId\_$username',
          't': DateTime.now().millisecondsSinceEpoch / 1000.0,
          'u': 'score',
          'v': score > 0 ? '+1' : '-1',
        }
      ]
    };

    final payloadStr = jsonEncode(payload);
    final builder = MqttClientPayloadBuilder()..addString(payloadStr);

    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void disconnect() {
    _client.disconnect();
    _connected = false;
  }
}

