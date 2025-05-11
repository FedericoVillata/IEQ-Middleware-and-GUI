import 'package:flutter/material.dart';
import 'pages/technical_location_selection_page.dart';
import 'pages/technical_home_page.dart';
import 'pages/technical_feedback_page.dart';
import 'pages/technical_threshold_page.dart';
import 'pages/technical_deleted_suggestions.dart';
import 'pages/technical_suggestions_page.dart';
import 'pages/technical_advanced_page.dart';
import 'login_page.dart';
import 'package:provider/provider.dart';                  
import 'app_config.dart';                                     
import 'mqtt_suggestions_manager.dart';                     

class TechnicalMainPage extends StatefulWidget {
  final String username;
  const TechnicalMainPage({super.key, required this.username});

  /// Allows nested widgets to reach the nearest [_TechnicalMainPageState]
  static _TechnicalMainPageState? of(BuildContext ctx) =>
      ctx.findAncestorStateOfType<_TechnicalMainPageState>();

  @override
  State<TechnicalMainPage> createState() => _TechnicalMainPageState();
}

class _TechnicalMainPageState extends State<TechnicalMainPage> {
  String? selectedLocation;
  int _currentIndex = 0;
  /// Pages are (re)built once a location is chosen
  late List<Widget> pages = List.filled(6, const Placeholder());

  /// Makes the Suggestions page visible from anywhere
  void goToSuggestions() => setState(() => _currentIndex = 5);

  /* ---------- location handling ---------- */
  void _buildPagesFor(String loc) {
    pages = [
      TechnicalHomePage(username: widget.username, location: loc),
      TechnicalAdvancePage(username: widget.username, location: loc),
      TechnicalFeedbackPage(username: widget.username, location: loc),
      TechnicalThresholdPage(username: widget.username, location: loc),
      TechnicalDeletedSuggestionsPage(username: widget.username, location: loc),
      TechnicalSuggestionsPage(username: widget.username, location: loc),
    ];
  }

  Future<void> _fetchInitialSuggestions(String apt) async {
    // one‑time bootstrap from REST service
    final mgr = context.read<MqttSuggestionsManager>();
    await mgr.syncFromRest(AppConfig.suggestionsRestUrl, [apt]);
  }

  void _onLocationSelected(String loc) async {
    setState(() {
      selectedLocation = loc;
      _currentIndex = 0;
      _buildPagesFor(loc);
    });

    // kick off the REST bootstrap (does nothing if already synced)
    await _fetchInitialSuggestions(loc);
  }

  /* ---------------- build ---------------- */
  @override
  Widget build(BuildContext context) {
    // ────────────────────────────────────────────────────────────────
    //  Step 1: if no apartment chosen -> show the selection page
    // ────────────────────────────────────────────────────────────────
    if (selectedLocation == null) {
      return LocationSelectionPage(
        username: widget.username,
        onLocationSelected: _onLocationSelected,
      );
    }

    // ────────────────────────────────────────────────────────────────
    //  Step 2: normal “Technical Interface” with chosen apartment
    // ────────────────────────────────────────────────────────────────
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Technical Interface – $selectedLocation'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          _Sidebar(
            currentIndex: _currentIndex,
            onChangeTab: (i) => setState(() => _currentIndex = i),
            onChangeLocation: () => setState(() {
              selectedLocation = null;
              _currentIndex = 0;
            }),
          ),
          Expanded(child: pages[_currentIndex]),
        ],
      ),
    );
  }
}

/*───────────────────────────────────────────────────────────────────────────*/
/*                               SIDEBAR                                    */
/*───────────────────────────────────────────────────────────────────────────*/
class _Sidebar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onChangeTab;
  final VoidCallback onChangeLocation;

  const _Sidebar({
    required this.currentIndex,
    required this.onChangeTab,
    required this.onChangeLocation,
  });

  Widget _item(IconData icon, String label, int idx) => InkWell(
        onTap: () => onChangeTab(idx),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: currentIndex == idx
                ? Colors.white.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(icon, color: Colors.white),
            title: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF1669C1)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(
              radius: 35,
              backgroundColor: Colors.white,
              child: Icon(Icons.engineering_rounded,
                  size: 40, color: Colors.blueAccent),
            ),
            const SizedBox(height: 8),
            const Text('Technical Menu',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Divider(
              color: Colors.white54,
              thickness: 1,
              indent: 16,
              endIndent: 16,
            ),
            _item(Icons.home,           'Detailed Metrics', 0),
            _item(Icons.construction,   'Advanced Metrics', 1),
            _item(Icons.bar_chart,      'Tenant Feedback',  2),
            _item(Icons.settings,       'Threshold Adjust.',3),
            _item(Icons.delete_forever, 'Deleted Suggs.',   4),
            _item(Icons.lightbulb,      'Tech. Suggestions',5),
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
                label: const Text('Change Location'),
                onPressed: onChangeLocation,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

