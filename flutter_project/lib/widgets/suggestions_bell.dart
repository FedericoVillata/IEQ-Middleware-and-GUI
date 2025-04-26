// widgets/suggestions_bell.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mqtt_suggestions_manager.dart';
import '../pages/technical_suggestions_page.dart';
import '../pages/tenant_suggestions_page.dart';
import '../technical_main.dart';
import '../tenant_main.dart';

/// Notification bell with popup and red badge indicator.
///
/// * **Technical** (`isTechnical = true`, default)
///   – shows the number of unread technical suggestions for the current apartment.
///
/// * **Tenant** (`isTechnical = false`)
///   – shows the number of unread tenant suggestions for the specified apartment and room.
class SuggestionsBell extends StatelessWidget {
  final String username;

  /// Apartment identifier (alias `location:` still accepted for backward compatibility)
  final String apartmentId;

  /// Legacy alias for apartmentId.
  final String? location;

  /// Room identifier (only for tenant suggestions).
  final String? roomId;

  /// `true` = technical suggestions (default), `false` = tenant suggestions.
  final bool isTechnical;

  const SuggestionsBell({
    super.key,
    required this.username,
    String? apartmentId,
    this.location,
    this.roomId,
    this.isTechnical = true,
  }) : apartmentId = apartmentId ?? location ?? '';

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<MqttSuggestionsManager>();

    // Count of unread suggestions
    final int unread = isTechnical
        ? mgr.unreadTechnicalCount(apartmentId)
        : mgr.unreadTenantCount(apartmentId, roomId ?? '');

    return InkResponse(
      customBorder: const CircleBorder(),
      containedInkWell: true,
      radius: 22,
      onTap: () {
        if (unread == 0) {
          _openSuggestions(context, mgr);
          return;
        }

        // Show popup if there are unread suggestions
        final message = isTechnical
            ? (unread == 1
                ? 'There is 1 technical suggestion in $apartmentId.'
                : 'There are $unread technical suggestions in $apartmentId.')
            : (unread == 1
                ? 'There is 1 suggestion in room $roomId.'
                : 'There are $unread suggestions in room $roomId.');

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('New suggestion arrived!'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openSuggestions(context, mgr);
                },
                child: const Text('See now'),
              ),
            ],
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none, size: 28),
          if (unread > 0)
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

  /// Navigate to the appropriate suggestions page and mark them as read.
  void _openSuggestions(BuildContext context, MqttSuggestionsManager mgr) {
    if (isTechnical) {
      mgr.markTechnicalRead(apartmentId);

      // If embedded in TechnicalMainPage, switch sidebar tab
      final techState = TechnicalMainPage.of(context);
      if (techState != null) {
        techState.goToSuggestions();
        return;
      }

      // Otherwise push full-screen page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TechnicalSuggestionsPage(
            username: username,
            location: apartmentId,
          ),
        ),
      );
    } else {
      mgr.markTenantRead(apartmentId, roomId ?? '');

      final tenantState = TenantMainPage.of(context);
      if (tenantState != null) {
        tenantState.goToSuggestionsTab();
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TenantSuggestionsPage(
            username: username,
            apartmentId: apartmentId,
            roomId: roomId ?? '',
          ),
        ),
      );
    }
  }
}
