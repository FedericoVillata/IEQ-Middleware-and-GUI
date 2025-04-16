import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

import '../app_config.dart';

/// Model to hold each incoming technical suggestion
class TechnicalSuggestion {
  final String roomId;
  final String code;   // e.g. "T3" or "PMV_NEUTRAL_DISCOMFORT"
  final String message;

  TechnicalSuggestion({
    required this.roomId,
    required this.code,
    required this.message,
  });
}

class TechnicalSuggestionsPage extends StatefulWidget {
  final String username;
  final String? location;

  const TechnicalSuggestionsPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalSuggestionsPage> createState() => _TechnicalSuggestionsPageState();
}

class _TechnicalSuggestionsPageState extends State<TechnicalSuggestionsPage> {
  // MQTT client instance
  late MqttServerClient _client;

  // List of all received technical suggestions for this session
  final List<TechnicalSuggestion> _suggestions = [];

  // Used to track our connection state or errors
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initMqtt();
  }

  @override
  void dispose() {
    _disconnectMqtt();
    super.dispose();
  }

  /// Initialize MQTT connection and subscribe to <topicBase>/<apartmentId>.
  Future<void> _initMqtt() async {
    // If location is null, we can't subscribe to anything.
    if (widget.location == null) {
      setState(() {
        _errorMessage = "No apartment selected.";
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final broker = AppConfig.mqttBroker;     // e.g. "mqtt.eclipseprojects.io"
      final port = AppConfig.mqttPort;         // e.g. 1883
      final topicBase = AppConfig.mqttTopicBase; // e.g. "IEQmidAndGUI"
      final apartmentId = widget.location!;

      // Create the MQTT client
      _client = MqttServerClient(broker, 'techSuggestions_${DateTime.now().millisecondsSinceEpoch}');
      _client.port = port;
      _client.logging(on: false); // set to true for extensive debug logs
      _client.keepAlivePeriod = 20;

      // Connection callbacks
      _client.onConnected = _onConnected;
      _client.onDisconnected = _onDisconnected;
      _client.onSubscribed = _onSubscribed;

      // Send a basic connection message
      _client.connectionMessage = mqtt.MqttConnectMessage()
          .withClientIdentifier('TechSuggestionsClient_${DateTime.now().millisecondsSinceEpoch}')
          .startClean()
          .withWillQos(mqtt.MqttQos.atLeastOnce);

      // Attempt to connect (this can throw on failure)
      await _client.connect();

      // Once connected, subscribe to <topicBase>/<apartmentId>
      if (_client.connectionStatus?.state == mqtt.MqttConnectionState.connected) {
        final fullTopic = "$topicBase/$apartmentId";
        _client.subscribe(fullTopic, mqtt.MqttQos.exactlyOnce);

        // Listen to incoming messages
        _client.updates!.listen((List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> c) {
          final recMsg = c[0].payload as mqtt.MqttPublishMessage;
          final payload =
              mqtt.MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);

          // Parse incoming JSON
          try {
            final Map<String, dynamic> data = jsonDecode(payload);
            if (data.containsKey("bn") && data.containsKey("e")) {
              final events = data["e"] as List<dynamic>;
              for (var evt in events) {
                _handleEvent(evt);
              }
            }
          } catch (e) {
            debugPrint("MQTT parse error: $e");
          }
        });
      } else {
        // If we fail to connect or the state is not "connected"
        setState(() {
          _errorMessage = "MQTT connection failed. State: ${_client.connectionStatus?.state}";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "MQTT connection error: $e";
      });
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  /// Handle each individual "event" from the MQTT payload
  void _handleEvent(dynamic evt) {
    // We expect a structure like:
    // {
    //   "n": "technical_suggestion/<roomId>/<key>",
    //   "t": 1681489650.123,
    //   "u": "string",
    //   "v": "Long suggestion text..."
    // }
    if (evt is! Map<String, dynamic>) return;

    final name = evt["n"]?.toString() ?? "";
    final value = evt["v"]?.toString() ?? "";

    // We only care about `technical_suggestion/...`
    if (!name.startsWith("technical_suggestion/")) {
      return; // Not a relevant suggestion
    }

    // Expected format: "technical_suggestion/<roomId>/<code>"
    final parts = name.split("/");
    if (parts.length < 3) {
      return; // Malformed
    }
    final roomId = parts[1];
    final code = parts[2];

    final newItem = TechnicalSuggestion(
      roomId: roomId,
      code: code,
      message: value,
    );

    // Add it to our local list and refresh UI
    setState(() {
      _suggestions.add(newItem);
    });
  }

  /// Gracefully disconnect from MQTT when the widget disposes
  void _disconnectMqtt() {
    try {
      _client.disconnect();
    } catch (_) {
      // Ignore any errors in disconnect
    }
  }

  // --- MQTT lifecycle callbacks ---
  void _onConnected() {
    debugPrint("MQTT Connected!");
  }

  void _onDisconnected() {
    debugPrint("MQTT Disconnected!");
  }

  void _onSubscribed(String topic) {
    debugPrint("MQTT Subscribed to $topic");
  }

  @override
  Widget build(BuildContext context) {
    // If there's an error, show it.
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    // If we're still connecting, show a spinner.
    if (_isConnecting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Otherwise, show the suggestions page UI.
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "Weekly Technical Suggestions for ${widget.location} (user: ${widget.username})",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _suggestions.isEmpty
                  ? const Center(
                      child: Text("No technical suggestions received yet."),
                    )
                  : ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return _buildTechnicalSuggestionCard(suggestion, index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalSuggestionCard(TechnicalSuggestion sugg, int index) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          "[Room: ${sugg.roomId}] ${sugg.message}",
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text("Code: ${sugg.code}"),
        trailing: ElevatedButton.icon(
          onPressed: () {
            // Example: remove from list as acknowledgement
            setState(() {
              _suggestions.removeAt(index);
            });
          },
          icon: const Icon(Icons.check),
          label: const Text("Ack"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
