import 'package:flutter/material.dart';

import '../features/career_comparator/career_comparator_screen.dart';
import '../features/heatmap/heatmap_screen.dart';
import '../features/job_match/job_match_screen.dart';
import '../features/learning_roadmap/learning_roadmap_screen.dart';
import '../features/mock_interview/mock_interview_screen.dart';
import '../features/project_discovery/project_discovery_screen.dart';
import '../theme/app_colors.dart';

/// Feature screens that are not built yet. Each one opens the "Coming soon"
/// placeholder page. Every card and tile that opens one of them shows a
/// "Soon" badge. When a feature is built, delete its line here and its
/// badges go away on every screen.
const Set<Type> comingSoonScreens = {
  CareerComparatorScreen,
  LearningRoadmapScreen,
  ProjectDiscoveryScreen,
  JobMatchScreen,
  MockInterviewScreen,
  HeatmapScreen,
};

/// True when [page] is one of the [comingSoonScreens].
bool isComingSoon(Widget? page) =>
    page != null && comingSoonScreens.contains(page.runtimeType);

/// The same check for a route builder (Home keeps its destinations as
/// builders). The builders only create the screen widget, so calling one
/// here builds or opens nothing.
bool opensComingSoon(BuildContext context, WidgetBuilder? builder) =>
    builder != null && isComingSoon(builder(context));

/// A small "Soon" pill for a card or tile that opens a feature that is not
/// built yet. It usually sits on its own line under the card's text (a card
/// with a fixed height shows it in its top row instead). It never changes
/// what a tap does.
///
/// - The default size has a small clock and is for cards.
/// - [small] has no clock and is for the Home quick action tiles, which are
///   narrow on small phones.
/// - [onBrand] is for a navy card ("Your Next Step"), where the usual navy
///   text would not show in light mode.
///
/// Screen readers hear "Coming soon" instead of "Soon". Inside a card or
/// tile that is tapped as a whole, it is read with that card or tile. Where
/// only a button or link opens the feature ("Your Next Step", Saudi Market
/// Insight), the badge is hidden from screen readers and that button or link
/// says "Coming soon" instead.
class SoonBadge extends StatelessWidget {
  final bool small;
  final bool onBrand;

  const SoonBadge({super.key, this.small = false, this.onBrand = false});

  @override
  Widget build(BuildContext context) {
    final textColor = onBrand ? AppColors.onBrand : AppColors.navyText;

    // A minimum height instead of a fixed one, so large system text grows
    // the pill instead of cutting the word off.
    final Widget pill = Container(
      constraints: BoxConstraints(minHeight: small ? 16 : 22),
      padding: small
          ? const EdgeInsets.symmetric(horizontal: 6)
          : const EdgeInsets.only(left: 7, right: 9),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!small) ...[
            Icon(Icons.schedule_rounded, size: 12, color: AppColors.gold),
            const SizedBox(width: 4),
          ],
          Text(
            'Soon',
            maxLines: 1,
            style: TextStyle(
              color: textColor,
              fontSize: small ? 9.5 : 11.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: 'Coming soon',
      child: ExcludeSemantics(
        // When there is room this changes nothing. When there isn't (a quick
        // action tile is only about 62 wide on a small phone, and a card's
        // top row is tight with large text), the pill shrinks to fit instead
        // of overflowing.
        child: FittedBox(fit: BoxFit.scaleDown, child: pill),
      ),
    );
  }
}
