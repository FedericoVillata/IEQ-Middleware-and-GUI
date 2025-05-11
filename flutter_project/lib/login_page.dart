import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'tenant_main.dart';
import 'technical_main.dart';
import 'app_config.dart';
import 'main.dart'; // per MainSelectorApp.setLocale
import 'package:flutter_gen/gen_l10n/app_localizations.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  Future<void> _attemptLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final url = Uri.parse('${AppConfig.registryUrl}/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': username, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200 || data['status'] != 'OK') {
        final msg = data['message'] ?? 'Login failed';
        _showErrorDialog(msg);
        return;
      }

      final message = data['message'];
      if (message == 'Base') {
        final apartments = await _fetchUserApartments(username);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MyAppTenant(username: username, apartments: apartments),
          ),
        );
      } else if (message == 'Technical') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TechnicalMainPage(username: username),
          ),
        );
      } else {
        _showErrorDialog('Unrecognized role: $message');
      }
    } catch (e) {
      _showErrorDialog("Connection error:\n$e");
    }
  }

  Future<List<String>> _fetchUserApartments(String userId) async {
  try {
    final url = Uri.parse('${AppConfig.registryUrl}/users');
    final response = await http.get(url);
    if (response.statusCode != 200) return [];

    final List<dynamic> users = jsonDecode(response.body);
    final user = users.firstWhere(
      (u) => u['userId'] == userId,
      orElse: () => {}, // ← ritorna un Map vuoto invece di null
    );

    if (user.containsKey('apartments') && user['apartments'] is List) {
      return List<String>.from(user['apartments']);
    }
  } catch (e) {
    debugPrint('Apartment fetch error: $e');
  }
  return [];
}


  void _showErrorDialog(String message) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.login),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.confirm),
        )
      ],
    ),
  );
}


  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[200],
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🔤 Language selector
            Align(
              alignment: Alignment.topRight,
              child: DropdownButton<Locale>(
                value: Localizations.localeOf(context),
                icon: const Icon(Icons.language),
                onChanged: (Locale? locale) {
                  if (locale != null) {
                    MainSelectorApp.setLocale(context, locale);
                  }
                },
                items: const [
                  DropdownMenuItem(
                    value: Locale('en'),
                    child: Text('English'),
                  ),
                  DropdownMenuItem(
                    value: Locale('it'),
                    child: Text('Italiano'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Icon(Icons.account_circle, size: 80, color: Color(0xFF236FC6)),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.login,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF236FC6)),
            ),
            const SizedBox(height: 20),

            // Username field
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.username,
                prefixIcon: const Icon(Icons.person, color: Color(0xFF236FC6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                prefixIcon: const Icon(Icons.lock, color: Color(0xFF236FC6)),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Login button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF236FC6),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _attemptLogin,
                child: Text(
                  AppLocalizations.of(context)!.login,
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

}
