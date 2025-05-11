import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mqtt_suggestions_manager.dart'
    show MqttSuggestionsManager, TechnicalSuggestion;

/// Displays the *technical suggestions* received via MQTT.
///
/// You can instantiate with **apartmentId:** (preferred)
/// or with the legacy **location:** – one is required.
class TechnicalSuggestionsPage extends StatefulWidget {
  final String username;
  final String? apartmentId; // new parameter name
  final String? location;    // legacy alias

  const TechnicalSuggestionsPage({
    super.key,
    required this.username,
    this.apartmentId,
    this.location,
  }) : assert(apartmentId != null || location != null,
          'You must specify apartmentId: or location:');

  @override
  State<TechnicalSuggestionsPage> createState() =>
      _TechnicalSuggestionsPageState();
}

class _TechnicalSuggestionsPageState extends State<TechnicalSuggestionsPage> {
  late final String apt; // chosen apartment

  @override
  void initState() {
    super.initState();
    apt = widget.apartmentId ?? widget.location!;

    // mark all suggestions as read immediately
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MqttSuggestionsManager>().markTechnicalRead(apt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<MqttSuggestionsManager>();

    final suggestions = mgr.allTechnicalSuggestions
        .where((s) => s.apartmentId == apt)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // no back button in embedded view
        title: Text(
          'Technical Suggestions',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: suggestions.isEmpty
          ? const Center(child: Text('No technical suggestions received yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) =>
                  _SuggestionCard(suggestion: suggestions[i], mgr: mgr),
            ),
    );
  }
}

// ───────────────────────────────────────── Card widget ─────────────────────────────────────────
class _SuggestionCard extends StatelessWidget {
  final TechnicalSuggestion suggestion;
  final MqttSuggestionsManager mgr;

  const _SuggestionCard({
    required this.suggestion,
    required this.mgr,
  });

  // formats the timestamp as HH:mm (e.g., 09:30)
  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          suggestion.message,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        subtitle: Text(
          _fmt(suggestion.timestamp),
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () => mgr.removeTechnicalSuggestion(suggestion),
          icon: const Icon(Icons.check),
          label: const Text('Ack'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

