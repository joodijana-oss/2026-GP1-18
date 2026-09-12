import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  late AnimationController _entranceController;

  // ============================================================
  // TEMPORARY DATA
  // لاحقاً هذه البيانات تجي من Backend / Database / AI Model
  // ============================================================

  final String userName = 'Jood';

  final int readinessScore = 72;

  // 0 Analyze
  // 1 Develop
  // 2 Build
  // 3 Prepare
  final int currentJourneyStage = 1;

  final List<RecommendationItem> recommendations = const [
    RecommendationItem(
      type: 'Course',
      title: 'Machine Learning Specialization',
      provider: 'Coursera',
      reason: 'Based on your skill gaps',
      icon: Icons.menu_book_rounded,
    ),
    RecommendationItem(
      type: 'Certification',
      title: 'Google Data Analytics',
      provider: 'Google',
      reason: 'Matches your career interests',
      icon: Icons.workspace_premium_rounded,
    ),
    RecommendationItem(
      type: 'Project',
      title: 'Build a Data Dashboard',
      provider: 'Masra',
      reason: 'Strengthen your portfolio',
      icon: Icons.code_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();

    // نفس فكرة الحركة الهادئة الموجودة في صفحات البداية
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    // دخول عناصر الصفحة
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  String get greeting {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  Widget _animatedSection({
    required Widget child,
    required double start,
    required double end,
  }) {
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        start,
        end,
        curve: Curves.easeOutCubic,
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // Navigation ثابت تحت
      bottomNavigationBar: _buildBottomNavigation(),

      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _animatedSection(
                start: 0.00,
                end: 0.30,
                child: _buildTopSection(),
              ),

              const SizedBox(height: 28),

              _animatedSection(
                start: 0.10,
                end: 0.42,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildCareerJourney(),
                ),
              ),

              const SizedBox(height: 34),

              _animatedSection(
                start: 0.20,
                end: 0.55,
                child: _buildRecommendations(),
              ),

              const SizedBox(height: 36),

              _animatedSection(
                start: 0.30,
                end: 0.66,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildQuickActions(),
                ),
              ),

              const SizedBox(height: 36),

              _animatedSection(
                start: 0.42,
                end: 0.80,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildSaudiMarketInsight(),
                ),
              ),

              const SizedBox(height: 30),

              _animatedSection(
                start: 0.55,
                end: 1.00,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildExploreMasra(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TOP SECTION
  // ============================================================

  Widget _buildTopSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ======================================================
          // LOGO + NOTIFICATIONS + PROFILE
          // ======================================================

          Row(
            children: [
              Image.asset(
                'lib/assets/images/Logoo.png',
                width: 108,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Text(
                    'Masra',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),

              const Spacer(),

              _topIconButton(
                icon: Icons.notifications_none_rounded,
                showDot: true,
                onTap: () {
                  // TODO: Notifications page
                },
              ),

              const SizedBox(width: 10),

              GestureDetector(
                onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
      ),
    );
  },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.secondaryNavy,
                        AppColors.teal,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.teal.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    userName.isNotEmpty
                        ? userName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),

          Text(
            '$greeting, $userName',
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            "Let's continue building your career.",
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 23),

          // ======================================================
          // CAREER READINESS HERO CARD
          // ======================================================

          _buildCareerReadinessCard(),
        ],
      ),
    );
  }

  Widget _topIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool showDot = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.softBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.lightGray,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: AppColors.navy,
              size: 23,
            ),
          ),
        ),

        if (showDot)
          Positioned(
            top: 7,
            right: 7,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // CAREER READINESS
  // ============================================================

  Widget _buildCareerReadinessCard() {
  return AnimatedBuilder(
    animation: _backgroundController,
    builder: (context, child) {
      final value = _backgroundController.value;

      return Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.navy,
              AppColors.secondaryNavy,
              AppColors.teal,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.17),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -45 + (value * 10),
              top: -65 + (value * 12),
              child: Container(
                width: 155,
                height: 155,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.lightTeal.withValues(
                    alpha: 0.09,
                  ),
                ),
              ),
            ),

            Positioned(
              left: -50,
              bottom: -70 + (value * 8),
              child: Container(
                width: 135,
                height: 135,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.lightTeal.withValues(
                      alpha: 0.07,
                    ),
                    width: 20,
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: AppColors.white,
                          size: 27,
                        ),
                      ),

                      const SizedBox(width: 14),

                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Next Step',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Keep moving forward in your career journey',
                              style: TextStyle(
                                color: Color(0xFFC7D6DF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(
                            alpha: 0.18,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Develop',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Main next step
                  const Text(
                    'Build your skills',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Based on your skill gaps, continue developing the skills needed for your career path.',
                    style: TextStyle(
                      color: AppColors.white.withValues(
                        alpha: 0.76,
                      ),
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 21),

                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () {
                        // TODO:
                        // لاحقاً نربطه بالصفحة المناسبة للـ next step
                        // مثل Skill Gap / Learning Roadmap
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(
                            alpha: 0.11,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.white.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Continue',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 7),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: AppColors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

  // ============================================================
  // CAREER JOURNEY
  // ============================================================

  Widget _buildCareerJourney() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          title: 'Your Career Journey',
          subtitle:
              'See where you are and what comes next.',
        ),

        const SizedBox(height: 18),

        Container(
          height: 385,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.softBackground,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.lightGray,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.045),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: CareerPathPainter(
                    stage: currentJourneyStage,
                  ),
                ),
              ),

              Positioned(
                left: 24,
                top: 28,
                child: JourneyNode(
                  title: 'Analyze',
                  subtitle: 'Understand\nyour readiness',
                  icon: Icons.psychology_alt_rounded,
                  state: _journeyState(0),
                ),
              ),

              Positioned(
                right: 22,
                top: 105,
                child: JourneyNode(
                  title: 'Develop',
                  subtitle: 'Build your\nskills',
                  icon: Icons.auto_graph_rounded,
                  state: _journeyState(1),
                ),
              ),

              Positioned(
                left: 35,
                bottom: 78,
                child: JourneyNode(
                  title: 'Build',
                  subtitle: 'Gain real\nexperience',
                  icon: Icons.handyman_outlined,
                  state: _journeyState(2),
                ),
              ),

              Positioned(
                right: 20,
                bottom: 24,
                child: JourneyNode(
                  title: 'Prepare',
                  subtitle: 'Get job-ready',
                  icon: Icons.work_outline_rounded,
                  state: _journeyState(3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  JourneyState _journeyState(int stage) {
    if (stage < currentJourneyStage) {
      return JourneyState.completed;
    }

    if (stage == currentJourneyStage) {
      return JourneyState.current;
    }

    return JourneyState.locked;
  }

  // ============================================================
  // RECOMMENDATIONS
  // ============================================================

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Recommended for You',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),

              TextButton(
                onPressed: () {},
                child: const Text(
                  'See all',
                  style: TextStyle(
                    color: AppColors.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          height: 205,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: recommendations.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: 14),
            itemBuilder: (context, index) {
              return _recommendationCard(
                recommendations[index],
                index,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _recommendationCard(
    RecommendationItem item,
    int index,
  ) {
    final bool goldAccent = index.isOdd;

    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 242,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.softBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: goldAccent
                ? AppColors.gold.withValues(alpha: 0.25)
                : AppColors.teal.withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.045),
              blurRadius: 15,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: goldAccent
                        ? AppColors.gold.withValues(alpha: 0.12)
                        : AppColors.lightTeal.withValues(
                            alpha: 0.60,
                          ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    item.icon,
                    color: goldAccent
                        ? AppColors.gold
                        : AppColors.teal,
                    size: 23,
                  ),
                ),

                const Spacer(),

                Text(
                  item.type.toUpperCase(),
                  style: TextStyle(
                    color: goldAccent
                        ? AppColors.gold
                        : AppColors.teal,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),

            const Spacer(),

            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              item.provider,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 13,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item.reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // QUICK ACTIONS
  // ============================================================

  Widget _buildQuickActions() {
    const actions = [
      QuickActionItem(
        title: 'Analyze CV',
        icon: Icons.document_scanner_outlined,
      ),
      QuickActionItem(
        title: 'Improve CV',
        icon: Icons.edit_note_rounded,
      ),
      QuickActionItem(
        title: 'Match a Job',
        icon: Icons.work_outline_rounded,
      ),
      QuickActionItem(
        title: 'Practice\nInterview',
        icon: Icons.record_voice_over_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          title: 'Quick Actions',
          subtitle:
              'Jump directly into the tools you need.',
        ),

        const SizedBox(height: 20),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            actions.length,
            (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right:
                        index == actions.length - 1 ? 0 : 10,
                  ),
                  child: _quickAction(
                    actions[index],
                    index,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quickAction(
    QuickActionItem action,
    int index,
  ) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.softBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.lightGray,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.045),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: index == 2
                      ? AppColors.gold.withValues(alpha: 0.11)
                      : AppColors.lightTeal.withValues(
                          alpha: 0.55,
                        ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  action.icon,
                  color: index == 2
                      ? AppColors.gold
                      : AppColors.teal,
                  size: 22,
                ),
              ),
            ),
          ),

          const SizedBox(height: 9),

          Text(
            action.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SAUDI MARKET INSIGHT
  // ============================================================

  Widget _buildSaudiMarketInsight() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          title: 'Saudi Market Insight',
          subtitle:
              'See what the local job market is looking for.',
        ),

        const SizedBox(height: 18),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(
            color: AppColors.softBackground,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color: AppColors.teal.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 49,
                    height: 49,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.secondaryNavy,
                          AppColors.teal,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      color: AppColors.white,
                      size: 25,
                    ),
                  ),

                  const SizedBox(width: 14),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technology roles are in demand',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Saudi Arabia',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'HIGH',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 21),

              const Text(
                'Skills employers are looking for',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 11),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _marketSkill('Cybersecurity'),
                  _marketSkill('Cloud'),
                  _marketSkill('Python'),
                  _marketSkill('Data'),
                ],
              ),

              const SizedBox(height: 19),

              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Explore Market',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.teal,
                        size: 17,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _marketSkill(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightTeal.withValues(
          alpha: 0.43,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: AppColors.secondaryNavy,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ============================================================
  // EXPLORE MASRA
  // ============================================================

  Widget _buildExploreMasra() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, _) {
        final value = _backgroundController.value;

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.secondaryNavy,
                AppColors.navy,
                AppColors.teal,
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.15),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -55 + (value * 10),
                top: -55,
                child: Container(
                  width: 145,
                  height: 145,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.lightTeal.withValues(
                      alpha: 0.08,
                    ),
                  ),
                ),
              ),

              Positioned(
                right: 45,
                bottom: -68 + (value * 6),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          AppColors.white.withValues(alpha: 0.05),
                      width: 18,
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(23),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 29,
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(width: 11),
                        const Text(
                          'Explore Masra',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 13),

                    Text(
                      'Discover all the tools built to guide, develop, and prepare your career.',
                      style: TextStyle(
                        color: AppColors.white.withValues(
                          alpha: 0.72,
                        ),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 21),

                    ElevatedButton(
                      onPressed: () {
                        // TODO: Explore page
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 19,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All Features',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 9),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _sectionTitle({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  Widget _buildBottomNavigation() {
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
              _navItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: true,
                onTap: () {},
              ),
              _navItem(
                icon: Icons.explore_outlined,
                label: 'Explore',
                selected: false,
                onTap: () {
                  // TODO
                },
              ),
              _navItem(
                icon: Icons.groups_2_outlined,
                label: 'Community',
                selected: false,
                onTap: () {
                  // TODO
                },
              ),
              _navItem(
  icon: Icons.person_outline_rounded,
  label: 'Profile',
  selected: false,
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
      ),
    );
  },
),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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

// ============================================================
// DATA MODELS
// ============================================================

class RecommendationItem {
  final String type;
  final String title;
  final String provider;
  final String reason;
  final IconData icon;

  const RecommendationItem({
    required this.type,
    required this.title,
    required this.provider,
    required this.reason,
    required this.icon,
  });
}

class QuickActionItem {
  final String title;
  final IconData icon;

  const QuickActionItem({
    required this.title,
    required this.icon,
  });
}

// ============================================================
// JOURNEY
// ============================================================

enum JourneyState {
  completed,
  current,
  locked,
}

class JourneyNode extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final JourneyState state;

  const JourneyNode({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final bool completed =
        state == JourneyState.completed;

    final bool current =
        state == JourneyState.current;

    final Color mainColor = completed
        ? AppColors.teal
        : current
            ? AppColors.gold
            : AppColors.mediumGray;

    return SizedBox(
      width: 125,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: completed
                  ? AppColors.lightTeal.withValues(alpha: 0.62)
                  : current
                      ? AppColors.gold.withValues(alpha: 0.13)
                      : AppColors.lightGray.withValues(alpha: 0.65),
              shape: BoxShape.circle,
              border: Border.all(
                color: mainColor.withValues(
                  alpha: current ? 0.75 : 0.25,
                ),
                width: current ? 2 : 1,
              ),
              boxShadow: current
                  ? [
                      BoxShadow(
                        color:
                            AppColors.gold.withValues(alpha: 0.16),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              completed
                  ? Icons.check_rounded
                  : current
                      ? icon
                      : Icons.lock_outline_rounded,
              color: mainColor,
              size: 24,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            title,
            style: TextStyle(
              color: current || completed
                  ? AppColors.navy
                  : AppColors.secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 10.5,
              height: 1.25,
            ),
          ),

          
        ],
      ),
    );
  }
}
// ============================================================
// CUSTOM JOURNEY PATH
// ============================================================

class CareerPathPainter extends CustomPainter {
  final int stage;

  CareerPathPainter({
    required this.stage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    path.moveTo(52, 55);

    path.cubicTo(
      size.width * 0.38,
      30,
      size.width * 0.72,
      45,
      size.width - 58,
      125,
    );

    path.cubicTo(
      size.width - 25,
      185,
      size.width * 0.72,
      225,
      size.width * 0.34,
      245,
    );

    path.cubicTo(
      size.width * 0.10,
      260,
      size.width * 0.38,
      350,
      size.width - 62,
      325,
    );

    // ============================================================
    // CURRENT PROGRESS
    // ============================================================

    double progress;

    switch (stage) {
      case 0:
        progress = 0.05;
        break;

      case 1:
        progress = 0.35;
        break;

      case 2:
        progress = 0.68;
        break;

      case 3:
        progress = 1.0;
        break;

      default:
        progress = 0;
    }

    // ============================================================
    // COMPLETED PART
    // الجزء المنجز من الرحلة
    // ============================================================

    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          AppColors.secondaryNavy,
          AppColors.teal,
        ],
      ).createShader(
        Rect.fromLTWH(
          0,
          0,
          size.width,
          size.height,
        ),
      )
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ============================================================
    // FUTURE PATH
    // الجزء المتبقي من الرحلة
    // ============================================================

    final futurePaint = Paint()
      ..color = AppColors.mediumGray.withValues(alpha: 0.38)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      final completedLength = metric.length * progress;

      // ----------------------------
      // Draw completed path
      // ----------------------------

      if (completedLength > 0) {
        final completedPath = metric.extractPath(
          0,
          completedLength,
        );

        canvas.drawPath(
          completedPath,
          progressPaint,
        );
      }

      // ----------------------------
      // Draw dashed future path
      // ----------------------------

      double distance = completedLength + 8;

      while (distance < metric.length) {
        final dashEnd = (distance + 9).clamp(
          0.0,
          metric.length,
        );

        final dashPath = metric.extractPath(
          distance,
          dashEnd,
        );

        canvas.drawPath(
          dashPath,
          futurePaint,
        );

        // المسافة بين كل dash والثاني
        distance += 18;
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant CareerPathPainter oldDelegate,
  ) {
    return oldDelegate.stage != stage;
  }
}