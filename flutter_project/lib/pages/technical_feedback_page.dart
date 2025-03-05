import 'package:flutter/material.dart';

class TechnicalFeedbackPage extends StatefulWidget {
  final String? location;
  const TechnicalFeedbackPage({Key? key, required this.location}) : super(key: key);

  @override
  State<TechnicalFeedbackPage> createState() => _TechnicalFeedbackPageState();
}

class _TechnicalFeedbackPageState extends State<TechnicalFeedbackPage> {
  String selectedFeedback = "Temperature Perception";
  final feedbackTypes = [
    "Temperature Perception",
    "Humidity Perception",
    "Environmental Satisfaction",
    "Service Rating"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Barra per selezione feedback
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: feedbackTypes.map((f) {
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: ElevatedButton(
                    child: Text(f),
                    onPressed: () {
                      setState(() => selectedFeedback = f);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Bar chart placeholder
          Expanded(
            child: Center(
              child: Text(
                "Bar chart for $selectedFeedback at ${widget.location}",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
