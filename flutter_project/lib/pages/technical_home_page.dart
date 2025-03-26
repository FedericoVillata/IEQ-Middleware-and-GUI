import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
// If you plan to do file downloads on web, you might import 'dart:html' for an anchor, etc.

/// This page displays detailed metrics for a selected location,
/// with sub-modes for Temperature (Carpet or Line).
/// Now it also includes date pickers for Carpet, plus
/// "Download Chart" & "Export CSV" for the selected metric and date range.
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

  // For Temperature, we manage two view modes: "carpet" or "line"
  // (The other metrics just show a single chart mode for now.)
  String temperatureViewMode = "carpet";

  // We have a global start/end date for the chart, used for both line & carpet
  // if the metric is "Temperature."
  // If the user picks "Humidity" etc., we'll also pass them in case the backend
  // eventually supports it.
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    // Request the default time range (last week) from the backend
    _loadDefaultRange();
  }

  /// Calls the backend endpoint '/getLastWeekRange' to retrieve
  /// the last-week time window from the dataset (output.json).
  Future<void> _loadDefaultRange() async {
    try {
      final url = Uri.parse("http://localhost:9090/getLastWeekRange");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        final String? startStr = jsonResp["start"];
        final String? endStr = jsonResp["end"];

        if (startStr != null && endStr != null) {
          final dtStart = DateTime.parse(startStr.replaceAll("Z", ""));
          final dtEnd = DateTime.parse(endStr.replaceAll("Z", ""));
          setState(() {
            startDate = dtStart;
            endDate = dtEnd;
          });
        } else {
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
      // We keep your same column structure
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                        // or keep whatever last mode we had?
                        if (metricName == "Temperature") {
                          // possibly reset:
                          // temperatureViewMode = "carpet";
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
          // 3) Show date pickers for all metrics
          //    (So we can pass start/end to the server for any metric we choose.)
          // --------------------------------------------------------------------
          // (You originally only had date pickers in "line" mode for Temperature,
          // but now you want them for both line & carpet (and possibly for any metric).
          // We'll unify them for convenience.)
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
                    // Start date picker
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
                    // End date picker
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
          // 4) Add row with "Download Chart" and "Export CSV" buttons
          // --------------------------------------------------------------------
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

          // --------------------------------------------------------------------
          // 5) Expanded area: show the actual chart (carpet or line, or a placeholder).
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

  /// Builds a button that opens a DatePicker dialog to update the selected date
  Widget _buildDateButton(
    BuildContext context, {
    required String label,
    required DateTime? date,
    required Function(DateTime) onDateSelected,
  }) {
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
        final firstDate = DateTime(now.year - 5); // or 2020
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

  /// Depending on the current metric and (if Temperature) the mode,
  /// returns an Image.network that loads from the server.
  Widget _buildMainContent() {
    // If the user picks a metric other than "Temperature," let's show a single chart
    // or a placeholder. For demonstration, let's just show a line chart for them, or
    // you can do separate endpoints if your backend supports multiple metrics for carpet, etc.
    // But to keep it consistent, we'll pass "metric=" param to the server, so it can handle it.

    // Build the base chart URL
    String chartUrl = "";
    final startParam = (startDate != null)
        ? "${DateFormat('yyyy-MM-dd').format(startDate!)}T00:00:00"
        : "";
    final endParam = (endDate != null)
        ? "${DateFormat('yyyy-MM-dd').format(endDate!)}T23:59:59"
        : "";

    // We'll add a &metric=whatever
    final metricParam = "&metric=$selectedMetric";

    if (selectedMetric == "Temperature") {
      if (temperatureViewMode == "carpet") {
        // Carpet Plot
        chartUrl =
            "http://localhost:9090/generateCarpetPlot?nocache=${DateTime.now().millisecondsSinceEpoch}";
      } else {
        // "line" => line chart
        chartUrl =
            "http://localhost:9090/generateLineChart?nocache=${DateTime.now().millisecondsSinceEpoch}";
      }
    } else {
      // For other metrics, let's just show line chart as an example
      chartUrl =
          "http://localhost:9090/generateLineChart?nocache=${DateTime.now().millisecondsSinceEpoch}";
    }

    // Add start, end, metric if present
    if (startParam.isNotEmpty) {
      chartUrl += "&start=$startParam";
    }
    if (endParam.isNotEmpty) {
      chartUrl += "&end=$endParam";
    }
    chartUrl += metricParam;

    // Now load from that URL
    return Image.network(
      chartUrl,
      errorBuilder: (ctx, error, stack) {
        return Text("Error loading chart for $selectedMetric");
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const CircularProgressIndicator();
      },
    );
  }

  /// Downloads the currently displayed chart image
  /// Simplest approach for Web: open the same chart URL in a new tab with content-disposition
  /// For Mobile: you'd need actual file writing logic or a share plugin
  Future<void> _downloadChart() async {
    // We'll just open the same chart URL in a new tab (if on web).
    // For demonstration, we'll print the URL or do nothing.
    // If you're on Flutter web, you could do:
    /*
    final chartUrl = _buildChartUrlForDownload();
    html.window.open(chartUrl, "_blank");
    */
    print("Download Chart not fully implemented (platform-specific).");
  }

  /// Exports CSV for the selected metric & date range
  /// We'll call `/exportCsv?start=...&end=...&metric=...` from the backend
  Future<void> _exportCsv() async {
    final baseUrl = "http://localhost:9090/exportCsv";
    final startParam = (startDate != null)
        ? "${DateFormat('yyyy-MM-dd').format(startDate!)}T00:00:00"
        : "";
    final endParam = (endDate != null)
        ? "${DateFormat('yyyy-MM-dd').format(endDate!)}T23:59:59"
        : "";
    String reqUrl = "$baseUrl?metric=$selectedMetric";

    if (startParam.isNotEmpty) {
      reqUrl += "&start=$startParam";
    }
    if (endParam.isNotEmpty) {
      reqUrl += "&end=$endParam";
    }
    // We can do a simple GET and then handle the CSV text
    try {
      final uri = Uri.parse(reqUrl);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final csvText = response.body;
        // For web, you might create a Blob and trigger a download, etc.
        print("Exported CSV with length = ${csvText.length}");
      } else {
        print("Error exporting CSV: ${response.statusCode}");
      }
    } catch (e) {
      print("Exception in _exportCsv: $e");
    }
  }
}
