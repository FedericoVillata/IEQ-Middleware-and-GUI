// tenant_main.dart
import 'package:flutter/material.dart';
import 'pages/tenant_home_page.dart';
import 'pages/tenant_feedback_page.dart' as feedback;
import 'pages/tenant_suggestions_page.dart' as suggestions;
import 'package:http/http.dart' as http;
import 'dart:convert';

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IEQ Tenant Interface',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: TenantMainPage(
        username: username,
        apartments: apartments,
      ),
    );
  }
}

class TenantMainPage extends StatefulWidget {
  final String username;
  final List<String> apartments;

  const TenantMainPage({
    super.key,
    required this.username,
    required this.apartments,
  });

  @override
  State<TenantMainPage> createState() => _TenantMainPageState();
}

class _TenantMainPageState extends State<TenantMainPage> {
  int _currentIndex = 0;
  late List<Widget> pages;
  late String selectedApartment;
  late String selectedRoom;
  Map<String, List<String>> apartmentRooms = {};
  Map<String, int> overallScores = {};
  Map<String, String> externalTemperatures = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    selectedApartment = widget.apartments.first;
    selectedRoom = '';
    fetchApartmentData();
  }

  Future<void> fetchApartmentData() async {
    try {
      final response = await http.get(Uri.parse("http://10.0.2.2:8081/apartments"));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        for (var apt in data) {
          if (widget.apartments.contains(apt['apartmentId'])) {
            final aptId = apt['apartmentId'];
            final List<String> rooms = List<String>.from(
              (apt['rooms'] as List<dynamic>).map((r) => r['roomId']),
            );
            apartmentRooms[aptId] = rooms;

            if (selectedRoom.isEmpty && rooms.isNotEmpty) {
              selectedRoom = rooms.first;
            }

            overallScores[aptId] = 85;
            externalTemperatures[aptId] = "20°C";
          }
        }
        _updatePages();
        setState(() {
          loading = false;
        });
      }
    } catch (e) {
      print("Errore fetch apartment data: $e");
    }
  }

  void updateSelectedRoom(String room) {
    setState(() {
      selectedRoom = room;
      _updatePages();
    });
  }

  void updateSelectedApartment(String apartment) {
    setState(() {
      selectedApartment = apartment;
      selectedRoom = apartmentRooms[apartment]?.first ?? "";
      _updatePages();
    });
  }

  void _updatePages() {
    pages = [
      HomePage(
        username: widget.username,
        apartments: widget.apartments,
        rooms: apartmentRooms,
        selectedApartment: selectedApartment,
        overallScores: overallScores,
        externalTemperatures: externalTemperatures,
        onRoomChanged: updateSelectedRoom,
        onApartmentChanged: updateSelectedApartment,
      ),
      suggestions.SuggestionsPage(),
      feedback.FeedbackPage(
        username: widget.username,
        apartmentId: selectedApartment,
        roomId: selectedRoom,),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenant Interface'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {},
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.lightbulb), label: 'Suggestions'),
          BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Feedback'),
        ],
      ),
    );
  }
}
