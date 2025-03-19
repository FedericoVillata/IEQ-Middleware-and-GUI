import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LocationSelectionPage extends StatefulWidget {
  final Function(String) onLocationSelected;

  const LocationSelectionPage({Key? key, required this.onLocationSelected})
      : super(key: key);

  @override
  State<LocationSelectionPage> createState() => _LocationSelectionPageState();
}

class _LocationSelectionPageState extends State<LocationSelectionPage> {
  static const String REGISTRY_URL = "http://localhost:8081/apartments";

  final TextEditingController _searchController = TextEditingController();

  // Questa sarà la lista che popoliamo via GET dal registry
  List<String> allLocations = [];
  String filter = "";

  // Aggiungiamo una variabile di stato per indicare se stiamo caricando o se c’è stato un errore
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    // Avviamo il caricamento delle location da registry
    _fetchLocationsFromRegistry();

    _searchController.addListener(() {
      setState(() {
        filter = _searchController.text;
      });
    });
  }

  /// Effettua la GET al registry e aggiorna `allLocations` con gli apartmentId
  Future<void> _fetchLocationsFromRegistry() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(REGISTRY_URL));

      if (response.statusCode == 200) {
        // Il registry risponde con una lista di oggetti JSON
        // Ciascun oggetto dovrebbe avere "apartmentId": es. { "apartmentId": "apartment0", ... }
        final List<dynamic> data = json.decode(response.body);

        // Estraiamo la lista di id
        final List<String> apartments = data
            .map((apt) => apt["apartmentId"] as String)
            .toList();

        setState(() {
          allLocations = apartments;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage = "Server error: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Connessione fallita: $e";
      });
    }
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

            // Se è in corso il caricamento mostriamo uno spinner
            if (isLoading)
              const Center(child: CircularProgressIndicator()),

            // Altrimenti se c'è errore, visualizziamo l’errore
            if (!isLoading && errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            // Se non è in loading e non abbiamo errori, mostriamo la lista
            if (!isLoading && errorMessage == null)
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
