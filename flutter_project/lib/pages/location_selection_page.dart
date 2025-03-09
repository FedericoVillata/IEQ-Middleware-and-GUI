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

  // Mock di location
  final List<String> allLocations = [
    "Location 1",
    "Location 2",
    "Location 3",
    "Location 4",
    "Aula Magna",
    "Sala Riunioni",
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
    // Filtra la lista delle location in base al testo inserito
    final filteredLocations = allLocations
        .where((loc) => loc.toLowerCase().contains(filter.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Location"),
        centerTitle: true,
      ),
      body: Container(
        // Sfondo più chiaro, se vuoi puoi inserire un gradiente
        color: Colors.grey[200],
        child: Column(
          children: [
            // Barra di ricerca
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: "Search location...",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ),

            // Lista delle location filtrate
            Expanded(
              child: ListView.builder(
                itemCount: filteredLocations.length,
                itemBuilder: (context, index) {
                  final loc = filteredLocations[index];
                  return _buildLocationTile(loc);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Crea una Card per ciascuna location filtrata
  Widget _buildLocationTile(String loc) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          loc,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          widget.onLocationSelected(loc);
        },
      ),
    );
  }
}
