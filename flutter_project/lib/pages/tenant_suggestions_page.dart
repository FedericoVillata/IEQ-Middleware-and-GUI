// pages/tenant_suggestions_page.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../app_config.dart';
import '../mqtt_suggestions_manager.dart';
import '../suggestion_vote_mqtt_publisher.dart';
import '../utils/suggestion_catalog.dart';

class TenantSuggestionsPage extends StatefulWidget {
  final String username;
  final String apartmentId;
  final String roomId;
  final Map<String, List<String>> rooms;

  const TenantSuggestionsPage({
    super.key,
    required this.username,
    required this.apartmentId,
    required this.roomId,
    required this.rooms,
  });

  @override
  State<TenantSuggestionsPage> createState() => _TenantSuggestionsPageState();
}

// ────────────────────────────────────────────────────────────────────────────
//                       S T A T E
// ────────────────────────────────────────────────────────────────────────────
class _TenantSuggestionsPageState extends State<TenantSuggestionsPage> {
  late String _selectedRoomId;

  // Dati scaricati via GET
  final Map<String, int> _serverUp = {};
  final Map<String, int> _serverDown = {};

  // Delta prodotti dall’utente nella sessione corrente
  final Map<String, int> _deltaUp = {};
  final Map<String, int> _deltaDown = {};

  // Per la logica “≥5 voti e 70 % down → disattiva”
  final Map<String, int> _localTotalVotes = {};
  final Map<String, int> _localDownVotes = {};
  late SharedPreferences _prefs;

  // ─────────────  INIT  ─────────────
  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.roomId;

    Future.microtask(() async {
      _prefs = await SharedPreferences.getInstance();
      await _refreshRoom(_selectedRoomId);
    });
  }

  // ─────────────  cambio stanza  ─────────────
  void _onRoomSelected(String newRoom) {
    setState(() => _selectedRoomId = newRoom);
    _refreshRoom(newRoom);
  }

  // ─────────────  REFRESH (GET + reset)  ─────────────
  Future<void> _refreshRoom(String room) async {
    await _loadThresholdMaps(room);          // 70 % logic
    await _fetchDailySuggestionVotes(room);  // GET voti
    setState(() {});
  }

  // Carica da SharedPreferences solo per la logica di disattivazione
  Future<void> _loadThresholdMaps(String room) async {
    _localTotalVotes.clear();
    _localDownVotes.clear();

    final keys = _prefs.getKeys();
    for (final k in keys.where((k) => k.contains('|$room|'))) {
      if (k.startsWith('vote_total_')) {
        _localTotalVotes[k.replaceFirst('vote_total_', '')] =
            _prefs.getInt(k) ?? 0;
      } else if (k.startsWith('vote_down_')) {
        _localDownVotes[k.replaceFirst('vote_down_', '')] =
            _prefs.getInt(k) ?? 0;
      }
    }
  }

  // ─────────────  GET voti dal server  ─────────────
  Future<void> _fetchDailySuggestionVotes(String room) async {
    _serverUp.clear();
    _serverDown.clear();
    _deltaUp.clear();
    _deltaDown.clear();

    final now = DateTime.now().toUtc();
    final dayId = '${now.year}-${now.month}-${now.day}';
    final start =
        DateTime(now.year, now.month, now.day).toIso8601String() + 'Z';
    final stop =
        DateTime(now.year, now.month, now.day + 1).toIso8601String() + 'Z';

    final uri = Uri.parse(
      '${AppConfig.adaptorUrl}/getDataInPeriod/'
      '${widget.username}/${widget.apartmentId}'
      '?measurement=suggestion_votes&start=$start&stop=$stop',
    );

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        debugPrint('GET votes error: ${res.statusCode}');
        return;
      }

      final list = jsonDecode(res.body) as List;
      for (final e in list) {
        if (e['room'] != room) continue;

        final key =
            '${widget.apartmentId}|$room|${e['ID']}|$dayId';

        if (e['v'] == '+1') {
          _serverUp[key] = (_serverUp[key] ?? 0) + 1;
        } else {
          _serverDown[key] = (_serverDown[key] ?? 0) + 1;
        }
      }
    } catch (err) {
      debugPrint('GET votes exception: $err');
    }
  }

  // ─────────────  helper per UI  ─────────────
  int _up(String k) => (_serverUp[k] ?? 0) + (_deltaUp[k] ?? 0);
  int _down(String k) => (_serverDown[k] ?? 0) + (_deltaDown[k] ?? 0);

  // ─────────────  KEY univoco  ─────────────
  String _key(TenantSuggestion s) {
    final d = s.timestamp;
    final date = '${d.year}-${d.month}-${d.day}';
    return '${s.apartmentId}|${s.roomId}|${s.code}|$date';
  }

  // ─────────────  VOTE handlers  ─────────────
  Future<void> _handleUpVote(TenantSuggestion s) async {
    final k = _key(s);
    _deltaUp[k] = (_deltaUp[k] ?? 0) + 1;
    setState(() {});

    _showSnack('${AppLocalizations.of(context)!.usefulVote} • ${_up(k)} 👍',
        color: Colors.green);
    await _sendVoteMQTT(s, 1);
  }

  Future<void> _handleDownVote(TenantSuggestion s) async {
    final k = _key(s);
    _deltaDown[k] = (_deltaDown[k] ?? 0) + 1;

    // logica 70 %
    _localTotalVotes[k] = (_localTotalVotes[k] ?? 0) + 1;
    _localDownVotes[k] = (_localDownVotes[k] ?? 0) + 1;
    await _prefs.setInt('vote_total_$k', _localTotalVotes[k]!);
    await _prefs.setInt('vote_down_$k', _localDownVotes[k]!);

    setState(() {});

    _showSnack('${AppLocalizations.of(context)!.notUsefulVote} • ${_down(k)} 👎',
        color: Colors.red);
    await _sendVoteMQTT(s, -1);

    // eventuale disattivazione (identico a prima)
    final total = _localTotalVotes[k]!;
    final downs = _localDownVotes[k]!;
    if (total >= 5 && downs / total >= 0.7) {
      if (await _deactivateSuggestion(s)) {
        if (!mounted) return;
        context.read<MqttSuggestionsManager>().removeTenantSuggestion(s);
        _serverUp.remove(k);
        _serverDown.remove(k);
        _deltaUp.remove(k);
        _deltaDown.remove(k);
        _localTotalVotes.remove(k);
        _localDownVotes.remove(k);
        await _prefs.remove('vote_total_$k');
        await _prefs.remove('vote_down_$k');
      }
    }
  }

  // ─────────────  UI  ─────────────
  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<MqttSuggestionsManager>();

    // filtro suggestions del giorno/stanza (come nel tuo codice originale)
    final suggestions = <String, TenantSuggestion>{};
    final now = DateTime.now();
    for (final s in mgr.allTenantSuggestions) {
      final sameDay   = s.timestamp.year == now.year &&
                        s.timestamp.month == now.month &&
                        s.timestamp.day == now.day;
      final sameRoom  = s.apartmentId == widget.apartmentId &&
                        s.roomId == _selectedRoomId;
      if (sameDay && sameRoom && s.code != 'value') {
        suggestions['${s.code}|${s.message}'] = s;
      }
    }
    final list = suggestions.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final roomList = widget.rooms[widget.apartmentId] ?? [];

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
        title: Text(AppLocalizations.of(context)!.dailySuggestionsHistory,
            style: const TextStyle(color: Colors.black)),
      ),
      body: Column(
        children: [
          //  scelta stanza
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child:SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  child: Row(
    children: roomList
        .where((r) => r.toLowerCase() != 'exterior')
        .map((room) {
      final selected = room == _selectedRoomId;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InputChip(
          avatar: Icon(Icons.meeting_room,
              color: selected ? Colors.white : Colors.grey[700], size: 20),
          label: Text(room),
          selected: selected,
          selectedColor: Colors.blueAccent,
          onSelected: (_) => _onRoomSelected(room),
          labelStyle:
              TextStyle(color: selected ? Colors.white : Colors.black),
          backgroundColor: Colors.white,
          elevation: 2,
          pressElevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }).toList(),
  ),
),

          ),
          const SizedBox(height: 8),
          //  lista suggestion
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context)!.noSuggestionsToday,
                      style: const TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final s = list[i];
                      final k = _key(s);
                      return _SuggestionCard(
                        suggestion: s,
                        upVotes: _up(k),
                        downVotes: _down(k),
                        onUpVote: _handleUpVote,
                        onDownVote: _handleDownVote,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────  utility UI  ─────────────
  void _showSnack(String txt, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(txt), backgroundColor: color),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  // ─────────────  MQTT / Registry helpers (inalterati)  ─────────────
  Future<void> _sendVoteMQTT(TenantSuggestion s, int score) async {
    await SuggestionVoteMqttPublisher.instance.init(
      broker: AppConfig.mqttBroker,
      port: kIsWeb ? 443 : AppConfig.mqttPort,
    );
    await SuggestionVoteMqttPublisher.instance.publishVote(
      apartmentId: widget.apartmentId,
      suggestionId: s.code,
      roomId: s.roomId,
      username: widget.username,
      score: score,
    );
  }

  Future<bool> _deactivateSuggestion(TenantSuggestion s) async {
    final url = '${AppConfig.registryUrl}/deactivate_suggestion';
    final body = {
      'suggestionId': s.code,
      'apartmentId': s.apartmentId,
      'roomId': s.roomId,
    };
    try {
      final r = await http.put(Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));
      if (r.statusCode == 200) {
        _showSnack(AppLocalizations.of(context)!.suggestionDeactivated,
            color: Colors.red);
        return true;
      }
    } catch (e) {
      _showSnack('${AppLocalizations.of(context)!.networkError}: $e',
          color: Colors.red);
    }
    return false;
  }
}

// ────────────────────────────────────────────────────────────────────────────
//                       C A R D   +   B U T T O N
// ────────────────────────────────────────────────────────────────────────────
class _SuggestionCard extends StatelessWidget {
  final TenantSuggestion suggestion;
  final int upVotes;
  final int downVotes;
  final void Function(TenantSuggestion) onUpVote;
  final void Function(TenantSuggestion) onDownVote;

  const _SuggestionCard({
    required this.suggestion,
    required this.upVotes,
    required this.downVotes,
    required this.onUpVote,
    required this.onDownVote,
  });

  @override
  Widget build(BuildContext context) {
    String _fmt(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      SuggestionCatalog.translate(
                          suggestion.code, Localizations.localeOf(context)),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${suggestion.roomId}/${suggestion.code} • ${_fmt(suggestion.timestamp)}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ]),
            ),
            _VoteButton(
              icon: Icons.thumb_down,
              color: Colors.red,
              count: downVotes,
              onTap: () => onDownVote(suggestion),
            ),
            const SizedBox(width: 4),
            _VoteButton(
              icon: Icons.thumb_up,
              color: Colors.green,
              count: upVotes,
              onTap: () => onUpVote(suggestion),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;

  const _VoteButton({
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: Icon(icon, color: color), onPressed: onTap),
        if (count > 0)
          Text('$count',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
