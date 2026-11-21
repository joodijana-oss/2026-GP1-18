import 'package:flutter/material.dart';

import '../../screens/home_screen.dart';
import '../../theme/app_colors.dart';

/// The Community screen.
///
/// Home, Explore and Profile open it from their bottom bar with
/// Navigator.push, so the tab the user came from stays underneath. The back
/// arrow and the phone's back button both return to it.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  // The back arrow: close this screen to show the one underneath. If there
  // is nothing underneath, open Home instead of leaving an empty screen.
  void _goBack(BuildContext context) {
    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The same header as Opportunity Radar and the Certification
            // Recommender. The back button's 48 dp touch area is taller
            // than the title, so the top space is 9.5 less ((48 - 29) / 2).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6.5, 20, 0),
              child: _buildHeader(context),
            ),

            // Placeholder until the Community feature is built
            Expanded(
              child: Center(
                child: Text(
                  'Community',
                  style: TextStyle(
                    color: AppColors.navyText,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        // A 48 dp touch area with a "Back" label for screen readers. It is
        // moved left by its extra padding ((48 - 21) / 2) so the arrow lines
        // up with the page edge, like on the other screens.
        Transform.translate(
          offset: const Offset(-13.5, 0),
          child: IconButton(
            onPressed: () => _goBack(context),
            tooltip: 'Back',
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.navyText,
              size: 21,
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Community',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.navyText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
