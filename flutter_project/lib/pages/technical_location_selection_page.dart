import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LocationSelectionPage extends StatefulWidget {
  final Function(String) onLocationSelected;
  final String username;

  const LocationSelectionPage({
    Key? key,
    required this.onLocationSelected,
    required this.username,
  }) : super(key: key);

  @override
  State<LocationSelectionPage> createState() => _LocationSelectionPageState();
}

class _LocationSelectionPageState extends State<LocationSelectionPage> {
  static const String REGISTRY_URL = "http://registry:8081/apartments";

  final TextEditingController _searchController = TextEditingController();

  List<String> allLocations = [];
  String filter = "";

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLocationsFromRegistry();
    _searchController.addListener(() {
      setState(() {
        filter = _searchController.text;
      });
    });
  }

  Future<void> _fetchLocationsFromRegistry() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(Uri.parse(REGISTRY_URL));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // We only keep apartments that include widget.username in their "users" list
        final List<String> userLocations = [];
        for (var apt in data) {
          final List<dynamic>? users = apt["users"];
          if (users != null && users.contains(widget.username)) {
            userLocations.add(apt["apartmentId"]);
          }
        }

        setState(() {
          allLocations = userLocations;
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
        errorMessage = "Connection failed: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Search bar
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

            if (isLoading)
              const Center(child: CircularProgressIndicator()),
            if (!isLoading && errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

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
