import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../login_page.dart';           // ← aggiunto

class LocationSelectionPage extends StatefulWidget {
  final Function(String) onLocationSelected;
  final String username;

  const LocationSelectionPage({
    super.key,
    required this.onLocationSelected,
    required this.username,
  });

  @override
  State<LocationSelectionPage> createState() => _LocationSelectionPageState();
}

class _LocationSelectionPageState extends State<LocationSelectionPage> {
  // Endpoint apartments
  static String get _registryUrl => '${AppConfig.registryUrl}/apartments';

  final _search = TextEditingController();

  List<String> _all = [];
  String _filter = '';

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLocations();
    _search.addListener(() => setState(() => _filter = _search.text));
  }

  /* ---------------- network ---------------- */
  Future<void> _fetchLocations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final r = await http.get(Uri.parse(_registryUrl));
      if (r.statusCode == 200) {
        final data = json.decode(r.body) as List<dynamic>;

        // solo gli appartamenti dove compare lo username
        final locs = <String>[];
        for (final apt in data) {
          final users = apt['users'] as List<dynamic>? ?? [];
          if (users.contains(widget.username)) locs.add(apt['apartmentId']);
        }

        setState(() {
          _all = locs;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server error: ${r.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection failed: $e';
        _loading = false;
      });
    }
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    final shown = _all
        .where((l) => l.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,          // ← niente freccia
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
      body: Container(
        color: Colors.grey[200],
        child: Column(
          children: [
            // search bar ---------------------------------------------------
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
                  itemBuilder: (_, i) => _LocationTile(
                    loc: shown[i],
                    onTap: widget.onLocationSelected,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- tile helper ---------------- */
class _LocationTile extends StatelessWidget {
  final String loc;
  final void Function(String) onTap;
  const _LocationTile({required this.loc, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          title: Text(loc, style: const TextStyle(fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () => onTap(loc),
        ),
      );
}
