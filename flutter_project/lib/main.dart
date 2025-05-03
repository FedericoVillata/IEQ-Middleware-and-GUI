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
import 'mqtt_suggestions_manager.dart';
import 'mqtt_alert_manager.dart'; // ⬅️ Importa il nuovo manager

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carica configurazioni dal JSON
  await AppConfig.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MqttSuggestionsManager>(
          create: (_) {
            final manager = MqttSuggestionsManager();
            manager.initMqtt(
              brokerHost: AppConfig.mqttBroker,
              brokerPort: AppConfig.mqttPort,
              topicBase: AppConfig.mqttTopicBase,
              apartmentsToListen: ["apartment0", "apartment1", "apartment3"],
            );
            return manager;
          },
        ),
        ChangeNotifierProvider<MqttAlertManager>(
          create: (_) {
            final manager = MqttAlertManager();
            manager.init(
              broker: AppConfig.mqttBroker,
              port: AppConfig.mqttPort,
              topicBase: AppConfig.mqttTopicBase,
              apartments: ["apartment0", "apartment1", "apartment3"],
            );
            return manager;
          },
        ),
      ],
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
