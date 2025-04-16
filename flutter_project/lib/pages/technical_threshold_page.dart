import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../app_config.dart';

class TechnicalThresholdPage extends StatefulWidget {
  final String username;
  final String? location;

  const TechnicalThresholdPage({
    Key? key,
    required this.username,
    required this.location,
  }) : super(key: key);

  @override
  State<TechnicalThresholdPage> createState() => _TechnicalThresholdPageState();
}

class _TechnicalThresholdPageState extends State<TechnicalThresholdPage> {
  // static const String REGISTRY_BASE_URL = "http://registry:8081";
  static String get REGISTRY_BASE_URL => AppConfig.registryUrl;

  bool isLoading = false;
  bool isError = false;
  String errorMessage = "";

  // Entire settings fetched from the registry
  Map<String, dynamic> currentApartmentSettings = <String, dynamic>{};
  Map<String, dynamic> baseSettings = <String, dynamic>{};

  // Ventilation & Adaptive Category
  String ventilationType = "nat"; // "nat" or "mec"
  String adaptiveTempCategory = "2"; // "1", "2", or "3"

  // ----- mechanical_temp_cold arrays ( G => 2, Y => 2, R => 4 ) -----
  // We do not display the 4 R fields in the UI. Instead, we keep them in memory.
  final TextEditingController coldG1 = TextEditingController();
  final TextEditingController coldG2 = TextEditingController();
  final TextEditingController coldY1 = TextEditingController(); // Y-min
  final TextEditingController coldY2 = TextEditingController(); // Y-max
  List<double> coldR = [0.0, 18.0, 26.0, 100.0];

  // ----- mechanical_temp_warm arrays ( G => 2, Y => 2, R => 4 ) -----
  final TextEditingController warmG1 = TextEditingController();
  final TextEditingController warmG2 = TextEditingController();
  final TextEditingController warmY1 = TextEditingController(); // Y-min
  final TextEditingController warmY2 = TextEditingController(); // Y-max
  List<double> warmR = [0.0, 20.0, 27.0, 100.0];

  // ----- humidity arrays ( G => 2, Y => 2, R => 4 ) -----
  final TextEditingController humG1 = TextEditingController();
  final TextEditingController humG2 = TextEditingController();
  final TextEditingController humY1 = TextEditingController(); // Y-min
  final TextEditingController humY2 = TextEditingController(); // Y-max
  List<double> humR = [0.0, 30.0, 70.0, 100.0];

  // ----- CO2 natural thresholds -----
  final TextEditingController co2NatG = TextEditingController();
  final TextEditingController co2NatY = TextEditingController();
  final TextEditingController co2NatR = TextEditingController();

  // ----- CO2 mechanical thresholds -----
  final TextEditingController co2MechTooGood = TextEditingController();
  final TextEditingController co2MechG = TextEditingController();
  final TextEditingController co2MechY = TextEditingController();
  final TextEditingController co2MechR = TextEditingController();
  final TextEditingController co2MechExtreme = TextEditingController();

  // ----- Overall Score Classification -----
  final TextEditingController overallG = TextEditingController();
  final TextEditingController overallY = TextEditingController();
  final TextEditingController overallR = TextEditingController();

  // ----- Weights (6 symmetrical fields, no iEQi) -----
  final TextEditingController weightTemp = TextEditingController();
  final TextEditingController weightHumidity = TextEditingController();
  final TextEditingController weightCo2 = TextEditingController();
  final TextEditingController weightPmv = TextEditingController();
  final TextEditingController weightPpd = TextEditingController();
  final TextEditingController weightIcone = TextEditingController();

  // ----- Personal "values": met, clo_warm, clo_cold -----
  final TextEditingController metController = TextEditingController();
  final TextEditingController cloWarmController = TextEditingController();
  final TextEditingController cloColdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCurrentSettings();
  }

  /// Fetch the current settings from the registry
  Future<void> _fetchCurrentSettings() async {
    if (widget.location == null) {
      setState(() {
        isError = true;
        errorMessage = "No apartment location selected.";
      });
      return;
    }

    setState(() {
      isLoading = true;
      isError = false;
      errorMessage = "";
    });

    try {
      // 1) GET /apartments
      final aptResp = await http.get(Uri.parse("$REGISTRY_BASE_URL/apartments"));
      if (aptResp.statusCode == 200) {
        final List<dynamic> apartments = json.decode(aptResp.body);
        Map<String, dynamic>? targetApt;
        for (final apt in apartments) {
          if (apt["apartmentId"] == widget.location) {
            targetApt = apt as Map<String, dynamic>;
            break;
          }
        }
        if (targetApt == null) {
          setState(() {
            isLoading = false;
            isError = true;
            errorMessage = "Apartment not found in registry.";
          });
          return;
        }

        // Ensure "settings" field
        if (targetApt["settings"] == null) {
          targetApt["settings"] = <String, dynamic>{};
        }
        currentApartmentSettings = Map<String, dynamic>.from(targetApt["settings"]);

        // 2) GET /base_settings
        final baseResp = await http.get(Uri.parse("$REGISTRY_BASE_URL/base_settings"));
        if (baseResp.statusCode == 200) {
          baseSettings = json.decode(baseResp.body) as Map<String, dynamic>;
        } else {
          baseSettings = <String, dynamic>{};
        }

        // Fill text fields
        _populateFieldsFromSettings();

        setState(() => isLoading = false);
      } else {
        setState(() {
          isLoading = false;
          isError = true;
          errorMessage =
              "Failed fetching apartments: ${aptResp.statusCode} - ${aptResp.reasonPhrase}";
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMessage = "Error: $e";
      });
    }
  }

  /// Populate text fields with the current settings
  void _populateFieldsFromSettings() {
    final Map<String, dynamic> thresholds =
        (currentApartmentSettings["thresholds"] ?? <String, dynamic>{}) as Map<String, dynamic>;
    final Map<String, dynamic> values =
        (currentApartmentSettings["values"] ?? <String, dynamic>{}) as Map<String, dynamic>;
    final Map<String, dynamic> weights =
        (currentApartmentSettings["weights"] ?? <String, dynamic>{}) as Map<String, dynamic>;

    // Ventilation
    final ventVal = values["ventilation"]?.toString() ?? "nat";
    ventilationType = (ventVal == "mec") ? "mec" : "nat";

    // Adaptive Category
    adaptiveTempCategory = thresholds["adaptive_temp_category"]?.toString() ?? "2";

    // mechanical_temp_cold => arrays (G => 2, Y => 2, R => 4)
    final cold = thresholds["mechanical_temp_cold"] as Map<String, dynamic>? ?? {};
    final List<dynamic> coldGArr = (cold["G"] is List) ? cold["G"] : [20.0, 23.0];
    final List<dynamic> coldYArr = (cold["Y"] is List) ? cold["Y"] : [18.0, 26.0];
    final List<dynamic> coldRArr = (cold["R"] is List) ? cold["R"] : [-100.0, 18.0, 26.0, 100.0];

    // G-min / G-max
    coldG1.text = coldGArr.isNotEmpty ? coldGArr[0].toString() : "20.0";
    coldG2.text = coldGArr.length > 1 ? coldGArr[1].toString() : "23.0";

    // Y-min / Y-max
    coldY1.text = coldYArr.isNotEmpty ? coldYArr[0].toString() : "18.0";
    coldY2.text = coldYArr.length > 1 ? coldYArr[1].toString() : "26.0";

    // R array, but do not display in UI
    // We keep the first and last as extremes, the middle as Y1, Y2
    coldR = [
      coldRArr.isNotEmpty ? coldRArr[0].toDouble() : -100.0,
      coldRArr.length > 1 ? coldRArr[1].toDouble() : 18.0,
      coldRArr.length > 2 ? coldRArr[2].toDouble() : 26.0,
      coldRArr.length > 3 ? coldRArr[3].toDouble() : 100.0,
    ];

    // mechanical_temp_warm => arrays
    final warm = thresholds["mechanical_temp_warm"] as Map<String, dynamic>? ?? {};
    final List<dynamic> warmGArr = (warm["G"] is List) ? warm["G"] : [22.0, 26.0];
    final List<dynamic> warmYArr = (warm["Y"] is List) ? warm["Y"] : [20.0, 27.0];
    final List<dynamic> warmRArr = (warm["R"] is List) ? warm["R"] : [-100.0, 20.0, 27.0, 100.0];

    warmG1.text = warmGArr.isNotEmpty ? warmGArr[0].toString() : "22.0";
    warmG2.text = warmGArr.length > 1 ? warmGArr[1].toString() : "26.0";

    warmY1.text = warmYArr.isNotEmpty ? warmYArr[0].toString() : "20.0";
    warmY2.text = warmYArr.length > 1 ? warmYArr[1].toString() : "27.0";

    warmR = [
      warmRArr.isNotEmpty ? warmRArr[0].toDouble() : -100.0,
      warmRArr.length > 1 ? warmRArr[1].toDouble() : 20.0,
      warmRArr.length > 2 ? warmRArr[2].toDouble() : 27.0,
      warmRArr.length > 3 ? warmRArr[3].toDouble() : 100.0,
    ];

    // humidity => arrays
    final hum = thresholds["humidity"] as Map<String, dynamic>? ?? {};
    final List<dynamic> humGArr = (hum["G"] is List) ? hum["G"] : [40.0, 60.0];
    final List<dynamic> humYArr = (hum["Y"] is List) ? hum["Y"] : [30.0, 70.0];
    final List<dynamic> humRArr = (hum["R"] is List) ? hum["R"] : [0.0, 30.0, 70.0, 100.0];

    humG1.text = humGArr.isNotEmpty ? humGArr[0].toString() : "40.0";
    humG2.text = humGArr.length > 1 ? humGArr[1].toString() : "60.0";

    humY1.text = humYArr.isNotEmpty ? humYArr[0].toString() : "30.0";
    humY2.text = humYArr.length > 1 ? humYArr[1].toString() : "70.0";

    humR = [
      humRArr.isNotEmpty ? humRArr[0].toDouble() : 0.0,
      humRArr.length > 1 ? humRArr[1].toDouble() : 30.0,
      humRArr.length > 2 ? humRArr[2].toDouble() : 70.0,
      humRArr.length > 3 ? humRArr[3].toDouble() : 100.0,
    ];

    // co2_natural
    final co2Nat = thresholds["co2_natural"] as Map<String, dynamic>? ?? {};
    co2NatG.text = (co2Nat["G"] ?? 1200).toString();
    co2NatY.text = (co2Nat["Y"] ?? 1500).toString();
    co2NatR.text = (co2Nat["R"] ?? 10000).toString();

    // co2_mechanical
    final co2Mech = thresholds["co2_mechanical"] as Map<String, dynamic>? ?? {};
    co2MechTooGood.text = (co2Mech["Too Good"] ?? 600).toString();
    co2MechG.text = (co2Mech["G"] ?? 1200).toString();
    co2MechY.text = (co2Mech["Y"] ?? 1700).toString();
    co2MechR.text = (co2Mech["R"] ?? 2500).toString();
    co2MechExtreme.text = (co2Mech["Extreme"] ?? 10000).toString();

    // overall_score_classification
    final overallScore = thresholds["overall_score_classification"] as Map<String, dynamic>? ?? {};
    overallG.text = (overallScore["G"] ?? 100).toString();
    overallY.text = (overallScore["Y"] ?? 70).toString();
    overallR.text = (overallScore["R"] ?? 40).toString();

    // weights (no iEQi)
    weightTemp.text = (weights["temperature"] ?? 15.0).toString();
    weightHumidity.text = (weights["humidity"] ?? 10.0).toString();
    weightCo2.text = (weights["co2"] ?? 20.0).toString();
    weightPmv.text = (weights["pmv"] ?? 15.0).toString();
    weightPpd.text = (weights["ppd"] ?? 10.0).toString();
    weightIcone.text = (weights["icone"] ?? 15.0).toString();

    // Personal "values"
    metController.text = (values["met"] ?? 1.2).toString();
    cloWarmController.text = (values["clo_warm"] ?? 0.5).toString();
    cloColdController.text = (values["clo_cold"] ?? 1.0).toString();
  }

  /// Save all changes
  Future<void> _saveAllChanges() async {
    if (widget.location == null) return;
    setState(() {
      isLoading = true;
      isError = false;
      errorMessage = "";
    });

    // mechanical_temp_cold arrays
    // R array: first/last are the extremes, middle two are y-min / y-max
    final List<double> cG = [
      double.tryParse(coldG1.text) ?? 20.0,
      double.tryParse(coldG2.text) ?? 23.0,
    ];
    final List<double> cY = [
      double.tryParse(coldY1.text) ?? 18.0,
      double.tryParse(coldY2.text) ?? 26.0,
    ];
    // keep extremes from memory for coldR[0] and coldR[3]
    // set coldR[1] = Y-min, coldR[2] = Y-max
    final double cYmin = cY[0];
    final double cYmax = cY[1];
    coldR[1] = cYmin;
    coldR[2] = cYmax;

    // mechanical_temp_warm
    final List<double> wG = [
      double.tryParse(warmG1.text) ?? 22.0,
      double.tryParse(warmG2.text) ?? 26.0,
    ];
    final List<double> wY = [
      double.tryParse(warmY1.text) ?? 20.0,
      double.tryParse(warmY2.text) ?? 27.0,
    ];
    final double wYmin = wY[0];
    final double wYmax = wY[1];
    warmR[1] = wYmin;
    warmR[2] = wYmax;

    // humidity
    final List<double> hG = [
      double.tryParse(humG1.text) ?? 40.0,
      double.tryParse(humG2.text) ?? 60.0,
    ];
    final List<double> hY = [
      double.tryParse(humY1.text) ?? 30.0,
      double.tryParse(humY2.text) ?? 70.0,
    ];
    final double hYmin = hY[0];
    final double hYmax = hY[1];
    humR[1] = hYmin;
    humR[2] = hYmax;

    // Build JSON body
    final Map<String, dynamic> body = <String, dynamic>{
      "apartmentId": widget.location,
      "settings": <String, dynamic>{
        "thresholds": <String, dynamic>{
          "adaptive_temp_category": int.tryParse(adaptiveTempCategory) ?? 2,

          "mechanical_temp_cold": <String, dynamic>{
            "G": cG,
            "Y": cY,
            "R": coldR,
          },
          "mechanical_temp_warm": <String, dynamic>{
            "G": wG,
            "Y": wY,
            "R": warmR,
          },
          "humidity": <String, dynamic>{
            "G": hG,
            "Y": hY,
            "R": humR,
          },
          "co2_natural": <String, dynamic>{
            "G": double.tryParse(co2NatG.text) ?? 1200.0,
            "Y": double.tryParse(co2NatY.text) ?? 1500.0,
            "R": double.tryParse(co2NatR.text) ?? 10000.0,
          },
          "co2_mechanical": <String, dynamic>{
            "Too Good": double.tryParse(co2MechTooGood.text) ?? 600.0,
            "G": double.tryParse(co2MechG.text) ?? 1200.0,
            "Y": double.tryParse(co2MechY.text) ?? 1700.0,
            "R": double.tryParse(co2MechR.text) ?? 2500.0,
            "Extreme": double.tryParse(co2MechExtreme.text) ?? 10000.0,
          },
          "overall_score_classification": <String, dynamic>{
            "G": double.tryParse(overallG.text) ?? 100.0,
            "Y": double.tryParse(overallY.text) ?? 70.0,
            "R": double.tryParse(overallR.text) ?? 40.0,
          },
        },
        "values": <String, dynamic>{
          "ventilation": ventilationType == "mec" ? "mec" : "nat",
          "met": double.tryParse(metController.text) ?? 1.2,
          "clo_warm": double.tryParse(cloWarmController.text) ?? 0.5,
          "clo_cold": double.tryParse(cloColdController.text) ?? 1.0,
        },
        "weights": <String, dynamic>{
          "temperature": double.tryParse(weightTemp.text) ?? 15.0,
          "humidity": double.tryParse(weightHumidity.text) ?? 10.0,
          "co2": double.tryParse(weightCo2.text) ?? 20.0,
          "pmv": double.tryParse(weightPmv.text) ?? 15.0,
          "ppd": double.tryParse(weightPpd.text) ?? 10.0,
          "icone": double.tryParse(weightIcone.text) ?? 15.0,
        }
      }
    };

    // PUT /modify_settings
    final Uri url = Uri.parse("$REGISTRY_BASE_URL/modify_settings");
    try {
      final resp = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );
      if (resp.statusCode == 200) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saved changes successfully"),
            backgroundColor: Colors.green,
          ),
        );
        _fetchCurrentSettings();
      } else {
        setState(() {
          isLoading = false;
          isError = true;
          errorMessage =
              "Error saving: ${resp.statusCode} - ${resp.reasonPhrase}\n${resp.body}";
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMessage = "Connection error while saving: $e";
      });
    }
  }

  /// Reset all thresholds to base defaults
  Future<void> _resetAll() async {
    if (widget.location == null) return;
    setState(() {
      isLoading = true;
      isError = false;
      errorMessage = "";
    });

    final Uri url = Uri.parse("$REGISTRY_BASE_URL/reset_settings");
    final Map<String, dynamic> body = <String, dynamic>{"apartmentId": widget.location};

    try {
      final resp = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All thresholds reset to base defaults."),
            backgroundColor: Colors.green,
          ),
        );
        _fetchCurrentSettings();
      } else {
        setState(() {
          isError = true;
          errorMessage = "Error resetting all: ${resp.statusCode} - ${resp.reasonPhrase}";
        });
      }
    } catch (e) {
      setState(() {
        isError = true;
        errorMessage = "Connection error while resetting all: $e";
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Reset only a certain section, e.g. "mechanical_temp_warm"
  Future<void> _resetSection(String pathKey) async {
    if (widget.location == null) return;
    if (baseSettings.isEmpty) {
      await _fetchCurrentSettings();
      if (baseSettings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No base settings found."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final Map<String, dynamic> partialThresholds = <String, dynamic>{};
    final Map<String, dynamic> partialValues = <String, dynamic>{};
    final Map<String, dynamic> partialWeights = <String, dynamic>{};

    dynamic bs(Object? x) => x; // short helper

    switch (pathKey) {
      case "mechanical_temp_cold":
        partialThresholds["mechanical_temp_cold"] =
            bs(baseSettings["thresholds"])["mechanical_temp_cold"] ??
                {
                  "G": [20.0, 23.0],
                  "Y": [18.0, 26.0],
                  "R": [-100.0, 18.0, 26.0, 100.0]
                };
        break;

      case "mechanical_temp_warm":
        partialThresholds["mechanical_temp_warm"] =
            bs(baseSettings["thresholds"])["mechanical_temp_warm"] ??
                {
                  "G": [22.0, 26.0],
                  "Y": [20.0, 27.0],
                  "R": [-100.0, 20.0, 27.0, 100.0]
                };
        break;

      case "humidity":
        partialThresholds["humidity"] =
            bs(baseSettings["thresholds"])["humidity"] ??
                {
                  "G": [40, 60],
                  "Y": [30, 70],
                  "R": [0, 30, 70, 100]
                };
        break;

      case "co2_natural":
        partialThresholds["co2_natural"] =
            bs(baseSettings["thresholds"])["co2_natural"] ??
                {"G": 1200.0, "Y": 1500.0, "R": 10000.0};
        break;

      case "co2_mechanical":
        partialThresholds["co2_mechanical"] =
            bs(baseSettings["thresholds"])["co2_mechanical"] ??
                {
                  "Too Good": 600.0,
                  "G": 1200.0,
                  "Y": 1700.0,
                  "R": 2500.0,
                  "Extreme": 10000.0
                };
        break;

      case "overall_score_classification":
        partialThresholds["overall_score_classification"] =
            bs(baseSettings["thresholds"])["overall_score_classification"] ??
                {"G": 100, "Y": 70, "R": 40};
        break;

      case "weights":
        partialWeights.addAll(bs(baseSettings["weights"]) ?? {
          "temperature": 15.0,
          "humidity": 10.0,
          "co2": 20.0,
          "pmv": 15.0,
          "ppd": 10.0,
          "icone": 15.0
        });
        break;

      case "personal_values":
        partialValues["met"] = bs(baseSettings["values"])["met"] ?? 1.2;
        partialValues["clo_warm"] = bs(baseSettings["values"])["clo_warm"] ?? 0.5;
        partialValues["clo_cold"] = bs(baseSettings["values"])["clo_cold"] ?? 1.0;
        break;
    }

    final Map<String, dynamic> settingsMap = <String, dynamic>{};
    if (partialThresholds.isNotEmpty) {
      settingsMap["thresholds"] = partialThresholds;
    }
    if (partialValues.isNotEmpty) {
      settingsMap["values"] = partialValues;
    }
    if (partialWeights.isNotEmpty) {
      settingsMap["weights"] = partialWeights;
    }

    // ensure at least "thresholds": {}
    if (settingsMap.isEmpty) {
      settingsMap["thresholds"] = <String, dynamic>{};
    }

    final Map<String, dynamic> body = <String, dynamic>{
      "apartmentId": widget.location,
      "settings": settingsMap
    };

    setState(() => isLoading = true);

    final Uri url = Uri.parse("$REGISTRY_BASE_URL/modify_settings");
    try {
      final resp = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Section reset to base."),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchCurrentSettings();
      } else {
        setState(() {
          isError = true;
          errorMessage =
              "Error resetting $pathKey: ${resp.statusCode} - ${resp.reasonPhrase}\n${resp.body}";
        });
      }
    } catch (e) {
      setState(() {
        isError = true;
        errorMessage = "Connection error while resetting $pathKey: $e";
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// A helper that builds a labeled text field. We do not show R fields,
  /// we only show G min, G max, Y min, Y max in the UI.
  Widget _buildLabeledTextField(
    String label,
    TextEditingController controller, {
    VoidCallback? onChangedCallback,
  }) {
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onChanged: (_) {
              if (onChangedCallback != null) {
                onChangedCallback();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExpansionTile({
    required String title,
    required String sectionKey,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          color: Theme.of(context).primaryColor,
          onPressed: () => _resetSection(sectionKey),
          tooltip: "Reset this section to base",
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent() {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Card(
            margin: const EdgeInsets.all(16),
            elevation: 5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Threshold & Settings for ${widget.location} (User: ${widget.username})",
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColorDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 228, 228, 228),
                      ),
                      onPressed: _resetAll,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text("Reset ALL"),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Ventilation & Category
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _buildVentilationDropdown()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildAdaptiveDropdown()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // mechanical_temp_cold
                  _buildExpansionTile(
                    title: "Mechanical Temperature (Cold Season)",
                    sectionKey: "mechanical_temp_cold",
                    children: [
                      _buildLabeledTextField("G Min", coldG1),
                      _buildLabeledTextField("G Max", coldG2),
                      // Y-min, Y-max
                      _buildLabeledTextField(
                        "Y Min",
                        coldY1,
                        onChangedCallback: () {
                          // automatically update coldR[1]
                          final val = double.tryParse(coldY1.text) ?? 18.0;
                          setState(() {
                            coldR[1] = val;
                          });
                        },
                      ),
                      _buildLabeledTextField(
                        "Y Max",
                        coldY2,
                        onChangedCallback: () {
                          final val = double.tryParse(coldY2.text) ?? 26.0;
                          setState(() {
                            coldR[2] = val;
                          });
                        },
                      ),
                    ],
                  ),

                  // mechanical_temp_warm
                  _buildExpansionTile(
                    title: "Mechanical Temperature (Warm Season)",
                    sectionKey: "mechanical_temp_warm",
                    children: [
                      _buildLabeledTextField("G Min", warmG1),
                      _buildLabeledTextField("G Max", warmG2),
                      _buildLabeledTextField(
                        "Y Min",
                        warmY1,
                        onChangedCallback: () {
                          final val = double.tryParse(warmY1.text) ?? 20.0;
                          setState(() {
                            warmR[1] = val;
                          });
                        },
                      ),
                      _buildLabeledTextField(
                        "Y Max",
                        warmY2,
                        onChangedCallback: () {
                          final val = double.tryParse(warmY2.text) ?? 27.0;
                          setState(() {
                            warmR[2] = val;
                          });
                        },
                      ),
                    ],
                  ),

                  // humidity
                  _buildExpansionTile(
                    title: "Humidity",
                    sectionKey: "humidity",
                    children: [
                      _buildLabeledTextField("G Min", humG1),
                      _buildLabeledTextField("G Max", humG2),
                      _buildLabeledTextField(
                        "Y Min",
                        humY1,
                        onChangedCallback: () {
                          final val = double.tryParse(humY1.text) ?? 30.0;
                          setState(() {
                            humR[1] = val;
                          });
                        },
                      ),
                      _buildLabeledTextField(
                        "Y Max",
                        humY2,
                        onChangedCallback: () {
                          final val = double.tryParse(humY2.text) ?? 70.0;
                          setState(() {
                            humR[2] = val;
                          });
                        },
                      ),
                    ],
                  ),

                  // CO2 for Natural Ventilation
                  _buildExpansionTile(
                    title: "CO2 for Natural Ventilation",
                    sectionKey: "co2_natural",
                    children: [
                      _buildLabeledTextField("Green", co2NatG),
                      _buildLabeledTextField("Yellow", co2NatY),
                      _buildLabeledTextField("Red", co2NatR),
                    ],
                  ),

                  // CO2 for Mechanical Ventilation
                  _buildExpansionTile(
                    title: "CO2 for Mechanical Ventilation",
                    sectionKey: "co2_mechanical",
                    children: [
                      _buildLabeledTextField("Too Good", co2MechTooGood),
                      _buildLabeledTextField("Green", co2MechG),
                      _buildLabeledTextField("Yellow", co2MechY),
                      _buildLabeledTextField("Red", co2MechR),
                      _buildLabeledTextField("Extreme", co2MechExtreme),
                    ],
                  ),

                  // Overall classification
                  _buildExpansionTile(
                    title: "Overall Score Classification",
                    sectionKey: "overall_score_classification",
                    children: [
                      _buildLabeledTextField("Green", overallG),
                      _buildLabeledTextField("Yellow", overallY),
                      _buildLabeledTextField("Red", overallR),
                    ],
                  ),

                  // Weights
                  _buildExpansionTile(
                    title: "Weights (KPI Calculations)",
                    sectionKey: "weights",
                    children: [
                      _buildLabeledTextField("Temperature", weightTemp),
                      _buildLabeledTextField("Humidity", weightHumidity),
                      _buildLabeledTextField("CO2", weightCo2),
                      _buildLabeledTextField("PMV", weightPmv),
                      _buildLabeledTextField("PPD", weightPpd),
                      _buildLabeledTextField("iCone", weightIcone),
                    ],
                  ),

                  // Personal values
                  _buildExpansionTile(
                    title: "Met & Clothing Level",
                    sectionKey: "personal_values",
                    children: [
                      _buildLabeledTextField("Met", metController),
                      _buildLabeledTextField("Clothing Warm", cloWarmController),
                      _buildLabeledTextField("Clothing Cold", cloColdController),
                    ],
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _saveAllChanges,
                    icon: const Icon(Icons.save),
                    label: const Text("Save All Changes"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVentilationDropdown() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueGrey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text("Ventilation:", style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: ventilationType,
              items: const [
                DropdownMenuItem(value: "nat", child: Text("Natural")),
                DropdownMenuItem(value: "mec", child: Text("Mechanical")),
              ],
              onChanged: (val) {
                setState(() {
                  ventilationType = val ?? "nat";
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdaptiveDropdown() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueGrey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text("Adaptive Cat:", style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: adaptiveTempCategory,
              items: const [
                DropdownMenuItem(value: "1", child: Text("1")),
                DropdownMenuItem(value: "2", child: Text("2")),
                DropdownMenuItem(value: "3", child: Text("3")),
              ],
              onChanged: (val) {
                setState(() {
                  adaptiveTempCategory = val ?? "2";
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (isError) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("Error: $errorMessage", style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildBodyContent(),
    );
  }
}
