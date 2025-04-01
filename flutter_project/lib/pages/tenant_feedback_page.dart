import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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
  int tempRating = 0;
  int humRating = 0;
  int envRating = 0;
  int serviceRating = 0;

  final List<Color> ratingColors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.lightGreen,
    Colors.green,
  ];

  Future<void> _submitFeedback(String category, int rating) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Feedback'),
        content: Text('Do you confirm a "$rating" rating for "$category"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );

    if (confirm != true) return;

    final topic = 'IEQmidAndGUI/${widget.apartmentId}';
    final timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    final parts = category.split(' ');
    final nPart = parts.isNotEmpty ? parts[0] : 'Unknown';
    final uPart = parts.length > 1 ? parts.sublist(1).join(' ') : 'Feedback';

    // ✅ Structured payload with "bn" and "e"
    final payload = jsonEncode({
      'bn': topic,
      'e': [
        {
          'n': '$nPart/Feedback/${widget.username}',
          'u': uPart,
          't': timestamp.toString(),
          'v': rating,
        }
      ]
    });

    final clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    final client = MqttServerClient('mqtt.eclipseprojects.io', clientId);
    client.logging(on: false);
    client.port = 1883;
    client.keepAlivePeriod = 20;
    client.onDisconnected = () => debugPrint('MQTT Disconnected');

    try {
      await client.connect();
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      await Future.delayed(const Duration(seconds: 1));
      client.disconnect();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Feedback sent!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ MQTT error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        title: const Text(
          "Give Your Daily Feedback",
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildRatingSection(
              "Temperature Perception",
              tempRating,
              (rating) => setState(() {
                tempRating = rating;
                _submitFeedback("Temperature Perception", rating);
              }),
              icons: List.filled(5, Icons.device_thermostat),
            ),
            const SizedBox(height: 16),
            _buildRatingSection(
              "Humidity Perception",
              humRating,
              (rating) => setState(() {
                humRating = rating;
                _submitFeedback("Humidity Perception", rating);
              }),
              icons: List.filled(5, Icons.water_drop),
            ),
            const SizedBox(height: 16),
            _buildRatingSection(
              "Environment Satisfaction",
              envRating,
              (rating) => setState(() {
                envRating = rating;
                _submitFeedback("Environment Satisfaction", rating);
              }),
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
              "Service Rating",
              serviceRating,
              (rating) => setState(() {
                serviceRating = rating;
                _submitFeedback("Service Rating", rating);
              }),
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
      ),
    );
  }

  Widget _buildRatingSection(
    String title,
    int rating,
    Function(int) onRatingChanged, {
    required List<IconData> icons,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(icons.length, (index) {
                final iconColor =
                    index < rating ? ratingColors[rating - 1] : Colors.grey;
                return IconButton(
                  iconSize: 30,
                  icon: Icon(icons[index], color: iconColor),
                  onPressed: () => onRatingChanged(index + 1),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
