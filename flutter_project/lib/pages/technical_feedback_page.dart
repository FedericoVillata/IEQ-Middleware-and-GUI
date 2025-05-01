import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../app_config.dart';
import '../widgets/suggestions_bell.dart';

// ---------------------------------------------------------------------------
// TechnicalFeedbackPage – fast & stable
//   • Uses getAllApartmentData with a *measurement* filter (smaller payload)
//   • Lightweight in‑place parsing (no isolate overhead)
//   • Keeps same UI: full‑width, 500‑px tall chart, dynamic X‑axis labels
// ---------------------------------------------------------------------------
class TechnicalFeedbackPage extends StatefulWidget {
  final String username;      // Technical user's ID
  final String? location;     // Selected apartment

  const TechnicalFeedbackPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalFeedbackPage> createState() => _TechnicalFeedbackPageState();
}

class _TechnicalFeedbackPageState extends State<TechnicalFeedbackPage> {
  // -----------------------------------------------------------------------
  //  Config & State --------------------------------------------------------
  // -----------------------------------------------------------------------
  static String get _adaptorUrl => AppConfig.adaptorUrl;

  final List<String> _feedbackTypes = [
    "Temperature Perception",
    "Humidity Perception",
    "Environmental Satisfaction",
    "Service Rating",
  ];
  String _selectedFeedback = "Temperature Perception";

  final Map<String, String> _durationOptions = {
    "1 day": "24",
    "3 days": "72",
    "1 week": "168",
    "1 month": "720",
    "3 months": "2160",
    "6 months": "4320",
    "1 year": "8760",
    "all": "999999",
  };
  String _selectedDuration = "168"; // default 1 week

  List<int> _ratingCounts = List.filled(5, 0);

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchFeedbackData();
  }

  // -----------------------------------------------------------------------
  //  Helpers ---------------------------------------------------------------
  // -----------------------------------------------------------------------
  String _mapFeedbackToField(String label) {
    switch (label) {
      case "Temperature Perception":
        return "Temperature"; // as stored in Influx
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

  String _ratingLabel(int rating) {
    switch (_selectedFeedback) {
      case "Temperature Perception":
        return [
          "Very Cold",
          "Cold",
          "Neutral",
          "Warm",
          "Very Warm",
        ][rating - 1];
      case "Humidity Perception":
        return [
          "Very Dry",
          "Dry",
          "Neutral",
          "Humid",
          "Very Humid",
        ][rating - 1];
      case "Environmental Satisfaction":
        return [
          "Very Unsatisfied",
          "Unsatisfied",
          "Neutral",
          "Satisfied",
          "Very Satisfied",
        ][rating - 1];
      case "Service Rating":
        return [
          "Poor",
          "Fair",
          "Average",
          "Good",
          "Excellent",
        ][rating - 1];
      default:
        return rating.toString();
    }
  }

  // -----------------------------------------------------------------------
  //  Data Fetch ------------------------------------------------------------
  // -----------------------------------------------------------------------
  Future<void> _fetchFeedbackData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _ratingCounts = List.filled(5, 0);
    });

    final String apartmentId = widget.location ?? "apartment0";
    final String fieldNeeded = _mapFeedbackToField(_selectedFeedback);

    // Smaller payload: filter by measurement directly
    final Uri url = Uri.parse(
      "$_adaptorUrl/getAllApartmentData/${widget.username}/$apartmentId?measurement=$fieldNeeded&duration=$_selectedDuration",
    );

    try {
      final http.Response resp = await http.get(url);
      if (resp.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Adaptor error: ${resp.statusCode} ${resp.reasonPhrase}";
        });
        return;
      }

      final dynamic decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Unexpected JSON format from adaptor.";
        });
        return;
      }

      final List<int> counts = List.filled(5, 0);
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          if (item['room'] == 'Feedback' && item['measurement'] == fieldNeeded) {
            final val = item['v'];
            if (val is num) {
              final int rating = val.toInt();
              if (rating >= 1 && rating <= 5) counts[rating - 1] += 1;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _ratingCounts = counts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Connection or parsing error: $e";
      });
    }
  }

  // -----------------------------------------------------------------------
  //  UI --------------------------------------------------------------------
  // -----------------------------------------------------------------------
  @override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      children: [
        // ── main content ────────────────────────────────────────────────
        Column(
          children: [
            // Duration selector ------------------------------------------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: const Text("Select Duration"),
                  trailing: DropdownButton<String>(
                    value: _selectedDuration,
                    onChanged: (val) async {
                      if (val == null) return;
                      setState(() => _selectedDuration = val);
                      await _fetchFeedbackData();
                    },
                    items: _durationOptions.entries
                        .map((e) => DropdownMenuItem(
                              value: e.value,
                              child: Text(e.key),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),

            // Feedback-type selector -------------------------------------------
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _feedbackTypes.map((f) {
                  final bool selected = (f == _selectedFeedback);
                  return Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            selected ? Colors.indigo : Colors.blueGrey,
                      ),
                      onPressed: () async {
                        setState(() => _selectedFeedback = f);
                        await _fetchFeedbackData();
                      },
                      child:
                          Text(f, style: const TextStyle(color: Colors.white)),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Chart / loading / error ------------------------------------------
            Expanded(
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : (_errorMessage != null
                        ? Text(_errorMessage!,
                            style: const TextStyle(color: Colors.red))
                        : _buildBarChart()),
              ),
            ),
          ],
        ),

        // ── Suggestions bell (top-right overlay) ─────────────────────────
        Positioned(
          // push it just below the normal app-bar height (56 px) + a little padding
          top: kToolbarHeight + 24,   // was: 12
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

  // -------------------------- Chart --------------------------------------
  Widget _buildBarChart() {
    final int totalVotes = _ratingCounts.reduce((a, b) => a + b);
    if (totalVotes == 0) {
      return const Text("No feedback data found in this period.");
    }

    final List<BarChartGroupData> barGroups = [];
    int maxCount = 0;
    for (int i = 0; i < 5; i++) {
      final int count = _ratingCounts[i];
      if (count > maxCount) maxCount = count;
      barGroups.add(
        BarChartGroupData(x: i + 1, barRods: [
          BarChartRodData(toY: count.toDouble(), width: 22, color: Colors.blue),
        ]),
      );
    }

    final double yMax = maxCount.toDouble() + 2; // headroom

    return Container(
      width: double.infinity,
      height: 500,
      alignment: Alignment.center,
      child: BarChart(
        BarChartData(
          maxY: yMax,
          barGroups: barGroups,
          barTouchData: BarTouchData(enabled: true),
          gridData: FlGridData(drawHorizontalLine: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameSize: 40,
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: RotatedBox(
                  quarterTurns: 0,
                  child: Text("Number of votes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, _) => value % 1 == 0 ? Text(value.toInt().toString()) : const SizedBox(),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameSize: 40,
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text("Rating", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final int xVal = value.toInt();
                  if (xVal >= 1 && xVal <= 5) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        _ratingLabel(xVal),
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
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
