import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Model for a technical suggestion from MQTT.
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
          timestamp.millisecondsSinceEpoch == other.timestamp.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(apartmentId, roomId, code, message, timestamp.millisecondsSinceEpoch);
}

/// Manager for MQTT technical suggestions.
class MqttSuggestionsManager extends ChangeNotifier {
  final List<TechnicalSuggestion> _all = [];
  List<TechnicalSuggestion> get allSuggestions => List.unmodifiable(_all);

  final List<String> _rawLogs = [];
  List<String> get rawLogs => List.unmodifiable(_rawLogs);

  late MqttServerClient _client;
  bool _initialized = false;
  final Set<String> _subscribedTopics = {};

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

  void _logRawMessage(String topic, String payload) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] $topic\n$payload';
    _rawLogs.insert(0, entry);
    if (_rawLogs.length > 50) _rawLogs.removeLast();
    notifyListeners();
  }

  Future<void> initMqtt({
    required String brokerHost,
    required int brokerPort,
    required String topicBase,
    required List<String> apartmentsToListen,
  }) async {
    if (!_initialized) {
      _initialized = true;

      _client = MqttServerClient(
        brokerHost,
        'techSuggestions_${DateTime.now().millisecondsSinceEpoch}',
      )
        ..port = brokerPort
        ..keepAlivePeriod = 20
        ..logging(on: false)
        ..connectionMessage = MqttConnectMessage()
            .withClientIdentifier('TechSuggestions_${DateTime.now().millisecondsSinceEpoch}')
            .startClean()
            .withWillQos(MqttQos.atLeastOnce);

      _client.onConnected = () => debugPrint('[MQTT] connected');
      _client.onDisconnected = () => debugPrint('[MQTT] disconnected');

      try {
        await _client.connect();
      } catch (e) {
        debugPrint('[MQTT] connection error: $e');
        return;
      }

      if (_client.connectionStatus?.state != MqttConnectionState.connected) {
        debugPrint('[MQTT] failed to connect – state: ${_client.connectionStatus?.state}');
        return;
      }

      _client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
        final rec = messages.first;
        final topic = rec.topic;
        final apartmentId = topic.split('/')[1];
        final msg = rec.payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

        _logRawMessage(topic, payload);

        try {
          final Map<String, dynamic> data = jsonDecode(payload);
          if (data['e'] is List) {
            for (final evt in data['e']) {
              _processEvent(evt, apartmentId);
            }
          }
        } catch (e) {
          debugPrint('[MQTT] parse error: $e');
        }
      });
    }

    for (final aptId in apartmentsToListen) {
      final topic = '$topicBase/$aptId/technical_suggestion';
      if (_subscribedTopics.add(topic)) {
        _client.subscribe(topic, MqttQos.exactlyOnce);
        debugPrint('[MQTT] subscribed to $topic');
      }
    }
  }

  void _processEvent(dynamic evt, String apartmentId) {
    if (evt is! Map<String, dynamic>) return;

    final name = evt['n']?.toString() ?? '';
    final value = evt['v']?.toString() ?? '';

    // NEW: parse any message with roomId/metric format
    final parts = name.split('/');
    if (parts.length == 2) {
      addSuggestion(TechnicalSuggestion(
        apartmentId: apartmentId,
        roomId: parts[0],
        code: parts[1],
        message: value,
      ));
      return;
    }

    // ORIGINAL fallback logic
    if (!name.startsWith('technical_suggestion/')) return;

    final partsTS = name.split('/');
    if (partsTS.length < 3) return;

    addSuggestion(TechnicalSuggestion(
      apartmentId: apartmentId,
      roomId: partsTS[1],
      code: partsTS[2],
      message: value,
    ));
  }
}

