import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../app_config.dart';
import '../widgets/suggestions_bell.dart';

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
  // The base URL for your adaptor and plot service
  // static const String ADAPTOR_URL = "http://localhost:8080";      // For CSV data, etc.
  //static const String PLOT_SERVICE_URL = "http://service_plot:9090"; // For images (line/carpet)
  static String get PLOT_SERVICE_URL => AppConfig.plotServiceUrl;

  // Metrics
  final List<String> metrics = ["Temperature", "Humidity", "CO2", "PM10.0", "VOC"];
  String selectedMetric = "Temperature";

  // Chart type
  // The user asked to swap the order: now "Line Chart" is first, "Carpet Plot" is second
  String selectedChartType = "line"; // possible values: "line" or "carpet"

  // Duration options
  final Map<String, String> durationOptions = {
    "1 day": "24",
    "3 days": "72",
    "1 week": "168",
    "1 month": "720",
    "3 months": "2160",
    "6 months": "4320",
    "1 year": "8760",
    "all": "999999",
  };
  String selectedDuration = "168";

  // Rooms
  List<String> availableRooms = [];
  String? selectedRoom;

  // For error or fallback
  String? errorMessage;
  bool isLoadingRooms = false;

  @override
  void initState() {
    super.initState();
    _fetchRoomsForApartment(widget.location ?? "apartment0");
  }

  Future<void> _fetchRoomsForApartment(String apartmentId) async {
    setState(() {
      isLoadingRooms = true;
      errorMessage = null;
      availableRooms = [];
      selectedRoom = null;
    });

    try {
      // final resp = await http.get(Uri.parse("http://localhost:8081/apartments"));
      final resp = await http.get(Uri.parse(AppConfig.registryUrl + "/apartments"));
      if (resp.statusCode == 200) {
        final arr = json.decode(resp.body);
        if (arr is List) {
          for (var apt in arr) {
            if (apt["apartmentId"] == apartmentId) {
              final rooms = apt["rooms"] as List<dynamic>;
              final foundRooms = rooms.map((r) => r["roomId"].toString()).toList();
              setState(() {
                if (foundRooms.isEmpty) {
                  availableRooms = ["(No rooms)"];
                  selectedRoom = null;
                } else {
                  availableRooms = foundRooms;
                  selectedRoom = foundRooms.first;
                }
                isLoadingRooms = false;
              });
              return;
            }
          }
        }
      }
      // If we got here, no success
      setState(() {
        availableRooms = ["(FallbackRoom1)", "(FallbackRoom2)"];
        selectedRoom = "(FallbackRoom1)";
        isLoadingRooms = false;
      });
    } catch (e) {
      setState(() {
        isLoadingRooms = false;
        errorMessage = "Connection error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Metric selection
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: metrics.map((m) {
                    final sel = (m == selectedMetric);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sel ? Colors.indigo : Colors.blueGrey,
                        ),
                        onPressed: () {
                          setState(() => selectedMetric = m);
                        },
                        child: Text(m, style: const TextStyle(color: Colors.white)),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Chart type: Line vs. Carpet (swapped order)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildChartTypeButton("Line Chart", "line"),
                  const SizedBox(width: 16),
                  _buildChartTypeButton("Carpet Plot", "carpet"),
                ],
              ),

              // Room selection
              if (availableRooms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      title: const Text("Select Room"),
                      trailing: DropdownButton<String>(
                        value: selectedRoom,
                        items: availableRooms.map((r) {
                          return DropdownMenuItem(value: r, child: Text(r));
                        }).toList(),
                        onChanged: (val) {
                          setState(() => selectedRoom = val);
                        },
                      ),
                    ),
                  ),
                ),

              // Duration selection
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Card(
                  elevation: 2,
                  child: ListTile(
                    title: const Text("Select Duration"),
                    trailing: DropdownButton<String>(
                      value: selectedDuration,
                      items: durationOptions.entries.map((e) {
                        return DropdownMenuItem(value: e.value, child: Text(e.key));
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => selectedDuration = val);
                      },
                    ),
                  ),
                ),
              ),

              // Buttons for "Download Chart" and "Export CSV"
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

              const SizedBox(height: 20),
              // The main chart area
              Expanded(
                child: Center(
                  child: isLoadingRooms
                      ? const CircularProgressIndicator()
                      : (errorMessage != null
                          ? Text(errorMessage!, style: const TextStyle(color: Colors.red))
                          : _buildChartImage()),
                ),
              ),
            ],
        ),

         Positioned(
          top: 12,
          right: 12,
          child: SuggestionsBell(
            location: widget.location,
            username: widget.username,
          ),
        ),
      ],
    ),
  );
}

  // ---------------------------------------------
  //   Chart Type Button
  // ---------------------------------------------
  Widget _buildChartTypeButton(String label, String value) {
    final isSelected = (selectedChartType == value);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue.shade100 : Colors.white,
        side: BorderSide(color: isSelected ? Colors.blue : Colors.grey),
      ),
      onPressed: () {
        setState(() {
          selectedChartType = value;
        });
      },
      child: Text(label, style: TextStyle(color: isSelected ? Colors.blue : Colors.black)),
    );
  }

  // --------------------------------------------------
  //  Build the image from plot_service.py
  // --------------------------------------------------
  Widget _buildChartImage() {
    final user = widget.username;
    final apt = widget.location ?? "apartment0";
    final measure = selectedMetric;
    final dur = selectedDuration;

    // Decide which endpoint to use
    final endpoint = (selectedChartType == "line") ? "generateLineChart" : "generateCarpetPlot";

    // Build URL
    String url = "$PLOT_SERVICE_URL/$endpoint?userId=$user&apartmentId=$apt&measure=$measure&duration=$dur";
    if (selectedRoom != null && !selectedRoom!.startsWith("(")) {
      url += "&room=$selectedRoom";
    }
    // Add a timestamp param to avoid caching
    final ts = DateTime.now().millisecondsSinceEpoch;
    url += "&ts=$ts";

    return SizedBox(
      width: 1200,
      height: 900,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const CircularProgressIndicator();
        },
        errorBuilder: (context, error, stack) => const Text("Error loading chart image."),
      ),
    );
  }

  // --------------------------------------------------
  //           Download / Export
  // --------------------------------------------------
  Future<void> _downloadChart() async {
    final user = widget.username;
    final apt = widget.location ?? "apartment0";
    final measure = selectedMetric;
    final dur = selectedDuration;

    // Which endpoint
    final endpoint = (selectedChartType == "line") ? "generateLineChart" : "generateCarpetPlot";

    // Add download=png param
    String url = "$PLOT_SERVICE_URL/$endpoint?userId=$user&apartmentId=$apt"
        "&measure=$measure&duration=$dur&download=png";

    if (selectedRoom != null && !selectedRoom!.startsWith("(")) {
      url += "&room=$selectedRoom";
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _exportCsv() async {
    final user = widget.username;
    final apt = widget.location ?? "apartment0";
    final measure = selectedMetric;
    final dur = selectedDuration;

    // The plot service uses exportCsv for CSV
    String url = "$PLOT_SERVICE_URL/exportCsv?userId=$user&apartmentId=$apt"
        "&measure=$measure&duration=$dur";

    if (selectedRoom != null && !selectedRoom!.startsWith("(")) {
      url += "&room=$selectedRoom";
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
