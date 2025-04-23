import 'dart:convert';

import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:flutter/foundation.dart' show debugPrint, ChangeNotifier, kIsWeb;

/// ---------------------------------------------------------------------------
/// Model that represents a single technical suggestion coming through MQTT
/// ---------------------------------------------------------------------------
class TechnicalSuggestion {
  final String apartmentId;
  final String roomId;
  final String code;
  final String message;
  final DateTime timestamp;

  TechnicalSuggestion({
    required this.apartmentId,
    required this.roomId,
    required this.code,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TechnicalSuggestion &&
          runtimeType == other.runtimeType &&
          apartmentId == other.apartmentId &&
          roomId == other.roomId &&
          code == other.code &&
          message == other.message &&
          timestamp.millisecondsSinceEpoch ==
              other.timestamp.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
      apartmentId, roomId, code, message, timestamp.millisecondsSinceEpoch);
}

/// ---------------------------------------------------------------------------
/// `ChangeNotifier` that maintains a live list of suggestions pushed via MQTT.
/// It works **both** on mobile/desktop (raw TCP :1883) and web (WS :80/443).
/// ---------------------------------------------------------------------------
class MqttSuggestionsManager extends ChangeNotifier {
  final List<TechnicalSuggestion> _all = [];
  List<TechnicalSuggestion> get allSuggestions => List.unmodifiable(_all);

  late final MqttClient _client;
  bool _initialised = false;

  /// Avoid duplicate subscriptions
  final Set<String> _subscribedTopics = {};

  // -------------------------------------------------------------------------
  // Public helpers ----------------------------------------------------------
  // -------------------------------------------------------------------------
  void addSuggestion(TechnicalSuggestion s) {
    if (!_all.contains(s)) {
      _all.add(s);
      notifyListeners();
    }
  }

  void removeSuggestion(TechnicalSuggestion s) {
    _all.remove(s);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // MQTT set‑up -------------------------------------------------------------
  // -------------------------------------------------------------------------
  Future<void> initMqtt({
    required String brokerHost,
    required int brokerPort,
    required String topicBase,
    required List<String> apartmentsToListen,
  }) async {
    if (!_initialised) {
      _initialised = true;

      const String clientId =
          'techSuggestions_\${DateTime.now().millisecondsSinceEpoch}';

      // ── Choose the correct client depending on platform ──────────────────
      if (kIsWeb) {
        //   Web → WebSocket transport
        final String scheme = brokerPort == 443 ? 'wss' : 'ws';
        final String url = '$scheme://$brokerHost:$brokerPort/mqtt';

        _client = MqttBrowserClient(url, clientId)
          ..port = brokerPort
          ..websocketProtocols = const <String>['mqtt']
          ..keepAlivePeriod = 20
          ..logging(on: false)
          ..connectionMessage = MqttConnectMessage()
              .withClientIdentifier(clientId)
              .startClean()
              .withWillQos(MqttQos.atLeastOnce);
      } else {
        //   Mobile / Desktop → raw TCP
        _client = MqttServerClient(brokerHost, clientId)
          ..port = brokerPort
          ..keepAlivePeriod = 20
          ..logging(on: false)
          ..connectionMessage = MqttConnectMessage()
              .withClientIdentifier(clientId)
              .startClean()
              .withWillQos(MqttQos.atLeastOnce);
      }

      // Optional logging for troubleshooting
      _client.onConnected = () {
        debugPrint('[MQTT] connected');
      };
      _client.onDisconnected = () {
        debugPrint('[MQTT] disconnected – reason: \${_client.connectionStatus?.reasonCode}');
      };
      _client.onSubscribed = (topic) => debugPrint('[MQTT] subscribed → $topic');

      try {
        await _client.connect();
      } catch (e) {
        debugPrint('[MQTT] connection error → \$e');
        return;
      }

      if (_client.connectionStatus?.state != MqttConnectionState.connected) {
        debugPrint('[MQTT] failed connection – state: \${_client.connectionStatus?.state}');
        debugPrint('[MQTT] ready to subscribe!');
        return;
      }

      // Stream listener -----------------------------------------------------
      _client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
        final rec = messages.first;
        final topic = rec.topic;
        final apartmentId = topic.split('/')[1];
        final msg = rec.payload as MqttPublishMessage;

        final payload =
            MqttPublishPayload.bytesToStringAsString(msg.payload.message);
        debugPrint('[MQTT] raw payload: $payload'); // 👈 METTILO QUI

        try {
          final Map<String, dynamic> data = jsonDecode(payload);
          final List<dynamic>? events = data['e'] as List<dynamic>?;
          if (events == null) return;
          for (final evt in events) {
            _processEvent(evt, apartmentId);
          }
        } catch (e) {
          debugPrint('[MQTT] parse error → $e');
        }
      });
    }

    // (Re)subscribe ---------------------------------------------------------
    for (final apt in apartmentsToListen) {
      final String topic = '$topicBase/$apt/technical_suggestion';
      if (_subscribedTopics.add(topic)) {
        _client.subscribe(topic, MqttQos.exactlyOnce);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Internal helpers --------------------------------------------------------
  // -------------------------------------------------------------------------
    void _processEvent(dynamic evt, String apartmentId) {
    if (evt is! Map<String, dynamic>) return;

    final String name = evt['n']?.toString() ?? '';
    final String value = evt['v']?.toString() ?? '';

    // NEW: allow n like "roomId/suggestionCode"
    final parts = name.split('/');
    if (parts.length != 2) return;

    final String roomId = parts[0];
    final String code = parts[1];

    addSuggestion(TechnicalSuggestion(
      apartmentId: apartmentId,
      roomId: roomId,
      code: code,
      message: value,
    ));
  }
}