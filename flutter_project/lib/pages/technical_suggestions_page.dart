import 'package:flutter/material.dart';

class TechnicalSuggestionsPage extends StatelessWidget {
  final String? location;
  const TechnicalSuggestionsPage({Key? key, required this.location}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Mock
    final technicalSuggestions = [
      "Weekly check on HVAC calibration",
      "Review threshold for advanced sensors",
      "Investigate persistent high humidity alarms"
    ];
    return Scaffold(
      body: Column(
        children: [
          Text("Weekly Technical Suggestions for $location",
              style: TextStyle(fontSize: 18)),
          Expanded(
            child: ListView.builder(
              itemCount: technicalSuggestions.length,
              itemBuilder: (context, index) {
                final sugg = technicalSuggestions[index];
                return ListTile(
                  title: Text(sugg),
                  // Se vuoi puoi aggiungere un pulsante "ack" 
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
