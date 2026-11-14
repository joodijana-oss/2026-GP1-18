import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/profile_options.dart';
import '../../models/certification.dart';
import '../../services/content_based_recommender.dart';
import '../../theme/app_colors.dart';
import '../../utils/skill_matcher.dart';

/// Details of one recommended certification, with a link to the official
/// certification page.
class CertificationDetailsScreen extends StatefulWidget {
  final Certification certification;

  /// The user's skills this certification works on (can be empty): skill
  /// gaps it covers, or current skills it builds on, depending on [goal].
  final List<String> matchedSkills;

  /// What the user chose: close skill gaps or strengthen current skills.
  final CertificationGoal goal;

  /// True when the certification level suits the user for this goal.
  final bool levelFits;

  /// The user's career goal name (for the "Why it fits you" list).
  final String careerName;

  const CertificationDetailsScreen({
    super.key,
    required this.certification,
    required this.matchedSkills,
    this.goal = CertificationGoal.closeGaps,
    required this.levelFits,
    required this.careerName,
  });

  @override
  State<CertificationDetailsScreen> createState() =>
      _CertificationDetailsScreenState();
}

class _CertificationDetailsScreenState
    extends State<CertificationDetailsScreen> {
  Certification get _cert => widget.certification;
  bool get _forGaps => widget.goal == CertificationGoal.closeGaps;

  Future<void> _openOfficialSource() async {
    final uri = Uri.tryParse(_cert.officialUrl.trim());
    var opened = false;
    if (uri != null && uri.hasScheme) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the official page. Please try again.'),
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _entrance(delay: 0, child: _buildHero()),
              const SizedBox(height: 18),
              if (!_cert.verified) ...[
                _entrance(delay: 50, child: _buildNotice()),
                const SizedBox(height: 18),
              ],
              _entrance(delay: 90, child: _buildAboutCard()),
              const SizedBox(height: 16),
              _entrance(delay: 150, child: _buildSkillsCard()),
              const SizedBox(height: 16),
              if (_cert.careerPaths.isNotEmpty) ...[
                _entrance(delay: 180, child: _buildCareersCard()),
                const SizedBox(height: 16),
              ],
              _entrance(delay: 210, child: _buildWhyCard()),
              const SizedBox(height: 16),
              _entrance(delay: 270, child: _buildFactsCard()),
              const SizedBox(height: 26),
              _entrance(delay: 330, child: _buildSourceButton()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.navyText,
            size: 21,
          ),
        ),
        const SizedBox(width: 26),
        Text(
          'Certification Details',
          style: TextStyle(
            color: AppColors.navyText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.lightTeal.withValues(alpha: 0.72),
            AppColors.softBackground,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            right: -25,
            child: Container(
              width: 125,
              height: 125,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.teal.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -46,
            left: -32,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.tealText.withValues(alpha: 0.10),
                  width: 18,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _cert.issuer,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _cert.name,
                        style: TextStyle(
                          color: AppColors.navyText,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_cert.level.isNotEmpty)
                            _heroBadge(_cert.level),
                          if (_cert.category.isNotEmpty)
                            _heroBadge(_cert.category),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 61,
                  height: 61,
                  decoration: BoxDecoration(
                    color: AppColors.softBackground,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.teal.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.workspace_premium_outlined,
                    color: AppColors.tealText,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.tealText,
          fontSize: 11.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppColors.navyText,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These details have not been verified on the official page yet. Check the official source before you decide.',
              style: TextStyle(
                color: AppColors.navyText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return _sectionCard(
      icon: Icons.description_rounded,
      title: 'About This Certification',
      child: SizedBox(
        width: double.infinity,
        child: Text(
          _cert.description,
          style: TextStyle(
            color: AppColors.secondaryNavyText,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _buildSkillsCard() {
    return _sectionCard(
      icon: Icons.trending_up_rounded,
      title: 'Skills Covered',
      subtitle: widget.matchedSkills.isEmpty
          ? null
          : (_forGaps
              ? 'Highlighted skills cover your gaps'
              : 'Highlighted skills build on what you know'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final skill in _cert.skills) _skillChip(skill),
        ],
      ),
    );
  }

  /// The career paths (fields) this certification is useful for.
  Widget _buildCareersCard() {
    final names = [
      for (final id in _cert.careerPaths) ProfileOptions.careerGoals[id] ?? id,
    ];
    return _sectionCard(
      icon: Icons.work_outline_rounded,
      title: 'Related Careers',
      subtitle: 'Fields where this certification is valued',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final name in names) _skillChip(name, plain: true)],
      ),
    );
  }

  Widget _skillChip(String skill, {bool plain = false}) {
    final covers = !plain &&
        widget.matchedSkills.any((mine) => SkillMatcher.matches(mine, skill));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: covers ? AppColors.teal : AppColors.softBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: covers ? AppColors.teal : AppColors.lightGray,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (covers) ...[
            const Icon(
              Icons.check_rounded,
              color: AppColors.onBrand,
              size: 16,
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              skill,
              style: TextStyle(
                color: covers ? AppColors.onBrand : AppColors.navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhyCard() {
    final skills = widget.matchedSkills.join(', ');
    final career = widget.careerName.trim();
    final reasons = <String>[
      if (widget.matchedSkills.isNotEmpty)
        _forGaps
            ? 'Covers your skill gaps in $skills.'
            : 'Builds on your skills in $skills.',
      if (widget.levelFits)
        _forGaps
            ? 'Its ${_cert.level} level fits your experience.'
            : 'Its ${_cert.level} level is a good next step for you.',
      career.isEmpty
          ? 'Relevant to your career goal.'
          : 'Relevant to your $career career goal.',
    ];

    return _sectionCard(
      icon: Icons.lightbulb_outline_rounded,
      title: 'Why It Fits You',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      reason,
                      style: TextStyle(
                        color: AppColors.secondaryNavyText,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
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

  Widget _buildFactsCard() {
    final facts = <MapEntry<String, String>>[
      MapEntry('Issuer', _cert.issuer),
      if (_cert.level.isNotEmpty) MapEntry('Level', _cert.level),
      if (_cert.category.isNotEmpty) MapEntry('Category', _cert.category),
      if (_cert.examCode.isNotEmpty) MapEntry('Exam code', _cert.examCode),
    ];

    return _sectionCard(
      icon: Icons.fact_check_outlined,
      title: 'Quick Facts',
      child: Column(
        children: [
          for (final fact in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      fact.key,
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      fact.value,
                      style: TextStyle(
                        color: AppColors.navyText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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

  Widget _buildSourceButton() {
    final available = _cert.officialUrl.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: available
              ? [
                  AppColors.navy,
                  AppColors.secondaryNavy,
                  AppColors.teal,
                ]
              : [
                  AppColors.mediumGray,
                  AppColors.mediumGray,
                ],
        ),
        boxShadow: available
            ? [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: ElevatedButton(
        onPressed: available ? _openOfficialSource : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.onBrand,
          disabledForegroundColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              available ? 'View Official Source' : 'Official source not available',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (available) ...[
              const SizedBox(width: 10),
              const Icon(Icons.open_in_new_rounded, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // SMALL PIECES
  // ---------------------------------------------------------
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.lightGray),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: AppColors.lightTeal,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.tealText, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.navyText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _entrance({
    required Widget child,
    required int delay,
    double offsetY = 18,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final progress =
            ((value * 1000 - delay) / (1000 - delay)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
