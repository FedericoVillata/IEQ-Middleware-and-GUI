import 'package:flutter/material.dart';

class SuggestionsPage extends StatelessWidget {
  final List<String> suggestions = [
    "Suggestion 1",
    "Suggestion 2",
    "Suggestion 3",
    "Suggestion 4",
    "Suggestion 5"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Text("Daily Suggestion History", style: TextStyle(color: Colors.black)),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            return _buildSuggestionCard(suggestions[index]);
          },
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(String suggestion) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      child: ListTile(
        title: Text(suggestion, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: Icon(Icons.thumb_down, color: Colors.red), onPressed: () {}),
            IconButton(icon: Icon(Icons.thumb_up, color: Colors.green), onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
