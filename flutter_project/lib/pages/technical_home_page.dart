import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TechnicalHomePage extends StatefulWidget {
  final String? location; // The selected apartment ID

  const TechnicalHomePage({
    Key? key,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalHomePage> createState() => _TechnicalHomePageState();
}

class _TechnicalHomePageState extends State<TechnicalHomePage> {
  static const String PLOT_SERVICE_URL = "http://localhost:9090";

  // Hard-coded user for demonstration
  static const String HARDCODED_USER_ID = "user0";

  final List<String> metrics = ["Temperature", "Humidity", "CO2", "PM10", "VOC"];
  String selectedMetric = "Temperature";

  // For temperature, we can pick "carpet" or "line"
  String temperatureViewMode = "carpet";

  // The rooms from registry
  List<String> availableRooms = [];
  String? selectedRoom;

  // Instead of date pickers, we provide a duration dropdown
  final Map<String, String> durationOptions = {
    "1 day": "24",
    "3 days": "72",
    "1 week": "168",
    "1 month": "720",
    "3 months": "2160",
    "6 months": "4320",
    "1 year": "8760",
    "all": "999999" // "all" => artificially large number
  };
  String selectedDuration = "24"; // default to 1 day

  @override
  void initState() {
    super.initState();

    selectedMetric = "Temperature";
    temperatureViewMode = "carpet";

    _fetchRoomsForApartment(widget.location ?? "apartment0");
  }

  Future<void> _fetchRoomsForApartment(String apartmentId) async {
    try {
      final url = Uri.parse("http://localhost:8081/apartments");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<String> foundRooms = [];

        for (final apt in data) {
          if (apt["apartmentId"] == apartmentId) {
            final List<dynamic> rooms = apt["rooms"];
            for (final r in rooms) {
              foundRooms.add(r["roomId"]);
            }
            break;
          }
        }

        setState(() {
          if (foundRooms.isEmpty) {
            availableRooms = ["(No rooms)"];
            selectedRoom = null;
          } else {
            availableRooms = foundRooms;
            selectedRoom = foundRooms[0]; // default
          }
        });
      } else {
        setState(() {
          availableRooms = ["(FallbackRoom1)", "(FallbackRoom2)"];
          selectedRoom = "(FallbackRoom1)";
        });
      }
    } catch (e) {
      setState(() {
        availableRooms = ["(Error fetching rooms)"];
        selectedRoom = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 1) Metric selection
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((metricName) {
                final bool isSelected = (selectedMetric == metricName);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.indigo : Colors.blueGrey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      metricName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        selectedMetric = metricName;
                        if (metricName != "Temperature") {
                          temperatureViewMode = "line";
                        }
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // 2) If "Temperature", pick carpet or line
          if (selectedMetric == "Temperature")
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPlotButton(
                      label: "Carpet Plot",
                      selected: (temperatureViewMode == "carpet"),
                      onTap: () {
                        setState(() {
                          temperatureViewMode = "carpet";
                        });
                      },
                    ),
                    const SizedBox(width: 16),
                    _buildPlotButton(
                      label: "Line Chart",
                      selected: (temperatureViewMode == "line"),
                      onTap: () {
                        setState(() {
                          temperatureViewMode = "line";
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 3) Room selection
          if (availableRooms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: const Text("Select Room"),
                  trailing: SizedBox(
                    width: 150,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedRoom,
                      onChanged: (value) {
                        setState(() {
                          selectedRoom = value;
                        });
                      },
                      items: availableRooms.map((roomId) {
                        return DropdownMenuItem<String>(
                          value: roomId,
                          child: Text(roomId),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),

          // 4) Duration selection (instead of start/end dates)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: const Text("Select Duration"),
                trailing: SizedBox(
                  width: 150,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedDuration,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedDuration = val;
                        });
                      }
                    },
                    items: durationOptions.entries.map((entry) {
                      final label = entry.key;
                      final hours = entry.value;
                      return DropdownMenuItem<String>(
                        value: hours,
                        child: Text(label),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),

          // 5) Buttons: "Download Chart" and "Export CSV"
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _downloadChart,
                icon: const Icon(Icons.download),
                label: const Text("Download Chart"),
              ),
              const SizedBox(width: 24),
              ElevatedButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.table_view),
                label: const Text("Export CSV"),
              ),
            ],
          ),

          // 6) Chart display
          Expanded(
            child: Center(
              child: _buildChartImage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlotButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: selected ? Colors.indigo : Colors.grey,
          width: 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: selected ? Colors.indigo.shade50 : Colors.transparent,
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.indigo : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildChartImage() {
    final userId = HARDCODED_USER_ID;
    final aptId = widget.location ?? "apartment0";
    final isTemp = (selectedMetric == "Temperature");
    final isCarpet = (temperatureViewMode == "carpet");

    final endpoint = (isTemp && isCarpet) ? "/generateCarpetPlot" : "/generateLineChart";

    String chartUrl = "$PLOT_SERVICE_URL$endpoint"
        "?userId=$userId"
        "&apartmentId=$aptId"
        "&measure=$selectedMetric"
        // pass 'duration' param
        "&duration=$selectedDuration";

    if (selectedRoom != null) {
      chartUrl += "&room=$selectedRoom";
    }

    // Force a unique param each time so the chart is regenerated
    final ts = DateTime.now().millisecondsSinceEpoch;
    chartUrl += "&ts=$ts";

    return Image.network(
      chartUrl,
      errorBuilder: (context, error, stackTrace) {
        return const Text("Error loading chart (404?)");
      },
    );
  }

  Future<void> _downloadChart() async {
    final userId = HARDCODED_USER_ID;
    final aptId = widget.location ?? "apartment0";
    final isTemp = (selectedMetric == "Temperature");
    final isCarpet = (temperatureViewMode == "carpet");
    final endpoint = (isTemp && isCarpet) ? "/generateCarpetPlot" : "/generateLineChart";

    String url = "$PLOT_SERVICE_URL$endpoint"
        "?userId=$userId"
        "&apartmentId=$aptId"
        "&measure=$selectedMetric"
        "&download=png"
        "&duration=$selectedDuration";

    if (selectedRoom != null) {
      url += "&room=$selectedRoom";
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<void> _exportCsv() async {
    final userId = HARDCODED_USER_ID;
    final aptId = widget.location ?? "apartment0";

    String url = "$PLOT_SERVICE_URL/exportCsv"
        "?userId=$userId"
        "&apartmentId=$aptId"
        "&measure=$selectedMetric"
        "&duration=$selectedDuration";

    if (selectedRoom != null) {
      url += "&room=$selectedRoom";
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}
