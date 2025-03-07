import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER CON SFONDO BLU
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 50),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blueAccent, Colors.lightBlueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Welcome, Tenant!",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Your Smart Environment",
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // INFORMAZIONI AMBIENTALI
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildInfoCard("External Temperature", "15°C", Icons.wb_sunny, Colors.orange),
                  SizedBox(height: 12),
                  _buildInfoCard("Indoor Temperature", "22°C", Icons.thermostat, Colors.red),
                  SizedBox(height: 12),
                  _buildInfoCard("Humidity Level", "45%", Icons.water_drop, Colors.blue),
                  SizedBox(height: 12),
                  _buildInfoCard("Air Quality", "Good", Icons.air, Colors.green),
                  SizedBox(height: 12),
                  _buildOverallScoreCard(85), // Example percentage
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color iconColor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      shadowColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text(value, style: TextStyle(fontSize: 16, color: Colors.black54)),
              ],
            ),
            Container(
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              padding: EdgeInsets.all(12),
              child: Icon(icon, color: iconColor, size: 40),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallScoreCard(int percentage) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      shadowColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text("Overall Score", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Colors.grey[300],
                    color: Colors.green,
                    strokeWidth: 8,
                  ),
                ),
                Text(
                  "$percentage%",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
