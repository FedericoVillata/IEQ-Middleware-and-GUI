import 'package:flutter/material.dart';

class FeedbackPage extends StatefulWidget {
  @override
  _FeedbackPageState createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int tempRating = 0;
  int humRating = 0;
  int envRating = 0;
  int serviceRating = 0;

  // Definisci una mappa/array di 5 colori, uno per ogni “livello”
  final List<Color> ratingColors = [
    Colors.red,           // rating 1
    Colors.orange,        // rating 2
    Colors.amber,         // rating 3
    Colors.lightGreen,    // rating 4
    Colors.green,         // rating 5
  ];

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
            // Temperature
            _buildRatingSection(
              "Temperature Perception",
              tempRating,
              (rating) => setState(() => tempRating = rating),
              icons: [
                Icons.device_thermostat,
                Icons.device_thermostat,
                Icons.device_thermostat,
                Icons.device_thermostat,
                Icons.device_thermostat,
              ],
            ),
            const SizedBox(height: 16),

            // Humidity
            _buildRatingSection(
              "Humidity Perception",
              humRating,
              (rating) => setState(() => humRating = rating),
              icons: [
                Icons.water_drop,
                Icons.water_drop,
                Icons.water_drop,
                Icons.water_drop,
                Icons.water_drop,
              ],
            ),
            const SizedBox(height: 16),

            // Environment Satisfaction
            _buildRatingSection(
              "Environment Satisfaction",
              envRating,
              (rating) => setState(() => envRating = rating),
              icons: [
                Icons.sentiment_very_dissatisfied,
                Icons.sentiment_dissatisfied,
                Icons.sentiment_neutral,
                Icons.sentiment_satisfied,
                Icons.sentiment_very_satisfied,
              ],
            ),
            const SizedBox(height: 16),

            // Service Rating
            _buildRatingSection(
              "Service Rating",
              serviceRating,
              (rating) => setState(() => serviceRating = rating),
              icons: [
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
                final iconColor = index < rating
                    ? ratingColors[rating - 1] // Colore in base al rating selezionato
                    : Colors.grey;

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
