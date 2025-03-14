import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  final String username;
  final List<String> apartments;
  final Map<String, List<String>> rooms;
  final String selectedApartment;
  final Map<String, int> overallScores;
  final Map<String, String> externalTemperatures;

  const HomePage({
    super.key,
    required this.username,
    required this.apartments,
    required this.rooms,
    required this.selectedApartment,
    required this.overallScores,
    required this.externalTemperatures,
  });

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  late String selectedApartment;
  late String selectedRoom;
  bool showDropdown = false;

  final Map<String, Map<String, Map<String, String>>> sensorData = {
    "Apartment1": {
      "Kitchen": {"Indoor Temperature": "22°C", "Humidity Level": "45%", "Air Quality": "Good"},
      "Living Room": {"Indoor Temperature": "23°C", "Humidity Level": "50%", "Air Quality": "Moderate"},
    },
    "Apartment2": {
      "Bedroom": {"Indoor Temperature": "21°C", "Humidity Level": "40%", "Air Quality": "Good"},
      "Bathroom": {"Indoor Temperature": "24°C", "Humidity Level": "55%", "Air Quality": "Poor"},
    },
  };

  @override
  void initState() {
    super.initState();
    selectedApartment = widget.selectedApartment;
    selectedRoom = widget.rooms[selectedApartment]?.first ?? "Unknown";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: false,
        // Rimosso il "Welcome, ..." dal titolo
        title: null,
        actions: [
          // Icona logout
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black87),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              if (showDropdown) _buildDropdownSelection(),
              const SizedBox(height: 20),
              _buildInfoCard("External Temperature", widget.externalTemperatures[selectedApartment] ?? "N/A", Icons.wb_sunny, Colors.orange),
              const SizedBox(height: 12),
              _buildInfoCard(
                "Indoor Temperature",
                sensorData[selectedApartment]?[selectedRoom]?["Indoor Temperature"] ?? "N/A",
                Icons.thermostat,
                Colors.red,
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                "Humidity Level",
                sensorData[selectedApartment]?[selectedRoom]?["Humidity Level"] ?? "N/A",
                Icons.water_drop,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                "Air Quality",
                sensorData[selectedApartment]?[selectedRoom]?["Air Quality"] ?? "N/A",
                Icons.air,
                Colors.green,
              ),
              const SizedBox(height: 30),
              _buildOverallScoreCard(widget.overallScores[selectedApartment] ?? 0),
            ],
          ),
        ),
      ),
    );
  }

  /// **Header grande e colorato con "Welcome" e Apartment-Room**
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF236FC6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Welcome, ${widget.username}!",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$selectedApartment - $selectedRoom",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    showDropdown = !showDropdown;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
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

  /// **Dropdown per selezione di appartamento e stanza**
  Widget _buildDropdownSelection() {
    return Column(
      children: [
        _buildDropdown("Select Apartment", selectedApartment, widget.apartments, (value) {
          if (value != null) {
            setState(() {
              selectedApartment = value;
              selectedRoom = widget.rooms[selectedApartment]?.first ?? "Unknown";
              showDropdown = false;
            });
          }
        }),
        const SizedBox(height: 10),
        _buildDropdown("Select Room", selectedRoom, widget.rooms[selectedApartment] ?? ["Unknown"], (value) {
          if (value != null) {
            setState(() {
              selectedRoom = value;
              showDropdown = false;
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
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, spreadRadius: 1)],
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

  Widget _buildInfoCard(String title, String value, IconData icon, Color iconColor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      shadowColor: Colors.black26,
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
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: iconColor, size: 40),
            ),
          ],
        ),
      ),
    );
  }

  /// **Overall Score Card centrato**
  /// Determina il colore in base alla percentuale
Color _getColorForScore(int percentage) {
  if (percentage < 30) {
    return Colors.red;
  } else if (percentage < 60) {
    return Colors.orange;
  } else if (percentage < 80) {
    return Colors.amber; // Giallo
  } else if (percentage < 100) {
    return Colors.lightGreen;
  } else {
    return Colors.green; // 100%
  }
}

/// Overall Score Card centrato
Widget _buildOverallScoreCard(int percentage) {
  final Color progressColor = _getColorForScore(percentage);

  return Center(
    child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      shadowColor: Colors.black26,
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
                    color: progressColor,   // Usa il colore dinamico
                    strokeWidth: 8,
                  ),
                ),
                Text(
                  "$percentage%",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: progressColor,  // Colora anche il testo
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}
