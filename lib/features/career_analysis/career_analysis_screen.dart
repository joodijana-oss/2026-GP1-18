import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/career_path_service.dart';
import '../../services/claude_service.dart';
import '../../services/job_market_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../learning_roadmap/learning_roadmap_screen.dart';

class CareerAnalysisScreen extends StatefulWidget {
  const CareerAnalysisScreen({super.key});

  @override
  State<CareerAnalysisScreen> createState() =>
      _CareerAnalysisScreenState();
}

class _CareerAnalysisScreenState extends State<CareerAnalysisScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final ClaudeService _claudeService = ClaudeService();
  final CareerPathService _careerPathService = CareerPathService();
  final JobMarketService _jobMarketService = JobMarketService();

  bool _isLoading = true;
  bool _isAnalyzing = false;
  bool _showResults = false;

  int _analysisStep = 0;

  String? _cvText;
  String? _cvFileName;
  String? _errorMessage;

  late final AnimationController _iconController;

  List<String> _strengths = [];
  List<String> _skillGaps = [];

  final List<String> _analysisSteps = [
    'Reading your CV',
    'Analyzing Saudi job-market data',
    'Preparing your career insights',
  ];

  @override
  void initState() {
    super.initState();

    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();

    _loadCareerAnalysisPage();
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  // =========================================================
  // LOAD PAGE
  // =========================================================

  Future<void> _loadCareerAnalysisPage() async {
    try {
      final userData = await _userService.getUser();
      final cvText = await _userService.getCvText();
      final validAnalysis =
          await _userService.getValidLatestAnalysis();

      if (!mounted) return;

      final cvData = userData?['cv'];

      setState(() {
        _cvText = cvText;

        if (cvData is Map && cvData['fileName'] != null) {
          _cvFileName = cvData['fileName'].toString();
        }

        if (validAnalysis != null) {
          _strengths = List<String>.from(
            validAnalysis['strengths'] ?? [],
          );

          _skillGaps = List<String>.from(
            validAnalysis['skillGaps'] ?? [],
          );

          _showResults = true;
        } else {
          _strengths = [];
          _skillGaps = [];
          _showResults = false;
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('LOAD CAREER ANALYSIS ERROR: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Could not load your career analysis.';
      });
    }
  }

  // =========================================================
  // ANALYZE CV
  // =========================================================

  Future<void> _analyzeCv() async {
    if (_cvText == null || _cvText!.trim().isEmpty) {
      setState(() {
        _errorMessage =
            'No CV found. Please upload your CV first.';
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _showResults = false;
      _analysisStep = 0;
      _errorMessage = null;
    });

    try {
      // 1) Career goal
      final userData = await _userService.getUser();

      final careerGoalId =
          userData?['careerGoalId']?.toString().trim();

      if (careerGoalId == null || careerGoalId.isEmpty) {
        throw Exception(
          'Career goal is missing from the user profile.',
        );
      }

      final careerName =
          await _careerPathService.getCareerName(careerGoalId);

      // 2) Analyze CV
      final cvAnalysis = await _claudeService.analyzeCv(
        cvText: _cvText!,
      );

      final currentSkills = List<String>.from(
        cvAnalysis['currentSkills'] ?? [],
      );

      if (!mounted) return;
      setState(() => _analysisStep = 1);

      // 3) Relevant jobs from Masra dataset
      final relevantJobs =
          await _jobMarketService.getRelevantJobs(
        careerGoalId,
        limit: 20,
      );

      if (relevantJobs.isEmpty) {
        throw Exception(
          'No relevant job postings were found for $careerName.',
        );
      }

      final marketJobCount = relevantJobs.length;

      // 4) Build market text
      final jobMarketText = _buildJobMarketText(relevantJobs);

      // 5) Extract target market skills
      final targetSkills =
          await _claudeService.extractMarketSkills(
        careerName: careerName,
        jobMarketText: jobMarketText,
      );

      if (targetSkills.isEmpty) {
        throw Exception(
          'No market skills could be identified.',
        );
      }

      if (!mounted) return;
      setState(() => _analysisStep = 2);

      // 6) Semantic comparison
      final skillGaps =
          await _claudeService.identifySkillGaps(
        currentSkills: currentSkills,
        targetSkills: targetSkills,
      );

      // 7) Final analysis
      final finalAnalysis = <String, dynamic>{
        'strengths': List<String>.from(
          cvAnalysis['strengths'] ?? [],
        ),
        'currentSkills': currentSkills,
        'skillGaps': skillGaps,
        'targetSkills': targetSkills,

        // Keep structured AI output as-is.
        'education': cvAnalysis['education'] ?? [],
        'certifications': cvAnalysis['certifications'] ?? [],
        'projects': cvAnalysis['projects'] ?? [],
        'experience': cvAnalysis['experience'] ?? [],

        'careerGoalId': careerGoalId,
        'careerGoalName': careerName,
        'marketJobCount': marketJobCount,
        'analysisSource':
            'Masra Saudi job postings dataset',
        'marketBased': true,
      };

      // 8) Save
      await _userService.saveLatestAnalysis(finalAnalysis);

      if (!mounted) return;

      // 9) Show results
      setState(() {
        _analysisStep = 3;
        _strengths = List<String>.from(
          finalAnalysis['strengths'] ?? [],
        );
        _skillGaps = List<String>.from(
          finalAnalysis['skillGaps'] ?? [],
        );
        _isAnalyzing = false;
        _showResults = true;
      });

      debugPrint('================================');
      debugPrint('CAREER ANALYSIS SUCCESS');
      debugPrint('Career Goal: $careerName');
      debugPrint('Relevant Jobs: $marketJobCount');
      debugPrint('Current Skills: $currentSkills');
      debugPrint('Market Target Skills: $targetSkills');
      debugPrint('Skill Gaps: $skillGaps');
      debugPrint('================================');
    } catch (e) {
      debugPrint('CAREER ANALYSIS ERROR: $e');

      if (!mounted) return;

      setState(() {
        _isAnalyzing = false;
        _errorMessage =
            'Could not analyze your CV. Please try again.';
      });
    }
  }

  String _buildJobMarketText(
    List<Map<String, String>> jobs,
  ) {
    final buffer = StringBuffer();

    for (int i = 0; i < jobs.length; i++) {
      final job = jobs[i];

      buffer.writeln('JOB ${i + 1}');
      buffer.writeln('Title: ${job['title'] ?? ''}');

      final city = job['city'] ?? '';

      if (city.trim().isNotEmpty) {
        buffer.writeln('City: $city');
      }

      buffer.writeln('Description:');
      buffer.writeln(job['description'] ?? '');
      buffer.writeln('------------------------------');
    }

    return buffer.toString();
  }

  bool get _hasCv =>
      _cvText != null && _cvText!.trim().isNotEmpty;

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.teal,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  30,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 28),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 480),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.03, 0.05),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _buildCurrentContent(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildCurrentContent() {
    if (_isAnalyzing) {
      return KeyedSubtree(
        key: const ValueKey('analyzing'),
        child: _buildAnalyzingContent(),
      );
    }

    if (_showResults) {
      return KeyedSubtree(
        key: const ValueKey('results'),
        child: _buildResultsContent(),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('start'),
      child: _buildStartContent(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.navy,
            size: 21,
          ),
        ),
        const SizedBox(width: 26),
        const Text(
          'AI Career Analysis',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
            ((value * 1000 - delay) / (1000 - delay))
                .clamp(0.0, 1.0);

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

  // =========================================================
  // START CONTENT — FINAL UI
  // =========================================================

  Widget _buildStartContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: _buildHeroSection(),
        ),
        const SizedBox(height: 22),
        _entrance(
          delay: 80,
          child: _buildCvCard(),
        ),
        const SizedBox(height: 24),
        _entrance(
          delay: 130,
          child: const Text(
            'Your analysis will focus on',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _entrance(
                  delay: 170,
                  child: _buildInsightCard(
                    title: 'Strengths',
                    subtitle: 'What stands out in your CV',
                    icon: Icons.star_outline_rounded,
                    isStar: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _entrance(
                  delay: 240,
                  child: _buildInsightCard(
                    title: 'Skill Gaps',
                    subtitle:
                        'Based on your career goal and market demand',
                    icon: Icons.trending_up_rounded,
                    isStar: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(),
        ],
        const SizedBox(height: 26),
        _entrance(
          delay: 310,
          child: _buildAnalyzeButton(),
        ),
      ],
    );
  }

  Widget _buildHeroSection() {
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
                  color: AppColors.teal.withValues(alpha: 0.10),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Understand your CV with AI',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.16,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Discover what stands out in your CV and which skills can bring you closer to your career goal.',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                      SizedBox(height: 15),
                      _CareerGoalBadge(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedBuilder(
                  animation: _iconController,
                  builder: (context, child) {
                    final movement = math.sin(
                          _iconController.value * 2 * math.pi,
                        ) *
                        5;

                    final rotation = math.sin(
                          _iconController.value * 2 * math.pi,
                        ) *
                        0.04;

                    return Transform.translate(
                      offset: Offset(0, movement),
                      child: Transform.rotate(
                        angle: rotation,
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
                          color:
                              AppColors.teal.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.teal,
                      size: 30,
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

  Widget _buildInsightCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isStar,
  }) {
    return _PressableInsightCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      isStar: isStar,
      controller: _iconController,
    );
  }

  // =========================================================
  // CV CARD
  // =========================================================

  Widget _buildCvCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.lightGray,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.lightTeal,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.description_rounded,
              color: AppColors.teal,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasCv
                      ? (_cvFileName ?? 'Uploaded CV')
                      : 'No CV uploaded',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _hasCv
                      ? 'Ready for analysis'
                      : 'Upload your CV before starting.',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (_hasCv)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.lightTeal,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.teal,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // ANALYZING
  // =========================================================

  Widget _buildAnalyzingContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analyzing your CV',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Masra is comparing your CV with relevant Saudi job-market data.',
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.softBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.lightGray),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.035),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildAnalyzingIcon(),
              const SizedBox(height: 20),
              const Text(
                'Building your insights',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'This may take a few moments.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 24),
              ...List.generate(
                _analysisSteps.length,
                (index) => _buildAnalysisStep(
                  index,
                  _analysisSteps[index],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzingIcon() {
    return AnimatedBuilder(
      animation: _iconController,
      builder: (context, child) {
        final pulse = 1 +
            math.sin(
                  _iconController.value * 2 * math.pi,
                ) *
                0.04;

        return Transform.scale(
          scale: pulse,
          child: Transform.rotate(
            angle: _iconController.value * 0.3,
            child: child,
          ),
        );
      },
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: AppColors.lightTeal,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: AppColors.teal,
          size: 34,
        ),
      ),
    );
  }

  Widget _buildAnalysisStep(
    int index,
    String text,
  ) {
    final isCompleted = _analysisStep > index;
    final isCurrent = _analysisStep == index;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.lightTeal.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isCompleted
                ? const Icon(
                    Icons.check_circle_rounded,
                    key: ValueKey('done'),
                    color: AppColors.teal,
                    size: 23,
                  )
                : isCurrent
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppColors.teal,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Icon(
                        Icons.radio_button_unchecked_rounded,
                        key: ValueKey('waiting'),
                        color: AppColors.mediumGray,
                        size: 22,
                      ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isCompleted || isCurrent
                    ? AppColors.navy
                    : AppColors.secondaryText,
                fontSize: 14,
                fontWeight: isCurrent
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // RESULTS
  // =========================================================

  Widget _buildResultsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(
          delay: 0,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Career Insights',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'See what stands out in your CV and what to develop next.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _entrance(
          delay: 100,
          child: _buildExpandableResultCard(
            title: 'Strengths',
            icon: Icons.star_outline_rounded,
            items: _strengths,
            isStar: true,
          ),
        ),
        const SizedBox(height: 18),
        _entrance(
          delay: 180,
          child: _buildExpandableResultCard(
            title: 'Skill Gaps',
            icon: Icons.trending_up_rounded,
            items: _skillGaps,
            isStar: false,
          ),
        ),
        const SizedBox(height: 26),
        _entrance(
          delay: 260,
          child: _buildNextStepCard(),
        ),
        const SizedBox(height: 20),
        _entrance(
          delay: 330,
          child: _buildRoadmapButton(),
        ),
      ],
    );
  }

  Widget _buildExpandableResultCard({
    required String title,
    required IconData icon,
    required List<String> items,
    required bool isStar,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: Material(
        color: AppColors.softBackground,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(
            color: AppColors.lightGray,
          ),
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 7,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18,
          ),
          iconColor: AppColors.teal,
          collapsedIconColor: AppColors.secondaryText,
          leading: Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.lightTeal,
              borderRadius: BorderRadius.circular(13),
            ),
            child: AnimatedBuilder(
              animation: _iconController,
              builder: (context, child) {
                final movement = isStar
                    ? math.sin(
                          _iconController.value * 2 * math.pi,
                        ) *
                        2.5
                    : math.cos(
                          _iconController.value * 2 * math.pi,
                        ) *
                        2.5;

                final rotation = isStar
                    ? math.sin(
                          _iconController.value * 2 * math.pi,
                        ) *
                        0.07
                    : 0.0;

                return Transform.translate(
                  offset: Offset(0, movement),
                  child: Transform.rotate(
                    angle: rotation,
                    child: child,
                  ),
                );
              },
              child: Icon(
                icon,
                color: AppColors.teal,
                size: 23,
              ),
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          children: items.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No items found.',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ]
              : List.generate(
                  items.length,
                  (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin:
                                const EdgeInsets.only(top: 7),
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              items[index],
                              style: const TextStyle(
                                color:
                                    AppColors.secondaryNavy,
                                fontSize: 13,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildNextStepCard() {
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
            child: const Icon(
              Icons.account_tree_outlined,
              color: AppColors.teal,
              size: 22,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready for your next step?',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Turn your skill gaps into a personalized learning roadmap built around your career goal.',
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

  // =========================================================
  // BUTTONS
  // =========================================================

  Widget _buildAnalyzeButton() {
    final isDisabled = !_hasCv || _isAnalyzing;

    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDisabled
              ? [
                  AppColors.mediumGray,
                  AppColors.mediumGray,
                ]
              : [
                  AppColors.navy,
                  AppColors.secondaryNavy,
                  AppColors.teal,
                ],
        ),
        boxShadow: isDisabled
            ? []
            : [
                BoxShadow(
                  color:
                      AppColors.teal.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: isDisabled ? null : _analyzeCv,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.white,
          disabledForegroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: const Text(
          'Analyze CV',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildRoadmapButton() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
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
        onPressed: _showRoadmapConfirmation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Generate Learning Roadmap',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_rounded,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ROADMAP CONFIRMATION
  // =========================================================

  void _showRoadmapConfirmation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            24,
            12,
            24,
            28,
          ),
          decoration: const BoxDecoration(
            color: AppColors.softBackground,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(30),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.lightGray,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.lightTeal,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.account_tree_outlined,
                      color: AppColors.teal,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Text(
                      'Create your learning roadmap?',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Masra will use your latest skill gaps and career goal to create a personalized learning roadmap.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(bottomSheetContext);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          side: const BorderSide(
                            color: AppColors.lightGray,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.navy,
                            AppColors.secondaryNavy,
                            AppColors.teal,
                          ],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(bottomSheetContext);

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const LearningRoadmapScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Generate',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorMessage() {
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
              _errorMessage!,
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
}

// =========================================================
// SMALL BADGE INSIDE HERO
// =========================================================

class _CareerGoalBadge extends StatelessWidget {
  const _CareerGoalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.track_changes_rounded,
            color: AppColors.teal,
            size: 14,
          ),
          SizedBox(width: 6),
          Text(
            'Based on your career goal',
            style: TextStyle(
              color: AppColors.teal,
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// PRESSABLE INSIGHT CARD
// =========================================================

class _PressableInsightCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isStar;
  final AnimationController controller;

  const _PressableInsightCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isStar,
    required this.controller,
  });

  @override
  State<_PressableInsightCard> createState() =>
      _PressableInsightCardState();
}

class _PressableInsightCardState
    extends State<_PressableInsightCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
      },
      onTapCancel: () {
        setState(() => _pressed = false);
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.softBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.lightGray,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lightTeal,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, child) {
                    final movement = widget.isStar
                        ? math.sin(
                              widget.controller.value *
                                  2 *
                                  math.pi,
                            ) *
                            2.5
                        : math.cos(
                              widget.controller.value *
                                  2 *
                                  math.pi,
                            ) *
                            2.5;

                    final rotation = widget.isStar
                        ? math.sin(
                              widget.controller.value *
                                  2 *
                                  math.pi,
                            ) *
                            0.08
                        : 0.0;

                    return Transform.translate(
                      offset: Offset(0, movement),
                      child: Transform.rotate(
                        angle: rotation,
                        child: child,
                      ),
                    );
                  },
                  child: Icon(
                    widget.icon,
                    color: AppColors.teal,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.subtitle,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
