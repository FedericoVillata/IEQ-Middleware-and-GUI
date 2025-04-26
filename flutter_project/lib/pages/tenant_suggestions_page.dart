// pages/tenant_suggestions_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../mqtt_suggestions_manager.dart';
import '../app_config.dart';

class TenantSuggestionsPage extends StatefulWidget {
  final String username;
  final String apartmentId;
  final String roomId;

  const TenantSuggestionsPage({
    super.key,
    required this.username,
    required this.apartmentId,
    required this.roomId,
  });

  @override
  State<TenantSuggestionsPage> createState() => _TenantSuggestionsPageState();
}

class _TenantSuggestionsPageState extends State<TenantSuggestionsPage> {
  /// key = "<apt>|<room>|<code>|<epoch-ms>"
  final Map<String, int> _downVotes = {};
  final Map<String, int> _upVotes   = {};

  //────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<MqttSuggestionsManager>();

    final suggestions = mgr.allTenantSuggestions
        .where((s) =>
            s.apartmentId == widget.apartmentId &&
            s.roomId      == widget.roomId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // ogni rebuild ⇒ tutte le suggestion di questa stanza diventano “lette”
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MqttSuggestionsManager>()
          .markTenantRead(widget.apartmentId, widget.roomId);
    });

    _cleanupVotes(suggestions);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: Text('Suggestions – ${widget.roomId}',
            style: const TextStyle(color: Colors.black)),
        centerTitle: true,
      ),
      body: suggestions.isEmpty
          ? const Center(
              child: Text('No suggestions available for the selected room.',
                  style: TextStyle(fontSize: 16)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: suggestions.length,
              itemBuilder: (_, i) {
                final s   = suggestions[i];
                final key = _key(s);
                return _SuggestionCard(
                  suggestion : s,
                  downVotes  : _downVotes[key] ?? 0,
                  upVotes    : _upVotes[key]   ?? 0,
                  onDownVote : _handleDownVote,
                  onUpVote   : _handleUpVote,
                );
              },
            ),
    );
  }

  //──────────────────── helpers ──────────────────────────────────────────
  String _key(TenantSuggestion s) =>
      '${s.apartmentId}|${s.roomId}|${s.code}|${s.timestamp.millisecondsSinceEpoch}';

  void _cleanupVotes(List<TenantSuggestion> current) {
    final keys = current.map(_key).toSet();
    _downVotes.removeWhere((k, _) => !keys.contains(k));
    _upVotes  .removeWhere((k, _) => !keys.contains(k));
  }

  void _showSnack(String txt, {Color? color}) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(txt), backgroundColor: color));

  //----------------------------  UP-VOTE  --------------------------------
  void _handleUpVote(TenantSuggestion s) {
    final k = _key(s);
    setState(() => _upVotes[k] = (_upVotes[k] ?? 0) + 1);

    _showSnack(
      'Useful • ${_upVotes[k]} 👍',
      color: Colors.green,
    );
  }

  //---------------------------  DOWN-VOTE  -------------------------------
  Future<void> _handleDownVote(TenantSuggestion s) async {
    final k    = _key(s);
    final curr = _downVotes[k] ?? 0;

    if (curr == 0) {
      setState(() => _downVotes[k] = 1);
      _showSnack('Not useful • 1 👎  (tap again to hide)', color: Colors.red);
      return;
    }

    // secondo tap → disattiva
    setState(() => _downVotes[k] = 2);
    if (await _deactivateSuggestion(s)) {
      context.read<MqttSuggestionsManager>().removeTenantSuggestion(s);
      _downVotes.remove(k);
      _upVotes.remove(k);
    }
  }

  //------------------ REST call: deactivate ------------------------------
  Future<bool> _deactivateSuggestion(TenantSuggestion s) async {
    final url  = '${AppConfig.registryUrl}/deactivate_suggestion';
    final body = {
      'suggestionId' : s.code,
      'apartmentId'  : s.apartmentId,
      'roomId'       : s.roomId,
    };

    try {
      final r = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (r.statusCode == 200) {
        _showSnack('Suggestion deactivated', color: Colors.red);
        return true;
      }
      _showSnack('Error ${r.statusCode}: ${r.body}', color: Colors.red);
    } catch (e) {
      _showSnack('Network error: $e', color: Colors.red);
    }
    return false;
  }
}

//──────────────────────── CARD WIDGET ───────────────────────────────────
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
            // testo ----------------------------------------------------------
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.message,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    '${suggestion.code}  •  '
                    '${suggestion.timestamp.toLocal().toString().substring(11,16)}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            // voti -----------------------------------------------------------
            _VoteButton(
              icon : Icons.thumb_down,
              color: Colors.red,
              count: downVotes,
              onTap : () => onDownVote(suggestion),
            ),
            const SizedBox(width: 4),
            _VoteButton(
              icon : Icons.thumb_up,
              color: Colors.green,
              count: upVotes,
              onTap : () => onUpVote(suggestion),
            ),
          ],
        ),
      ),
    );
  }
}

//───────────────────── vote button helper ───────────────────────────────
class _VoteButton extends StatelessWidget {
  final IconData    icon;
  final Color       color;
  final int         count;
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
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
