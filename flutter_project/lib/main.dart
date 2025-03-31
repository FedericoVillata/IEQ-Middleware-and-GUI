import 'package:flutter/material.dart';
import 'login_page.dart'; // 👈 Importa la nuova pagina di login

void main() {
  runApp(MainSelectorApp());
}

class MainSelectorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IEQ App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginPage(), // 👈 Mostra la login all'avvio
    );
  }
}
