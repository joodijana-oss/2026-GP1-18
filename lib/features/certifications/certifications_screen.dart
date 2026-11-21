import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/profile_options.dart';
import '../../models/certification.dart';
import '../../services/certification_service.dart';
import '../../services/content_based_recommender.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../career_analysis/career_analysis_screen.dart';
import 'certification_details_screen.dart';
import 'certification_setup_memory.dart';

/// Certification Recommender.
///
/// Flow:
///  - no valid AI Career Analysis  -> ask the user to complete it first
///  - analysis found, and it is the first time, a new analysis or the
///    career goal changed          -> the setup page: the user chooses what
///                                    they want (close skill gaps /
///                                    strengthen skills) and how many
///                                    (Top 5 / Top 10 / All)
///  - analysis found, nothing changed since the last time
///                                 -> the results open straight away with
///                                    the last choices
///  - "Change" on the results      -> back to the setup page; the back arrow
///                                    returns to the same results
///  - nothing found                -> "no matching certifications" message
///
/// Matching runs on the phone (300 certifications). The choices are
/// remembered on this device for each signed-in user when Find
/// Certifications is tapped; nothing is saved in Firestore.
class CertificationsScreen extends StatefulWidget {
  const CertificationsScreen({
    super.key,
    this.userService,
    this.certificationService,
    this.currentUserId,
  });

  /// Only tests pass these. The app uses the real services and the signed-in
  /// Firebase user.
  final UserService? userService;
  final CertificationService? certificationService;
  final String? Function()? currentUserId;

  @override
  State<CertificationsScreen> createState() => _CertificationsScreenState();
}

enum _ScreenState { loading, noAnalysis, start, matching, error, ready }

class _CertificationsScreenState extends State<CertificationsScreen>
    with SingleTickerProviderStateMixin {
  // Created only when first used, so a test can pass its own services and
  // Firebase is never touched.
  late final UserService _userService = widget.userService ?? UserService();
  late final CertificationService _certificationService =
      widget.certificationService ?? CertificationService();
  final ContentBasedRecommender _recommender = const ContentBasedRecommender();
  final CertificationSetupMemory _memory = const CertificationSetupMemory();

  late final AnimationController _iconController;

  // The same scroll view stays on screen when switching between the results
  // and the setup page, so it is moved back to the top by hand.
  final ScrollController _scrollController = ScrollController();

  _ScreenState _state = _ScreenState.loading;
  Map<String, dynamic>? _analysis;
  CertificationRecommendations? _recs;
  List<Certification>? _catalog;
  String? _experienceLevel;
  String _careerName = '';

  CertificationGoal _goal = CertificationGoal.closeGaps;
  int? _limit = CertificationSetupMemory.defaultLimit;

  // Who is signed in, and which analysis and career goal are on screen.
  // Saved with the choices so the next visit can tell if anything changed.
  String? _uid;
  String? _analysisKey;
  String? _careerGoalId;

  // True while the user is on the setup page after tapping "Change". The
  // choices the results were made with are kept, so going back restores
  // them without changing anything.
  bool _changingChoices = false;
  CertificationGoal _goalBeforeChange = CertificationGoal.closeGaps;
  int? _limitBeforeChange;

  bool get _forGaps => _goal == CertificationGoal.closeGaps;

  /// True when back should return to the results instead of leaving.
  bool get _canReturnToResults =>
      _changingChoices && _recs != null && _state == _ScreenState.start;

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
    _scrollController.dispose();
    super.dispose();
  }

  /// The signed-in user's id (a test can pass its own).
  String? _currentUid() {
    final fromTest = widget.currentUserId;
    return fromTest != null
        ? fromTest()
        : FirebaseAuth.instance.currentUser?.uid;
  }

  // ---------------------------------------------------------
  // CHOICES (saved only when Find Certifications is tapped)
  // ---------------------------------------------------------
  void _chooseGoal(CertificationGoal goal) {
    if (goal == _goal) return;
    setState(() => _goal = goal);
  }

  void _chooseLimit(int? limit) {
    if (limit == _limit) return;
    setState(() => _limit = limit);
  }

  /// "Change" on the results: open the setup page with the current choices.
  void _openChangeChoices() {
    setState(() {
      _goalBeforeChange = _goal;
      _limitBeforeChange = _limit;
      _changingChoices = true;
      _state = _ScreenState.start;
    });
    _scrollToTop();
  }

  /// Back from the setup page after "Change": the same results as before,
  /// with any choice picked on the setup page dropped.
  void _backToResults() {
    setState(() {
      _goal = _goalBeforeChange;
      _limit = _limitBeforeChange;
      _changingChoices = false;
      _state = _ScreenState.ready;
    });
    _scrollToTop();
  }

  void _handleBack() {
    if (_canReturnToResults) {
      _backToResults();
    } else {
      Navigator.pop(context);
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  // ---------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------
  /// Step 1: is there an AI Career Analysis for the current CV? Then show
  /// the setup page, or the results straight away if nothing changed.
  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _state = _ScreenState.loading;
        _changingChoices = false;
      });
    }
    try {
      _uid = _currentUid();
      final saved = _uid == null ? null : await _memory.load(_uid!);

      // Only an analysis that belongs to the current CV (and career goal)
      // counts.
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
      final careerName = (savedName != null && savedName.isNotEmpty)
          ? savedName
          : (ProfileOptions.careerGoals[goalId] ?? '');

      _analysisKey = CertificationSetupMemory.analysisKeyOf(analysis);
      _careerGoalId = CertificationSetupMemory.careerGoalIdOf(analysis);
      // The last choices, or the defaults the first time.
      _goal = saved?.goal ?? CertificationGoal.closeGaps;
      _limit = saved == null
          ? CertificationSetupMemory.defaultLimit
          : saved.limit;

      final showSetup = CertificationSetupMemory.shouldShowSetup(
        saved: saved,
        analysisKey: _analysisKey,
        careerGoalId: _careerGoalId,
      );

      if (showSetup) {
        setState(() {
          _analysis = analysis;
          _careerName = careerName;
          _state = _ScreenState.start;
        });
        return;
      }

      // Nothing changed: go straight to the results. The matching view is
      // set in the same frame, so the setup page never shows.
      _analysis = analysis;
      _careerName = careerName;
      await _findCertifications(remember: false);
    } catch (e) {
      debugPrint('CertificationsScreen: $e');
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _state = _ScreenState.error;
      });
    }
  }

  CertificationRecommendations _compute() {
    return _recommender.recommendCertifications(
      analysis: _analysis!,
      certifications: _catalog!,
      experienceLevel: _experienceLevel,
      goal: _goal,
    );
  }

  /// Step 2: the user taps "Find Certifications" (or the results open
  /// straight away). [remember] saves the choices for the next visit.
  Future<void> _findCertifications({bool remember = true}) async {
    if (_analysis == null) return;

    setState(() => _state = _ScreenState.matching);
    try {
      final startedAt = DateTime.now();
      if (_catalog == null) {
        final user = await _userService.getUser();
        _experienceLevel = user?['experienceLevel']?.toString();
        _catalog = await _certificationService.getAll();
      }
      final recs = _compute();

      // Keep the "matching" screen visible for a moment so it does not flash.
      const minimum = Duration(milliseconds: 900);
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < minimum) await Future.delayed(minimum - elapsed);

      if (!mounted) return;
      setState(() {
        _recs = recs;
        _state = _ScreenState.ready;
        _changingChoices = false;
      });
      // Not awaited: it catches its own errors.
      if (remember && _uid != null) {
        _memory.saveRun(
          _uid!,
          goal: _goal,
          limit: _limit,
          analysisKey: _analysisKey,
          careerGoalId: _careerGoalId,
        );
      }
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
    _recs = null;
    _load();
  }

  void _openDetails(CertificationMatch match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CertificationDetailsScreen(
          certification: match.certification,
          matchedSkills: match.matchedSkills,
          goal: _goal,
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
    // After "Change", the system back gesture returns to the results instead
    // of closing the screen.
    return PopScope(
      canPop: !_canReturnToResults,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canReturnToResults) _backToResults();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: _state == _ScreenState.loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: AppColors.tealText,
                  ),
                )
              : SingleChildScrollView(
                  controller: _scrollController,
                  // The back button's 48 dp touch area is taller than the
                  // title (29), so the top space and the gap under the
                  // header are 9.5 less than before ((48 - 29) / 2). The
                  // arrow, the title and the page stay where they were.
                  padding: const EdgeInsets.fromLTRB(20, 6.5, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 18.5),
                      _buildContent(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // A 48 dp touch area with a "Back" label for screen readers. It is
        // moved left by its extra padding ((48 - 21) / 2) so the arrow stays
        // lined up with the cards below, and the title stays where it was.
        Transform.translate(
          offset: const Offset(-13.5, 0),
          child: IconButton(
            onPressed: _handleBack,
            tooltip: 'Back',
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.navyText,
              size: 21,
            ),
          ),
        ),
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
    final targets = _forGaps
        ? ContentBasedRecommender.skillGapsOf(_analysis!)
        : ContentBasedRecommender.currentSkillsOf(_analysis!);
    final n = targets.length;
    final what = _forGaps ? 'skill gap' : 'current skill';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: _buildHero(
            title: 'Find Certifications That Fit You',
            text:
                'Masra compares your analysis and career goal with a catalog of professional certifications and shows how each one helps you.',
            badge: 'Based on your career goal',
            icon: Icons.workspace_premium_outlined,
          ),
        ),
        const SizedBox(height: 22),
        _entrance(
          delay: 80,
          child: _buildAnalysisCard(
            title: _careerName.isEmpty ? 'Your career goal' : _careerName,
            subtitle: n == 1
                ? '1 $what from your latest analysis'
                : '$n ${what}s from your latest analysis',
          ),
        ),
        const SizedBox(height: 26),
        _entrance(delay: 140, child: _buildChoices()),
        const SizedBox(height: 26),
        _entrance(
          delay: 250,
          child: _buildPrimaryButton(
            label: 'Find Certifications',
            onPressed: () => _findCertifications(),
          ),
        ),
      ],
    );
  }

  /// "What do you want?" and "How many?" on the setup page. The results show
  /// them as one "Your choices" row instead.
  Widget _buildChoices() {
    const limits = CertificationSetupMemory.limits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _choiceLabel('What do you want?'),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _goalOption(
                  goal: CertificationGoal.closeGaps,
                  icon: Icons.trending_up_rounded,
                  title: CertificationSetupMemory.goalTitle(
                    CertificationGoal.closeGaps,
                  ),
                  subtitle: 'Learn what your career goal needs',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _goalOption(
                  goal: CertificationGoal.strengthenSkills,
                  icon: Icons.bolt_rounded,
                  title: CertificationSetupMemory.goalTitle(
                    CertificationGoal.strengthenSkills,
                  ),
                  subtitle: 'Prove and deepen what you know',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _choiceLabel('How many?'),
        const SizedBox(height: 10),
        // All three tiles take the height of the tallest, so they stay even
        // when large text makes a label wrap.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < limits.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _limitOption(limits[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _choiceLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.navyText,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _goalOption({
    required CertificationGoal goal,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _goal == goal;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
        onTap: () => _chooseGoal(goal),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppColors.teal : AppColors.softBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.lightGray,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.onBrand : AppColors.tealText,
                size: 22,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: selected ? AppColors.onBrand : AppColors.navyText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: selected
                      ? AppColors.onBrand.withValues(alpha: 0.85)
                      : AppColors.secondaryText,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _limitOption(int? limit) {
    final selected = _limit == limit;
    final label = CertificationSetupMemory.limitLabel(limit);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: () => _chooseLimit(limit),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // A minimum height instead of a fixed one, so large text does not
          // spill out of the tile.
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : AppColors.softBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.lightGray,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.onBrand : AppColors.navyText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
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



  // ---------------------------------------------------------
  // STATE: MATCHING (short loading view after the button, or when the
  // results open straight away)
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
              _forGaps
                  ? 'Matching certifications to your skill gaps'
                  : 'Matching certifications to your skills',
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
            title: 'Start With Your AI Career Analysis',
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
            onPressed: _analysis == null ? _load : () => _findCertifications(),
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
    final total = recs.targetSkills.length;
    final limit = _limit;
    final shown = recs.top(limit);

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
                _forGaps
                    ? 'Certifications that close your skill gaps for your career goal.'
                    : 'Certifications that build on the skills you already have.',
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
        _entrance(delay: 40, child: _buildYourChoicesRow()),
        const SizedBox(height: 22),
        _entrance(delay: 80, child: _buildSummaryCard(recs)),
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
        ] else ...[
          if (recs.matched.isEmpty) ...[
            const SizedBox(height: 22),
            _buildInfoCard(
              icon: Icons.info_outline_rounded,
              title: total == 0
                  ? (_forGaps ? 'No skill gaps found' : 'No skills found')
                  : (_forGaps
                      ? 'No certification covers your gaps yet'
                      : 'No certification builds on your skills yet'),
              subtitle: 'Here are certifications that fit your career goal.',
            ),
          ],
          if (limit != null) ...[
            const SizedBox(height: 26),
            _sectionTitle(_topHeading(shown.length, limit), shown.length),
            const SizedBox(height: 14),
            for (final match in shown) _buildCertCard(match, total),
            if (recs.total > shown.length)
              Text(
                'Showing ${shown.length} of ${recs.total} certifications for your career goal. Tap Change and choose All to see every one.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            // Fewer than chosen: every certification for the career goal is
            // already on screen.
            if (shown.length < limit)
              Text(
                shown.length == 1
                    ? 'Showing the only certification for your career goal, fewer than the $limit you chose. We keep adding new ones.'
                    : 'Showing all ${shown.length} certifications for your career goal, fewer than the $limit you chose. We keep adding new ones.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
          ] else ...[
            if (recs.matched.isNotEmpty) ...[
              const SizedBox(height: 26),
              _sectionTitle(
                _forGaps ? 'Covers your skill gaps' : 'Builds on your skills',
                recs.matched.length,
              ),
              const SizedBox(height: 14),
              for (final match in recs.matched) _buildCertCard(match, total),
            ],
            if (recs.others.isNotEmpty) ...[
              const SizedBox(height: 26),
              _sectionTitle('Also for your career goal', recs.others.length),
              const SizedBox(height: 14),
              for (final match in recs.others) _buildCertCard(match, total),
            ],
          ],
        ],
        if (recs.hiddenOwned > 0) ...[
          const SizedBox(height: 8),
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
                'Replace your CV or change your career goal and run a new analysis to get updated certification matches.',
          ),
        ),
      ],
    );
  }

  /// The heading over a "Top 5" or "Top 10" list. It says "Top 5" only when
  /// there are enough certifications to fill the choice, so it always
  /// matches "Your choices". With fewer it says "All 4" or "The only one",
  /// so it is clear the list is complete.
  String _topHeading(int shownCount, int limit) {
    final String count;
    if (shownCount >= limit) {
      count = 'Top $limit';
    } else if (shownCount == 1) {
      count = 'The only one';
    } else {
      count = 'All $shownCount';
    }
    return _forGaps
        ? '$count to close your gaps'
        : '$count to strengthen your skills';
  }

  static const TextStyle _changeLabelStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w800,
  );

  /// "Your choices" above the results: what the list was made with, and a
  /// "Change" button that opens the setup page again.
  ///
  /// On a small phone or with large text there is not enough room for the
  /// choices beside the button, so the button moves under them.
  Widget _buildYourChoicesRow() {
    const tileSize = 43.0;
    const iconGap = 13.0;
    const buttonGap = 12.0;

    final icon = _iconTile(
      Icons.tune_rounded,
      size: tileSize,
      radius: 13,
      iconSize: 22,
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your choices',
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        // No line limit, so "Top 5", "Top 10" or "All" is never cut off.
        Text(
          CertificationSetupMemory.choicesSummary(_goal, _limit),
          style: TextStyle(
            color: AppColors.navyText,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
      ],
    );

    final changeButton = OutlinedButton(
      onPressed: _openChangeChoices,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.tealText,
        side: BorderSide(color: AppColors.tealText, width: 1.5),
        // A minimum height instead of a fixed one, so large text does not
        // clip.
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
      // The style is on the text (not the button) so it keeps the app font.
      child: const Text('Change', style: _changeLabelStyle),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _cardDecoration(radius: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Room left for the texts when the button sits beside them. They
          // need about 120 dp at normal text size to show the choices on
          // two lines, and more as the text gets larger.
          final textRoom = constraints.maxWidth -
              tileSize -
              iconGap -
              buttonGap -
              _changeButtonWidth(context);
          final textScale =
              MediaQuery.textScalerOf(context).scale(14.5) / 14.5;

          if (textRoom >= 120 * textScale) {
            return Row(
              children: [
                icon,
                const SizedBox(width: iconGap),
                Expanded(child: texts),
                const SizedBox(width: buttonGap),
                changeButton,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icon,
                  const SizedBox(width: iconGap),
                  Expanded(child: texts),
                ],
              ),
              const SizedBox(height: 12),
              // Lined up with the texts above.
              Padding(
                padding: const EdgeInsets.only(left: tileSize + iconGap),
                child: changeButton,
              ),
            ],
          );
        },
      ),
    );
  }

  /// How wide the "Change" button is at the phone's text size: the label
  /// plus the button's padding on both sides.
  double _changeButtonWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Change',
        style: DefaultTextStyle.of(context).style.merge(_changeLabelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 2 * 16;
    painter.dispose();
    return width;
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
                      _careerName.isEmpty ? 'Your career goal' : _careerName,
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
            _forGaps ? 'Your skill gaps' : 'Your current skills',
            style: TextStyle(
              color: AppColors.navyText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (recs.targetSkills.isEmpty)
            Text(
              _forGaps
                  ? 'No skill gaps were found in your latest analysis.'
                  : 'No skills were found in your latest analysis.',
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
                for (final skill in recs.targetSkills)
                  _chip(
                    skill,
                    icon: _forGaps
                        ? Icons.trending_up_rounded
                        : Icons.check_circle_outline_rounded,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCertCard(CertificationMatch match, int totalTargets) {
    final cert = match.certification;
    final covers = match.matchCount > 0;

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
                        _forGaps
                            ? '${match.matchCount} of $totalTargets ${totalTargets == 1 ? 'gap' : 'gaps'} covered'
                            : 'Uses ${match.matchCount} of your $totalTargets ${totalTargets == 1 ? 'skill' : 'skills'}',
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
                            value: totalTargets == 0
                                ? 0
                                : match.matchCount / totalTargets,
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
                if (match.matchCount > 0)
                  Text.rich(
                    TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(
                          text: _forGaps
                              ? 'Covers your gaps: '
                              : 'Builds on your skills: ',
                        ),
                        TextSpan(
                          text: match.matchedSkills.join(', '),
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
                    _forGaps
                        ? 'Fits your experience level.'
                        : 'A good next step for your level.',
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

  Color get _errorText =>
      AppColors.isDark ? const Color(0xFFFF9A9A) : const Color(0xFFB84545);

  Widget _buildErrorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.isDark
            ? const Color(0xFF3A1F24)
            : const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: _errorText,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: _errorText,
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
