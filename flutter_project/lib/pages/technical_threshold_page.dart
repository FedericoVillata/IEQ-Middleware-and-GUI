import 'package:flutter/material.dart';

class TechnicalThresholdPage extends StatefulWidget {
  final String? location;
  const TechnicalThresholdPage({Key? key, required this.location}) : super(key: key);

  @override
  State<TechnicalThresholdPage> createState() => _TechnicalThresholdPageState();
}

class _TechnicalThresholdPageState extends State<TechnicalThresholdPage> {
  // Esempio di soglie correnti
  double tempThreshold = 26;
  double humThreshold = 60;
  double co2Threshold = 1200;
  double pm10Threshold = 50;
  double tvocThreshold = 500;

  void _restoreDefault() {
    setState(() {
      // Valori di default
      tempThreshold = 26;
      humThreshold = 60;
      co2Threshold = 1200;
      pm10Threshold = 50;
      tvocThreshold = 500;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Threshold Adjustment for ${widget.location}",
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Card per Temperature
                _buildThresholdCard(
                  label: "Temperature (°C)",
                  value: tempThreshold,
                  onChanged: (val) => setState(() => tempThreshold = val),
                ),

                // Card per Humidity
                _buildThresholdCard(
                  label: "Humidity (%)",
                  value: humThreshold,
                  onChanged: (val) => setState(() => humThreshold = val),
                ),

                // Card per CO2
                _buildThresholdCard(
                  label: "CO2 (ppm)",
                  value: co2Threshold,
                  onChanged: (val) => setState(() => co2Threshold = val),
                ),

                // Card per PM10
                _buildThresholdCard(
                  label: "PM10 (µg/m³)",
                  value: pm10Threshold,
                  onChanged: (val) => setState(() => pm10Threshold = val),
                ),

                // Card per TVOC
                _buildThresholdCard(
                  label: "TVOC (ppb)",
                  value: tvocThreshold,
                  onChanged: (val) => setState(() => tvocThreshold = val),
                ),

                const SizedBox(height: 20),

                // Pulsante Restore
                ElevatedButton(
                  onPressed: _restoreDefault,
                  child: const Text("Restore default for this location"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Costruisce una Card con un titolo e un TextFormField per il valore della soglia
  Widget _buildThresholdCard({
    required String label,
    required double value,
    required Function(double) onChanged,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Etichetta param
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
              ),
            ),
            // Campo di input
            Expanded(
              child: TextFormField(
                initialValue: value.toStringAsFixed(1),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      // Esempio di refresh singolo su un valore predefinito
                      onChanged(999); // demo
                    },
                  ),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (val) => onChanged(double.tryParse(val) ?? value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
