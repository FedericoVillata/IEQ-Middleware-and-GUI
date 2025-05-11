import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../mqtt_suggestions_manager.dart';
import '../app_config.dart';
import '../suggestion_vote_mqtt_publisher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';




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

class _TenantSuggestionsPageState extends State<TenantSuggestionsPage> {
  late String _selectedRoomId;

 @override
void initState() {
  super.initState();
  _selectedRoomId = widget.roomId;
  _loadVotesForRoom(_selectedRoomId);
}



  final Map<String, int> _downVotes = {};
  final Map<String, int> _upVotes = {};
  late SharedPreferences _prefs;
final Map<String, int> _localTotalVotes = {};
final Map<String, int> _localDownVotes = {};

   @override
  void didUpdateWidget(covariant TenantSuggestionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      setState(() => _selectedRoomId = widget.roomId);
      _loadVotesForRoom(widget.roomId);
    }
  }



  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<MqttSuggestionsManager>();

    final suggestions = <String, TenantSuggestion>{};

    for (final s in mgr.allTenantSuggestions) {
      final now = DateTime.now();
final isSameDay = s.timestamp.year == now.year &&
                  s.timestamp.month == now.month &&
                  s.timestamp.day == now.day;

final isSameRoom = s.apartmentId == widget.apartmentId && s.roomId == _selectedRoomId;
final isValid = s.code != 'value';

if (isSameRoom && isValid && isSameDay) {
  final key = '${s.code}|${s.message}';
  suggestions.putIfAbsent(key, () => s);
}

    }

    final deduplicatedList = suggestions.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _cleanupVotes(deduplicatedList);

   final roomList = widget.rooms[widget.apartmentId] ?? [];


    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        automaticallyImplyLeading: false, 
        backgroundColor: Colors.white,
        elevation: 2,
        title: Text(
  AppLocalizations.of(context)!.dailySuggestionsHistory,
  style: const TextStyle(color: Colors.black),
),

        centerTitle: true,
      ),
      
      body: Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
          children: roomList.where((room) => room.toLowerCase() != 'exterior').map((room) {
          final isSelected = room == _selectedRoomId;
          return InputChip(
  avatar: Icon(Icons.meeting_room, color: isSelected ? Colors.white : Colors.grey[700], size: 20),
  label: Text(room),
  selected: isSelected,
  selectedColor: Colors.blueAccent,
  onSelected: (_) {
    setState(() {
      _selectedRoomId = room;
      _loadVotesForRoom(room);
    });
  },
  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
  backgroundColor: Colors.white,
  elevation: 2,
  pressElevation: 5,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

        }).toList(),
      ),
    ),
    const SizedBox(height: 8),
   Expanded(
  child: suggestions.isEmpty
      ? SizedBox.expand(
          child: Center(
            child: Text(
              AppLocalizations.of(context)!.noSuggestionsToday,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        )

          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(), 
              padding: const EdgeInsets.all(16),
              itemCount: deduplicatedList.length,
              itemBuilder: (_, i) {
                final s = deduplicatedList[i];
                final key = _key(s);
                return _SuggestionCard(
                  suggestion: s,
                  downVotes: _downVotes[key] ?? 0,
                  upVotes: _upVotes[key] ?? 0,
                  onDownVote: _handleDownVote,
                  onUpVote: _handleUpVote,
                );
              },
            ),
    ),
  ],
),

    );
  }

  String _key(TenantSuggestion s) {
  final date = '${s.timestamp.year}-${s.timestamp.month}-${s.timestamp.day}';
  return '${s.apartmentId}|${s.roomId}|${s.code}|$date';
}



  void _cleanupVotes(List<TenantSuggestion> current) {
    final keys = current.map(_key).toSet();
    _downVotes.removeWhere((k, _) => !keys.contains(k));
    _upVotes.removeWhere((k, _) => !keys.contains(k));
  }

  void _showSnack(String txt, {Color? color}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt), backgroundColor: color));

  void _handleUpVote(TenantSuggestion s) async {
  final k = _key(s);
  _upVotes[k] = (_upVotes[k] ?? 0) + 1;

  // 🔐 Salva anche nei dati persistenti
  await _prefs.setInt('vote_up_$k', _upVotes[k]!);

  setState(() {}); // forzi aggiornamento visivo

_showSnack('${AppLocalizations.of(context)!.usefulVote} • ${_upVotes[k]} 👍', color: Colors.green);
  await _sendVoteMQTT(s, 1);
}
 Future<void> _loadVotesForRoom(String roomId) async {
  final prefs = await SharedPreferences.getInstance();
  _prefs = prefs;

  _downVotes.clear();
  _upVotes.clear();
  _localTotalVotes.clear();
  _localDownVotes.clear();

  final keys = prefs.getKeys();
  for (final k in keys.where((k) => k.startsWith('vote_total_'))) {
    final baseKey = k.replaceFirst('vote_total_', '');
    if (baseKey.contains('|$roomId|')) {
      _localTotalVotes[baseKey] = prefs.getInt(k) ?? 0;
    }
  }

  for (final k in keys.where((k) => k.startsWith('vote_down_'))) {
    final baseKey = k.replaceFirst('vote_down_', '');
    if (baseKey.contains('|$roomId|')) {
      final count = prefs.getInt(k) ?? 0;
      _localDownVotes[baseKey] = count;
      _downVotes[baseKey] = count;
    }
  }

  for (final k in keys.where((k) => k.startsWith('vote_up_'))) {
    final baseKey = k.replaceFirst('vote_up_', '');
    if (baseKey.contains('|$roomId|')) {
      _upVotes[baseKey] = prefs.getInt(k) ?? 0;
    }
  }

  setState(() {});
}



  Future<void> _handleDownVote(TenantSuggestion s) async {
  final k = _key(s);
  // Aggiorna i contatori in memoria
  _localTotalVotes[k] = (_localTotalVotes[k] ?? 0) + 1;
  _localDownVotes[k] = (_localDownVotes[k] ?? 0) + 1;

  // Salva i contatori su disco
  await _prefs.setInt('vote_total_$k', _localTotalVotes[k]!);
  await _prefs.setInt('vote_down_$k', _localDownVotes[k]!);

  // Aggiorna l'interfaccia
  setState(() {
    _downVotes[k] = (_downVotes[k] ?? 0) + 1;
  });

 _showSnack('${AppLocalizations.of(context)!.notUsefulVote} • ${_downVotes[k]} 👎', color: Colors.red);
  await _sendVoteMQTT(s, -1);

  // Controlla se deve essere disattivata
  final total = _localTotalVotes[k]!;
  final downs = _localDownVotes[k]!;
  final percent = downs / total;

  if (total >= 5 && percent >= 0.7) {
    if (await _deactivateSuggestion(s)) {
      if (!mounted) return;

      // Rimuovi suggestion e voti
      context.read<MqttSuggestionsManager>().removeTenantSuggestion(s);
      _downVotes.remove(k);
      _upVotes.remove(k);
      _localTotalVotes.remove(k);
      _localDownVotes.remove(k);

      // Elimina anche da SharedPreferences
      await _prefs.remove('vote_total_$k');
      await _prefs.remove('vote_down_$k');
    }
  }
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
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));

      if (r.statusCode == 200) {
        _showSnack(AppLocalizations.of(context)!.suggestionDeactivated, color: Colors.red);
        return true;
      }
      _showSnack('${AppLocalizations.of(context)!.error}: ${r.statusCode}: ${r.body}', color: Colors.red);

    } catch (e) {
      _showSnack('${AppLocalizations.of(context)!.networkError}: $e', color: Colors.red);
    }
    return false;
  }

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
}

String _fmt(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}



// ─────────────────────────────────────────────────────────────────────────────
class _SuggestionCard extends StatelessWidget {
  final TenantSuggestion suggestion;
  final int downVotes;
  final int upVotes;
  final void Function(TenantSuggestion) onDownVote;
  final void Function(TenantSuggestion) onUpVote;

  const _SuggestionCard({
    required this.suggestion,
    required this.downVotes,
    required this.upVotes,
    required this.onDownVote,
    required this.onUpVote,
  });

  @override
  Widget build(BuildContext context) {
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
                  Text(suggestion.message,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
  '${suggestion.roomId}/${suggestion.code} • ${_fmt(suggestion.timestamp)}',
  style: const TextStyle(fontSize: 13, color: Colors.grey),
),

                ],
              ),
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
          Text('$count', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}



