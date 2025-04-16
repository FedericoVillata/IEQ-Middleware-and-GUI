import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../app_config.dart';

class TechnicalDeletedSuggestionsPage extends StatefulWidget {
  final String username;
  final String? location;

  const TechnicalDeletedSuggestionsPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalDeletedSuggestionsPage> createState() =>
      _TechnicalDeletedSuggestionsPageState();
}

class _TechnicalDeletedSuggestionsPageState
    extends State<TechnicalDeletedSuggestionsPage> {
  bool isLoading = false;
  String? errorMessage;

  List<String> availableRooms = [];
  String? selectedRoom;
  Map<String, String> suggestionTexts = {};
  List<Map<String, dynamic>> deletedSuggestions = [];
  Map<String, dynamic>? catalogData;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    if (widget.location == null) {
      setState(() {
        errorMessage = "No apartment location selected.";
      });
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
      availableRooms.clear();
      suggestionTexts.clear();
      deletedSuggestions.clear();
      catalogData = null;
      selectedRoom = null;
    });
    try {
      final resp = await http.get(Uri.parse(AppConfig.registryUrl + "/catalog"));
      if (resp.statusCode != 200) {
        setState(() {
          isLoading = false;
          errorMessage = "Error ${resp.statusCode}: ${resp.body}";
        });
        return;
      }
      final data = json.decode(resp.body);
      if (data is! Map<String, dynamic>) {
        setState(() {
          isLoading = false;
          errorMessage = "Invalid catalog format.";
        });
        return;
      }
      catalogData = data;

      final tenantSugg = data["tenant_suggestions"] as List<dynamic>? ?? [];
      for (var s in tenantSugg) {
        final id = s["suggestionID"] ?? s["suggestionId"];
        final txt = s["text"] ?? "";
        if (id != null && txt is String) {
          suggestionTexts["$id"] = txt;
        }
      }

      final apartments = data["apartments"] as List<dynamic>? ?? [];
      final apt = apartments.firstWhere(
        (a) => a["apartmentId"] == widget.location,
        orElse: () => null,
      );
      if (apt == null) {
        setState(() {
          isLoading = false;
          errorMessage = "Apartment '${widget.location}' not found.";
        });
        return;
      }

      final rooms = apt["rooms"] as List<dynamic>? ?? [];
      if (rooms.isEmpty) {
        setState(() {
          isLoading = false;
          errorMessage = "No rooms found in this apartment.";
        });
        return;
      }
      List<String> foundRooms = [];
      for (var r in rooms) {
        if (r["roomId"] != null) {
          foundRooms.add(r["roomId"].toString());
        }
      }
      if (foundRooms.isEmpty) {
        setState(() {
          isLoading = false;
          errorMessage = "No valid rooms in this apartment.";
        });
        return;
      }
      setState(() {
        availableRooms = foundRooms;
        selectedRoom = foundRooms.first;
      });

      await _loadDeletedForRoom(selectedRoom!);
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Fetch error: $e";
      });
    }
  }

  Future<void> _loadDeletedForRoom(String roomId) async {
    if (catalogData == null) return;
    deletedSuggestions.clear();

    final apartments = catalogData!["apartments"] as List<dynamic>? ?? [];
    final apt = apartments.firstWhere(
      (a) => a["apartmentId"] == widget.location,
      orElse: () => null,
    );
    if (apt == null) return;

    final rooms = apt["rooms"] as List<dynamic>? ?? [];
    final rMap = rooms.firstWhere(
      (r) => r["roomId"] == roomId,
      orElse: () => null,
    );
    if (rMap == null) return;

    final suggList = rMap["suggestions"] as List<dynamic>? ?? [];
    final zeroState = suggList.where((s) => s["state"] == 0).toList();
    for (var s in zeroState) {
      final sid = s["suggestionId"] ?? s["suggestionID"];
      final text = suggestionTexts["$sid"] ?? "(No text)";
      deletedSuggestions.add({"suggestionId": "$sid", "text": text});
    }
    setState(() {});
  }

  Future<void> _onRoomChanged(String? newRoom) async {
    if (newRoom == null) return;
    setState(() {
      selectedRoom = newRoom;
      deletedSuggestions.clear();
    });
    await _loadDeletedForRoom(newRoom);
  }

  Future<void> _restoreSuggestion(Map<String, dynamic> item) async {
    if (catalogData == null || selectedRoom == null) return;
    final suggestionId = item["suggestionId"] ?? "";
    try {
      final url = AppConfig.registryUrl + "/update_suggestion";
      final body = {
        "suggestionId": suggestionId,
        "text": item["text"] ?? "",
        "roomId": selectedRoom,
        "state": 1
      };
      final resp = await http.put(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );
      if (resp.statusCode == 200) {
        await _loadDeletedForRoom(selectedRoom!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Restore failed: ${resp.statusCode} ${resp.body}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              "Deleted Tenant Suggestions for ${widget.location} (user: ${widget.username})",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (availableRooms.isNotEmpty)
              Card(
                child: ListTile(
                  title: const Text("Select Room"),
                  trailing: DropdownButton<String>(
                    value: selectedRoom,
                    items: availableRooms.map((r) {
                      return DropdownMenuItem(value: r, child: Text(r));
                    }).toList(),
                    onChanged: _onRoomChanged,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: deletedSuggestions.isEmpty
                  ? const Center(child: Text("No deleted suggestions found."))
                  : ListView.builder(
                      itemCount: deletedSuggestions.length,
                      itemBuilder: (context, index) {
                        final item = deletedSuggestions[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(
                              item["text"] ?? "",
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () => _restoreSuggestion(item),
                              icon: const Icon(Icons.refresh),
                              label: const Text("Restore"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
