import 'package:flutter/material.dart';
import 'pages/tenant_home_page.dart';
import 'pages/tenant_feedback_page.dart';
import 'pages/tenant_suggestions_page.dart';
import 'pages/tenant_login_page.dart';

class MyAppTenant extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IEQ Tenant Interface',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => TenantLoginPage(),
        '/tenant': (context) => TenantMainPage(
              username: "Yasmin",
              apartments: ["Apartment1", "Apartment2"],
              rooms: {
                "Apartment1": ["Kitchen", "Living Room"],
                "Apartment2": ["Bedroom", "Bathroom"],
              },
              overallScores: {
                "Apartment1": 85,
                "Apartment2": 78,
              },
              externalTemperatures: {
                "Apartment1": "15°C",
                "Apartment2": "18°C",
              },
            ),
      },
    );
  }
}

class TenantMainPage extends StatefulWidget {
  final String username;
  final List<String> apartments;
  final Map<String, List<String>> rooms;
  final Map<String, int> overallScores;
  final Map<String, String> externalTemperatures;

  TenantMainPage({
    required this.username,
    required this.apartments,
    required this.rooms,
    required this.overallScores,
    required this.externalTemperatures,
  });

  @override
  State<TenantMainPage> createState() => _TenantMainPageState();
}

class _TenantMainPageState extends State<TenantMainPage> {
  int _currentIndex = 0;
  late List<Widget> pages;
  late String selectedApartment;

  @override
  void initState() {
    super.initState();
    selectedApartment = widget.apartments.first;
    _updatePages();
  }

  void _updatePages() {
    pages = [
      HomePage(
        username: widget.username,
        apartments: widget.apartments,
        rooms: widget.rooms,
        selectedApartment: selectedApartment,
        overallScores: widget.overallScores,
        externalTemperatures: widget.externalTemperatures,
      ),
      SuggestionsPage(),
      FeedbackPage(),
    ];
  }

  void updateSelectedApartment(String apartment) {
    setState(() {
      selectedApartment = apartment;
      _updatePages();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tenant Interface'),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {},
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
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
