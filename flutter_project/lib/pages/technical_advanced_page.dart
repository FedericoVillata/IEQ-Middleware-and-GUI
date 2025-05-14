import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../widgets/suggestions_bell.dart';

class TechnicalAdvancePage extends StatefulWidget {
  final String username;
  final String? location;
  final String? apartmentName;

  const TechnicalAdvancePage({
    Key? key,
    required this.username,
    required this.location,
    this.apartmentName,
  }) : super(key: key);

  @override
  State<TechnicalAdvancePage> createState() => _TechnicalAdvancePageState();
}

class _TechnicalAdvancePageState extends State<TechnicalAdvancePage> {
  // ──────────────────────────────────────────────────────────────────────────
  //  Configuration
  // ──────────────────────────────────────────────────────────────────────────
  static String get PLOT_SERVICE_URL => AppConfig.plotServiceUrl;

  // Metrics shown in the Advanced page
  final List<String> metrics = [
    "Environment Score",
    "ICONE",
    "IEQI",
    "PMV",
    "PPD",
  ];
  String selectedMetric = "Environment Score";

  /// Texts for the legend (RED label first, BLUE label second).
  final Map<String, List<String>> _legendTexts = {
    "Environment Score": ["Ideal environmental score", "Low environmental score"],
    "ICONE": ["Ideal iCone level", "Low iCone level"],
    "IEQI": ["Ideal IEQI level", "Low IEQI level"],
    "PMV": ["Very hot", "Very cold"],
    "PPD": ["Ideal PPD value", "Low PPD value"],
  };

  // Map visible label ➜ measure key used by plot_service
  final Map<String, String> measureMap = {
    "Environment Score": "environment_score",
    "ICONE": "icone",
    "IEQI": "ieqi",
    "PMV": "pmv",
    "PPD": "ppd",
  };

  // Chart type
  String selectedChartType = "line"; // "line" or "carpet"

  // Duration dropdown
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
  String selectedDuration = "24";

  // Rooms
  List<String> availableRooms = [];
  String? selectedRoom;

  // Error / loading flags
  String? errorMessage;
  bool isLoadingRooms = false;

  // ──────────────────────────────────────────────────────────────────────────
  //  Lifecycle
  // ──────────────────────────────────────────────────────────────────────────
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
      final resp = await http.get(Uri.parse("${AppConfig.registryUrl}/apartments"));
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
      // Fallback
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

  // ──────────────────────────────────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Metric selector ────────────────────────────────────────────
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
                        onPressed: () => setState(() => selectedMetric = m),
                        child: Text(m, style: const TextStyle(color: Colors.white)),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Chart-type buttons ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildChartTypeButton("Line Chart", "line"),
                  const SizedBox(width: 16),
                  _buildChartTypeButton("Carpet Plot", "carpet"),
                ],
              ),

              // Room selector ──────────────────────────────────────────────
              if (availableRooms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      title: const Text("Select Room"),
                      trailing: DropdownButton<String>(
                        focusColor: Colors.transparent,
                        value: selectedRoom,
                        items: availableRooms
                            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (val) => setState(() => selectedRoom = val),
                      ),
                    ),
                  ),
                ),

              // Duration selector ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Card(
                  elevation: 2,
                  child: ListTile(
                    title: const Text("Select Duration"),
                    trailing: DropdownButton<String>(
                      focusColor: Colors.transparent,
                      value: selectedDuration,
                      items: durationOptions.entries
                          .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key)))
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => selectedDuration = val);
                      },
                    ),
                  ),
                ),
              ),

              // Download / Export buttons ──────────────────────────────────
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

              // Chart area (spinner → img/legend/“no data”) ───────────────
              Expanded(child: Center(child: _buildChartArea())),
            ],
          ),

          // Suggestions bell (top-right) ──────────────────────────────────
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

  // ──────────────────────────────────────────────────────────────────────────
  //  UI helpers
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildChartTypeButton(String label, String value) {
    final isSelected = (selectedChartType == value);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue.shade100 : Colors.white,
        side: BorderSide(color: isSelected ? Colors.blue : Colors.grey),
      ),
      onPressed: () => setState(() => selectedChartType = value),
      child: Text(
        label,
        style: TextStyle(color: isSelected ? Colors.blue : Colors.black),
      ),
    );
  }

  Widget _buildLegend() {
    final List<String> labels = _legendTexts[selectedMetric] ?? ["High", "Low"];

    Widget legendRow(Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 16, height: 16, color: color),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12, offset: Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          legendRow(const Color(0xFF8B0000), labels[0]),
          legendRow(const Color(0xFF090F7D), labels[1]),
        ],
      ),
    );
  }

  Widget _buildChartArea() {
    if (isLoadingRooms) return const CircularProgressIndicator();
    if (errorMessage != null) {
      return Text(errorMessage!, style: const TextStyle(color: Colors.red));
    }

    return (selectedChartType == "carpet")
        ? _buildCarpetChartWithLegend()
        : _buildChartOnly();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Chart builders (fast transition – no “old” image flash)
  // ──────────────────────────────────────────────────────────────────────────
  String _chartUrl() {
    final user = widget.username;
    final apt = widget.location ?? "apartment0";
    final measureKey = measureMap[selectedMetric] ?? "environment_score";
    final endpoint =
        (selectedChartType == "line") ? "generateLineChart" : "generateCarpetPlot";

    String url =
        "$PLOT_SERVICE_URL/$endpoint?userId=$user&apartmentId=$apt&measure=$measureKey&duration=$selectedDuration";

    if (selectedRoom != null && !selectedRoom!.startsWith("(")) {
      url += "&room=$selectedRoom";
    }
    // Bust HTTP cache so we always fetch the new image
    url += "&ts=${DateTime.now().millisecondsSinceEpoch}";
    return url;
  }

  /// Line chart or carpet *without* legend
  Widget _buildChartOnly() {
    return FutureBuilder<http.Response>(
      future: http.get(Uri.parse(_chartUrl())),
      builder: (context, snapshot) {
        // Show spinner while waiting for the new image
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }

        if (snapshot.hasError) return const Text("Error loading chart image.");
        if (!snapshot.hasData) return const Text("No response from server.");

        final res = snapshot.data!;
        if (res.statusCode != 200) return const Text("Error loading chart image.");

        final noData = _isNoData(res);
        if (noData) {
          return Text(_noDataMessageForMetric(selectedMetric),
              style: const TextStyle(fontStyle: FontStyle.italic));
        }

        return SizedBox(
          width: 800,
          height: 600,
          child: Image.memory(res.bodyBytes, fit: BoxFit.contain),
        );
      },
    );
  }

  /// Carpet plot + legend (legend hidden if no data)
  Widget _buildCarpetChartWithLegend() {
    return FutureBuilder<http.Response>(
      future: http.get(Uri.parse(_chartUrl())),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }

        if (snapshot.hasError) return const Text("Error loading chart image.");
        if (!snapshot.hasData) return const Text("No response from server.");

        final res = snapshot.data!;
        if (res.statusCode != 200) return const Text("Error loading chart image.");

        final noData = _isNoData(res);
        if (noData) {
          return Text(_noDataMessageForMetric(selectedMetric),
              style: const TextStyle(fontStyle: FontStyle.italic));
        }

        final img = SizedBox(
          width: 800,
          height: 600,
          child: Image.memory(res.bodyBytes, fit: BoxFit.contain),
        );

        // Image + legend side-by-side
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              img,
              const SizedBox(width: 0),
              Transform.translate(offset: const Offset(0, -22), child: _buildLegend()),
            ],
          ),
        );
      },
    );
  }

  bool _isNoData(http.Response res) {
        final h = res.headers;
        // case‑insensitive lookup
        return (h['X-No-Data'] == '1') || (h['x-no-data'] == '1');
  }

  // Custom “no-data” text per metric
  String _noDataMessageForMetric(String metric) =>
    'No data for $metric in the selected time period';

  // ──────────────────────────────────────────────────────────────────────────
  //  Download / Export helpers
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _downloadChart() async {
    final url = _chartUrl().replaceFirst("&ts=", "&download=png&ts=");
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _exportCsv() async {
    final user = widget.username;
    final apt = widget.location ?? "apartment0";
    final measureKey = measureMap[selectedMetric] ?? "environment_score";

    String url =
        "$PLOT_SERVICE_URL/exportCsv?userId=$user&apartmentId=$apt&measure=$measureKey&duration=$selectedDuration";

    if (selectedRoom != null && !selectedRoom!.startsWith("(")) {
      url += "&room=$selectedRoom";
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
