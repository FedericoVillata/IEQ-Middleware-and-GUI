import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Simple model representing a technical suggestion.
class TechnicalSuggestion {
  final String roomId;
  final String code;    // e.g., "T3" or "PMV_COLD_WARM_PERCEPTION"
  final String message; // The suggestion text
  final DateTime timestamp;

  TechnicalSuggestion({
    required this.roomId,
    required this.code,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class MqttSuggestionsManager extends ChangeNotifier {
  // Internal list of all suggestions received.
  final List<TechnicalSuggestion> _allSuggestions = [];
  // Public, read-only access to the suggestions.
  List<TechnicalSuggestion> get allSuggestions => List.unmodifiable(_allSuggestions);

  late MqttServerClient _client;
  bool _initialized = false;

  /// Call this once (e.g. in main.dart) to connect to MQTT and subscribe.
  Future<void> initMqtt({
    required String brokerHost,
    required int brokerPort,
    required String topicBase,
    required List<String> apartmentsToListen,
  }) async {
    // If we've already initialized, don't re-init.
    if (_initialized) return;
    _initialized = true;

    _client = MqttServerClient(brokerHost, 'techSuggestions_${DateTime.now().millisecondsSinceEpoch}');
    _client.port = brokerPort;
    _client.logging(on: false);
    _client.keepAlivePeriod = 20;

    // Optional: set up a connect message
    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('TechSuggestions_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;

    // Attempt connecting
    try {
      await _client.connect();
    } catch (e) {
      debugPrint("MQTT connect error: $e");
      return;
    }

    // If successfully connected, subscribe to relevant topics
    if (_client.connectionStatus?.state == MqttConnectionState.connected) {
      for (final aptId in apartmentsToListen) {
        final fullTopic = "$topicBase/$aptId";
        debugPrint("Subscribing to $fullTopic ...");
        _client.subscribe(fullTopic, MqttQos.exactlyOnce);
      }

      // Listen for incoming updates
      _client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMsg = c[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);

        try {
          final Map<String, dynamic> data = jsonDecode(payload);
          if (data.containsKey("e")) {
            for (var evt in data["e"]) {
              _processEvent(evt);
            }
          }
        } catch (e) {
          debugPrint("MQTT parse error: $e");
        }
      });
    } else {
      debugPrint("MQTT not connected. Status: ${_client.connectionStatus}");
    }
  }

  void _onConnected() {
    debugPrint("MQTT connected");
  }

  void _onDisconnected() {
    debugPrint("MQTT disconnected");
  }

  void _processEvent(dynamic evt) {
    // We expect structure: { "n": "technical_suggestion/<roomId>/<code>", "v": "text..." }
    if (evt is! Map<String, dynamic>) return;

    final name = evt["n"]?.toString() ?? "";
    final value = evt["v"]?.toString() ?? "";

    // Check if it's a technical suggestion
    if (!name.startsWith("technical_suggestion/")) return;

    // "technical_suggestion/roomId/code"
    final parts = name.split("/");
    if (parts.length < 3) return;

    final roomId = parts[1];
    final code = parts[2];

    // Create and store the suggestion
    final newItem = TechnicalSuggestion(
      roomId: roomId,
      code: code,
      message: value,
    );
    _allSuggestions.add(newItem);

    notifyListeners();
  }
}
