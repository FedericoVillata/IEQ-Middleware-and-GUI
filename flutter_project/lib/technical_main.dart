import 'package:flutter/material.dart';
import 'pages/technical_location_selection_page.dart';
import 'pages/technical_home_page.dart';
import 'pages/technical_feedback_page.dart';
import 'pages/technical_threshold_page.dart';
import 'pages/technical_deleted_suggestions.dart';
import 'pages/technical_suggestions_page.dart';
import 'pages/technical_advanced_page.dart';
import 'login_page.dart';

class TechnicalMainPage extends StatefulWidget {
  final String username;
  const TechnicalMainPage({super.key, required this.username});

  static _TechnicalMainPageState? of(BuildContext ctx) =>
      ctx.findAncestorStateOfType<_TechnicalMainPageState>();

  @override
  State<TechnicalMainPage> createState() => _TechnicalMainPageState();
}

class _TechnicalMainPageState extends State<TechnicalMainPage> {
  String? selectedLocation;
  int _currentIndex = 0;

  void goToSuggestions() => setState(() => _currentIndex = 5);

  late List<Widget> pages = List.filled(6, const Placeholder());

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

  void _onLocationSelected(String loc) {
    setState(() {
      selectedLocation = loc;
      _currentIndex = 0;
      _buildPagesFor(loc);
    });
  }

  /* ---------------- build ---------------- */
  @override
  Widget build(BuildContext context) {
    if (selectedLocation == null) {
      return LocationSelectionPage(
        username: widget.username,
        onLocationSelected: _onLocationSelected,
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Technical Interface – $selectedLocation'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            selectedLocation = null;
            _currentIndex = 0;
          }),
        ),
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
          ),
          Expanded(child: pages[_currentIndex]),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onChangeTab;

  const _Sidebar({required this.currentIndex, required this.onChangeTab});

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
          ],
        ),
      ),
    );
  }
}
