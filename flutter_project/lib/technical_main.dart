import 'package:flutter/material.dart';
import 'pages/technical_location_selection_page.dart';
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
    // Pagine di placeholder finché non viene selezionata la Location
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
    // Se non è stata selezionata la location, mostra la pagina di selezione
    if (selectedLocation == null) {
      return LocationSelectionPage(onLocationSelected: onLocationSelected);
    }

    // Altrimenti, mostra la UI con la sidebar a sinistra
    return Scaffold(
      appBar: AppBar(
        title: Text("Technical Interface - $selectedLocation"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              // Eventuale logica per il profilo
            },
          )
        ],
      ),
      body: Row(
        children: [
          // ------ SIDEBAR MODERNA ------
          Container(
            width: 240,
            decoration: const BoxDecoration(
              // Esempio di gradiente diagonale
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A73E8), // Blu più chiaro
                  Color(0xFF1669C1), // Blu più scuro
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header in alto con avatar e titolo
                  const SizedBox(height: 20),
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.engineering_rounded,
                      size: 40,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Technical Menu",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Divider per separare header e voci di menu
                  const Divider(
                    color: Colors.white54,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
                  const SizedBox(height: 4),

                  // Voci di menu (Home, Feedback, ecc.)
                  _buildSidebarItem(
                    icon: Icons.home,
                    label: "Detailed Metrics",
                    index: 0,
                  ),
                  _buildSidebarItem(
                    icon: Icons.bar_chart,
                    label: "Tenant Feedback",
                    index: 1,
                  ),
                  _buildSidebarItem(
                    icon: Icons.settings,
                    label: "Threshold Adjust.",
                    index: 2,
                  ),
                  _buildSidebarItem(
                    icon: Icons.delete_forever,
                    label: "Deleted Suggs.",
                    index: 3,
                  ),
                  _buildSidebarItem(
                    icon: Icons.lightbulb,
                    label: "Tech. Suggestions",
                    index: 4,
                  ),

                  // Spazio per spingere in basso il resto
                  const Spacer(),

                  // Bottone per cambiare location (logout)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text("Change Location"),
                      onPressed: () {
                        setState(() {
                          selectedLocation = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ------ CONTENUTO PRINCIPALE ------
          Expanded(
            child: pages[_currentIndex],
          ),
        ],
      ),
    );
  }

  /// Widget di supporto per costruire le voci della sidebar
  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final bool selected = _currentIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(icon, color: Colors.white),
          title: Text(
            label,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
