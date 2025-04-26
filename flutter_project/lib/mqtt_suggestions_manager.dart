// lib/mqtt_suggestions_manager.dart
//
// Manages all incoming MQTT suggestions (both technical and tenant) using ChangeNotifier.
// • Deduplicates technical suggestions by apartmentId|code.
// • Supports tolerant parsing of SenML `n` field in formats: "code", "room/code", or "room/.../code".

import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kIsWeb;
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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
///  Model that represents a single *tenant* suggestion received via MQTT
/// ---------------------------------------------------------------------------
class TenantSuggestion {
  final String apartmentId;
  final String roomId;
  final String code;
  final String message;
  final DateTime timestamp;

  TenantSuggestion({
    required this.apartmentId,
    required this.roomId,
    required this.code,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// ---------------------------------------------------------------------------
/// `ChangeNotifier` that manages the live lists of suggestions pushed by MQTT.
///  * Works both on *mobile / desktop* (raw TCP – :1883) and on *web* (WS).
///  * Prevents duplicates of technical suggestions based on apartmentId|code.
///  * Tolerant parsing of SenML `n`: "code", "room/code", or "room/.../code".
/// ---------------------------------------------------------------------------
class MqttSuggestionsManager extends ChangeNotifier {
  // ──────────────────────────────────────────────────────────────────────────
  //  Public, read-only lists exposed to the UI
  // ──────────────────────────────────────────────────────────────────────────
  final List<TechnicalSuggestion> _technical = [];
  final List<TenantSuggestion>     _tenant    = [];

  List<TechnicalSuggestion> get allTechnicalSuggestions =>
      List.unmodifiable(_technical);
  List<TenantSuggestion> get allTenantSuggestions =>
      List.unmodifiable(_tenant);

  // ──────────────────────────────────────────────────────────────────────────
  //  Read/unread tracking & deduplication
  // ──────────────────────────────────────────────────────────────────────────
  final Set<String> _techRead       = {}; // keys = "apt|code"
  final Set<String> _tenRead        = {}; // keys = "apt|room|code"
  final Set<String> _activeTechKeys = {}; // for deduplicating technical

  String _tKey(TenantSuggestion s)   => '${s.apartmentId}|${s.roomId}|${s.code}';
  String _cKey(TechnicalSuggestion s)=> '${s.apartmentId}|${s.code}';

  /// Count unread technical suggestions for a given apartment.
  int unreadTechnicalCount(String apartment) =>
      _technical.where((s) =>
        s.apartmentId == apartment && !_techRead.contains(_cKey(s))
      ).length;

  /// Count unread tenant suggestions for a given apartment and room.
  int unreadTenantCount(String apartment, String room) =>
      _tenant.where((s) =>
        s.apartmentId == apartment &&
        s.roomId      == room &&
        !_tenRead.contains(_tKey(s))
      ).length;

  /// Mark all technical suggestions in an apartment as read.
  void markTechnicalRead(String apartment) {
    for (final s in _technical.where((t) => t.apartmentId == apartment)) {
      _techRead.add(_cKey(s));
    }
    notifyListeners();
  }

  /// Mark all tenant suggestions for apartment+room as read.
  void markTenantRead(String apartment, String room) {
    for (final s in _tenant.where((t) =>
        t.apartmentId == apartment && t.roomId == room)) {
      _tenRead.add(_tKey(s));
    }
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Add / remove suggestions
  // ──────────────────────────────────────────────────────────────────────────
  /// Add a new technical suggestion, ignoring duplicates by key.
  void addTechnicalSuggestion(TechnicalSuggestion suggestion) {
    final key = _cKey(suggestion);
    if (_activeTechKeys.contains(key)) return;
    _technical.add(suggestion);
    _activeTechKeys.add(key);
    _techRead.remove(key); // new → unread
    notifyListeners();
  }

  /// Add a new tenant suggestion.
  void addTenantSuggestion(TenantSuggestion suggestion) {
    _tenant.add(suggestion);
    _tenRead.remove(_tKey(suggestion)); // new → unread
    notifyListeners();
  }

  /// Remove (acknowledge) a technical suggestion.
  void removeTechnicalSuggestion(TechnicalSuggestion suggestion) {
    _technical.remove(suggestion);
    final key = _cKey(suggestion);
    _activeTechKeys.remove(key);
    _techRead.remove(key);
    notifyListeners();
  }

  /// Remove (acknowledge) a tenant suggestion.
  void removeTenantSuggestion(TenantSuggestion suggestion) {
    _tenant.remove(suggestion);
    _tenRead.remove(_tKey(suggestion));
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  MQTT connection & stream handling
  // ──────────────────────────────────────────────────────────────────────────
  late final MqttClient _client;
  bool _initialised = false;
  final Set<String> _subscribedTopics = {};

  /// Initialize MQTT client, connect, and subscribe to topics.
  Future<void> initMqtt({
    required String brokerHost,
    required int brokerPort,
    required String topicBase,
    required List<String> apartmentsToListen,
  }) async {
    if (_initialised) return;
    _initialised = true;

    final clientId = 'suggestions_${DateTime.now().millisecondsSinceEpoch}';

    // Select transport based on platform
    if (kIsWeb) {
      final scheme = brokerPort == 443 ? 'wss' : 'ws';
      _client = MqttBrowserClient('$scheme://$brokerHost:$brokerPort/mqtt', clientId);
    } else {
      _client = MqttServerClient(brokerHost, clientId);
    }

    _client
      ..port = brokerPort
      ..keepAlivePeriod = 20
      ..logging(on: false)
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

    _client.onConnected  = () => debugPrint('[MQTT] connected');
    _client.onSubscribed = (t) => debugPrint('[MQTT] subscribed → $t');

    try {
      await _client.connect();
    } catch (e) {
      debugPrint('[MQTT] connection error → $e');
      return;
    }

    // Listen for publications
    _client.updates?.listen((messages) {
      final rec         = messages.first;
      final topic       = rec.topic;
      final apartmentId = topic.split('/').elementAtOrNull(1) ?? '';
      final payload     = MqttPublishPayload.bytesToStringAsString(
        (rec.payload as MqttPublishMessage).payload.message
      );

      try {
        final data   = jsonDecode(payload) as Map<String, dynamic>;
        final events = data['e'] as List<dynamic>?;
        if (events == null) return;
        final isTech = topic.contains('technical_suggestion');
        for (final evt in events) {
          _processEvent(evt, apartmentId, isTech);
        }
      } catch (e) {
        debugPrint('[MQTT] parse error → $e');
      }
    });

    // Subscribe to each apartment's topics
    for (final apt in apartmentsToListen) {
      final techTopic   = '$topicBase/$apt/technical_suggestion';
      final tenantTopic = '$topicBase/$apt/tenant_suggestion';
      if (_subscribedTopics.add(techTopic)) {
        _client.subscribe(techTopic, MqttQos.exactlyOnce);
      }
      if (_subscribedTopics.add(tenantTopic)) {
        _client.subscribe(tenantTopic, MqttQos.exactlyOnce);
      }
    }
  }

  /// Parse a single SenML event and dispatch to the proper list.
  void _processEvent(dynamic evt, String apartmentId, bool isTech) {
    if (evt is! Map<String, dynamic>) return;

    final name    = evt['n']?.toString() ?? '';
    final message = evt['v']?.toString() ?? '';
    final parts   = name.split('/');

    String room = '';
    String code = '';

    if (parts.length >= 2) {
      room = parts.first;
      code = parts.last;
    } else if (parts.length == 1) {
      code = parts[0];
    } else {
      return; // unexpected format
    }

    if (isTech) {
      addTechnicalSuggestion(TechnicalSuggestion(
        apartmentId: apartmentId,
        roomId: room,
        code: code,
        message: message,
      ));
    } else {
      addTenantSuggestion(TenantSuggestion(
        apartmentId: apartmentId,
        roomId: room,
        code: code,
        message: message,
      ));
    }
  }
}
