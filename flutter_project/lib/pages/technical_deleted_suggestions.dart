import 'package:flutter/material.dart';

class TechnicalDeletedSuggestionsPage extends StatelessWidget {
  final String? location;
  const TechnicalDeletedSuggestionsPage({Key? key, required this.location})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Mock: suggerimenti eliminati
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
              "Deleted Tenant Suggestions for $location",
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

  /// Costruisce una Card moderna con titolo e bottone 'Restore'
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
            // Logica per "ripristinare" il suggerimento eliminato
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
