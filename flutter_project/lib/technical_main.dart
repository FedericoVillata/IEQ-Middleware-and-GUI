import 'package:flutter/material.dart';
import 'pages/location_selection_page.dart';
import 'pages/technical_home_page.dart';
import 'pages/technical_feedback_page.dart';
import 'pages/technical_threshold_page.dart';
import 'pages/technical_deleted_suggestions.dart';
import 'pages/technical_suggestions_page.dart';

class TechnicalMainPage extends StatefulWidget {
  const TechnicalMainPage({Key? key}) : super(key: key);

  @override
  State<TechnicalMainPage> createState() => _TechnicalMainPageState();
}

class _TechnicalMainPageState extends State<TechnicalMainPage> {
  String? selectedLocation; 
  int _currentIndex = 0;

  late List<Widget> pages;

  @override
  void initState() {
    super.initState();
    // All'inizio non c’è location selezionata, quindi potresti lasciarle vuote 
    pages = [
      const Placeholder(),
      const Placeholder(),
      const Placeholder(),
      const Placeholder(),
      const Placeholder(),
    ];
  }

  void onLocationSelected(String loc) {
    setState(() {
      selectedLocation = loc;
      // Ricostruiamo le pagine con la location scelta
      pages = [
        TechnicalHomePage(location: selectedLocation),
        TechnicalFeedbackPage(location: selectedLocation),
        TechnicalThresholdPage(location: selectedLocation),
        TechnicalDeletedSuggestionsPage(location: selectedLocation),
        TechnicalSuggestionsPage(location: selectedLocation),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    // Se non hai ancora selezionato la location, mostra la pagina "LocationSelectionPage"
    if (selectedLocation == null) {
      return LocationSelectionPage(onLocationSelected: onLocationSelected);
    }

    // Altrimenti mostra la sidebar fissa + content
    return Scaffold(
      // Mostriamo un AppBar in alto (se vuoi replicare la UI delle slide, 
      // potresti anche toglierla e fare un header personalizzato)
      appBar: AppBar(
        title: Text("Technical Interface - $selectedLocation"),
        actions: [
          // Bottone per aprire il profilo
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              // Logica per il profilo
            },
          )
        ],
      ),
      body: Row(
        children: [
          // ---- SIDEBAR SINISTRA ----
          Container(
            width: 200,
            color: Colors.blue.shade50,
            child: Column(
              children: [
                // Un header della sidebar (es. immagine/logo)
                Container(
                  height: 80,
                  color: Colors.blue.shade100,
                  child: const Center(
                    child: Text(
                      "Sidebar Menu",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // Pulsante 1: Detailed Metrics
                ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text("Detailed Metrics"),
                  selected: _currentIndex == 0,
                  onTap: () {
                    setState(() => _currentIndex = 0);
                  },
                ),
                // Pulsante 2: Feedback
                ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: const Text("Tenant Feedback"),
                  selected: _currentIndex == 1,
                  onTap: () {
                    setState(() => _currentIndex = 1);
                  },
                ),
                // Pulsante 3: Threshold
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text("Threshold Adjust."),
                  selected: _currentIndex == 2,
                  onTap: () {
                    setState(() => _currentIndex = 2);
                  },
                ),
                // Pulsante 4: Deleted Suggestions
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text("Deleted Suggs."),
                  selected: _currentIndex == 3,
                  onTap: () {
                    setState(() => _currentIndex = 3);
                  },
                ),
                // Pulsante 5: Tech Suggestions
                ListTile(
                  leading: const Icon(Icons.lightbulb),
                  title: const Text("Tech. Suggestions"),
                  selected: _currentIndex == 4,
                  onTap: () {
                    setState(() => _currentIndex = 4);
                  },
                ),

                const Spacer(), // Spinge verso il basso se vuoi un pulsante in fondo
                // Eventuale bottone "logout" o "switch location"
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text("Change Location"),
                  onTap: () {
                    setState(() => selectedLocation = null);
                  },
                ),
              ],
            ),
          ),

          // ---- AREA CENTRALE (Expanded) ----
          Expanded(
            child: pages[_currentIndex],
          ),
        ],
      ),
    );
  }
}
