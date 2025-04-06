import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  static const String REGISTRY_BASE_URL = "http://localhost:8081";

  bool isLoading = false;
  bool isError = false;
  String errorMessage = "";

  // Apartment settings from the registry
  Map<String, dynamic> currentApartmentSettings = <String, dynamic>{};
  Map<String, dynamic> baseSettings = <String, dynamic>{};

  // Ventilation & Adaptive Category
  String ventilationType = "nat"; // "nat" or "mec"
  String adaptiveTempCategory = "2"; // "1","2","3"

  // Mechanical Temperature (cold)
  final TextEditingController mechTempColdG = TextEditingController();
  final TextEditingController mechTempColdY = TextEditingController();
  final TextEditingController mechTempColdR = TextEditingController();

  // Mechanical Temperature (warm)
  final TextEditingController mechTempWarmG = TextEditingController();
  final TextEditingController mechTempWarmY = TextEditingController();
  final TextEditingController mechTempWarmR = TextEditingController();

  // Humidity => (G, Y, R)
  final TextEditingController humidityG = TextEditingController();
  final TextEditingController humidityY = TextEditingController();
  final TextEditingController humidityR = TextEditingController();

  // CO2 (natural)
  final TextEditingController co2NatG = TextEditingController();
  final TextEditingController co2NatY = TextEditingController();
  final TextEditingController co2NatR = TextEditingController();

  // CO2 (mechanical)
  final TextEditingController co2MechTooGood = TextEditingController();
  final TextEditingController co2MechG = TextEditingController();
  final TextEditingController co2MechY = TextEditingController();
  final TextEditingController co2MechR = TextEditingController();
  final TextEditingController co2MechExtreme = TextEditingController();

  // Overall Score
  final TextEditingController overallG = TextEditingController();
  final TextEditingController overallY = TextEditingController();
  final TextEditingController overallR = TextEditingController();

  // Weights
  final TextEditingController weightTemp = TextEditingController();
  final TextEditingController weightHumidity = TextEditingController();
  final TextEditingController weightCo2 = TextEditingController();
  final TextEditingController weightPmv = TextEditingController();
  final TextEditingController weightPpd = TextEditingController();
  final TextEditingController weightIcone = TextEditingController();
  final TextEditingController weightIeqi = TextEditingController();

  // Personal "values": met, clo_warm, clo_cold
  final TextEditingController metController = TextEditingController();
  final TextEditingController cloWarmController = TextEditingController();
  final TextEditingController cloColdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCurrentSettings();
  }

  // -------------------- FETCH AND PARSE --------------------
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

        // Make sure the apartment has "settings"
        if (targetApt["settings"] == null) {
          targetApt["settings"] = <String, dynamic>{};
        }
        currentApartmentSettings = Map<String, dynamic>.from(targetApt["settings"]);

        final baseResp = await http.get(Uri.parse("$REGISTRY_BASE_URL/base_settings"));
        if (baseResp.statusCode == 200) {
          baseSettings = json.decode(baseResp.body) as Map<String, dynamic>;
        } else {
          baseSettings = <String, dynamic>{};
        }

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

    // mechanical_temp_cold
    final mechCold = thresholds["mechanical_temp_cold"] as Map<String, dynamic>? ?? {};
    mechTempColdG.text = (mechCold["G"] ?? 23.0).toString();
    mechTempColdY.text = (mechCold["Y"] ?? 26.0).toString();
    mechTempColdR.text = (mechCold["R"] ?? 100.0).toString();

    // mechanical_temp_warm
    final mechWarm = thresholds["mechanical_temp_warm"] as Map<String, dynamic>? ?? {};
    mechTempWarmG.text = (mechWarm["G"] ?? 26.0).toString();
    mechTempWarmY.text = (mechWarm["Y"] ?? 27.0).toString();
    mechTempWarmR.text = (mechWarm["R"] ?? 100.0).toString();

    // humidity
    final humThr = thresholds["humidity"] as Map<String, dynamic>? ?? {};
    humidityG.text = (humThr["G"] ?? 60).toString();
    humidityY.text = (humThr["Y"] ?? 70).toString();
    humidityR.text = (humThr["R"] ?? 100).toString();

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

    // weights
    weightTemp.text = (weights["temperature"] ?? 15.0).toString();
    weightHumidity.text = (weights["humidity"] ?? 10.0).toString();
    weightCo2.text = (weights["co2"] ?? 20.0).toString();
    weightPmv.text = (weights["pmv"] ?? 15.0).toString();
    weightPpd.text = (weights["ppd"] ?? 10.0).toString();
    weightIcone.text = (weights["icone"] ?? 15.0).toString();
    weightIeqi.text = (weights["ieqi"] ?? 15.0).toString();

    // Personal "values"
    metController.text = (values["met"] ?? 1.2).toString();
    cloWarmController.text = (values["clo_warm"] ?? 0.5).toString();
    cloColdController.text = (values["clo_cold"] ?? 1.0).toString();
  }

  // -------------------- SAVE / RESET --------------------
  Future<void> _saveAllChanges() async {
    if (widget.location == null) return;
    setState(() {
      isLoading = true;
      isError = false;
      errorMessage = "";
    });

    final Map<String, dynamic> body = <String, dynamic>{
      "apartmentId": widget.location,
      "settings": <String, dynamic>{
        "thresholds": <String, dynamic>{
          "adaptive_temp_category": int.tryParse(adaptiveTempCategory) ?? 2,
          "mechanical_temp_cold": <String, dynamic>{
            "G": double.tryParse(mechTempColdG.text) ?? 23.0,
            "Y": double.tryParse(mechTempColdY.text) ?? 26.0,
            "R": double.tryParse(mechTempColdR.text) ?? 100.0,
          },
          "mechanical_temp_warm": <String, dynamic>{
            "G": double.tryParse(mechTempWarmG.text) ?? 26.0,
            "Y": double.tryParse(mechTempWarmY.text) ?? 27.0,
            "R": double.tryParse(mechTempWarmR.text) ?? 100.0,
          },
          "humidity": <String, dynamic>{
            "G": double.tryParse(humidityG.text) ?? 60.0,
            "Y": double.tryParse(humidityY.text) ?? 70.0,
            "R": double.tryParse(humidityR.text) ?? 100.0,
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
          "ieqi": double.tryParse(weightIeqi.text) ?? 15.0,
        }
      }
    };

    final Uri url = Uri.parse("$REGISTRY_BASE_URL/modify_settings");
    try {
      final resp = await http.put(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );
      if (resp.statusCode == 200) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Saved changes successfully"),
          backgroundColor: Colors.green,
        ));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("All thresholds reset to base defaults."),
          backgroundColor: Colors.green,
        ));
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

  Future<void> _resetSection(String pathKey) async {
    if (widget.location == null) return;
    if (baseSettings.isEmpty) {
      await _fetchCurrentSettings();
      if (baseSettings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No base settings found."),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    final Map<String, dynamic> partialThresholds = <String, dynamic>{};
    final Map<String, dynamic> partialValues = <String, dynamic>{};
    final Map<String, dynamic> partialWeights = <String, dynamic>{};

    dynamic bs(Object? x) => x;

    switch (pathKey) {
      case "mechanical_temp_cold":
        partialThresholds["mechanical_temp_cold"] =
            bs(baseSettings["thresholds"])["mechanical_temp_cold"] ??
                <String, dynamic>{"G": 23.0, "Y": 26.0, "R": 100.0};
        break;
      case "mechanical_temp_warm":
        partialThresholds["mechanical_temp_warm"] =
            bs(baseSettings["thresholds"])["mechanical_temp_warm"] ??
                <String, dynamic>{"G": 26.0, "Y": 27.0, "R": 100.0};
        break;
      case "humidity":
        partialThresholds["humidity"] =
            bs(baseSettings["thresholds"])["humidity"] ??
                <String, dynamic>{"G": 60.0, "Y": 70.0, "R": 100.0};
        break;
      case "co2_natural":
        partialThresholds["co2_natural"] =
            bs(baseSettings["thresholds"])["co2_natural"] ??
                <String, dynamic>{"G": 1200.0, "Y": 1500.0, "R": 10000.0};
        break;
      case "co2_mechanical":
        partialThresholds["co2_mechanical"] =
            bs(baseSettings["thresholds"])["co2_mechanical"] ??
                <String, dynamic>{
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
                <String, dynamic>{"G": 100, "Y": 70, "R": 40};
        break;
      case "weights":
        partialWeights.addAll(
          bs(baseSettings["weights"]) ??
              <String, dynamic>{
                "temperature": 15.0,
                "humidity": 10.0,
                "co2": 20.0,
                "pmv": 15.0,
                "ppd": 10.0,
                "icone": 15.0,
                "ieqi": 15.0
              },
        );
        break;

      // Reset the personal "values" => met, clo_warm, clo_cold
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

    // Ensure we at least send an empty "thresholds" to avoid KeyError
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Section reset to base."),
          backgroundColor: Colors.green,
        ));
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

  // -------------------- UI BUILDERS --------------------
  /// We'll show the label above the TextField so no truncation happens.
  Widget _buildLabeledTextField(String label, TextEditingController controller) {
    return SizedBox(
      width: 140,
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

                  // Reset ALL
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 228, 228, 228), // consistent with your Temperature color
                      ),
                      onPressed: _resetAll,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text("Reset ALL"),
                    ),
                  ),

                  const SizedBox(height: 12),
                  // Ventilation & Category row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _buildVentilationDropdown()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildAdaptiveDropdown()),
                    ],
                  ),

                  const SizedBox(height: 16),
                  // Mechanical cold
                  _buildExpansionTile(
                    title: "Mechanical Temperature (Cold Season)",
                    sectionKey: "mechanical_temp_cold",
                    children: [
                      _buildLabeledTextField("Green", mechTempColdG),
                      _buildLabeledTextField("Yellow", mechTempColdY),
                      _buildLabeledTextField("Red", mechTempColdR),
                    ],
                  ),

                  // Mechanical warm
                  _buildExpansionTile(
                    title: "Mechanical Temperature (Warm Season)",
                    sectionKey: "mechanical_temp_warm",
                    children: [
                      _buildLabeledTextField("Green", mechTempWarmG),
                      _buildLabeledTextField("Yellow", mechTempWarmY),
                      _buildLabeledTextField("Red", mechTempWarmR),
                    ],
                  ),

                  // Humidity
                  _buildExpansionTile(
                    title: "Humidity",
                    sectionKey: "humidity",
                    children: [
                      _buildLabeledTextField("Green", humidityG),
                      _buildLabeledTextField("Yellow", humidityY),
                      _buildLabeledTextField("Red", humidityR),
                    ],
                  ),

                  // CO2 natural
                  _buildExpansionTile(
                    title: "CO2 for Natural Ventilation",
                    sectionKey: "co2_natural",
                    children: [
                      _buildLabeledTextField("Green", co2NatG),
                      _buildLabeledTextField("Yellow", co2NatY),
                      _buildLabeledTextField("Red", co2NatR),
                    ],
                  ),

                  // CO2 mechanical
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
                      _buildLabeledTextField("iEQi", weightIeqi),
                    ],
                  ),

                  // Personal Values => met, clo_warm, clo_cold
                  _buildExpansionTile(
                    title: "Met & Clothing Level",
                    sectionKey: "personal_values",
                    children: [
                      // All in one row
                      _buildLabeledTextField("Metabolic Rate", metController),
                      _buildLabeledTextField("Clothing Level (Warm Season)", cloWarmController),
                      _buildLabeledTextField("Clothing Level (Cold Season)", cloColdController),
                    ],
                  ),

                  const SizedBox(height: 24),
                  // Save
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
