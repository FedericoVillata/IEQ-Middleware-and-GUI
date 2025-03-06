import 'package:flutter/material.dart';

class TechnicalThresholdPage extends StatefulWidget {
  final String? location;
  const TechnicalThresholdPage({Key? key, required this.location}) : super(key: key);

  @override
  State<TechnicalThresholdPage> createState() => _TechnicalThresholdPageState();
}

class _TechnicalThresholdPageState extends State<TechnicalThresholdPage> {
  // Esempio: soglie
  double tempThreshold = 26;
  double humThreshold = 60;
  double co2Threshold = 1200;
  double pm10Threshold = 50;
  double tvocThreshold = 500;

  void _restoreDefault() {
    setState(() {
      tempThreshold = 26;
      humThreshold = 60;
      co2Threshold = 1200;
      pm10Threshold = 50;
      tvocThreshold = 500;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text("Threshold Adjustment for ${widget.location}",
                  style: TextStyle(fontSize: 18)),
              _thresholdRow("Temperature", tempThreshold, (val) {
                setState(() => tempThreshold = val);
              }),
              _thresholdRow("Humidity", humThreshold, (val) {
                setState(() => humThreshold = val);
              }),
              _thresholdRow("CO2", co2Threshold, (val) {
                setState(() => co2Threshold = val);
              }),
              _thresholdRow("PM10", pm10Threshold, (val) {
                setState(() => pm10Threshold = val);
              }),
              _thresholdRow("TVOC", tvocThreshold, (val) {
                setState(() => tvocThreshold = val);
              }),
              ElevatedButton(
                onPressed: _restoreDefault,
                child: Text("Restore default for this location"),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _thresholdRow(String label, double value, Function(double) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 150, child: Text(label)),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: value.toStringAsFixed(1),
            keyboardType: TextInputType.number,
            onChanged: (val) => onChanged(double.tryParse(val) ?? value),
          ),
        ),
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            // Esempio di refresh singolo
            onChanged(999); // mock
          },
        ),
      ],
    );
  }
}
