import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mqtt_suggestions_manager.dart';
import '../technical_main.dart';                      // ← added
import '../pages/technical_suggestions_page.dart';

class SuggestionsBell extends StatelessWidget {
  final String? location;           // apartmentId
  final String username;            // technical user

  const SuggestionsBell({
    super.key,
    required this.location,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<MqttSuggestionsManager>();
    final int total = location == null
        ? 0
        : mgr.allSuggestions
            .where((s) => s.apartmentId == location)
            .length;

    return InkResponse(
      // circular splash instead of rectangular
      customBorder: const CircleBorder(),
      containedInkWell: true,
      radius: 22,
      onTap: () {
        // Prefer switching the sidebar tab if we are inside TechnicalMainPage
        final parent = TechnicalMainPage.of(context);
        if (parent != null) {
          parent.goToSuggestions();
        } else {
          // Fallback: open a full-screen page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TechnicalSuggestionsPage(
                username: username,
                location: location,
              ),
            ),
          );
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none, size: 28),
          if (total > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
