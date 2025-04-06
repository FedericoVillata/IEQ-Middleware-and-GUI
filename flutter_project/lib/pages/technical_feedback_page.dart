import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';

class TechnicalFeedbackPage extends StatefulWidget {
  final String username;     // The logged technical user
  final String? location;    // The selected apartment ID

  const TechnicalFeedbackPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalFeedbackPage> createState() => _TechnicalFeedbackPageState();
}

class _TechnicalFeedbackPageState extends State<TechnicalFeedbackPage> {
  // Adaptor endpoint
  static const String adaptorUrl = "http://localhost:8080";

  // The feedback categories available
  final feedbackTypes = [
    "Temperature Perception",
    "Humidity Perception",
    "Environmental Satisfaction",
    "Service Rating",
  ];
  String selectedFeedback = "Temperature Perception";

  // Time range selection, just like in technical_home_page.dart
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
  String selectedDuration = "168"; // default to "1 week" (168 hours)

  // The distribution ratingCounts[r-1] => how many times rating=r was given
  List<int> ratingCounts = [0, 0, 0, 0, 0];

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchFeedbackData();
  }

  /// Convert the user-friendly label to the underlying Influx field name
  /// "Temperature Perception" => "Temperature"
  String _mapFeedbackToField(String label) {
    switch (label) {
      case "Temperature Perception":
        return "Temperature";
      case "Humidity Perception":
        return "Humidity";
      case "Environmental Satisfaction":
        return "Environment";
      case "Service Rating":
        return "Service";
      default:
        return "Unknown";
    }
  }

  /// Fetch data from: GET /getAllApartmentData/<techUser>/<apartment>?duration=...
  /// Filter by room="Feedback" & measurement=the mapped field => build rating distribution
  Future<void> _fetchFeedbackData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      ratingCounts = [0, 0, 0, 0, 0];
    });

    final apartmentId = widget.location ?? "apartment0";
    final duration = selectedDuration;
    final measurementNeeded = _mapFeedbackToField(selectedFeedback);

    final url =
        "$adaptorUrl/getAllApartmentData/${widget.username}/$apartmentId?duration=$duration";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        setState(() {
          isLoading = false;
          errorMessage = "Adaptor error: ${response.statusCode}\n${response.body}";
        });
        return;
      }

      final raw = json.decode(response.body);
      if (raw is! List) {
        setState(() {
          isLoading = false;
          errorMessage = "Adaptor returned non-list JSON";
        });
        return;
      }

      // Filter: room=="Feedback" and measurement==measurementNeeded
      for (var item in raw) {
        if (item is Map<String, dynamic>) {
          if (item["room"] == "Feedback" && item["measurement"] == measurementNeeded) {
            final val = item["v"];
            if (val is num) {
              final rating = val.toInt();
              if (rating >= 1 && rating <= 5) {
                ratingCounts[rating - 1] += 1;
              }
            }
          }
        }
      }

      setState(() {
        isLoading = false;
        // ratingCounts updated
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Connection/Parsing error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 1) Time range selection (dropdown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: const Text("Select Duration"),
                trailing: DropdownButton<String>(
                  value: selectedDuration,
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() => selectedDuration = val);
                      await _fetchFeedbackData();
                    }
                  },
                  items: durationOptions.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.value,
                      child: Text(entry.key),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // 2) Feedback type selection
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: feedbackTypes.map((f) {
                final bool sel = (f == selectedFeedback);
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: sel ? Colors.indigo : Colors.blueGrey,
                    ),
                    child: Text(f, style: const TextStyle(color: Colors.white)),
                    onPressed: () async {
                      setState(() => selectedFeedback = f);
                      await _fetchFeedbackData();
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // 3) The bar chart or loading/error
          Expanded(
            child: Center(
              child: isLoading
                  ? const CircularProgressIndicator()
                  : (errorMessage != null
                      ? Text(errorMessage!, style: const TextStyle(color: Colors.red))
                      : _buildBarChart()),
            ),
          ),
        ],
      ),
    );
  }

  /// We have ratingCounts[0..4], each representing how many times rating i+1 was selected
  /// x-axis => 1..5, y-axis => ratingCounts
  Widget _buildBarChart() {
    // If there's no data (i.e. sum(ratingCounts)==0), we can display "No data"
    final totalFeedbacks = ratingCounts.reduce((a, b) => a + b);
    if (totalFeedbacks == 0) {
      return const Text("No feedback data found in this period.");
    }

    // Build 5 bars => x=1..5
    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < 5; i++) {
      final count = ratingCounts[i].toDouble();
      barGroups.add(
        BarChartGroupData(
          x: i + 1, // rating=1..5
          barRods: [
            BarChartRodData(
              toY: count,
              width: 22,
              color: Colors.blue,
            )
          ],
        ),
      );
    }

    // Y-axis max => add a bit of headroom
    final maxCount = ratingCounts.reduce((a, b) => a > b ? a : b);
    final yMax = (maxCount + 2).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: BarChart(
        BarChartData(
          maxY: yMax,
          barGroups: barGroups,
          barTouchData: BarTouchData(enabled: true),

          gridData: FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),

          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1, // show integer steps on Y
                getTitlesWidget: (value, meta) {
                  // Show integer if value is near an integer
                  if (value % 1 == 0) {
                    return Text(value.toInt().toString());
                  }
                  return const SizedBox();
                },
              ),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final int xVal = value.toInt();
                  return Text(xVal.toString());
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
