// pages/location_selection_page.dart
import 'package:flutter/material.dart';

class LocationSelectionPage extends StatefulWidget {
  final Function(String) onLocationSelected;

  const LocationSelectionPage({Key? key, required this.onLocationSelected})
      : super(key: key);

  @override
  State<LocationSelectionPage> createState() => _LocationSelectionPageState();
}

class _LocationSelectionPageState extends State<LocationSelectionPage> {
  final TextEditingController _searchController = TextEditingController();

  // mock di location
  final List<String> allLocations = [
    "Location 1",
    "Location 2",
    "Location 3",
    "Location 4",
    "Aula Magna",
    "Sala Riunioni"
  ];

  String filter = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        filter = _searchController.text;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredLocations = allLocations
        .where((loc) =>
            loc.toLowerCase().contains(filter.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text("Select Location")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: "Search location...",
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredLocations.length,
              itemBuilder: (context, index) {
                final loc = filteredLocations[index];
                return ListTile(
                  title: Text(loc),
                  onTap: () {
                    widget.onLocationSelected(loc);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
