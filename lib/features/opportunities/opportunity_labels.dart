import 'package:flutter/material.dart';

import '../../models/opportunity.dart';
import '../../theme/app_colors.dart';

/// Small helpers shared by the Opportunity Radar screens.
class OpportunityLabels {
  OpportunityLabels._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "15 Dec 2026"
  static String date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// One icon for each opportunity type.
  static IconData typeIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'hackathon':
        return Icons.emoji_events_outlined;
      case 'bootcamp':
        return Icons.rocket_launch_outlined;
      case 'training program':
        return Icons.school_outlined;
      case 'meetup':
        return Icons.groups_outlined;
      case 'webinar':
        return Icons.videocam_outlined;
      case 'course':
        return Icons.menu_book_outlined;
      default:
        return Icons.track_changes_rounded;
    }
  }

  /// "Free", the price, "Paid", or null when the cost is not known.
  static String? cost(Opportunity o) {
    if (o.isFree == true) return 'Free';
    if (o.isFree == false) {
      final price = o.price.trim();
      return price.isEmpty ? 'Paid' : price;
    }
    return null;
  }

  /// "12 days left", "1 day left" or "Last day to register".
  static String daysLeft(int days) {
    if (days < 0) return 'Registration closed';
    if (days == 0) return 'Last day to register';
    if (days == 1) return '1 day left';
    return '$days days left';
  }

  /// A deadline this close is highlighted.
  static bool isUrgent(int? days) => days != null && days <= 7;

  /// Text colour for a close deadline (readable in light and dark mode).
  static Color get urgentText =>
      AppColors.isDark ? const Color(0xFFF2B544) : const Color(0xFF9A5B00);

  /// "A, B, C" and how many are left out ("+2 more").
  static ({String shown, int more}) shortList(
    List<String> items, {
    int max = 3,
  }) {
    final shown = items.take(max).join(', ');
    final more = items.length > max ? items.length - max : 0;
    return (shown: shown, more: more);
  }
}
