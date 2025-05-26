// pages/tenant_home_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/suggestions_bell.dart';
import '../app_config.dart';
import '../mqtt_alert_manager.dart';
import 'package:provider/provider.dart'; 
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../utils/alert_catalog.dart';
import 'package:weather_icons/weather_icons.dart';




class HomePage extends StatefulWidget {
  final String username;
  final List<String> apartments;
  final Map<String, List<String>> rooms;
  final String selectedApartment;
  final String selectedRoom;
  final Map<String, int> overallScores;
  final Function(String) onRoomChanged;
  final Function(String) onApartmentChanged;
  final Map<String, String> apartmentNames;


  const HomePage({
    super.key,
    required this.username,
    required this.apartments,
    required this.rooms,
    required this.selectedApartment,
    required this.selectedRoom,
    required this.overallScores,
    required this.onRoomChanged,
    required this.onApartmentChanged,
    required this.apartmentNames, 
  });

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // ─────────────────────────────── state vars
  late String selectedApartment;
  late String selectedRoom;
  bool  showDropdown = false;
  Timer? _refreshTimer;
  String? apartmentType;


  String indoorTemp     = 'Loading...';
  String humidity       = 'Loading...';
  String co2            = 'Loading...';
  String tempClass = '';
  String humidityClass = '';
  String co2Class = '';
  String environmentClass = '';

  int environmentScore = 10;
  


  // meteo
  String externalTemp = 'Loading...';
  int    weatherCode  = 0;
  final  String adaptorUrl = AppConfig.adaptorUrl;
  double? apartmentLat;
  double? apartmentLong;


  // ─────────────────────────────── lifecycle
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selectedApartment = widget.selectedApartment;
    selectedRoom = widget.selectedRoom;
    _fetchRoomData();
    _fetchExternalWeatherData();
    _startAutoRefresh();
    _fetchApartmentCoordinates();

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Quando si torna alla homepage, aggiorna entrambi
    _fetchRoomData();
    _fetchExternalWeatherData();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedApartment != widget.selectedApartment ||
        oldWidget.selectedRoom != widget.selectedRoom) {
      _fetchRoomData();
      _fetchExternalWeatherData();
    }
  }

  void _startAutoRefresh() {
  _refreshTimer =
      Timer.periodic(const Duration(minutes: 10), (_) {
        _fetchExternalWeatherData();
        _fetchRoomData(); 
      });
}

  // ─────────────────────────────── HTTP helpers
  void _fetchExternalWeatherData() async {
  if (apartmentLat == null || apartmentLong == null) return;

  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=$apartmentLat&longitude=$apartmentLong'
    '&hourly=temperature_2m,weather_code'
    '&timezone=auto&forecast_days=1',
  );

  try {
    final r = await http.get(url);
    if (r.statusCode == 200) {
      final d     = jsonDecode(r.body);
      final temps = d['hourly']['temperature_2m'] as List<dynamic>;
      final codes = d['hourly']['weather_code']   as List<dynamic>;
      final h     = DateTime.now().hour;
      debugPrint('🕒 Ora corrente: $h');
      debugPrint('🌡️ Temperature orarie: $temps');
      debugPrint('🌤️ Codici meteo orari: $codes');


      setState(() {
        externalTemp = '${(temps[h] as num).toStringAsFixed(1)}°C';
        weatherCode  = codes[h];
        //weatherCode = 3;
        debugPrint('✅ Meteo attuale settato: codice $weatherCode');
      });
    }
  } catch (e) {
    debugPrint('meteo error: $e');
  }
}


    Future<void> _fetchApartmentCoordinates() async {
  final url = Uri.parse('${AppConfig.registryUrl}/apartments');
  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      for (final apt in data) {
        if (apt['apartmentId'] == selectedApartment) {
          final coords = apt['coordinates'];
          setState(() {
            apartmentLat = coords['lat'];
            apartmentLong = coords['long'];
            apartmentType = apt['type'];
          });

          // 🔁 Sempre aggiorna il meteo dopo aver aggiornato le coordinate
          _fetchExternalWeatherData();

          return;
        }
      }
    } else {
      debugPrint('Error fetching apartments: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Exception while fetching coordinates: $e');
  }
}



  Future<void> _fetchRoomData() async {
    try {
      final url = Uri.parse(
        '$adaptorUrl/getLastRoomData/'
        '${widget.username}/$selectedApartment/$selectedRoom',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        for (final d in data) {
          switch (d['measurement']) {
            case 'avg_temperature':
              final v = d['v'] as num;
              indoorTemp = '${v.toStringAsFixed(1)}°C';
              break;
            case 'avg_humidity':
              final v = d['v'] as num;
              humidity = '${v.toStringAsFixed(1)}%';
              break;
            case 'avg_co2':
              final v = d['v'] as num;
              co2 = '${v.toInt()} ppm';
              break;
            case 'environment_score':
              final v = d['v'] as num;
              environmentScore = v.clamp(0, 100).toInt();
              break;

            // classi
            case 'temperature_class':
              tempClass = d['v'] as String;
              break;
            case 'humidity_class':
              humidityClass = d['v'] as String;
              break;
            case 'co2_class':
              co2Class = d['v'] as String;
              break;
            case 'environment_score_class':
              environmentClass = d['v'] as String;
              break;
          }
        }
      } else {
        indoorTemp = humidity = co2 = 'Error';
      }
    } catch (e) {
      indoorTemp = humidity = co2 = 'Error';
    }
    if (mounted) setState(() {});
  }

  // ─────────────────────────────── UI helpers

  IconData _getWeatherIcon(int code, bool isDay) {
    if (code == 0) return isDay ? WeatherIcons.day_sunny : WeatherIcons.night_clear;
    if (code == 1) return isDay ? WeatherIcons.day_sunny_overcast : WeatherIcons.night_alt_partly_cloudy;
    if (code == 2) return isDay ? WeatherIcons.day_cloudy : WeatherIcons.night_alt_cloudy;
    if (code == 3) return WeatherIcons.cloudy;
    if (code >= 45 && code <= 48) return WeatherIcons.fog;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return WeatherIcons.rain;
    if (code >= 71 && code <= 77) return WeatherIcons.snow;
    if (code >= 95) return WeatherIcons.thunderstorm;
    return WeatherIcons.cloud;
  }



  Color _getWeatherColor(int code) {
  if (code == 0) return Colors.yellow.shade700;          // ☀️ Sole pieno
  if (code == 1) return Colors.orangeAccent;             // 🌤️ Sole con qualche nuvola
  if (code == 2) return Colors.lightBlue.shade400;       // 🌥️ Nuvoloso parziale
  if (code == 3) return Colors.blueGrey.shade600;        // ☁️ Coperto
  if (code >= 45 && code <= 48) return Colors.grey.shade700; // 🌫️ Nebbia
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return Colors.indigo; // 🌧️ Pioggia
  if (code >= 71 && code <= 77) return Colors.cyan;      // ❄️ Neve
  if (code >= 95) return Colors.deepPurple;              // ⛈️ Temporale
  return Colors.blueGrey;
}

  Color _colorFromClass(String cls) {
  switch (cls) {
    case 'G':
      return Colors.green;
    case 'Y':
      return Colors.amber;
    case 'R':
      return Colors.red;
    default:
      return Colors.grey;
  }
}


  Widget _buildHeader() {
    final localizations = AppLocalizations.of(context);
    final welcomeText = localizations?.welcome ?? 'Welcome';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF236FC6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text('$welcomeText, ${widget.username}!',

              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.apartmentNames[selectedApartment] ?? selectedApartment} - $selectedRoom', style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
              GestureDetector(
                onTap: () => setState(() => showDropdown = !showDropdown),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.edit, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String selectedValue,
    List<String> options,
    void Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueGrey),
              onChanged: onChanged,
              items: options
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(widget.apartmentNames[e] ?? e, style: const TextStyle(fontSize: 16)),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
  String title,
  String value,
  IconData icon,
  Color color,
) {
  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    elevation: 6,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(fontSize: 14, color: Colors.black54)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 40),
          ),
        ],
      ),
    ),
  );
}

Widget _buildAlertBanner(AlertMessage alert, MqttAlertManager manager, String roomLabel) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.red[700],
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: Row(
      children: [
        const Icon(Icons.warning, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${_fmt(alert.timestamp)} • $roomLabel ${alert.roomId.toUpperCase()}: ${AlertCatalog.translate(alert.message, Localizations.localeOf(context))}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            manager.removeAlert(alert);
          },
        ),
      ],
    ),
  );
}




  Widget _buildOverallScoreCard(int p, Color c) {
  return Center(
    child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(AppLocalizations.of(context)?.overallScore ?? 'Overall Score', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: p / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey[300],
                    color: c,
                  ),
                ),
                Text('$p%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}


  // ─────────────────────────────── build
  @override
  Widget build(BuildContext context) {
    // 1️⃣  Localizzazione (può essere null al primo frame)
  final loc = AppLocalizations.of(context);
  final roomLabel = loc?.alertRoomLabel ?? 'Room';

  // 2️⃣  Etichette tradotte con fallback di default
  final tSelectApartment = loc?.selectApartment            ?? 'Select Apartment';
  final tSelectRoom      = loc?.selectRoom                 ?? 'Select Room';
  final tHumidity        = loc?.humidityLevel              ?? 'Humidity Level';
  final tAirQuality      = loc?.airQuality                 ?? 'Air Quality';
  final tExtMeteo        = loc?.externalTemperatureMeteo   ?? 'External Temperature • Open-Meteo';
  final tTempRoom        = selectedRoom.toLowerCase() == 'exterior'
        ? (loc?.externalTemperatureSensor ?? 'External Temperature • Sensor')
        : (loc?.indoorTemperature         ?? 'Indoor Temperature');
  final tWelcome         = loc?.welcome                    ?? 'Welcome';
  final alertManager = Provider.of<MqttAlertManager>(context);
final now = DateTime.now();
final hour = now.hour;
final isDay = hour >= 6 && hour <= 19;
final relevantAlerts = alertManager.allAlerts.where((a) {
  final sameApartment = a.apartmentId == selectedApartment;
  final correctRoom = apartmentType == 'House' || a.roomId == selectedRoom;
  final sameDay = a.timestamp.year == now.year &&
                  a.timestamp.month == now.month &&
                  a.timestamp.day == now.day;
  return sameApartment && correctRoom && sameDay;
}).toList()
  ..sort((a, b) => b.timestamp.compareTo(a.timestamp));



    

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        automaticallyImplyLeading: false, 
        backgroundColor: Colors.white,
        elevation: 2,
        title: null,
        actions: [
          SuggestionsBell(
            username: widget.username,
            apartmentId: selectedApartment,
            roomId: selectedRoom,
            isTechnical: false,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), // 👈 AGGIUNTO
      padding: const EdgeInsets.all(16),
      child: Column(
  children: [
    ...relevantAlerts.map((a) => _buildAlertBanner(a, alertManager, roomLabel)),


            _buildHeader(),

            const SizedBox(height: 20),

            // dropdown se visibile
            if (showDropdown) ...[
              _buildDropdown(
              tSelectApartment,
              selectedApartment,
              widget.apartments,
              (v) async {
                if (v == null) return;

                final sameApartment = selectedApartment == v;

                setState(() {
                  selectedApartment = v;
                  selectedRoom = widget.rooms[v]?.first ?? 'Unknown';
                  widget.onApartmentChanged(v);
                  widget.onRoomChanged(selectedRoom);
                  showDropdown = false;
                });

                await _fetchApartmentCoordinates(); // 🔁 aggiorna lat/lon
                if (sameApartment) {
                  // 🔁 forza aggiornamento se è lo stesso apartment
                  _fetchExternalWeatherData();
                }
                _fetchRoomData(); // 🔁 sempre aggiorna stanza
              },
            ),


              const SizedBox(height: 10),
              _buildDropdown(
                    tSelectRoom,
                    selectedRoom,
                    (widget.rooms[selectedApartment] ?? ['Unknown'])
                      .where((room) => room.toLowerCase() != 'exterior')
                      .toList(),
                    (v) {
                      if (v == null) return;
                      setState(() {
                        selectedRoom = v;
                        widget.onRoomChanged(v);
                        showDropdown = false;
                        _fetchRoomData();
                        _fetchApartmentCoordinates();
                      });
                    },
                  ),

              const SizedBox(height: 20),
            ],

            _buildInfoCard(
              tExtMeteo,
              externalTemp,
              _getWeatherIcon(weatherCode, isDay),
              _getWeatherColor(weatherCode),
            ),
            const SizedBox(height: 12),
            _buildInfoCard(
              tTempRoom,  indoorTemp,
              Icons.thermostat,
              _colorFromClass(tempClass),
            ),

            const SizedBox(height: 12),
            _buildInfoCard(
              tHumidity,
              humidity,
              Icons.water_drop,
              _colorFromClass(humidityClass),
            ),
            const SizedBox(height: 12),
            _buildInfoCard(
              tAirQuality, co2,
              Icons.air,
              _colorFromClass(co2Class),
            ),

            const SizedBox(height: 30),
            _buildOverallScoreCard(environmentScore, _colorFromClass(environmentClass)),

          ],
        ),
      ),
    );
    
  }
}

String _fmt(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

