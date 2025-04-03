import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TechnicalHomePage extends StatefulWidget {
  final String username;
  final String? location;

  const TechnicalHomePage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalHomePage> createState() => _TechnicalHomePageState();
}

class _TechnicalHomePageState extends State<TechnicalHomePage> {
  // PlotService base URL
  static const String PLOT_SERVICE_URL = "http://localhost:9090";

  // All metrics
  final List<String> metrics = ["Temperature", "humidity", "CO2", "PM10", "VOC"];
  String selectedMetric = "Temperature";

  // Carpet vs. Line
  String selectedChartType = "carpet";

  // Rooms
  List<String> availableRooms = [];
  String? selectedRoom;

  // Duration dropdown
  final Map<String, String> durationOptions = {
    "1 day": "24",
    "3 days": "72",
    "1 week": "168",
    "1 month": "720",
    "3 months": "2160",
    "6 months": "4320",
    "1 year": "8760",
    "all": "999999"
  };
  String selectedDuration = "24";

  @override
  void initState() {
    super.initState();
    _fetchRoomsForApartment(widget.location ?? "apartment0");
  }

  Future<void> _fetchRoomsForApartment(String apartmentId) async {
    try {
      final response = await http.get(Uri.parse("http://localhost:8081/apartments"));
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
            selectedRoom = foundRooms.first;
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
          // Row of metric selection
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((metricName) {
                final isSelected = (selectedMetric == metricName);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.indigo : Colors.blueGrey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      metricName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onPressed: () => setState(() {
                      selectedMetric = metricName;
                    }),
                  ),
                );
              }).toList(),
            ),
          ),

          // Chart type selection
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
                  _buildToggleButton("Carpet Plot", "carpet"),
                  const SizedBox(width: 16),
                  _buildToggleButton("Line Chart", "line"),
                ],
              ),
            ),
          ),

          // Room selection
          if (availableRooms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

          // Duration selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

          // Download/Export
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

          // Chart display
          Expanded(
            child: Center(
              child: _buildChartImage(),
            ),
          ),
        ],
      ),
    );
  }

  // Button for toggling "carpet" vs. "line"
  Widget _buildToggleButton(String label, String typeValue) {
    final bool selected = (selectedChartType == typeValue);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: selected ? Colors.indigo.shade50 : Colors.transparent,
      ),
      onPressed: () => setState(() {
        selectedChartType = typeValue;
      }),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.indigo : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // The chart image with a spinner while loading
  Widget _buildChartImage() {
    final userId = widget.username;
    final aptId = widget.location ?? "apartment0";
    final endpoint = (selectedChartType == "carpet")
        ? "/generateCarpetPlot"
        : "/generateLineChart";

    // Construct the URL
    String chartUrl = "$PLOT_SERVICE_URL$endpoint"
        "?userId=$userId"
        "&apartmentId=$aptId"
        "&measure=$selectedMetric"
        "&duration=$selectedDuration";

    if (selectedRoom != null) {
      chartUrl += "&room=$selectedRoom";
    }
    // Add a timestamp param to avoid caching
    final ts = DateTime.now().millisecondsSinceEpoch;
    chartUrl += "&ts=$ts";

    return Image.network(
      chartUrl,
      // If loading is in progress, show spinner
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          // Fully loaded
          return child;
        }
        // Still loading => show spinner
        return const Center(child: CircularProgressIndicator());
      },
      // If error occurs (e.g. 404), show message
      errorBuilder: (context, error, stackTrace) {
        return const Text("Error loading chart. Possibly no data found.");
      },
    );
  }

  // Download chart as PNG
  Future<void> _downloadChart() async {
    final userId = widget.username;
    final aptId = widget.location ?? "apartment0";
    final endpoint = (selectedChartType == "carpet")
        ? "/generateCarpetPlot"
        : "/generateLineChart";

    String url = "$PLOT_SERVICE_URL$endpoint"
        "?userId=$userId"
        "&apartmentId=$aptId"
        "&measure=$selectedMetric"
        "&duration=$selectedDuration"
        "&download=png";

    if (selectedRoom != null) {
      url += "&room=$selectedRoom";
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  // Export CSV
  Future<void> _exportCsv() async {
    final userId = widget.username;
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
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
