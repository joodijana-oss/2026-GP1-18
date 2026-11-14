import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/opportunity.dart';
import '../../services/opportunity_recommender.dart';
import '../../theme/app_colors.dart';
import '../../utils/skill_matcher.dart';
import 'opportunity_labels.dart';

/// Details of one recommended opportunity, with its important dates and a
/// link to the page where the user can register.
class OpportunityDetailsScreen extends StatefulWidget {
  final OpportunityMatch match;

  /// The user's career goal name (can be empty).
  final String careerGoalName;

  const OpportunityDetailsScreen({
    super.key,
    required this.match,
    required this.careerGoalName,
  });

  @override
  State<OpportunityDetailsScreen> createState() =>
      _OpportunityDetailsScreenState();
}

class _OpportunityDetailsScreenState extends State<OpportunityDetailsScreen> {
  Opportunity get _o => widget.match.opportunity;

  Future<void> _openSource() async {
    final raw = _o.url.trim();
    var uri = Uri.tryParse(raw);
    // "www.example.com" has no scheme
    if (uri != null && !uri.hasScheme && raw.isNotEmpty) {
      uri = Uri.tryParse('https://$raw');
    }
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
          content: Text('Could not open the page. Please try again.'),
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final description = _o.description.trim();
    final objectives = _clean(_o.objectives);
    final requirements = _clean(_o.requirements);
    final skills = _clean(_o.skills);

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
              _entrance(delay: 60, child: _buildWhyCard()),
              const SizedBox(height: 16),
              _entrance(delay: 120, child: _buildDatesCard()),
              const SizedBox(height: 16),
              _entrance(
                delay: 170,
                child: _sectionCard(
                  icon: Icons.description_rounded,
                  title: 'About This Opportunity',
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      description.isEmpty
                          ? 'No description yet. Open the page on ${_sourceName()} for the full details.'
                          : description,
                      style: _bodyStyle,
                    ),
                  ),
                ),
              ),
              if (objectives.isNotEmpty) ...[
                const SizedBox(height: 16),
                _entrance(
                  delay: 210,
                  child: _sectionCard(
                    icon: Icons.school_outlined,
                    title: 'What You Will Learn',
                    child: _bulletList(objectives),
                  ),
                ),
              ],
              if (requirements.isNotEmpty) ...[
                const SizedBox(height: 16),
                _entrance(
                  delay: 240,
                  child: _sectionCard(
                    icon: Icons.checklist_rounded,
                    title: 'Requirements',
                    child: _bulletList(requirements),
                  ),
                ),
              ],
              if (skills.isNotEmpty) ...[
                const SizedBox(height: 16),
                _entrance(delay: 270, child: _buildSkillsCard(skills)),
              ],
              const SizedBox(height: 26),
              _entrance(delay: 320, child: _buildSourceButton()),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _clean(List<String> items) => [
        for (final item in items)
          if (item.trim().isNotEmpty) item.trim(),
      ];

  String _sourceName() =>
      _o.sourceLabel.trim().isEmpty ? 'the source' : _o.sourceLabel.trim();

  TextStyle get _bodyStyle => TextStyle(
        color: AppColors.secondaryNavyText,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.6,
      );

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
        Expanded(
          child: Text(
            'Opportunity Details',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.navyText,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final cost = OpportunityLabels.cost(_o);

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
                      if (_o.providerLabel.isNotEmpty) ...[
                        Text(
                          _o.providerLabel,
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        _o.title,
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
                          if (_o.type.isNotEmpty)
                            _heroBadge(
                              _o.type,
                              icon: OpportunityLabels.typeIcon(_o.type),
                            ),
                          if (_o.sourceLabel.isNotEmpty)
                            _heroBadge(
                              _o.sourceLabel,
                              icon: Icons.public_rounded,
                            ),
                          if (cost != null)
                            _heroBadge(cost, highlight: _o.isFree == true),
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
                    OpportunityLabels.typeIcon(_o.type),
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

  Widget _heroBadge(String text, {IconData? icon, bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.gold.withValues(alpha: 0.3)
            : AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.tealText, size: 14),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: highlight ? AppColors.navyText : AppColors.tealText,
                fontSize: 11.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // WHY IT IS RECOMMENDED
  // ---------------------------------------------------------
  Widget _buildWhyCard() {
    final match = widget.match;
    final career = widget.careerGoalName.trim();

    final reasons = <List<InlineSpan>>[
      if (match.gapSkills.isNotEmpty)
        [
          const TextSpan(text: 'Covers your skill gaps: '),
          _boldSpan(match.gapSkills.join(', ')),
          const TextSpan(text: '.'),
        ],
      if (match.goalRelated)
        career.isEmpty
            ? [const TextSpan(text: 'Related to your career goal.')]
            : [
                const TextSpan(text: 'Related to your career goal: '),
                _boldSpan(career),
                const TextSpan(text: '.'),
              ],
      if (match.currentSkills.isNotEmpty)
        [
          const TextSpan(text: 'Builds on your skills: '),
          _boldSpan(match.currentSkills.join(', ')),
          const TextSpan(text: '.'),
        ],
    ];
    if (reasons.isEmpty) {
      reasons.add([const TextSpan(text: 'Matches your career goal.')]);
    }

    return _sectionCard(
      icon: Icons.lightbulb_outline_rounded,
      title: 'Why It Is Recommended',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < reasons.length; i++)
            _bullet(
              Text.rich(TextSpan(style: _reasonStyle, children: reasons[i])),
              last: i == reasons.length - 1,
            ),
        ],
      ),
    );
  }

  TextStyle get _reasonStyle => TextStyle(
        color: AppColors.secondaryNavyText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.45,
      );

  TextSpan _boldSpan(String text) => TextSpan(
        text: text,
        style: TextStyle(
          color: AppColors.navyText,
          fontWeight: FontWeight.w700,
        ),
      );

  // ---------------------------------------------------------
  // IMPORTANT DATES
  // ---------------------------------------------------------
  Widget _buildDatesCard() {
    final now = DateTime.now();
    final deadline = _o.registrationDeadline;
    final start = _o.startDate;
    final end = _o.endDate;
    final duration = _o.duration.trim();
    final location = _o.location.trim();
    final cost = OpportunityLabels.cost(_o);

    final dateRows = <Widget>[];
    if (deadline != null) {
      final days = _o.daysLeft(now);
      dateRows.add(
        _infoRow(
          icon: Icons.event_available_rounded,
          label: 'Registration deadline',
          value: OpportunityLabels.date(deadline),
          note: days == null ? null : OpportunityLabels.daysLeft(days),
          urgent: OpportunityLabels.isUrgent(days),
        ),
      );
    }
    if (start != null) {
      dateRows.add(
        _infoRow(
          icon: Icons.play_circle_outline_rounded,
          label: 'Start date',
          value: OpportunityLabels.date(start),
        ),
      );
    }
    if (end != null) {
      dateRows.add(
        _infoRow(
          icon: Icons.flag_outlined,
          label: 'End date',
          value: OpportunityLabels.date(end),
        ),
      );
    }
    if (dateRows.isEmpty) {
      dateRows.add(
        _infoRow(
          icon: Icons.all_inclusive_rounded,
          label: 'Availability',
          value: 'Available any time (self-paced)',
        ),
      );
    }

    final factRows = <Widget>[
      if (duration.isNotEmpty)
        _infoRow(
          icon: Icons.schedule_rounded,
          label: 'Duration',
          value: duration,
        ),
      if (location.isNotEmpty)
        _infoRow(
          icon: Icons.place_outlined,
          label: 'Location',
          value: location,
        ),
      if (cost != null)
        _infoRow(
          icon: Icons.payments_outlined,
          label: 'Cost',
          value: cost,
        ),
    ];

    return _sectionCard(
      icon: Icons.calendar_month_rounded,
      title: 'Important Dates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._spaced(dateRows),
          if (factRows.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: AppColors.lightGray),
            ),
            ..._spaced(factRows),
          ],
        ],
      ),
    );
  }

  List<Widget> _spaced(List<Widget> rows) => [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ];

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    String? note,
    bool urgent = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: urgent
                ? AppColors.gold.withValues(alpha: 0.22)
                : AppColors.lightTeal.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: urgent ? OpportunityLabels.urgentText : AppColors.tealText,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: AppColors.navyText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(
                  note,
                  style: TextStyle(
                    color: urgent
                        ? OpportunityLabels.urgentText
                        : AppColors.tealText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // SKILLS
  // ---------------------------------------------------------
  Widget _buildSkillsCard(List<String> skills) {
    final gaps = widget.match.gapSkills;
    bool covers(String skill) =>
        gaps.any((gap) => SkillMatcher.matches(gap, skill));
    final anyCovered = skills.any(covers);

    return _sectionCard(
      icon: Icons.trending_up_rounded,
      title: 'Skills',
      subtitle: anyCovered ? 'Highlighted skills cover your gaps' : null,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final skill in skills) _skillChip(skill, covers(skill)),
        ],
      ),
    );
  }

  Widget _skillChip(String skill, bool covers) {
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

  // ---------------------------------------------------------
  // SOURCE BUTTON
  // ---------------------------------------------------------
  Widget _buildSourceButton() {
    final available = _o.url.trim().isNotEmpty;
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
        onPressed: available ? _openSource : null,
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
            Flexible(
              child: Text(
                available ? 'Open on ${_sourceName()}' : 'Link not available',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
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
  Widget _bulletList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          _bullet(
            Text(items[i], style: _reasonStyle),
            last: i == items.length - 1,
          ),
      ],
    );
  }

  Widget _bullet(Widget text, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
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
          Expanded(child: text),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    String? subtitle,
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
