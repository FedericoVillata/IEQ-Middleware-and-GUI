import 'dart:convert';

import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kIsWeb;

/// ---------------------------------------------------------------------------
///  Model that represents a single *technical* suggestion received via MQTT
/// ---------------------------------------------------------------------------
class TechnicalSuggestion {
  final String apartmentId;
  final String roomId; // can be empty if not provided in the MQTT payload
  final String code;   // unique identifier contained in the SenML `n` field
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
          code == other.code &&
          message == other.message &&
          timestamp.millisecondsSinceEpoch ==
              other.timestamp.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
      apartmentId, code, message, timestamp.millisecondsSinceEpoch);
}

/// ---------------------------------------------------------------------------
/// `ChangeNotifier` that manages the live list of suggestions pushed by MQTT.
///  * Works both on *mobile / desktop* (raw TCP – :1883) and on *web* (WS).
///  * It now prevents duplicates based on the `n` field of the SenML payload.
/// ---------------------------------------------------------------------------
class MqttSuggestionsManager extends ChangeNotifier {
  // ──────────────────────────────────────────────────────────────────────────
  //  Public, read‑only list exposed to the UI
  // ──────────────────────────────────────────────────────────────────────────
  final List<TechnicalSuggestion> _all = [];
  List<TechnicalSuggestion> get allSuggestions => List.unmodifiable(_all);

  // Keys in the form `apartmentId|suggestionCode` currently shown to the user.
  // Used to avoid showing the same code twice until it is *acknowledged*.
  final Set<String> _activeKeys = {};

  // MQTT internals -----------------------------------------------------------
  late final MqttClient _client;
  bool _initialised = false;

  /// Avoid duplicate subscriptions to the same topic.
  final Set<String> _subscribedTopics = {};

  // -------------------------------------------------------------------------
  //  Public helpers (called from the UI) ------------------------------------
  // -------------------------------------------------------------------------
  void addSuggestion(TechnicalSuggestion s) {
    final String key = '${s.apartmentId}|${s.code}';

    //  If the *code* is already active for this apartment, we do nothing.
    if (_activeKeys.contains(key)) return;

    _all.add(s);
    _activeKeys.add(key);
    notifyListeners();
  }

  void removeSuggestion(TechnicalSuggestion s) {
    _all.remove(s);
    _activeKeys.remove('${s.apartmentId}|${s.code}');
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  //  MQTT set‑up -------------------------------------------------------------
  // -------------------------------------------------------------------------
  Future<void> initMqtt({
    required String brokerHost,
    required int brokerPort,
    required String topicBase,
    required List<String> apartmentsToListen,
  }) async {
    if (!_initialised) {
      _initialised = true;

      final String clientId =
          'techSuggestions_${DateTime.now().millisecondsSinceEpoch}';

      // ── Choose the correct client depending on the platform ──────────────
      if (kIsWeb) {
        // → WebSocket transport
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
        // → Native TCP transport
        _client = MqttServerClient(brokerHost, clientId)
          ..port = brokerPort
          ..keepAlivePeriod = 20
          ..logging(on: false)
          ..connectionMessage = MqttConnectMessage()
              .withClientIdentifier(clientId)
              .startClean()
              .withWillQos(MqttQos.atLeastOnce);
      }

      // Optional logging ---------------------------------------------------
      _client.onConnected = () => debugPrint('[MQTT] connected');
      _client.onSubscribed = (topic) => debugPrint('[MQTT] subscribed → $topic');

      try {
        await _client.connect();
      } catch (e) {
        debugPrint('[MQTT] connection error → $e');
        return;
      }

      if (_client.connectionStatus?.state != MqttConnectionState.connected) {
        debugPrint('[MQTT] failed connection – state: ${_client.connectionStatus?.state}');
        return;
      }

      // Stream listener -----------------------------------------------------
      _client.updates?.listen(
        (List<MqttReceivedMessage<MqttMessage>> messages) {
          final rec = messages.first;
          final topic = rec.topic;
          final apartmentId = topic.split('/').elementAtOrNull(1) ?? '';

          final msg = rec.payload as MqttPublishMessage;
          final payload =
              MqttPublishPayload.bytesToStringAsString(msg.payload.message);
          debugPrint('[MQTT] raw payload: $payload');

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
        },
      );
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
  //  Internal helpers --------------------------------------------------------
  // -------------------------------------------------------------------------
  void _processEvent(dynamic evt, String apartmentId) {
    if (evt is! Map<String, dynamic>) return;

    final String name = evt['n']?.toString() ?? '';
    final String value = evt['v']?.toString() ?? '';

    String roomId = '';
    String code = '';

    // Accept both "roomId/suggestionCode" and plain "suggestionCode"
    final parts = name.split('/');
    if (parts.length == 2) {
      roomId = parts[0];
      code = parts[1];
    } else if (parts.length == 1) {
      code = parts[0];
    } else {
      // Unexpected format → skip
      return;
    }

    addSuggestion(
      TechnicalSuggestion(
        apartmentId: apartmentId,
        roomId: roomId,
        code: code,
        message: value,
      ),
    );
  }
}
