import 'package:flutter/material.dart';

import '../features/community/community_screen.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'explore_screen.dart';
import 'profile_setup_screen.dart';
import 'settings_screen.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ============================================================
  // TEMPORARY USER DATA
  // لاحقًا يمكن ربطها بالـ Backend / Database / AI
  // ============================================================

  final String userName = 'Jood Al-Otaibi';
  final String major = 'Information Technology';
  final String careerGoal = 'AI Specialist';

  final int profileCompletion = 86;

  final List<SkillItem> skills = const [
    SkillItem(
      name: 'Python',
      level: 'Intermediate',
      progress: 0.72,
    ),
    SkillItem(
      name: 'SQL',
      level: 'Intermediate',
      progress: 0.68,
    ),
    SkillItem(
      name: 'Machine Learning',
      level: 'Beginner',
      progress: 0.38,
    ),
    SkillItem(
      name: 'Data Analysis',
      level: 'Intermediate',
      progress: 0.65,
    ),
  ];

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // ----------------------------------------------------------
      // BOTTOM NAVIGATION
      // ----------------------------------------------------------

      bottomNavigationBar: _buildBottomNavigation(),

      // ----------------------------------------------------------
      // BODY
      // ----------------------------------------------------------

      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================
              // HERO
              // ==================================================

              _buildProfileHero(),

              const SizedBox(height: 22),

              // ==================================================
              // QUICK ACTIONS
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildQuickProfileActions(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // CAREER SNAPSHOT
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCareerSnapshot(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // SKILLS
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSkillsSection(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // CERTIFICATIONS
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCertifications(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // PROJECTS
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProjects(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // EXPERIENCE
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildExperience(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // CV
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCVCard(),
              ),

              const SizedBox(height: 32),

              // ==================================================
              // CAREER PREFERENCES
              // ==================================================

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCareerPreferences(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PROFILE HERO
  // ============================================================

  Widget _buildProfileHero() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.navy,
            AppColors.secondaryNavy,
            AppColors.teal,
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(42),
          bottomRight: Radius.circular(42),
        ),
      ),
      child: Stack(
        children: [
          // ------------------------------------------------------
          // BACKGROUND CIRCLE
          // ------------------------------------------------------

          Positioned(
            right: -65,
            top: -80,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.lightTeal.withValues(
                  alpha: 0.08,
                ),
              ),
            ),
          ),

          // ------------------------------------------------------
          // SECOND CIRCLE
          // ------------------------------------------------------

          Positioned(
            left: -85,
            bottom: -80,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withValues(
                    alpha: 0.09,
                  ),
                  width: 25,
                ),
              ),
            ),
          ),

          // ------------------------------------------------------
          // SMALL GOLD CIRCLE
          // ------------------------------------------------------

          Positioned(
            right: 105,
            top: 145,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(
                  alpha: 0.12,
                ),
              ),
            ),
          ),

          // ------------------------------------------------------
          // CONTENT
          // ------------------------------------------------------

          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              14,
              20,
              25,
            ),
            child: Column(
              children: [
                // =================================================
                // TOP BAR
                // =================================================

                Row(
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),

                    const Spacer(),

                    // ------------------------------------------------
                    // LOGO
                    // ------------------------------------------------

                    Container(
                      width: 62,
                      height: 42,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.white.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                      child: Image.asset(
                        'lib/assets/images/Logoo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (
                          context,
                          error,
                          stackTrace,
                        ) {
                          return const Center(
                            child: Text(
                              'Masra',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 9),

                    // ------------------------------------------------
                    // SETTINGS BUTTON
                    // ------------------------------------------------

                    _heroIconButton(
                      icon: Icons.settings_outlined,
                      onTap: _openSettings,
                    ),
                  ],
                ),

                const SizedBox(height: 27),

                // =================================================
                // USER INFORMATION
                // =================================================

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ------------------------------------------------
                    // AVATAR
                    // ------------------------------------------------

                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.teal,
                            AppColors.lightTeal,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: AppColors.white.withValues(
                            alpha: 0.18,
                          ),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.teal.withValues(
                              alpha: 0.22,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'J',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    const SizedBox(width: 17),

                    // ------------------------------------------------
                    // NAME + MAJOR + GOAL
                    // ------------------------------------------------

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            major,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.white.withValues(
                                alpha: 0.70,
                              ),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 9),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.gold.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.gps_fixed_rounded,
                                  color: AppColors.gold,
                                  size: 14,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  careerGoal,
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                // =================================================
                // PROFILE STRENGTH
                // =================================================

                InkWell(
                  onTap: _showProfileStrength,
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(
                        alpha: 0.075,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppColors.white.withValues(
                          alpha: 0.10,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // ------------------------------------------------
                        // PROGRESS RING
                        // ------------------------------------------------

                        SizedBox(
                          width: 62,
                          height: 62,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 62,
                                height: 62,
                                child: CircularProgressIndicator(
                                  value:
                                      profileCompletion / 100,
                                  strokeWidth: 5,
                                  backgroundColor:
                                      AppColors.white.withValues(
                                    alpha: 0.10,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<
                                          Color>(
                                    AppColors.gold,
                                  ),
                                ),
                              ),
                              Text(
                                '$profileCompletion%',
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 15),

                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profile Strength',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Your profile is looking strong. Add more experience to reach 100%.',
                                style: TextStyle(
                                  color: Color(0xB8FFFFFF),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: AppColors.gold,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HERO BUTTON
  // ============================================================

  Widget _heroIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(
            alpha: 0.10,
          ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: AppColors.white.withValues(
              alpha: 0.11,
            ),
          ),
        ),
        child: Icon(
          icon,
          color: AppColors.white,
          size: 21,
        ),
      ),
    );
  }

  // ============================================================
  // QUICK ACTIONS
  // ============================================================

  Widget _buildQuickProfileActions() {
    return Row(
      children: [
        Expanded(
          child: _profileAction(
            icon: Icons.edit_note_rounded,
            title: 'Edit Profile',
            accent: AppColors.teal,
            onTap: _openEditProfile,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _profileAction(
            icon: Icons.description_outlined,
            title: 'Manage CV',
            accent: AppColors.gold,
            onTap: _manageCV,
          ),
        ),
      ],
    );
  }

  Widget _profileAction({
    required IconData icon,
    required String title,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
        ),
        decoration: BoxDecoration(
          color: AppColors.softBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(
              alpha: 0.15,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(
                alpha: 0.045,
              ),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: 0.10,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: accent,
                size: 20,
              ),
            ),

            const SizedBox(width: 9),

            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CAREER SNAPSHOT
  // ============================================================

  Widget _buildCareerSnapshot() {
    return _profileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Career Snapshot',
            subtitle:
                'The essentials behind your career path.',
            icon: Icons.route_rounded,
            accent: AppColors.teal,
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: _snapshotItem(
                  icon: Icons.school_outlined,
                  label: 'University',
                  value: 'King Saud University',
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _snapshotItem(
                  icon: Icons.calendar_today_outlined,
                  label: 'Graduation',
                  value: 'Expected 2026',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _snapshotItem(
                  icon: Icons.star_outline_rounded,
                  label: 'Major',
                  value: 'Information Technology',
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _snapshotItem(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Goal',
                  value: 'AI Specialist',
                  gold: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _snapshotItem({
    required IconData icon,
    required String label,
    required String value,
    bool gold = false,
  }) {
    final accent =
        gold ? AppColors.gold : AppColors.teal;

    return InkWell(
      onTap: () {
        _showInformationDialog(
          title: label,
          message: value,
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.lightGray,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: 0.10,
                ),
                borderRadius:
                    BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                color: accent,
                size: 19,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              label,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SKILLS
  // ============================================================

  Widget _buildSkillsSection() {
    return _profileCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionHeader(
                  title: 'Skills',
                  subtitle:
                      'Your current skill landscape.',
                  icon: Icons.auto_graph_rounded,
                  accent: AppColors.teal,
                ),
              ),

              InkWell(
                onTap: _editSkills,
                borderRadius:
                    BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Row(
                    children: [
                      Text(
                        'Edit',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.teal,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          ...List.generate(
            skills.length,
            (index) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom:
                      index == skills.length - 1
                          ? 0
                          : 13,
                ),
                child: _skillCard(
                  skills[index],
                  index,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _skillCard(
    SkillItem skill,
    int index,
  ) {
    final bool gold =
        skill.level == 'Beginner';

    final Color accent =
        gold ? AppColors.gold : AppColors.teal;

    return InkWell(
      onTap: () {
        _showInformationDialog(
          title: skill.name,
          message:
              '${skill.level} • ${(skill.progress * 100).round()}%',
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          14,
          13,
          14,
          14,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.lightGray,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    skill.name,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                  child: Text(
                    skill.level,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 11),

            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(10),
                    child:
                        LinearProgressIndicator(
                      value: skill.progress,
                      minHeight: 6,
                      backgroundColor:
                          AppColors.lightGray
                              .withValues(
                        alpha: 0.65,
                      ),
                      valueColor:
                          AlwaysStoppedAnimation<
                              Color>(
                        accent,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Text(
                  '${(skill.progress * 100).round()}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w800,
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
  // CERTIFICATIONS
  // ============================================================

  Widget _buildCertifications() {
    return _profileCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Certifications',
            subtitle:
                'Credentials that strengthen your profile.',
            icon:
                Icons.workspace_premium_outlined,
            accent: AppColors.gold,
          ),

          const SizedBox(height: 20),

          InkWell(
            onTap: _openCertification,
            borderRadius:
                BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(
                      alpha: 0.07,
                    ),
                    AppColors.background,
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(20),
                border: Border.all(
                  color:
                      AppColors.gold.withValues(
                    alpha: 0.15,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color:
                          AppColors.gold.withValues(
                        alpha: 0.11,
                      ),
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons
                          .workspace_premium_rounded,
                      color: AppColors.gold,
                      size: 27,
                    ),
                  ),

                  const SizedBox(width: 13),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Data Analytics',
                          style: TextStyle(
                            color:
                                AppColors.navy,
                            fontSize: 14.5,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Google • 2025',
                          style: TextStyle(
                            color: AppColors
                                .secondaryText,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.gold,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROJECTS
  // ============================================================

  Widget _buildProjects() {
    return _profileCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Projects',
            subtitle:
                'Proof of what you can build.',
            icon: Icons.code_rounded,
            accent: AppColors.teal,
          ),

          const SizedBox(height: 20),

          _projectItem(
            title: 'Student Grade Predictor',
            subtitle:
                'Python • scikit-learn',
            icon: Icons.auto_graph_rounded,
            accent: AppColors.teal,
          ),

          const SizedBox(height: 12),

          _projectItem(
            title: 'AI Career Platform',
            subtitle:
                'Python • Machine Learning',
            icon:
                Icons.psychology_alt_rounded,
            accent: AppColors.gold,
          ),
        ],
      ),
    );
  }

  Widget _projectItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return InkWell(
      onTap: () {
        _showInformationDialog(
          title: title,
          message: subtitle,
        );
      },
      borderRadius: BorderRadius.circular(19),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.circular(19),
          border: Border.all(
            color: AppColors.lightGray,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: 0.10,
                ),
                borderRadius:
                    BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: accent,
                size: 23,
              ),
            ),

            const SizedBox(width: 13),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    style: const TextStyle(
                      color:
                          AppColors.secondaryText,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.arrow_forward_ios_rounded,
              color:
                  AppColors.secondaryText
                      .withValues(
                alpha: 0.55,
              ),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EXPERIENCE
  // ============================================================

  Widget _buildExperience() {
    return _profileCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Experience',
            subtitle:
                'Your professional journey so far.',
            icon: Icons.work_outline_rounded,
            accent: AppColors.teal,
          ),

          const SizedBox(height: 21),

          InkWell(
            onTap: _openExperience,
            borderRadius:
                BorderRadius.circular(15),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.lightTeal
                            .withValues(
                          alpha: 0.48,
                        ),
                        borderRadius:
                            BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons
                            .business_center_outlined,
                        color: AppColors.teal,
                        size: 23,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Container(
                      width: 2,
                      height: 38,
                      decoration: BoxDecoration(
                        color:
                            AppColors.lightGray,
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 13),

                const Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IT Intern',
                          style: TextStyle(
                            color:
                                AppColors.navy,
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'STC Solutions',
                          style: TextStyle(
                            color: AppColors
                                .secondaryNavy,
                            fontSize: 12.5,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Summer 2025',
                          style: TextStyle(
                            color: AppColors
                                .secondaryText,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        AppColors.teal.withValues(
                      alpha: 0.08,
                    ),
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                  child: const Text(
                    'Experience',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontSize: 9.5,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CV
  // ============================================================

  Widget _buildCVCard() {
    return _profileCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Your CV',
            subtitle:
                'The document powering your career analysis.',
            icon: Icons.description_outlined,
            accent: AppColors.navy,
          ),

          const SizedBox(height: 20),

          InkWell(
            onTap: _openCV,
            borderRadius:
                BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius:
                    BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.lightGray,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient:
                          const LinearGradient(
                        begin:
                            Alignment.topLeft,
                        end:
                            Alignment.bottomRight,
                        colors: [
                          AppColors.navy,
                          AppColors.secondaryNavy,
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.navy
                                  .withValues(
                            alpha: 0.14,
                          ),
                          blurRadius: 12,
                          offset:
                              const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons
                          .picture_as_pdf_outlined,
                      color: AppColors.white,
                      size: 25,
                    ),
                  ),

                  const SizedBox(width: 13),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Jood_CV_2026.pdf',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                AppColors.navy,
                            fontSize: 13.5,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Uploaded Aug 2026',
                          style: TextStyle(
                            color: AppColors
                                .secondaryText,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  InkWell(
                    onTap: _replaceCV,
                    borderRadius:
                        BorderRadius.circular(12),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold
                            .withValues(
                          alpha: 0.10,
                        ),
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Replace',
                        style: TextStyle(
                          color:
                              AppColors.gold,
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CAREER PREFERENCES
  // ============================================================

  Widget _buildCareerPreferences() {
    return _profileCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Career Preferences',
            subtitle:
                'Tell Masra where you want your career to go.',
            icon: Icons.explore_outlined,
            accent: AppColors.gold,
          ),

          const SizedBox(height: 22),

          _preferenceGroup(
            title: 'Interests',
            icon: Icons.interests_outlined,
            children: [
              _preferenceChip(
                'Artificial Intelligence',
                AppColors.teal,
              ),
              _preferenceChip(
                'Data Science',
                AppColors.teal,
              ),
              _preferenceChip(
                'Machine Learning',
                AppColors.teal,
              ),
            ],
          ),

          const SizedBox(height: 19),

          _preferenceGroup(
            title: 'Desired Roles',
            icon: Icons.work_outline_rounded,
            children: [
              _preferenceChip(
                'AI Specialist',
                AppColors.navy,
              ),
              _preferenceChip(
                'Data Analyst',
                AppColors.navy,
              ),
              _preferenceChip(
                'ML Engineer',
                AppColors.navy,
              ),
            ],
          ),

          const SizedBox(height: 19),

          _preferenceGroup(
            title: 'Preferred Regions',
            icon: Icons.location_on_outlined,
            children: [
              _preferenceChip(
                'Riyadh',
                AppColors.secondaryText,
                icon:
                    Icons.location_on_outlined,
              ),
              _preferenceChip(
                'Remote',
                AppColors.secondaryText,
                icon: Icons.public_rounded,
              ),
            ],
          ),

          const SizedBox(height: 20),

          InkWell(
            onTap: _showPersonalizationInfo,
            borderRadius:
                BorderRadius.circular(17),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(
                      alpha: 0.10,
                    ),
                    AppColors.gold.withValues(
                      alpha: 0.035,
                    ),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(17),
                border: Border.all(
                  color: AppColors.gold.withValues(
                    alpha: 0.14,
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.gold,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Masra uses these preferences to personalize your recommendations.',
                      style: TextStyle(
                        color:
                            AppColors.secondaryNavy,
                        fontSize: 10.5,
                        height: 1.35,
                        fontWeight:
                            FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PREFERENCE GROUP
  // ============================================================

  Widget _preferenceGroup({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: AppColors.secondaryText,
              size: 17,
            ),

            const SizedBox(width: 7),

            Text(
              title,
              style: const TextStyle(
                color:
                    AppColors.secondaryText,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 9),

        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: children,
        ),
      ],
    );
  }

  // ============================================================
  // PREFERENCE CHIP
  // ============================================================

  Widget _preferenceChip(
    String text,
    Color color, {
    IconData? icon,
  }) {
    return InkWell(
      onTap: () {
        _showInformationDialog(
          title: text,
          message:
              'This preference is currently selected for your career profile.',
        );
      },
      borderRadius:
          BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: 0.075,
          ),
          borderRadius:
              BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(
              alpha: 0.08,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: color,
                size: 13,
              ),
              const SizedBox(width: 4),
            ],

            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // GENERIC PROFILE CARD
  // ============================================================

  Widget _profileCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius:
            BorderRadius.circular(27),
        border: Border.all(
          color: AppColors.lightGray
              .withValues(
            alpha: 0.85,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(
              alpha: 0.045,
            ),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  // ============================================================
  // SECTION HEADER
  // ============================================================

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.center,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: accent.withValues(
              alpha: 0.09,
            ),
            borderRadius:
                BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: accent,
            size: 21,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  color:
                      AppColors.secondaryText,
                  fontSize: 10.5,
                ),
              ),
            ],
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
            color: AppColors.lightGray
                .withValues(
              alpha: 0.8,
            ),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(
              alpha: 0.055,
            ),
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
              // --------------------------------------------------
              // HOME
              // --------------------------------------------------

              _navItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: false,
                onTap: _goHome,
              ),

              // --------------------------------------------------
              // EXPLORE
              // --------------------------------------------------

              _navItem(
                icon: Icons.explore_outlined,
                label: 'Explore',
                selected: false,
                onTap: _openExplore,
              ),

              // --------------------------------------------------
              // COMMUNITY
              // --------------------------------------------------

              _navItem(
                icon: Icons.groups_2_outlined,
                label: 'Community',
                selected: false,
                onTap: _openCommunity,
              ),

              // --------------------------------------------------
              // PROFILE
              // --------------------------------------------------

              _navItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NAV ITEM
  // ============================================================

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
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration:
                  const Duration(
                milliseconds: 250,
              ),
              curve: Curves.easeOut,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.lightTeal
                        .withValues(
                      alpha: 0.58,
                    )
                    : Colors.transparent,
                borderRadius:
                    BorderRadius.circular(20),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: selected
                        ? AppColors.teal
                        : AppColors
                            .secondaryText,
                  ),

                  if (selected)
                    Positioned(
                      top: -7,
                      right: -2,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration:
                            const BoxDecoration(
                          color:
                              AppColors.gold,
                          shape:
                              BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 3),

            Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.teal
                    : AppColors
                        .secondaryText,
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

  // ============================================================
  // NAVIGATION FUNCTIONS
  // ============================================================

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
             SettingsScreen(),
      ),
    );
  }

  void _openEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
             ProfileSetupScreen(),
      ),
    );
  }

  void _openExplore() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
             ExploreScreen(),
      ),
    );
  }

  void _openCommunity() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CommunityScreen(),
      ),
    );
  }

 void _goHome() {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => const HomeScreen(),
    ),
  );
}

  // ============================================================
  // ACTIONS
  // ============================================================

  void _manageCV() {
    _showInformationDialog(
      title: 'Manage CV',
      message:
          'Your CV is ready to be managed. You can replace or review your current CV.',
    );
  }

  void _replaceCV() {
    _showInformationDialog(
      title: 'Replace CV',
      message:
          'CV replacement will be connected to the file picker and backend later.',
    );
  }

  void _openCV() {
    _showInformationDialog(
      title: 'Jood_CV_2026.pdf',
      message:
          'This CV is currently used as part of your career profile analysis.',
    );
  }

  void _editSkills() {
    _showInformationDialog(
      title: 'Edit Skills',
      message:
          'Skill editing will allow you to update your skills and proficiency levels.',
    );
  }

  void _openCertification() {
    _showInformationDialog(
      title: 'Google Data Analytics',
      message:
          'Google Data Analytics certification • 2025',
    );
  }

  void _openExperience() {
    _showInformationDialog(
      title: 'IT Intern',
      message:
          'STC Solutions • Summer 2025',
    );
  }

  void _showProfileStrength() {
    _showInformationDialog(
      title: 'Profile Strength',
      message:
          'Your profile is $profileCompletion% complete. Add more experience and skills to improve your profile.',
    );
  }

  void _showPersonalizationInfo() {
    _showInformationDialog(
      title: 'Personalized Recommendations',
      message:
          'Masra uses your career interests, desired roles, skills, and preferred regions to personalize recommendations.',
    );
  }

  // ============================================================
  // GENERIC DIALOG
  // ============================================================

  void _showInformationDialog({
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              AppColors.softBackground,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(24),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 19,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color:
                  AppColors.secondaryText,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'Close',
                style: TextStyle(
                  color: AppColors.teal,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// DATA MODEL - SKILL
// ============================================================

class SkillItem {
  final String name;
  final String level;
  final double progress;

  const SkillItem({
    required this.name,
    required this.level,
    required this.progress,
  });
}