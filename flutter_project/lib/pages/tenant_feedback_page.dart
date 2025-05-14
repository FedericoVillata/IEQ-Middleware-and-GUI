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

  late List<String?> temperatureLabels;
late List<String?> humidityLabels;

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final loc = AppLocalizations.of(context)!;
  
  temperatureLabels = [
    loc.tooCold,
    null,
    null,
    null,
    loc.tooHot,
  ];

  humidityLabels = [
    loc.tooDry,
    null,
    null,
    null,
    loc.tooHumid,
  ];
}





  final List<IconData> tempIcons = [
  Icons.device_thermostat, // freddo
  Icons.device_thermostat, 
  Icons.device_thermostat,
  Icons.device_thermostat,
  Icons.device_thermostat, // caldo
];

final List<IconData> humidityIcons = [
  Icons.water_drop_outlined,   // troppo secco
  Icons.water_drop,            // secco
  Icons.water_drop,            // confortevole
  Icons.water_drop,            // umido
  Icons.water_drop,            // troppo umido
];

final List<double> humiditySizes = [18.0, 24.0, 30.0, 36.0, 42.0];



  static const Map<String, String> categoryKeys = {
  'temperaturePerception': 'Temperature Perception',
  'humidityPerception': 'Humidity Perception',
  'environmentSatisfaction': 'Environment Satisfaction',
  'serviceRating': 'Service Rating',
};


  Future<void> _submitFeedback(
  String categoryKey,
  int rating, {
  required void Function(int) onConfirmed,
}) async {
  final loc = AppLocalizations.of(context)!;
  final displayText = {
    'temperaturePerception': loc.temperaturePerception,
    'humidityPerception': loc.humidityPerception,
    'environmentSatisfaction': loc.environmentSatisfaction,
    'serviceRating': loc.serviceRating,
  }[categoryKey] ?? categoryKey;

  final englishCategory = categoryKeys[categoryKey] ?? categoryKey;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.confirmFeedback),
      content: Text(loc.confirmFeedbackMessage('$rating', displayText)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.confirm)),
      ],
    ),
  );

  if (confirmed != true || !mounted) return;

  onConfirmed(rating);

  final topic = 'IEQmidAndGUI/${widget.apartmentId}';
  final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;
  final parts = englishCategory.split(' ');
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
          content: Text(
            rating == 0 ? loc.feedbackReset : loc.feedbackSent,
          ),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.mqttError('$e')),
        ),
      );
    }
  }
}


 Widget buildRatingSection(
  String categoryKey,
  int rating,
  void Function(int) onConfirmedRating, {
  required List<IconData> icons,
}) {
  final loc = AppLocalizations.of(context)!;
  final title = {
    'temperaturePerception': loc.temperaturePerception,
    'humidityPerception': loc.humidityPerception,
    'environmentSatisfaction': loc.environmentSatisfaction,
    'serviceRating': loc.serviceRating,
  }[categoryKey]!;

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
if (categoryKey == 'temperaturePerception') {
  color = [
    Colors.blue[700],
    Colors.lightBlue,
    Colors.green,
    Colors.orange,
    Colors.red[700],
  ][i]!;
} else if (categoryKey == 'humidityPerception') {
  color = [
    Colors.blueGrey[200],
    Colors.lightBlue[300],
    Colors.green,
    Colors.blue[600],
    Colors.indigo[700],
  ][i]!;
} else {
  color = ratingColors[i];
}


              final bool selected = index <= rating;

              return Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      iconSize: 30,
      icon: Icon(
        icons[i],
        size: categoryKey == 'humidityPerception' ? humiditySizes[i] : 30.0,
        color: color.withOpacity(selected ? 1.0 : 0.3),
      ),
      onPressed: () {
        _submitFeedback(categoryKey, index, onConfirmed: onConfirmedRating);
      },
    ),
  if (categoryKey == 'humidityPerception')
  Text(
    humidityLabels[i] ?? '',
    style: const TextStyle(fontSize: 10),
  ),

if (categoryKey == 'temperaturePerception')
  Text(
    temperatureLabels[i] ?? '',
    style: const TextStyle(fontSize: 10),
  ),




  ],
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
            'temperaturePerception',
            tempRating,
            (r) => setState(() => tempRating = r),
            icons: tempIcons,
          ),
          const SizedBox(height: 16),
          buildRatingSection(
            'humidityPerception',
            humRating,
            (r) => setState(() => humRating = r),
            icons: humidityIcons,
          ),
          const SizedBox(height: 16),
          buildRatingSection(
            'environmentSatisfaction',
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
            'serviceRating',
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


