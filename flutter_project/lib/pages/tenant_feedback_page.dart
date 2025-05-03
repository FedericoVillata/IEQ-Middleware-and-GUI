// pages/tenant_feedback_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../app_config.dart';
import '../widgets/suggestions_bell.dart';
import '../feedback_mqtt_publisher.dart';


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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm Feedback'),
      content: Text('Do you confirm a "$rating" rating for "$category"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
      ],
    ),
  );

  if (confirmed != true || !mounted) return;

  final topic = 'IEQmidAndGUI/${widget.apartmentId}';
  final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;
  final parts = category.split(' ');
  final nPart = parts.isNotEmpty ? parts.first : 'Unknown';
  final uPart = parts.length > 1 ? parts.sublist(1).join(' ') : 'Feedback';

  final payload = {
    'bn': topic,
    'e': [
      {
        'n': '$nPart/Feedback/${widget.username}/${widget.roomId}',
        'u': uPart,
        't': ts,
        'v': rating,
      }
    ]
  };

  try {
    await FeedbackMqttPublisher.instance.init(
      broker: AppConfig.mqttBroker,
      port: kIsWeb ? 443 : AppConfig.mqttPort,
    );

    await FeedbackMqttPublisher.instance.publish(topic, payload);

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


  // ───────────────────────────────── helper widget
  Widget buildRatingSection(
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
                final color = selected ? ratingColors[rating - 1] : Colors.grey;
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
            username: widget.username,
            apartmentId: widget.apartmentId,
            roomId: widget.roomId,
            isTechnical: false,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildRatingSection(
            'Temperature Perception',
            tempRating,
            (r) {
              setState(() => tempRating = r);
              _submitFeedback('Temperature Perception', r);
            },
            icons: List.filled(5, Icons.device_thermostat),
          ),
          const SizedBox(height: 16),
          buildRatingSection(
            'Humidity Perception',
            humRating,
            (r) {
              setState(() => humRating = r);
              _submitFeedback('Humidity Perception', r);
            },
            icons: List.filled(5, Icons.water_drop),
          ),
          const SizedBox(height: 16),
          buildRatingSection(
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
          buildRatingSection(
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
}
