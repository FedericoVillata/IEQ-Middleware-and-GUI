import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import '../app_config.dart';
import '../widgets/suggestions_bell.dart';

class TechnicalFeedbackPage extends StatefulWidget {
  final String username;    // The technical user's ID
  final String? location;   // The chosen apartment

  const TechnicalFeedbackPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalFeedbackPage> createState() => _TechnicalFeedbackPageState();
}

class _TechnicalFeedbackPageState extends State<TechnicalFeedbackPage> {
  //static const String adaptorUrl = "http://adaptor:8080";
  static String get adaptorUrl => AppConfig.adaptorUrl;

  // Feedback categories
  final feedbackTypes = [
    "Temperature Perception",
    "Humidity Perception",
    "Environmental Satisfaction",
    "Service Rating",
  ];
  String selectedFeedback = "Temperature Perception";

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
  String selectedDuration = "168"; // default to 1 week

  // ratingCounts[r-1] => how many times rating=r was submitted
  List<int> ratingCounts = [0, 0, 0, 0, 0];

  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchFeedbackData();
  }

  // Convert the UI label to the underlying Influx field
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

  /// GET /getAllApartmentData/<techUser>/<apartment>?duration=...
  /// Then filter by room="Feedback" and measurement=the chosen field => build rating distribution
  Future<void> _fetchFeedbackData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      ratingCounts = [0, 0, 0, 0, 0];
    });

    final apartmentId = widget.location ?? "apartment0";
    final fieldNeeded = _mapFeedbackToField(selectedFeedback);

    final url =
        "$adaptorUrl/getAllApartmentData/${widget.username}/$apartmentId?duration=$selectedDuration";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        setState(() {
          errorMessage = "Adaptor error: ${response.statusCode}\n${response.body}";
          isLoading = false;
        });
        return;
      }

      final raw = json.decode(response.body);
      if (raw is! List) {
        setState(() {
          errorMessage = "Adaptor returned non-list JSON!";
          isLoading = false;
        });
        return;
      }

      for (var item in raw) {
        if (item is Map<String, dynamic>) {
          if (item["room"] == "Feedback" && item["measurement"] == fieldNeeded) {
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
      });
    } catch (e) {
      setState(() {
        errorMessage = "Connection/Parsing error: $e";
        isLoading = false;
      });
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    body: Column(
      children: [
        // ──────────────────────────────────────────────────────────
        //  Duration selector
        // ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: const Text('Select Duration'),
              trailing: DropdownButton<String>(
                value: selectedDuration,
                onChanged: (val) async {
                  if (val != null) {
                    setState(() => selectedDuration = val);
                    await _fetchFeedbackData();
                  }
                },
                items: durationOptions.entries
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.value,
                        child: Text(entry.key),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),

        // ──────────────────────────────────────────────────────────
        //  Feedback-type selector  +  bell aligned right
        // ──────────────────────────────────────────────────────────
        // ──────────────────────────────────────────────────────────
//  Feedback-type buttons centred   +   bell on the far right
// ──────────────────────────────────────────────────────────
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  child: Row(
    children: [
      /// ① centred buttons ─────────────────────────────────────
      Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: feedbackTypes.map((type) {
            final bool isSelected = type == selectedFeedback;
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isSelected ? Colors.indigo : Colors.blueGrey,
                ),
                onPressed: () async {
                  setState(() => selectedFeedback = type);
                  await _fetchFeedbackData();
                },
                child: Text(type, style: const TextStyle(color: Colors.white)),
              ),
            );
          }).toList(),
        ),
      ),

      const SizedBox(width: 8),

      /// ② bell aligned to the right ───────────────────────────
      SuggestionsBell(
        location: widget.location,
        username: widget.username,
      ),
    ],
  ),
),


        // ──────────────────────────────────────────────────────────
        //  Chart area / loading / error
        // ──────────────────────────────────────────────────────────
        Expanded(
          child: Center(
            child: isLoading
                ? const CircularProgressIndicator()
                : (errorMessage != null
                    ? Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      )
                    : _buildBarChart()),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildBarChart() {
    // If no data (sum==0), show a simple text
    final total = ratingCounts.reduce((a, b) => a + b);
    if (total == 0) {
      return const Text("No feedback data found in this period.");
    }

    // Create bar groups for x=1..5
    final barGroups = <BarChartGroupData>[];
    int maxCount = 0;
    for (int i = 0; i < 5; i++) {
      final count = ratingCounts[i];
      if (count > maxCount) maxCount = count;
      barGroups.add(
        BarChartGroupData(
          x: i + 1,
          barRods: [
            BarChartRodData(
              toY: count.toDouble(),
              width: 22,
              color: Colors.blue,
            )
          ],
        ),
      );
    }

    // Add a bit of headroom
    final yMax = maxCount + 2.0;

    return Container(
      width: 1600,  // the size you prefer
      height: 900,
      alignment: Alignment.center,
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
              axisNameSize: 40, // more space to avoid cutting
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                // Rotate "Number of votes" so it fits
                child: RotatedBox(
                  quarterTurns: 0,
                  child: Text(
                    "Number of votes",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  if (value % 1 == 0) {
                    return Text(value.toInt().toString());
                  }
                  return const SizedBox();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameSize: 40,
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "Rating (1..5)",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final xVal = value.toInt();
                  if (xVal >= 1 && xVal <= 5) {
                    return Text(xVal.toString());
                  }
                  return const SizedBox();
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      ),
    );
  }
}
