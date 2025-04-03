import 'package:flutter/material.dart';

class TechnicalDeletedSuggestionsPage extends StatelessWidget {
  final String username;
  final String? location;

  const TechnicalDeletedSuggestionsPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Example "deleted suggestions"
    final deletedSuggestions = [
      "Open windows near corridor",
      "Use fan to improve airflow",
      "Lower humidity using dehumidifier"
    ];

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "Deleted Tenant Suggestions for $location (user: $username)",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: deletedSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = deletedSuggestions[index];
                  return _buildDeletedSuggestionCard(suggestion);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedSuggestionCard(String suggestion) {
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
            // Logic to "restore" the deleted suggestion
          },
          icon: const Icon(Icons.refresh),
          label: const Text("Restore"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
