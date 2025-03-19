import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

/// This page displays detailed metrics for a selected location.
/// It includes a "Temperature" button that can switch between
/// a Carpet Plot and a Line Chart, as well as date pickers 
/// for specifying a custom time range for the line chart.
class TechnicalHomePage extends StatefulWidget {
  final String? location;
  const TechnicalHomePage({Key? key, required this.location}) : super(key: key);

  @override
  State<TechnicalHomePage> createState() => _TechnicalHomePageState();
}

class _TechnicalHomePageState extends State<TechnicalHomePage> {
  // List of metrics available
  final metrics = ["Temperature", "Humidity", "CO2", "PM10", "TVOC"];

  // Current metric selection
  String selectedMetric = "Temperature";

  // We manage two view modes for Temperature: "carpet" or "line"
  String temperatureViewMode = "carpet";

  // For the line chart: we have a start date and an end date
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    // Request the default time range (last week) from the backend
    _loadDefaultRange();
  }

  /// Calls the backend endpoint '/getLastWeekRange' to retrieve
  /// the last week time window from the dataset (output.json).
  Future<void> _loadDefaultRange() async {
    try {
      final url = Uri.parse("http://localhost:9092/getLastWeekRange");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        final String? startStr = jsonResp["start"];
        final String? endStr = jsonResp["end"];

        if (startStr != null && endStr != null) {
          // Convert to DateTime objects
          final dtStart = DateTime.parse(startStr.replaceAll("Z", ""));
          final dtEnd = DateTime.parse(endStr.replaceAll("Z", ""));

          setState(() {
            startDate = dtStart;
            endDate = dtEnd;
          });
        } else {
          // If the JSON has no data, we just keep them null
          print("No 'start'/'end' in backend response.");
        }
      } else {
        print("Server returned an error code: ${response.statusCode}");
      }
    } catch (e) {
      print("Exception in _loadDefaultRange: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // -----------------------------------------------------
          // 1) Row of metric buttons (Temperature, Humidity, etc.)
          // -----------------------------------------------------
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((metricName) {
                final bool isSelected = (selectedMetric == metricName);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isSelected ? Colors.indigo : Colors.blueGrey,
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
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        selectedMetric = metricName;
                        // If user clicks Temperature, revert to 'carpet' by default
                        if (metricName == "Temperature") {
                          temperatureViewMode = "carpet";
                        }
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // --------------------------------------------------------------------
          // 2) If the current metric is "Temperature", show the sub-menu
          //    to switch between "Carpet Plot" and "Line Chart".
          // --------------------------------------------------------------------
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
                    // Carpet Plot button
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
                    // Line Chart button
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

          // --------------------------------------------------------------------
          // 3) If we are in "Line Chart" mode, show date pickers for start & end
          // --------------------------------------------------------------------
          if (selectedMetric == "Temperature" && temperatureViewMode == "line")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Start date picker button
                      _buildDateButton(
                        context,
                        label: "Start: ",
                        date: startDate,
                        onDateSelected: (picked) {
                          setState(() {
                            startDate = picked;
                          });
                        },
                      ),
                      // End date picker button
                      _buildDateButton(
                        context,
                        label: "End: ",
                        date: endDate,
                        onDateSelected: (picked) {
                          setState(() {
                            endDate = picked;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // --------------------------------------------------------------------
          // 4) Expanded area: show either a text placeholder (if not Temperature)
          //    or the chart (Carpet or Line).
          // --------------------------------------------------------------------
          Expanded(
            child: Center(
              child: _buildMainContent(),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the two "Carpet Plot" / "Line Chart" buttons with a custom style
  Widget _buildPlotButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  /// Builds a button that opens a DatePicker dialog to update the selected date
  Widget _buildDateButton(
    BuildContext context, {
    required String label,
    required DateTime? date,
    required Function(DateTime) onDateSelected,
  }) {
    // Display either "Not set" or the date in YYYY-MM-DD
    final String text = (date == null)
        ? "Not set"
        : DateFormat('yyyy-MM-dd').format(date);

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () async {
        final now = DateTime.now();
        final firstDate = DateTime(now.year - 2);
        final lastDate = DateTime(now.year + 2);

        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? now,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) {
          onDateSelected(picked);
        }
      },
      child: Text(
        label + text,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  /// Depending on the current metric and mode, returns either:
  ///  - Placeholder text (if not Temperature),
  ///  - Image.network with the Carpet Plot,
  ///  - or Image.network with the Line Chart.
  Widget _buildMainContent() {
    if (selectedMetric != "Temperature") {
      return Text("Monitor for $selectedMetric at ${widget.location}");
    }
    // If the metric is Temperature...
    if (temperatureViewMode == "carpet") {
      // Carpet Plot
      return Image.network(
        'http://localhost:9092/generateCarpetPlot?nocache=${DateTime.now().millisecondsSinceEpoch}',
        errorBuilder: (ctx, error, stack) {
          return const Text("Error loading Carpet Plot");
        },
        loadingBuilder: (context, child, progress) {
          return (progress == null) ? child : const CircularProgressIndicator();
        },
      );
    } else {
      // "line" => Line Chart
      // Build the URL with 'start' and 'end' if available.
      // If user never sets a date, we might rely on the backend's default
      // but for clarity we pass the range if we have them.
      final String startParam = (startDate != null)
          ? "${DateFormat('yyyy-MM-dd').format(startDate!)}T00:00:00"
          : "";
      final String endParam = (endDate != null)
          ? "${DateFormat('yyyy-MM-dd').format(endDate!)}T23:59:59"
          : "";

      // If the user didn't select anything, the server will handle a fallback.
      String lineChartUrl =
          "http://localhost:9092/generateLineChart?nocache=${DateTime.now().millisecondsSinceEpoch}";
      if (startParam.isNotEmpty) {
        lineChartUrl += "&start=$startParam";
      }
      if (endParam.isNotEmpty) {
        lineChartUrl += "&end=$endParam";
      }

      return Image.network(
        lineChartUrl,
        errorBuilder: (ctx, error, stack) {
          return const Text("Error loading Line Chart");
        },
        loadingBuilder: (context, child, progress) {
          return (progress == null) ? child : const CircularProgressIndicator();
        },
      );
    }
  }
}
