import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mqtt_suggestions_manager.dart' show MqttSuggestionsManager, TechnicalSuggestion;

/// Page that visualises *technical* suggestions coming from MQTT for the
/// currently‑selected apartment. It relies on the global [MqttSuggestionsManager]
/// registered in **main.dart** with a `ChangeNotifierProvider`.
class TechnicalSuggestionsPage extends StatelessWidget {
  final String username;
  final String? location;

  const TechnicalSuggestionsPage({
    super.key,
    required this.username,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return const Scaffold(
        body: Center(
          child: Text('No apartment selected.', style: TextStyle(color: Colors.red)),
        ),
      );
    }

    final manager = context.watch<MqttSuggestionsManager>();
    final suggestions = manager.allSuggestions
        .where((s) => s.apartmentId == location)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Technical Suggestions for $location – user: $username',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: suggestions.isEmpty
                  ? const Center(child: Text('No technical suggestions received yet.'))
                  : ListView.builder(
                      itemCount: suggestions.length,
                      itemBuilder: (_, i) => _SuggestionCard(suggestions[i], manager),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small Card widget to render each suggestion
// -----------------------------------------------------------------------------
class _SuggestionCard extends StatelessWidget {
  final TechnicalSuggestion suggestion;
  final MqttSuggestionsManager manager;

  const _SuggestionCard(this.suggestion, this.manager);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          '${suggestion.message}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () => manager.removeSuggestion(suggestion),
          icon: const Icon(Icons.check),
          label: const Text('Ack'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
