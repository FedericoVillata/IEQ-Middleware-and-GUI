import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../login_page.dart';

class HomePage extends StatefulWidget {
  final String username;
  final List<String> apartments;
  final Map<String, List<String>> rooms;
  final String selectedApartment;
  final Map<String, int> overallScores;
  final Map<String, String> externalTemperatures;
  final Function(String) onRoomChanged;
  final Function(String) onApartmentChanged;

  const HomePage({
    super.key,
    required this.username,
    required this.apartments,
    required this.rooms,
    required this.selectedApartment,
    required this.overallScores,
    required this.externalTemperatures,
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

  String indoorTemp = "Loading...";
  String humidity = "Loading...";
  String co2 = "Loading...";
  String tempStatus = "";
  String humidityStatus = "";
  String co2Status = "";

  final String adaptorUrl = "http://10.0.2.2:8080";

  @override
  void initState() {
    super.initState();
    selectedApartment = widget.selectedApartment;
    selectedRoom = widget.rooms[selectedApartment]?.first ?? "Unknown";
    _fetchRoomData();
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
            _buildInfoCard("External Temperature", widget.externalTemperatures[selectedApartment] ?? "N/A", Icons.wb_sunny, Colors.orange),
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
}
