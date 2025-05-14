// pages/technical_location_selection_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../login_page.dart';

class LocationSelectionPage extends StatefulWidget {
  /// Callback now returns **both** id and name
  final void Function(String /*apartmentId*/, String /*apartmentName*/)
      onLocationSelected;
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
  // ---------------------------------------------------------------------------
  //  Config & State
  // ---------------------------------------------------------------------------
  static String get _registryUrl => '${AppConfig.registryUrl}/apartments';

  final TextEditingController _search = TextEditingController();

  final List<String> _ids = [];                   
  final Map<String, String> _id2name = {};         
  String _filter = '';

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLocations();
    _search.addListener(() => setState(() => _filter = _search.text));
  }

  // ---------------------------------------------------------------------------
  //  Network
  // ---------------------------------------------------------------------------
  Future<void> _fetchLocations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(Uri.parse(_registryUrl));
      if (resp.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Server error: ${resp.statusCode}';
        });
        return;
      }

      final data = json.decode(resp.body) as List<dynamic>;

      final ids = <String>[];
      final names = <String, String>{};
      for (final apt in data) {
        final users = apt['users'] as List<dynamic>? ?? [];
        if (!users.contains(widget.username)) continue;

        final String id = apt['apartmentId'];
        final String name = (apt['apartmentName'] as String?) ?? id;
        ids.add(id);
        names[id] = name;
      }

      setState(() {
        _ids
          ..clear()
          ..addAll(ids);
        _id2name
          ..clear()
          ..addAll(names);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Connection failed: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  //  UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final lc = _filter.toLowerCase();
    final shown = _ids.where((id) {
      final name = _id2name[id] ?? id;
      return id.toLowerCase().contains(lc) || name.toLowerCase().contains(lc);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Select Location'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── search bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search location…',
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

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final id = shown[i];
                  final name = _id2name[id] ?? id;
                  return _LocationTile(
                    id: id,
                    name: name,
                    onTap: widget.onLocationSelected,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Helper tile
// ---------------------------------------------------------------------------
class _LocationTile extends StatelessWidget {
  final String id;
  final String name;
  final void Function(String, String) onTap;

  const _LocationTile({
    required this.id,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: id != name ? Text(id) : null,
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () => onTap(id, name),
        ),
      );
}
