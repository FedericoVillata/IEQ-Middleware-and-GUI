// tenant_home_page.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../login_page.dart';

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
  late String selectedApartment;
  late String selectedRoom;
  bool showDropdown = false;
  Timer? _refreshTimer;

  String indoorTemp = "Loading...";
  String humidity = "Loading...";
  String co2 = "Loading...";
  String tempStatus = "";
  String humidityStatus = "";
  String co2Status = "";

  // Meteo
  String externalTemp = "20°C"; // Valore predefinito
  int weatherCode = 0;
  final String adaptorUrl = "http://10.0.2.2:8080";

  @override
  void initState() {
    super.initState();
    selectedApartment = widget.selectedApartment;
    selectedRoom = widget.rooms[selectedApartment]?.first ?? "Unknown";
    _fetchRoomData();
    _fetchExternalWeatherData(); // Chiamata immediata per il meteo
    _startExternalWeatherRefresh(); // Start the weather update here
  }

  // Chiamata immediata per recuperare il meteo
  void _fetchExternalWeatherData() async {
    final meteoUrl = Uri.parse(
      "https://api.open-meteo.com/v1/forecast?latitude=45.0705&longitude=7.6868&hourly=temperature_2m,weather_code&timezone=auto&forecast_days=1",
    );

    try {
      final meteoResponse = await http.get(meteoUrl);
      if (meteoResponse.statusCode == 200) {
        final meteoData = jsonDecode(meteoResponse.body);
        final List<dynamic> temperatures = meteoData['hourly']['temperature_2m'];
        final List<dynamic> weatherCodes = meteoData['hourly']['weather_code'];
        final now = DateTime.now().hour;

        final String updatedTemp = "${(temperatures[now] as num).toStringAsFixed(1)}°C";
        final int updatedCode = weatherCodes[now];

        setState(() {
          externalTemp = updatedTemp; // Aggiorna la temperatura esterna
          weatherCode = updatedCode;  // Aggiorna il codice meteo
        });
      }
    } catch (e) {
      print("Errore aggiornamento meteo: $e");
    }
  }

  // Periodicamente recupera i dati del meteo
  void _startExternalWeatherRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (timer) async {
      _fetchExternalWeatherData(); // Chiamata ripetuta ogni 10 minuti
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRoomData() async {
    try {
      final url = Uri.parse("$adaptorUrl/getLastRoomData/${widget.username}/$selectedApartment/$selectedRoom");
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        for (var d in data) {
          switch (d["measurament"]) {
            case "Temperature":
              double tempVal = d["v"];
              indoorTemp = "${tempVal.toStringAsFixed(1)}°C";
              tempStatus = tempVal < 18 ? "poor" : tempVal <= 26 ? "good" : "medium";
              break;
            case "Humidity":
              double humVal = d["v"];
              humidity = "${humVal.toStringAsFixed(1)}%";
              humidityStatus = humVal < 30 ? "poor" : humVal <= 60 ? "good" : "medium";
              break;
            case "CO2":
              double co2Val = d["v"];
              co2 = "${co2Val.toInt()} ppm";
              co2Status = co2Val < 800 ? "good" : co2Val <= 1200 ? "medium" : "poor";
              break;
          }
        }
      } else {
        indoorTemp = humidity = co2 = "Error";
      }
    } catch (e) {
      indoorTemp = humidity = co2 = "Error";
    }
    if (mounted) setState(() {});
  }

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
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Welcome, ${widget.username}!",
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$selectedApartment - $selectedRoom",
                style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
              ),
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

  Widget _buildDropdownSelection() {
    return Column(
      children: [
        _buildDropdown("Select Apartment", selectedApartment, widget.apartments, (value) {
          if (value != null) {
            setState(() {
              selectedApartment = value;
              selectedRoom = widget.rooms[selectedApartment]?.first ?? "Unknown";
              widget.onApartmentChanged(value);
              widget.onRoomChanged(selectedRoom);
              showDropdown = false;
              _fetchRoomData();
            });
          }
        }),
        const SizedBox(height: 10),
        _buildDropdown("Select Room", selectedRoom, widget.rooms[selectedApartment] ?? ["Unknown"], (value) {
          if (value != null) {
            setState(() {
              selectedRoom = value;
              widget.onRoomChanged(value);
              showDropdown = false;
              _fetchRoomData();
            });
          }
        }),
      ],
    );
  }

  Widget _buildDropdown(String label, String selectedValue, List<String> options, Function(String?) onChanged) {
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
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey),
              isExpanded: true,
              onChanged: onChanged,
              items: options.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, style: const TextStyle(fontSize: 16)),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color defaultColor, {String? status}) {
    Color iconColor = defaultColor;
    if (status != null) {
      switch (status.toLowerCase()) {
        case 'good':
          iconColor = Colors.green;
          break;
        case 'medium':
          iconColor = Colors.amber;
          break;
        case 'poor':
          iconColor = Colors.red;
          break;
      }
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(fontSize: 14, color: Colors.black54)),
            ]),
            Container(
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: iconColor, size: 40),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForScore(int percentage) {
    if (percentage < 30) return Colors.red;
    if (percentage < 60) return Colors.orange;
    if (percentage < 80) return Colors.amber;
    if (percentage < 100) return Colors.lightGreen;
    return Colors.green;
  }

  Widget _buildOverallScoreCard(int percentage) {
    final color = _getColorForScore(percentage);
    return Center(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text("Overall Score", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[300],
                      color: color,
                      strokeWidth: 8,
                    ),
                  ),
                  Text("$percentage%", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: null,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            if (showDropdown) _buildDropdownSelection(),
            const SizedBox(height: 20),
            _buildInfoCard(
              "External Temperature",
              externalTemp,
              _getWeatherIcon(weatherCode),
              _getWeatherColor(weatherCode),
            ),
            const SizedBox(height: 12),
            _buildInfoCard("Indoor Temperature", indoorTemp, Icons.thermostat, Colors.red, status: tempStatus),
            const SizedBox(height: 12),
            _buildInfoCard("Humidity Level", humidity, Icons.water_drop, Colors.blue, status: humidityStatus),
            const SizedBox(height: 12),
            _buildInfoCard("Air Quality", co2, Icons.air, Colors.green, status: co2Status),
            const SizedBox(height: 30),
            _buildOverallScoreCard(widget.overallScores[selectedApartment] ?? 0),
          ],
        ),
      ),
    );
  }
}
