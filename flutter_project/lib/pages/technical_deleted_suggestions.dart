import 'package:flutter/material.dart';

class TechnicalDeletedSuggestionsPage extends StatelessWidget {
  final String? location;
  const TechnicalDeletedSuggestionsPage({Key? key, required this.location}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Mock
    final deletedSuggestions = [
      "Open windows near corridor",
      "Use fan to improve airflow",
      "Lower humidity using dehumidifier"
    ];
    
    return Scaffold(
      body: Column(
        children: [
          Text("Deleted Tenant Suggestions for $location",
              style: TextStyle(fontSize: 18)),
          Expanded(
            child: ListView.builder(
              itemCount: deletedSuggestions.length,
              itemBuilder: (context, index) {
                final suggestion = deletedSuggestions[index];
                return ListTile(
                  title: Text(suggestion),
                  trailing: IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: () {
                      // Logica per "ripristinare" il suggerimento eliminato
                    },
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
