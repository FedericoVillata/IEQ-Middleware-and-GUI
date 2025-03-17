import 'package:flutter/material.dart';
import 'tenant_main.dart';
import 'technical_main.dart';

void main() {
  runApp(MainSelectorApp());
}

class MainSelectorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IEQ App Selector',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: SelectionScreen(),
    );
  }
}

class SelectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Select Interface"),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // BOTTONE TENANT
            ElevatedButton.icon(
              icon: Icon(Icons.person),
              label: Text("Tenant Interface"),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                textStyle: TextStyle(fontSize: 18),
              ),
              onPressed: () {
                // LANCIA MyAppTenant (che contiene la login e la main)
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => MyAppTenant()),
                );
              },
            ),
            SizedBox(height: 20),

            // BOTTONE TECHNICAL
            ElevatedButton.icon(
              icon: Icon(Icons.engineering),
              label: Text("Technical Interface"),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                textStyle: TextStyle(fontSize: 18),
              ),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => TechnicalMainPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
