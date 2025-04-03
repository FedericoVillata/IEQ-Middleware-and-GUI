import 'package:flutter/material.dart';

class TechnicalSuggestionsPage extends StatelessWidget {
  final String username;
  final String? location;

  const TechnicalSuggestionsPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final technicalSuggestions = [
      "Weekly check on HVAC calibration",
      "Review threshold for advanced sensors",
      "Investigate persistent high humidity alarms"
    ];

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "Weekly Technical Suggestions for $location (user: $username)",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: technicalSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = technicalSuggestions[index];
                  return _buildTechnicalSuggestionCard(suggestion);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalSuggestionCard(String suggestion) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          suggestion,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () {
            // Acknowledge logic
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
