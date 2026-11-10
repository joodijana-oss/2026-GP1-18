import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../constants/profile_options.dart';
import '../../services/certification_matches_store.dart';
import '../../services/certification_service.dart';
import '../../services/content_based_recommender.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../career_analysis/career_analysis_screen.dart';
import 'certification_details_screen.dart';

/// Professional Certification Recommender.
///
/// Flow (same as the Release 1 flowchart):
///  - no valid AI Career Analysis  -> ask the user to complete it first
///  - analysis found               -> recommend certifications from the
///                                    skill gaps and the career goal
///  - nothing found                -> "no matching certifications" message
class CertificationsScreen extends StatefulWidget {
  const CertificationsScreen({super.key});

  @override
  State<CertificationsScreen> createState() => _CertificationsScreenState();
}

enum _ScreenState { loading, noAnalysis, start, matching, error, ready }

class _CertificationsScreenState extends State<CertificationsScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 10;

  final UserService _userService = UserService();
  final CertificationService _certificationService = CertificationService();
  final CertificationMatchesStore _matchesStore = CertificationMatchesStore();
  final ContentBasedRecommender _recommender = const ContentBasedRecommender();

  late final AnimationController _iconController;

  _ScreenState _state = _ScreenState.loading;
  Map<String, dynamic>? _analysis;
  CertificationRecommendations? _recs;
  String _careerName = '';
  int _gapCount = 0;
  int _visibleGapMatches = _pageSize;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------
  /// Step 1: is there an AI Career Analysis for the current CV?
  Future<void> _load() async {
    if (mounted) setState(() => _state = _ScreenState.loading);
    try {
      // Only an analysis that belongs to the current CV counts.
      final analysis = await _userService.getValidLatestAnalysis();
      if (!mounted) return;
      if (analysis == null) {
        setState(() {
          _analysis = null;
          _state = _ScreenState.noAnalysis;
        });
        return;
      }

      final savedName = analysis['careerGoalName']?.toString().trim();
      final goalId = analysis['careerGoalId']?.toString() ?? '';
      final gaps = analysis['skillGaps'];

      final careerName = (savedName != null && savedName.isNotEmpty)
          ? savedName
          : (ProfileOptions.careerGoals[goalId] ?? 'your career goal');
      final gapCount = gaps is List ? gaps.length : 0;

      // Matches saved for this analysis? Show them right away.
      final saved = analysis['certificationMatches'];
      CertificationRecommendations? restored;
      if (saved is Map) {
        final all = await _certificationService.getAll();
        restored = CertificationRecommendations.fromSaved(
          saved,
          byId: {for (final cert in all) cert.id: cert},
          careerGoalId: goalId,
          skillGaps: ContentBasedRecommender.skillGapsOf(analysis),
        );
        if (!mounted) return;
      }

      final restoredRecs = restored;
      setState(() {
        _analysis = analysis;
        _careerName = careerName;
        _gapCount = gapCount;
        if (restoredRecs != null) {
          _recs = restoredRecs;
          _visibleGapMatches = _pageSize;
          _state = _ScreenState.ready;
        } else {
          _state = _ScreenState.start;
        }
      });
    } catch (e) {
      debugPrint('CertificationsScreen: $e');
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _state = _ScreenState.error;
      });
    }
  }

  /// Step 2: the user taps "Find Certifications".
  Future<void> _findCertifications() async {
    final analysis = _analysis;
    if (analysis == null) return;

    setState(() => _state = _ScreenState.matching);
    try {
      final startedAt = DateTime.now();
      final user = await _userService.getUser();
      final all = await _certificationService.getAll();

      final recs = _recommender.recommendCertifications(
        analysis: analysis,
        certifications: all,
        experienceLevel: user?['experienceLevel']?.toString(),
      );

      // Save the result in the analysis document so it opens by itself next
      // time. A failed save must not hide the results.
      try {
        await _matchesStore.save(recs.toMap());
      } catch (e) {
        debugPrint('CertificationsScreen: could not save matches: $e');
      }

      // Keep the "matching" screen visible for a moment so it does not flash.
      const minimum = Duration(milliseconds: 900);
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < minimum) await Future.delayed(minimum - elapsed);

      if (!mounted) return;
      setState(() {
        _recs = recs;
        _visibleGapMatches = _pageSize;
        _state = _ScreenState.ready;
      });
    } catch (e) {
      debugPrint('CertificationsScreen: $e');
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  Future<void> _openCareerAnalysis() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CareerAnalysisScreen()),
    );
    if (!mounted) return;
    _load();
  }

  void _openDetails(CertificationMatch match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CertificationDetailsScreen(
          certification: match.certification,
          matchedGaps: match.matchedGaps,
          levelFits: match.levelFits,
          careerName: _careerName,
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _state == _ScreenState.loading
            ? Center(
                child: CircularProgressIndicator(
                  color: AppColors.tealText,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 28),
                    _buildContent(),
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
        Expanded(
          child: Text(
            'Certification Recommender',
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

  Widget _buildContent() {
    switch (_state) {
      case _ScreenState.noAnalysis:
        return _buildNoAnalysis();
      case _ScreenState.start:
        return _buildStart();
      case _ScreenState.matching:
        return _buildMatching();
      case _ScreenState.error:
        return _buildError();
      case _ScreenState.ready:
        return _buildReady();
      case _ScreenState.loading:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------
  // STATE: START (same layout as the AI Career Analysis start page)
  // ---------------------------------------------------------
  Widget _buildStart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: _buildHero(
            title: 'Find Certifications That Fit You',
            text:
                'Masra compares your skill gaps and career goal with a catalog of professional certifications and shows how each one helps you.',
            badge: 'Based on your career goal',
            icon: Icons.workspace_premium_outlined,
          ),
        ),
        const SizedBox(height: 22),
        _entrance(
          delay: 80,
          child: _buildAnalysisCard(
            title: _careerName,
            subtitle: _gapCount == 1
                ? '1 skill gap from your latest analysis'
                : '$_gapCount skill gaps from your latest analysis',
          ),
        ),
        const SizedBox(height: 26),
        _entrance(
          delay: 140,
          child: Text(
            'Your recommendations will focus on',
            style: TextStyle(
              color: AppColors.navyText,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _entrance(
          delay: 190,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildInsightCard(
                    icon: Icons.trending_up_rounded,
                    title: 'Skill Gaps',
                    subtitle: 'Certifications that close your gaps',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInsightCard(
                    icon: Icons.track_changes_rounded,
                    title: 'Career Goal',
                    subtitle: 'Certifications for your target role',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        _entrance(
          delay: 250,
          child: _buildPrimaryButton(
            label: 'Find Certifications',
            onPressed: _findCertifications,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisCard({
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(radius: 20),
      child: Row(
        children: [
          _iconTile(Icons.analytics_rounded, size: 54, radius: 16, iconSize: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.lightTeal,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.check_rounded,
              color: AppColors.tealText,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconTile(icon, size: 42, radius: 13),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: AppColors.navyText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // STATE: MATCHING (short loading view after the button)
  // ---------------------------------------------------------
  Widget _buildMatching() {
    return Padding(
      padding: const EdgeInsets.only(top: 90),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                color: AppColors.tealText,
                strokeWidth: 3.5,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Matching certifications to your skill gaps',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.navyText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This only takes a moment.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // STATE: NO ANALYSIS
  // ---------------------------------------------------------
  Widget _buildNoAnalysis() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: _buildHero(
            title: 'Start With Your Career Analysis',
            text:
                'Certification recommendations are built from your skill gaps and your career goal, so Masra needs your AI Career Analysis results first.',
            badge: 'Based on your career goal',
            icon: Icons.insights_rounded,
          ),
        ),
        const SizedBox(height: 22),
        _entrance(
          delay: 80,
          child: _buildInfoCard(
            icon: Icons.analytics_rounded,
            title: 'No analysis results yet',
            subtitle: 'Analyze your CV to unlock certification matches.',
          ),
        ),
        const SizedBox(height: 26),
        _entrance(
          delay: 140,
          child: _buildPrimaryButton(
            label: 'Go to AI Career Analysis',
            onPressed: _openCareerAnalysis,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // STATE: ERROR
  // ---------------------------------------------------------
  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: _buildErrorBox(
            'We could not load your certification matches. Check your connection and try again.',
          ),
        ),
        const SizedBox(height: 20),
        _entrance(
          delay: 60,
          child: _buildPrimaryButton(
            label: 'Try Again',
            onPressed: _analysis == null ? _load : _findCertifications,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // STATE: READY
  // ---------------------------------------------------------
  Widget _buildReady() {
    final recs = _recs!;
    final shown = recs.forGaps.take(_visibleGapMatches).toList();
    final hasMore = recs.forGaps.length > shown.length;
    final totalGaps = recs.skillGaps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Certification Matches',
                style: TextStyle(
                  color: AppColors.navyText,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Certifications that fit your skill gaps and your career goal.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _entrance(delay: 60, child: _buildSummaryCard(recs)),
        if (recs.isEmpty) ...[
          const SizedBox(height: 22),
          _entrance(
            delay: 120,
            child: _buildInfoCard(
              icon: Icons.search_off_rounded,
              title: 'No matching certifications yet',
              subtitle:
                  'We do not have certifications for this career goal yet. We keep adding new ones, so check back soon.',
            ),
          ),
        ],
        if (recs.forGaps.isNotEmpty) ...[
          const SizedBox(height: 26),
          _sectionTitle('Closes your skill gaps', recs.forGaps.length),
          const SizedBox(height: 14),
          for (final match in shown) _buildCertCard(match, totalGaps),
          if (hasMore)
            _buildShowMore(
              remaining: recs.forGaps.length - shown.length,
              onTap: () => setState(() => _visibleGapMatches += _pageSize),
            ),
        ],
        if (recs.forGaps.isEmpty && !recs.isEmpty) ...[
          const SizedBox(height: 22),
          _entrance(
            delay: 120,
            child: _buildInfoCard(
              icon: Icons.info_outline_rounded,
              title: totalGaps == 0
                  ? 'No skill gaps found'
                  : 'No certification covers your gaps yet',
              subtitle: totalGaps == 0
                  ? 'Here are certifications that fit your career goal.'
                  : 'These certifications fit your career goal. More are added over time.',
            ),
          ),
        ],
        if (recs.forGoal.isNotEmpty) ...[
          const SizedBox(height: 26),
          _sectionTitle('More for your goal', recs.forGoal.length),
          const SizedBox(height: 14),
          for (final match in recs.forGoal) _buildCertCard(match, totalGaps),
        ],
        if (recs.hiddenOwned > 0) ...[
          const SizedBox(height: 4),
          Text(
            recs.hiddenOwned == 1
                ? '1 certification already listed in your CV is hidden.'
                : '${recs.hiddenOwned} certifications already listed in your CV are hidden.',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 22),
        _entrance(
          delay: 100,
          child: _buildNextCard(
            title: 'Fresh with every analysis',
            text:
                'Replace your CV and run a new analysis to get updated certification matches.',
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(CertificationRecommendations recs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconTile(Icons.track_changes_rounded, size: 43, radius: 13),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Based on your analysis',
                      style: TextStyle(
                        color: AppColors.navyText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _careerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Your skill gaps',
            style: TextStyle(
              color: AppColors.navyText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (recs.skillGaps.isEmpty)
            Text(
              'No skill gaps were found in your latest analysis.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12.5,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final gap in recs.skillGaps)
                  _chip(gap, icon: Icons.trending_up_rounded),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCertCard(CertificationMatch match, int totalGaps) {
    final cert = match.certification;
    final covers = match.gapCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _entrance(
        delay: 0,
        child: _PressableCard(
          onTap: () => _openDetails(match),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(radius: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _iconTile(
                      Icons.workspace_premium_outlined,
                      size: 54,
                      radius: 16,
                      iconSize: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cert.issuer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cert.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.navyText,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                      size: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (cert.level.isNotEmpty) _pill(cert.level),
                    if (cert.category.isNotEmpty) _pill(cert.category),
                    if (!cert.verified) _pill('Not verified', warning: true),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  cert.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                _buildWhyBox(match),
                if (covers) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '${match.gapCount} of $totalGaps gaps covered',
                        style: TextStyle(
                          color: AppColors.tealText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: totalGaps == 0
                                ? 0
                                : match.gapCount / totalGaps,
                            minHeight: 6,
                            backgroundColor: AppColors.lightGray,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.teal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhyBox(CertificationMatch match) {
    final baseStyle = TextStyle(
      color: AppColors.secondaryNavyText,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.5,
    );
    final boldStyle = baseStyle.copyWith(
      color: AppColors.navyText,
      fontWeight: FontWeight.w700,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightTeal.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.tealText,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (match.gapCount > 0)
                  Text.rich(
                    TextSpan(
                      style: baseStyle,
                      children: [
                        const TextSpan(text: 'Covers your gaps: '),
                        TextSpan(
                          text: match.matchedGaps.join(', '),
                          style: boldStyle,
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'Relevant to your career goal.',
                    style: baseStyle,
                  ),
                if (match.levelFits) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Fits your experience level.',
                    style: baseStyle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowMore({
    required int remaining,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppColors.softBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.lightGray),
        ),
        alignment: Alignment.center,
        child: Text(
          'Show more ($remaining)',
          style: TextStyle(
            color: AppColors.navyText,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // SMALL PIECES (same look as the AI Career Analysis screen)
  // ---------------------------------------------------------
  BoxDecoration _cardDecoration({required double radius}) {
    return BoxDecoration(
      color: AppColors.softBackground,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.lightGray),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: 0.035),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _iconTile(
    IconData icon, {
    required double size,
    required double radius,
    double iconSize = 23,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.lightTeal,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: AppColors.tealText, size: iconSize),
    );
  }

  Widget _chip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGray),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.tealText, size: 16),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.navyText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {bool warning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: warning
            ? AppColors.gold.withValues(alpha: 0.22)
            : AppColors.lightTeal,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: warning ? AppColors.navyText : AppColors.secondaryNavyText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, int count) {
    return _entrance(
      delay: 100,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.navyText,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.lightTeal,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: AppColors.secondaryNavyText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(radius: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconTile(icon, size: 54, radius: 16, iconSize: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextCard({required String title, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lightTeal.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.softBackground,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.refresh_rounded,
              color: AppColors.tealText,
              size: 22,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.navyText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero({
    required String title,
    required String text,
    required String badge,
    required IconData icon,
  }) {
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
                        title,
                        style: TextStyle(
                          color: AppColors.navyText,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        text,
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softBackground,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.track_changes_rounded,
                              color: AppColors.tealText,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              badge,
                              style: TextStyle(
                                color: AppColors.tealText,
                                fontSize: 11.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildFloatingIcon(icon),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingIcon(IconData icon) {
    return AnimatedBuilder(
      animation: _iconController,
      builder: (context, child) {
        final t = _iconController.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * 5),
          child: Transform.rotate(
            angle: math.sin(t) * 0.04,
            child: child,
          ),
        );
      },
      child: Container(
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
        child: Icon(icon, color: AppColors.tealText, size: 30),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppColors.navy,
            AppColors.secondaryNavy,
            AppColors.teal,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB84545),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB84545),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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

/// A card that shrinks slightly while it is pressed.
class _PressableCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _PressableCard({required this.onTap, required this.child});

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
