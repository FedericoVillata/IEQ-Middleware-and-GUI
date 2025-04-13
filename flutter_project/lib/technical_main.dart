import 'package:flutter/material.dart';
import 'pages/technical_location_selection_page.dart';
import 'pages/technical_home_page.dart';
import 'pages/technical_feedback_page.dart';
import 'pages/technical_threshold_page.dart';
import 'pages/technical_deleted_suggestions.dart';
import 'pages/technical_suggestions_page.dart';
// Import the new page
import 'pages/technical_advanced_page.dart';

class TechnicalMainPage extends StatefulWidget {
  final String username;

  const TechnicalMainPage({
    Key? key,
    required this.username,
  }) : super(key: key);

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
    // Placeholder pages if no location selected
    pages = [
      const Placeholder(),
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
        // index 0
        TechnicalHomePage(username: widget.username, location: selectedLocation),
        // index 1
        TechnicalAdvancePage(username: widget.username, location: selectedLocation),
        // index 2
        TechnicalFeedbackPage(username: widget.username, location: selectedLocation),
        // index 3
        TechnicalThresholdPage(username: widget.username, location: selectedLocation),
        // index 4
        TechnicalDeletedSuggestionsPage(username: widget.username, location: selectedLocation),
        // index 5
        TechnicalSuggestionsPage(username: widget.username, location: selectedLocation),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    // If no location selected, show the location selection page
    if (selectedLocation == null) {
      return LocationSelectionPage(
        username: widget.username,
        onLocationSelected: onLocationSelected,
      );
    }

    // Otherwise, show the main interface
    return Scaffold(
      appBar: AppBar(
        title: Text("Technical Interface - $selectedLocation"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              // Potential user profile logic
            },
          )
        ],
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 240,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A73E8),
                  Color(0xFF1669C1),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
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
                  const Divider(
                    color: Colors.white54,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
                  const SizedBox(height: 4),

                  // index=0: Detailed Metrics
                  _buildSidebarItem(
                    icon: Icons.home,
                    label: "Detailed Metrics",
                    index: 0,
                  ),

                  // index=1: Advanced Metrics (NEW)
                  _buildSidebarItem(
                    icon: Icons.construction, // or any relevant icon
                    label: "Advanced Metrics",
                    index: 1,
                  ),

                  // index=2: Tenant Feedback
                  _buildSidebarItem(
                    icon: Icons.bar_chart,
                    label: "Tenant Feedback",
                    index: 2,
                  ),
                  // index=3: Threshold Adjustments
                  _buildSidebarItem(
                    icon: Icons.settings,
                    label: "Threshold Adjust.",
                    index: 3,
                  ),
                  // index=4: Deleted Suggestions
                  _buildSidebarItem(
                    icon: Icons.delete_forever,
                    label: "Deleted Suggs.",
                    index: 4,
                  ),
                  // index=5: Technical Suggestions
                  _buildSidebarItem(
                    icon: Icons.lightbulb,
                    label: "Tech. Suggestions",
                    index: 5,
                  ),

                  const Spacer(),

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
                          _currentIndex = 0;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Main content
          Expanded(
            child: pages[_currentIndex],
          ),
        ],
      ),
    );
  }

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
