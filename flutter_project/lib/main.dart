import 'package:flutter/material.dart';
import 'start_screen.dart';

void main() {
  runApp(const MainSelectorApp());
}

class MainSelectorApp extends StatelessWidget {
  const MainSelectorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IEQ App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const StartScreen(),
    );
  }
}
