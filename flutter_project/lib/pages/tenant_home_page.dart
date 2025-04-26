// pages/tenant_home_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/suggestions_bell.dart';

class HomePage extends StatefulWidget {
  final String username;
  final List<String> apartments;
  final Map<String, List<String>> rooms;
  final String selectedApartment;
  final Map<String, int> overallScores;
  final Function(String) onRoomChanged;
  final Function(String) onApartmentChanged;

  const HomePage({
    super.key,
    required this.username,
    required this.apartments,
    required this.rooms,
    required this.selectedApartment,
    required this.overallScores,
    required this.onRoomChanged,
    required this.onApartmentChanged,
  });

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // ─────────────────────────────── state vars
  late String selectedApartment;
  late String selectedRoom;
  bool  showDropdown = false;
  Timer? _refreshTimer;

  String indoorTemp     = 'Loading...';
  String humidity       = 'Loading...';
  String co2            = 'Loading...';
  String tempStatus     = '';
  String humidityStatus = '';
  String co2Status      = '';

  // meteo
  String externalTemp = '20°C';
  int    weatherCode  = 0;
  final  String adaptorUrl = 'http://localhost:8080';

  // ─────────────────────────────── lifecycle
  @override
  void initState() {
    super.initState();
    selectedApartment = widget.selectedApartment;
    selectedRoom      = widget.rooms[selectedApartment]?.first ?? 'Unknown';
    _fetchRoomData();
    _fetchExternalWeatherData();
    _startExternalWeatherRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────── HTTP helpers
  void _fetchExternalWeatherData() async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=45.0705&longitude=7.6868'
      '&hourly=temperature_2m,weather_code'
      '&timezone=auto&forecast_days=1',
    );

    try {
      final r = await http.get(url);
      if (r.statusCode == 200) {
        final d     = jsonDecode(r.body);
        final temps = d['hourly']['temperature_2m'] as List<dynamic>;
        final codes = d['hourly']['weather_code']   as List<dynamic>;
        final h     = DateTime.now().hour;

        setState(() {
          externalTemp = '${(temps[h] as num).toStringAsFixed(1)}°C';
          weatherCode  = codes[h];
        });
      }
    } catch (e) {
      debugPrint('meteo error: $e');
    }
  }

  void _startExternalWeatherRefresh() {
    _refreshTimer =
        Timer.periodic(const Duration(minutes: 10), (_) => _fetchExternalWeatherData());
  }

  Future<void> _fetchRoomData() async {
    try {
      final url = Uri.parse(
        '$adaptorUrl/getLastRoomData/'
        '${widget.username}/$selectedApartment/$selectedRoom',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        for (final d in data) {
          switch (d['measurement']) {
            case 'Temperature':
              final v = d['v'] as num;
              indoorTemp = '${v.toStringAsFixed(1)}°C';
              tempStatus = v < 18 ? 'poor' : v <= 26 ? 'good' : 'medium';
              break;
            case 'Humidity':
              final v = d['v'] as num;
              humidity = '${v.toStringAsFixed(1)}%';
              humidityStatus = v < 30 ? 'poor' : v <= 60 ? 'good' : 'medium';
              break;
            case 'CO2':
              final v = d['v'] as num;
              co2 = '${v.toInt()} ppm';
              co2Status = v < 800 ? 'good' : v <= 1200 ? 'medium' : 'poor';
              break;
          }
        }
      } else {
        indoorTemp = humidity = co2 = 'Error';
      }
    } catch (e) {
      indoorTemp = humidity = co2 = 'Error';
    }
    if (mounted) setState(() {});
  }

  // ─────────────────────────────── UI helpers
  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code == 1 || code == 2) return Icons.cloud;
    if (code == 3) return Icons.cloud_queue;
    if (code >= 45 && code <= 48) return Icons.foggy;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Icons.grain;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 95) return Icons.bolt;
    return Icons.wb_cloudy;
  }

  Color _getWeatherColor(int code) {
    if (code == 0) return Colors.orange;
    if (code == 1 || code == 2 || code == 3) return Colors.blueGrey;
    if (code >= 45 && code <= 48) return Colors.grey;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Colors.blue;
    if (code >= 71 && code <= 77) return Colors.lightBlueAccent;
    if (code >= 95) return Colors.purple;
    return Colors.blueGrey;
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF236FC6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome, ${widget.username}!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$selectedApartment - $selectedRoom',
                  style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
              GestureDetector(
                onTap: () => setState(() => showDropdown = !showDropdown),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.edit, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String selectedValue,
    List<String> options,
    void Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey),
              onChanged: onChanged,
              items: options
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, style: const TextStyle(fontSize: 16)),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color defaultColor, {
    String? status,
  }) {
    Color c = defaultColor;
    if (status != null) {
      if (status == 'good')   c = Colors.green;
      if (status == 'medium') c = Colors.amber;
      if (status == 'poor')   c = Colors.red;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(value, style: const TextStyle(fontSize: 14, color: Colors.black54)),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: c, size: 40),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForScore(int p) =>
      p < 30 ? Colors.red :
      p < 60 ? Colors.orange :
      p < 80 ? Colors.amber :
      p < 100 ? Colors.lightGreen :
      Colors.green;

  Widget _buildOverallScoreCard(int p) {
    final c = _colorForScore(p);
    return Center(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text('Overall Score', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: p / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey[300],
                      color: c,
                    ),
                  ),
                  Text('$p%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: null,
        actions: [
          SuggestionsBell(
            username: widget.username,
            apartmentId: selectedApartment,
            roomId: selectedRoom,
            isTechnical: false,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),

            // dropdown se visibile
            if (showDropdown) ...[
              _buildDropdown(
                'Select Apartment',
                selectedApartment,
                widget.apartments,
                (v) {
                  if (v == null) return;
                  setState(() {
                    selectedApartment = v;
                    selectedRoom      = widget.rooms[v]?.first ?? 'Unknown';
                    widget.onApartmentChanged(v);
                    widget.onRoomChanged(selectedRoom);
                    showDropdown = false;
                    _fetchRoomData();
                  });
                },
              ),
              const SizedBox(height: 10),
              _buildDropdown(
                'Select Room',
                selectedRoom,
                widget.rooms[selectedApartment] ?? ['Unknown'],
                (v) {
                  if (v == null) return;
                  setState(() {
                    selectedRoom = v;
                    widget.onRoomChanged(v);
                    showDropdown = false;
                    _fetchRoomData();
                  });
                },
              ),
              const SizedBox(height: 20),
            ],

            _buildInfoCard(
              'External Temperature',
              externalTemp,
              _getWeatherIcon(weatherCode),
              _getWeatherColor(weatherCode),
            ),
            const SizedBox(height: 12),
            _buildInfoCard(
              'Indoor Temperature',
              indoorTemp,
              Icons.thermostat,
              Colors.red,
              status: tempStatus,
            ),
            const SizedBox(height: 12),
            _buildInfoCard(
              'Humidity Level',
              humidity,
              Icons.water_drop,
              Colors.blue,
              status: humidityStatus,
            ),
            const SizedBox(height: 12),
            _buildInfoCard(
              'Air Quality',
              co2,
              Icons.air,
              Colors.green,
              status: co2Status,
            ),
            const SizedBox(height: 30),
            _buildOverallScoreCard(widget.overallScores[selectedApartment] ?? 0),
          ],
        ),
      ),
    );
  }
}
