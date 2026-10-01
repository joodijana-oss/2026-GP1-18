
import 'package:flutter/material.dart';

// Main screens
import 'home_screen.dart';
import 'profile_screen.dart';
import '../features/community/community_screen.dart';
import '../theme/app_colors.dart';

// Feature screens
import '../features/career_analysis/career_analysis_screen.dart';
import '../features/career_comparator/career_comparator_screen.dart';
import '../features/certifications/certifications_screen.dart';
import '../features/cv_improvement/cv_improvement_screen.dart';
import '../features/heatmap/heatmap_screen.dart';
import '../features/job_match/job_match_screen.dart';
import '../features/learning_roadmap/learning_roadmap_screen.dart';
import '../features/mock_interview/mock_interview_screen.dart';
import '../features/opportunities/opportunities_screen.dart';
import '../features/project_discovery/project_discovery_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  int _currentIndex = 1;
  String _searchQuery = '';

  // ------------------------------------------------------------
  // Colors
  // ------------------------------------------------------------

  static const Color navy = Color(0xFF16324F);
  static const Color teal = Color(0xFF2D8C99);
  static const Color lightTeal = Color(0xFFEAF4F5);
  static const Color gold = Color(0xFFC69225);
  static const Color background = AppColors.background;
  static const Color greyText = Color(0xFF71808F);

  // ------------------------------------------------------------
  // Feature data
  // ------------------------------------------------------------

  final List<ExploreFeature> _features = [
    ExploreFeature(
      title: 'AI Career Analysis',
      description: 'Understand your career readiness',
      category: 'UNDERSTAND YOURSELF',
      icon: Icons.psychology_outlined,
      page: const CareerAnalysisScreen(),
    ),
    ExploreFeature(
      title: 'Career Path Comparator',
      description: 'Compare two career paths',
      category: 'UNDERSTAND YOURSELF',
      icon: Icons.alt_route_rounded,
      page: const CareerComparatorScreen(),
    ),
    ExploreFeature(
      title: 'Personalized Learning Roadmap',
      description: 'Your guided skill journey',
      category: 'DEVELOP YOUR SKILLS',
      icon: Icons.account_tree_outlined,
      page: const LearningRoadmapScreen(),
    ),
    ExploreFeature(
      title: 'Professional Certification Recommender',
      description: 'Find the right certifications',
      category: 'DEVELOP YOUR SKILLS',
      icon: Icons.workspace_premium_outlined,
      page: const CertificationsScreen(),
    ),
    ExploreFeature(
      title: 'Opportunity Radar',
      description: 'Discover development opportunities',
      category: 'DEVELOP YOUR SKILLS',
      icon: Icons.track_changes_rounded,
      page: const OpportunitiesScreen(),
    ),
    ExploreFeature(
      title: 'Smart Project Discovery',
      description: 'GitHub projects matched to you',
      category: 'DEVELOP YOUR SKILLS',
      icon: Icons.code_rounded,
      page: const ProjectDiscoveryScreen(),
    ),
    ExploreFeature(
      title: 'CV Improvement Assistant',
      description: 'Optimize your CV with AI',
      category: 'PREPARE FOR JOBS',
      icon: Icons.edit_document,
      page: const CVImprovementScreen(),
    ),
    ExploreFeature(
      title: 'Job Match',
      description: 'Compare your profile to a job',
      category: 'PREPARE FOR JOBS',
      icon: Icons.business_center_outlined,
      page: const JobMatchScreen(),
    ),
    ExploreFeature(
      title: 'AI Mock Interview Simulator',
      description: 'Practice with AI interviews',
      category: 'PREPARE FOR JOBS',
      icon: Icons.chat_bubble_outline_rounded,
      page: const MockInterviewScreen(),
    ),
    ExploreFeature(
      title: 'Job Demand Heatmap',
      description: 'Explore demand across Saudi Arabia',
      category: 'UNDERSTAND THE SAUDI MARKET',
      icon: Icons.map_outlined,
      page: const HeatmapScreen(),
    ),
  ];

  // ------------------------------------------------------------
  // Search
  // ------------------------------------------------------------

  List<ExploreFeature> get _filteredFeatures {
    if (_searchQuery.trim().isEmpty) {
      return _features;
    }

    final query = _searchQuery.toLowerCase();

    return _features.where((feature) {
      return feature.title.toLowerCase().contains(query) ||
          feature.description.toLowerCase().contains(query) ||
          feature.category.toLowerCase().contains(query);
    }).toList();
  }

  // ------------------------------------------------------------
  // Navigation
  // ------------------------------------------------------------

  void _openFeature(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _onBottomNavTap(int index) {
    if (index == _currentIndex) return;

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        ),
      );
    }

    if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CommunityScreen(),
        ),
      );
    }

    if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ProfileScreen(),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredFeatures;

    return Scaffold(
      backgroundColor: background,

      // --------------------------------------------------------
      // App Bar
      // --------------------------------------------------------

      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 118,

        title: Padding(
          padding: const EdgeInsets.only(
            top: 4,
            left: 4,
            right: 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                height: 42,
                child: Image.asset(
                  'lib/assets/images/Logoo.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Explore',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                'All career development tools',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),

      // --------------------------------------------------------
      // Body
      // --------------------------------------------------------

      body: Column(
        children: [
          // Search bar

          Container(
            color: background,
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              24,
            ),
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE8EDF0),
                ),
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: const TextStyle(
                  color: navy,
                  fontSize: 16,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: greyText,
                    size: 29,
                  ),
                  hintText: 'Search features...',
                  hintStyle: TextStyle(
                    color: Color(0xFFA5AFB8),
                    fontSize: 17,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 17,
                  ),
                ),
              ),
            ),
          ),

          // Features

          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      26,
                      20,
                      110,
                    ),
                    children: _buildFeatureSections(filtered),
                  ),
          ),
        ],
      ),

      // --------------------------------------------------------
      // Bottom Navigation
      // --------------------------------------------------------

      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ------------------------------------------------------------
  // Sections
  // ------------------------------------------------------------

  List<Widget> _buildFeatureSections(
    List<ExploreFeature> features,
  ) {
    final categories = <String>[
      'UNDERSTAND YOURSELF',
      'DEVELOP YOUR SKILLS',
      'PREPARE FOR JOBS',
      'UNDERSTAND THE SAUDI MARKET',
    ];

    final List<Widget> widgets = [];

    for (final category in categories) {
      final categoryFeatures = features
          .where((feature) => feature.category == category)
          .toList();

      if (categoryFeatures.isEmpty) continue;

      widgets.add(
        _buildSectionTitle(category),
      );

      widgets.add(
        const SizedBox(height: 14),
      );

      for (int i = 0; i < categoryFeatures.length; i++) {
        widgets.add(
          _buildFeatureCard(categoryFeatures[i]),
        );

        if (i != categoryFeatures.length - 1) {
          widgets.add(
            const SizedBox(height: 14),
          );
        }
      }

      widgets.add(
        const SizedBox(height: 30),
      );
    }

    return widgets;
  }

  // ------------------------------------------------------------
  // Section title
  // ------------------------------------------------------------

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 28,
          decoration: BoxDecoration(
            color: gold,
            borderRadius: BorderRadius.circular(10),
          ),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: greyText,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // Feature Card
  // ------------------------------------------------------------

  Widget _buildFeatureCard(ExploreFeature feature) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _openFeature(feature.page),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 126,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFF0F2F4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon

              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: lightTeal,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Icon(
                  feature.icon,
                  color: teal,
                  size: 32,
                ),
              ),

              const SizedBox(width: 17),

              // Text

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      feature.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF172332),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      feature.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: greyText,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Arrow

              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: gold,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Empty search
  // ------------------------------------------------------------

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: lightTeal,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: teal,
                size: 45,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'No features found',
              style: TextStyle(
                color: navy,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Try searching for another career tool.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: greyText,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.lightGray.withValues(alpha: 0.8),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_rounded,
                label: 'Home',
              ),

              _buildNavItem(
                index: 1,
                icon: Icons.explore_rounded,
                label: 'Explore',
              ),

              _buildNavItem(
                index: 2,
                icon: Icons.groups_2_outlined,
                label: 'Community',
              ),

              _buildNavItem(
                index: 3,
                icon: Icons.person_outline_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool selected = _currentIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () => _onBottomNavTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.lightTeal.withValues(
                            alpha: 0.58,
                          )
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: selected
                        ? AppColors.teal
                        : AppColors.secondaryText,
                  ),
                ),

                if (selected)
                  Positioned(
                    top: -4,
                    right: 2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 3),

            Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.teal
                    : AppColors.secondaryText,
                fontSize: 11,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Feature Model
// ================================================================

class ExploreFeature {
  final String title;
  final String description;
  final String category;
  final IconData icon;
  final Widget page;

  const ExploreFeature({
    required this.title,
    required this.description,
    required this.category,
    required this.icon,
    required this.page,
  });
}
