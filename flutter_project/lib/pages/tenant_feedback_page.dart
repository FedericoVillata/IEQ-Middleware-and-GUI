import 'package:flutter/material.dart';

class FeedbackPage extends StatefulWidget {
  @override
  _FeedbackPageState createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int tempRating = 0;
  int humRating = 0;
  int envRating = 0;
  int serviceRating = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text("Give Your Daily Feedback", style: TextStyle(color: Colors.black)),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.account_circle, color: Colors.black, size: 30),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildRatingSection("Temperature Perception", tempRating, (rating) {
              setState(() {
                tempRating = rating;
              });
            }),
            _buildRatingSection("Humidity Perception", humRating, (rating) {
              setState(() {
                humRating = rating;
              });
            }),
            _buildRatingSection("Environment Satisfaction", envRating, (rating) {
              setState(() {
                envRating = rating;
              });
            }),
            _buildRatingSection("Service Rating", serviceRating, (rating) {
              setState(() {
                serviceRating = rating;
              });
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSection(String title, int rating, Function(int) onRatingChanged) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    Icons.star,
                    color: index < rating ? Colors.orange : Colors.grey,
                  ),
                  onPressed: () => onRatingChanged(index + 1),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
