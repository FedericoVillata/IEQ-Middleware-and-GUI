// pages/tenant_feedback_page.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

import '../widgets/suggestions_bell.dart';

class FeedbackPage extends StatefulWidget {
  final String username;
  final String apartmentId;
  final String roomId;

  const FeedbackPage({
    super.key,
    required this.username,
    required this.apartmentId,
    required this.roomId,
  });

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int tempRating    = 0;
  int humRating     = 0;
  int envRating     = 0;
  int serviceRating = 0;

  final List<Color> ratingColors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.lightGreen,
    Colors.green,
  ];

  // ───────────────────────────────── MQTT helper
  Future<void> _submitFeedback(String category, int rating) async {
    // 1. Conferma
    final confirmed = await showDialog<bool>(
  context: context,
  builder: (dialogCtx) => AlertDialog(
    title: const Text('Confirm Feedback'),
    content: Text('Do you confirm a "$rating" rating for "$category"?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogCtx, false),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dialogCtx, true), // <-- dialogCtx
        child: const Text('Confirm'),
      ),
    ],
  ),
);
    if (confirmed != true || !mounted) return;

    // 2. Topic & Payload SenML
    final topic     = 'IEQmidAndGUI/${widget.apartmentId}';
    final ts        = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final parts     = category.split(' ');
    final nPart     = parts.isNotEmpty ? parts.first : 'Unknown';
    final uPart     = parts.length > 1 ? parts.sublist(1).join(' ') : 'Feedback';

    final payload = jsonEncode({
      'bn': topic,
      'e' : [
        {
          'n': '$nPart/Feedback/${widget.username}',
          'u': uPart,
          't': ts,            // numerico, non stringa
          'v': rating,
        }
      ]
    });

    // 3. Client WS su Web, TCP su mobile/desktop
    const brokerHost = 'mqtt.eclipseprojects.io';
    const tcpPort    = 1883;
    const wsUrl      = 'wss://mqtt.eclipseprojects.io/mqtt';

    final clientId = 'feedback_${DateTime.now().millisecondsSinceEpoch}';
    late final MqttClient client;

    if (kIsWeb) {
      client = MqttBrowserClient(wsUrl, clientId)
        ..websocketProtocols = const ['mqtt'];
    } else {
      client = MqttServerClient(brokerHost, clientId)..port = tcpPort;
    }

    client
      ..keepAlivePeriod = 20
      ..logging(on: false)
      ..onDisconnected = () => debugPrint('[MQTT] disconnected');

    try {
      await client.connect();
      final builder = MqttClientPayloadBuilder()..addString(payload);
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      await Future.delayed(const Duration(milliseconds: 600));
      client.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Feedback sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ MQTT error: $e')),
        );
      }
    }
  }

  // ───────────────────────────────── build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: const Text('Give Your Daily Feedback', style: TextStyle(color: Colors.black)),
        actions: [
          SuggestionsBell(
            username   : widget.username,
            apartmentId: widget.apartmentId,
            roomId     : widget.roomId,
            isTechnical: false,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRatingSection(
            'Temperature Perception',
            tempRating,
            (r) {
              setState(() => tempRating = r);
              _submitFeedback('Temperature Perception', r);
            },
            icons: List.filled(5, Icons.device_thermostat),
          ),
          const SizedBox(height: 16),
          _buildRatingSection(
            'Humidity Perception',
            humRating,
            (r) {
              setState(() => humRating = r);
              _submitFeedback('Humidity Perception', r);
            },
            icons: List.filled(5, Icons.water_drop),
          ),
          const SizedBox(height: 16),
          _buildRatingSection(
            'Environment Satisfaction',
            envRating,
            (r) {
              setState(() => envRating = r);
              _submitFeedback('Environment Satisfaction', r);
            },
            icons: const [
              Icons.sentiment_very_dissatisfied,
              Icons.sentiment_dissatisfied,
              Icons.sentiment_neutral,
              Icons.sentiment_satisfied,
              Icons.sentiment_very_satisfied,
            ],
          ),
          const SizedBox(height: 16),
          _buildRatingSection(
            'Service Rating',
            serviceRating,
            (r) {
              setState(() => serviceRating = r);
              _submitFeedback('Service Rating', r);
            },
            icons: const [
              Icons.thumb_down,
              Icons.thumb_down_alt,
              Icons.thumbs_up_down,
              Icons.thumb_up_alt,
              Icons.thumb_up,
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────── helper widget
  Widget _buildRatingSection(
    String title,
    int rating,
    ValueChanged<int> onRatingChanged, {
    required List<IconData> icons,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(icons.length, (i) {
                final selected = i < rating;
                final color    = selected ? ratingColors[rating - 1] : Colors.grey;
                return IconButton(
                  iconSize: 30,
                  icon: Icon(icons[i], color: color),
                  onPressed: () => onRatingChanged(i + 1),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
