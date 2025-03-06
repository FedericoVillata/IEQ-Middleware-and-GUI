import 'package:flutter/material.dart';

class TechnicalHomePage extends StatefulWidget {
  final String? location;
  const TechnicalHomePage({Key? key, required this.location}) : super(key: key);

  @override
  State<TechnicalHomePage> createState() => _TechnicalHomePageState();
}

class _TechnicalHomePageState extends State<TechnicalHomePage> {
  String selectedMetric = "Temperature";
  final metrics = ["Temperature", "Humidity", "CO2", "PM10", "TVOC"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Barra per selezione metrica
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: metrics.map((m) {
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: ElevatedButton(
                    child: Text(m),
                    onPressed: () {
                      setState(() => selectedMetric = m);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          // Qui mostra il carpet plot
          Expanded(
            child: Center(
              child: Text(
                "Carpet plot for $selectedMetric at ${widget.location}",
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
