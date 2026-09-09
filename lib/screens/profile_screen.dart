import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.userName = 'Jood Al-Otaibi',
    this.major = 'Information Technology',
    this.specialization = 'AI Specialist',
    this.university = 'King Saud University',
    this.graduation = 'Expected 2026',
    this.careerGoal = 'AI Specialist',
  });

  // User information
  final String userName;
  final String major;
  final String specialization;
  final String university;
  final String graduation;
  final String careerGoal;

  // Main colors
  static const Color navy = Color(0xFF0B2D49);
  static const Color teal = Color(0xFF378F9C);
  static const Color gold = Color(0xFFD6A53A);
  static const Color background = Color(0xFFF5F7F9);
  static const Color lightTeal = Color(0xFFE8F3F5);
  static const Color lightGold = Color(0xFFF8F0DE);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                children: [
                  // =========================
                  // PROFILE HEADER
                  // =========================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 42),
                    decoration: const BoxDecoration(
                      color: navy,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(42),
                        bottomRight: Radius.circular(42),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top bar
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  // Logo
                                  Container(
                                    width: 42,
                                    height: 42,
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Image.asset(
                                      'assets/images/Logoo.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  const Text(
                                    'Profile',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Notification button
                            _headerButton(
                              icon: Icons.notifications_none_rounded,
                              onTap: () {},
                            ),

                            const SizedBox(width: 10),

                            // Settings button
                            _headerButton(
                              icon: Icons.settings_outlined,
                              onTap: () {},
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // User information
                        Row(
                          children: [
                            // User initial
                            Container(
                              width: 114,
                              height: 114,
                              decoration: BoxDecoration(
                                color: teal,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            const SizedBox(width: 22),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  const SizedBox(height: 5),

                                  Text(
                                    major,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.72),
                                      fontSize: 19,
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  Row(
                                    children: [
                                      const Text(
                                        '🎯',
                                        style: TextStyle(fontSize: 18),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          specialization,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: gold,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // =========================
                  // EDIT PROFILE / MANAGE CV
                  // =========================
                  Transform.translate(
                    offset: const Offset(0, -20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: _actionButton(
                              icon: Icons.edit_outlined,
                              text: 'Edit Profile',
                              onTap: () {},
                            ),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: _actionButton(
                              icon: Icons.description_outlined,
                              text: 'Manage CV',
                              onTap: () {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // =========================
                  // CAREER PROFILE
                  // =========================
                  _sectionCard(
                    title: 'Career Profile',
                    child: Column(
                      children: [
                        _infoRow(
                          icon: Icons.school_outlined,
                          title: 'University',
                          value: university,
                        ),

                        _infoRow(
                          icon: Icons.star_border_rounded,
                          title: 'Major',
                          value: major,
                        ),

                        _infoRow(
                          icon: Icons.school_outlined,
                          title: 'Graduation',
                          value: graduation,
                        ),

                        _infoRow(
                          icon: Icons.business_center_outlined,
                          title: 'Career Goal',
                          value: careerGoal,
                          last: true,
                        ),
                      ],
                    ),
                  ),

                  // =========================
                  // SKILLS
                  // =========================
                  _sectionCard(
                    title: 'Skills',
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: teal,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            color: teal,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        _skillItem(
                          name: 'Python',
                          level: 'Intermediate',
                        ),
                        _skillItem(
                          name: 'SQL',
                          level: 'Intermediate',
                        ),
                        _skillItem(
                          name: 'Machine Learning',
                          level: 'Beginner',
                          beginner: true,
                        ),
                        _skillItem(
                          name: 'Data Analysis',
                          level: 'Intermediate',
                        ),
                      ],
                    ),
                  ),

                  // =========================
                  // CERTIFICATIONS
                  // =========================
                  _sectionCard(
                    title: 'Certifications',
                    child: _certificateItem(
                      title: 'Google Data Analytics',
                      company: 'Google',
                      year: '2025',
                    ),
                  ),

                  // =========================
                  // PROJECTS
                  // =========================
                  _sectionCard(
                    title: 'Projects',
                    child: _projectItem(
                      title: 'Student Grade Predictor',
                      technologies: 'Python, scikit-learn',
                    ),
                  ),

                  // =========================
                  // EXPERIENCE
                  // =========================
                  _sectionCard(
                    title: 'Experience',
                    child: _experienceItem(
                      title: 'IT Intern',
                      company: 'STC Solutions',
                      duration: 'Summer 2025',
                    ),
                  ),

                  // =========================
                  // CV
                  // =========================
                  _sectionCard(
                    title: 'CV',
                    child: _cvItem(),
                  ),

                  // =========================
                  // CAREER PREFERENCES
                  // =========================
                  _sectionCard(
                    title: 'Career Preferences',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _preferenceTitle('Interests'),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _tag('Artificial Intelligence'),
                            _tag('Data Science'),
                            _tag('Machine Learning'),
                          ],
                        ),

                        const SizedBox(height: 22),

                        _preferenceTitle('Desired Roles'),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _tag('AI Specialist', dark: true),
                            _tag('Data Analyst', dark: true),
                            _tag('ML Engineer', dark: true),
                          ],
                        ),

                        const SizedBox(height: 22),

                        _preferenceTitle('Preferred Regions'),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _tagWithIcon(
                              'Riyadh',
                              Icons.location_on_outlined,
                            ),
                            _tagWithIcon(
                              'Remote',
                              Icons.location_on_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // =========================
            // BOTTOM NAVIGATION
            // =========================
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _bottomNavigation(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER BUTTON
  // ============================================================

  static Widget _headerButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(
            icon,
            color: Colors.white,
            size: 31,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ACTION BUTTON
  // ============================================================

  static Widget _actionButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: navy,
                size: 28,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SECTION CARD
  // ============================================================

  static Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 22),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),

          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // CAREER INFO
  // ============================================================

  static Widget _infoRow({
    required IconData icon,
    required String title,
    required String value,
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 17),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF687984),
              size: 29,
            ),
          ),

          const SizedBox(width: 17),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF87939C),
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF172533),
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
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
  // SKILLS
  // ============================================================

  static Widget _skillItem({
    required String name,
    required String level,
    bool beginner = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 17,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE9EDF0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: Color(0xFF172533),
                fontSize: 19,
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: beginner ? lightGold : lightTeal,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              level,
              style: TextStyle(
                color: beginner ? gold : teal,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CERTIFICATION
  // ============================================================

  static Widget _certificateItem({
    required String title,
    required String company,
    required String year,
  }) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: lightGold,
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(
            Icons.workspace_premium_outlined,
            color: gold,
            size: 32,
          ),
        ),

        const SizedBox(width: 18),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF172533),
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$company • $year',
                style: const TextStyle(
                  color: Color(0xFF87939C),
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PROJECT
  // ============================================================

  static Widget _projectItem({
    required String title,
    required String technologies,
  }) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: lightTeal,
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(
            Icons.star_border_rounded,
            color: teal,
            size: 34,
          ),
        ),

        const SizedBox(width: 18),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF172533),
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                technologies,
                style: const TextStyle(
                  color: Color(0xFF87939C),
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EXPERIENCE
  // ============================================================

  static Widget _experienceItem({
    required String title,
    required String company,
    required String duration,
  }) {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xFFE9EEF1),
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(
            Icons.business_center_outlined,
            color: navy,
            size: 31,
          ),
        ),

        const SizedBox(width: 18),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF172533),
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$company • $duration',
                style: const TextStyle(
                  color: Color(0xFF87939C),
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CV
  // ============================================================

  static Widget _cvItem() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE9EDF0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: navy,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),

          const SizedBox(width: 15),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jood_CV_2026.pdf',
                  style: TextStyle(
                    color: Color(0xFF172533),
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Uploaded Aug 2026',
                  style: TextStyle(
                    color: Color(0xFF87939C),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          TextButton(
            onPressed: () {},
            child: const Text(
              'Replace',
              style: TextStyle(
                color: teal,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PREFERENCES
  // ============================================================

  static Widget _preferenceTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7B8790),
          fontSize: 18,
        ),
      ),
    );
  }

  static Widget _tag(
    String text, {
    bool dark = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFFE7EBEE)
            : lightTeal,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: dark ? navy : teal,
          fontSize: 16,
        ),
      ),
    );
  }

  static Widget _tagWithIcon(
    String text,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: const Color(0xFF7B8790),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF7B8790),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  static Widget _bottomNavigation() {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(
            icon: Icons.home_outlined,
            label: 'Home',
            selected: false,
            onTap: () {},
          ),
          _navItem(
            icon: Icons.explore_outlined,
            label: 'Explore',
            selected: false,
            onTap: () {},
          ),
          _navItem(
            icon: Icons.people_outline_rounded,
            label: 'Community',
            selected: false,
            onTap: () {},
          ),
          _navItem(
            icon: Icons.person_outline_rounded,
            label: 'Profile',
            selected: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  static Widget _navItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 30,
              color: selected
                  ? teal
                  : const Color(0xFF6E7B84),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? teal
                    : const Color(0xFF6E7B84),
                fontSize: 14,
                fontWeight: selected
                    ? FontWeight.w500
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}