// tenant_main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'login_page.dart';                         // ← aggiunto
import 'pages/tenant_home_page.dart';
import 'pages/tenant_feedback_page.dart' as feedback;
import 'pages/tenant_suggestions_page.dart' as suggestions;
import 'app_config.dart';
import 'package:provider/provider.dart';
import 'mqtt_suggestions_manager.dart';          //  ← aggiungi questo
import 'package:flutter/gestures.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';


class MyAppTenant extends StatelessWidget {
  final String username;
  final List<String> apartments;

  const MyAppTenant({
    super.key,
    required this.username,
    required this.apartments,
  });

  @override
  Widget build(BuildContext context) {
return ChangeNotifierProvider<MqttSuggestionsManager>(
      create: (_) {
        final mgr = MqttSuggestionsManager();
        mgr.initMqtt(
          brokerHost: AppConfig.mqttBroker,
          brokerPort: AppConfig.mqttPort,
          topicBase: 'IEQmidAndGUI',
          apartmentsToListen: apartments,
        );
        return mgr;
      },
      child: TenantMainPage(
  username: username,
  apartments: apartments,
),

    );
  }
}


// ─────────────────────────────────────────────────────────────
//                   MAIN PAGE – TENANT
// ─────────────────────────────────────────────────────────────
class TenantMainPage extends StatefulWidget {
  final String username;
  final List<String> apartments;

  const TenantMainPage({
    super.key,
    required this.username,
    required this.apartments,
  });

  static _TenantMainPageState? of(BuildContext ctx) =>
    ctx.findAncestorStateOfType<_TenantMainPageState>();


  @override
  State<TenantMainPage> createState() => _TenantMainPageState();
}

class _TenantMainPageState extends State<TenantMainPage> {
  // ---------------- state vars ----------------
  int _currentIndex = 0;
  late List<Widget> pages;

  late String selectedApartment;
  late String selectedRoom;
  final Map<String, List<String>> apartmentRooms = {};
  final Map<String, int> overallScores = {};
  final Map<String, String> apartmentNames = {};


  bool loading = true;

  // ---------------- lifecycle ----------------
  @override
  void initState() {
    super.initState();
    selectedApartment = widget.apartments.first;
    selectedRoom = '';
    fetchApartmentData();
  }

  // ---------------- public helper for SuggestionsBell -------
  void goToSuggestionsTab() => setState(() => _currentIndex = 1);

  // ---------------- data fetch ----------------
  Future<void> fetchApartmentData() async {
    try {
      final resp =
          await http.get(Uri.parse('${AppConfig.registryUrl}/apartments'));
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body) as List<dynamic>;
      for (final apt in data) {
        if (widget.apartments.contains(apt['apartmentId'])) {
          final aptId = apt['apartmentId'];
          final aptName = apt['apartmentName'];
          apartmentNames[aptId] = aptName;
          final rooms = List<String>.from(
              (apt['rooms'] as List<dynamic>).map((r) => r['roomId']));
          apartmentRooms[aptId] = rooms;

          if (selectedRoom.isEmpty && rooms.isNotEmpty) {
            selectedRoom = rooms.first;
          }
          overallScores[aptId] = 85; // placeholder
        }
      }

      _updatePages();
      setState(() => loading = false);
    } catch (e) {
      debugPrint('fetchApartmentData error: $e');
    }
  }

  // ---------------- callbacks from child ----------------
  void updateSelectedRoom(String room) {
    setState(() {
      selectedRoom = room;
      _updatePages();
    });
  }

  void updateSelectedApartment(String apartment) {
    setState(() {
      selectedApartment = apartment;
      selectedRoom = apartmentRooms[apartment]?.first ?? '';
      _updatePages();
    });
  }

  // ---------------- build pages list ----------------
  void _updatePages() {
    pages = [
      HomePage(
        username: widget.username,
        apartments: widget.apartments,
        rooms: apartmentRooms,
        selectedApartment: selectedApartment,
        selectedRoom: selectedRoom,
        overallScores: overallScores,
        onRoomChanged: updateSelectedRoom,
        onApartmentChanged: updateSelectedApartment,
        apartmentNames: apartmentNames,
      ),
      suggestions.TenantSuggestionsPage(
        username: widget.username,
        apartmentId: selectedApartment,
        roomId: selectedRoom,
        rooms: apartmentRooms,
      ),
      feedback.FeedbackPage(
        username: widget.username,
        apartmentId: selectedApartment,
        roomId: selectedRoom,
      ),
    ];
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // tenant_main.dart  →  _TenantMainPageState.build
return Scaffold(
  appBar: AppBar(
    automaticallyImplyLeading: false, 
    title: Text(AppLocalizations.of(context)?.tenantInterface ?? 'Tenant Interface'),
    actions: [
      IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Log‑out',
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        ),
      ),
    ],
  ),

  // 🔄 Mantieni vive tutte le pagine
  body: IndexedStack(
    index: _currentIndex,
    children: pages,   // <— le stesse istanze create in _updatePages()
  ),

  bottomNavigationBar: BottomNavigationBar(
    type: BottomNavigationBarType.fixed,
    currentIndex: _currentIndex,
   onTap: (i) {
  setState(() => _currentIndex = i);

  if (i == 1) { // Suggestions
    context.read<MqttSuggestionsManager>()
           .markTenantRead(selectedApartment, selectedRoom);
  }
},


    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      BottomNavigationBarItem(icon: Icon(Icons.lightbulb), label: 'Suggestions'),
      BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Feedback'),
    ],
  ),
);

  }
}

