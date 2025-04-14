import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'tenant_main.dart';
import 'technical_main.dart';
import 'app_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  final String baseUrl = AppConfig.registryUrl;
  //final String baseUrl = "http://registry:8081";
  //final String baseUrl = "Registry.ieqmiddleware.com";

  // Handles the login logic
  Future<void> _attemptLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final response = await http.get(Uri.parse("$baseUrl/users"));
      if (response.statusCode != 200) {
        _showErrorDialog("Server error: ${response.statusCode}");
        return;
      }

      final List<dynamic> users = jsonDecode(response.body);
      final user = users.firstWhere(
        (u) => u['userId'] == username && u['password'] == password,
        orElse: () => null,
      );

      if (user == null) {
        _showErrorDialog("Wrong credentials");
        return;
      }

      final permission = user['permissions'];
      final List<String> apartments = List<String>.from(user['apartments']);

      // Ensure each apartment has its data bucket (if needed)
      for (String apt in apartments) {
        await _ensureApartmentBucketExists(apt);
      }

      if (!mounted) return;

      // Redirect based on user role
      if (permission == "Base") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MyAppTenant(
              username: username,
              apartments: apartments,
            ),
          ),
        );
      } else if (permission == "Technical") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TechnicalMainPage(
              username: username, // Pass the logged user here
            ),
          ),
        );
      } else {
        _showErrorDialog("Unrecognized permission type");
      }
    } catch (e) {
      _showErrorDialog("Connection error:\n$e");
    }
  }

  // Sends a dummy request to ensure the apartment's data bucket exists
  Future<void> _ensureApartmentBucketExists(String apartmentId) async {
    try {
      await http.post(
        Uri.parse("$baseUrl/addApartment"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"apartmentId": apartmentId}),
      );
    } catch (_) {
      // Fail silently
    }
  }

  // Displays error messages in a dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  // UI: main login screen
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
              const Icon(Icons.account_circle, size: 80, color: Color(0xFF236FC6)),
              const SizedBox(height: 20),
              const Text(
                "Login",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF236FC6)),
              ),
              const SizedBox(height: 20),

              // Username input
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.person, color: Color(0xFF236FC6)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Password input
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
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
                  child: const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
