import 'package:flutter/material.dart';
import 'technical_main.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IEQ Technical Interface',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/technical',
      routes: {
        '/technical': (context) => const TechnicalMainPage(),
        // Altre route se servono
      },
    );
  }
}
