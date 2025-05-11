// pages/tenant_feedback_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../app_config.dart';
import '../widgets/suggestions_bell.dart';
import '../feedback_mqtt_publisher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';


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

  Future<void> _submitFeedback(
    String category,
    int rating, {
    required void Function(int) onConfirmed,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmFeedback),
content: Text(
  AppLocalizations.of(context)!
      .confirmFeedbackMessage('$rating', category),
),
actions: [
  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.cancel)),
  TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context)!.confirm)),
],

      ),
    );

    if (confirmed != true || !mounted) return;

    onConfirmed(rating); // Aggiorna stato solo se confermato

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
          SnackBar(
            content: Text(rating == 0
  ? AppLocalizations.of(context)!.feedbackReset
  : AppLocalizations.of(context)!.feedbackSent),

          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
  content: Text(
    AppLocalizations.of(context)!.mqttError('$e'),
  ),
),


        );
      }
    }
  }

  Widget buildRatingSection(
    String title,
    int rating,
    void Function(int) onConfirmedRating, {
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
                final int index = i + 1;

                Color color;
                if (title == 'Temperature Perception' || title == 'Humidity Perception') {
                  if (index == 1 || index == 5) {
                    color = Colors.red;
                  } else if (index == 2 || index == 4) {
                    color = Colors.yellow[700]!;
                  } else {
                    color = Colors.green;
                  }
                } else {
                  color = ratingColors[index - 1];
                }

                final bool selected = index <= rating;

                return IconButton(
                  iconSize: 30,
                  icon: Icon(
                    icons[i],
                    color: color.withOpacity(selected ? 1.0 : 0.3),
                  ),
                  onPressed: () {
                    _submitFeedback(title, index, onConfirmed: onConfirmedRating);

                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true, 
        title: Text(AppLocalizations.of(context)!.giveYourDailyFeedback, style: const TextStyle(color: Colors.black)),
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
        physics: const AlwaysScrollableScrollPhysics(), 
        padding: const EdgeInsets.all(16),
        children: [
          buildRatingSection(
            AppLocalizations.of(context)!.temperaturePerception,
            tempRating,
            (r) => setState(() => tempRating = r),
            icons: List.filled(5, Icons.device_thermostat),
          ),
          const SizedBox(height: 16),
          buildRatingSection(
            AppLocalizations.of(context)!.humidityPerception,
            humRating,
            (r) => setState(() => humRating = r),
            icons: List.filled(5, Icons.water_drop),
          ),
          const SizedBox(height: 16),
          buildRatingSection(
            AppLocalizations.of(context)!.environmentSatisfaction,
            envRating,
            (r) => setState(() => envRating = r),
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
            AppLocalizations.of(context)!.serviceRating,
            serviceRating,
            (r) => setState(() => serviceRating = r),
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

