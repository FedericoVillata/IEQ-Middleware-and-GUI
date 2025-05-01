// import 'package:flutter/material.dart';
// import 'start_screen.dart';
// import 'app_config.dart';

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
  
//   await AppConfig.load();
  
//   runApp(const MainSelectorApp());
// }

// class MainSelectorApp extends StatelessWidget {
//   const MainSelectorApp({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'IEQ App',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: const StartScreen(),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'start_screen.dart';
import 'app_config.dart';
import 'mqtt_suggestions_manager.dart'; // Where we put the manager file


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load the JSON
  await AppConfig.load();

  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final manager = MqttSuggestionsManager();
        // Example: Subscribing to 2 or 3 apartments. 
        // If you only need one, pass just ["apartment1"] or whichever is relevant.
        manager.initMqtt(
          brokerHost: AppConfig.mqttBroker,
          brokerPort: AppConfig.mqttPort,
          topicBase: AppConfig.mqttTopicBase,
          apartmentsToListen: ["apartment0", "apartment1", "apartment3"],
        );
        return manager;
      },
      child: const MainSelectorApp(),
    ),
  );
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
