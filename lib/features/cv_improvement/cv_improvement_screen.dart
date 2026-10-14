import 'dart:math' as math;
 
import 'package:flutter/material.dart';
 
import '../../services/career_path_service.dart';
import '../../services/claude_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
 
// =========================================================
// CV IMPROVEMENT ASSISTANT
// Reviews the CV saved in the user's profile against five
// ATS-related areas and shows suggestions only.
// The saved CV is never changed. Like the career analysis,
// the latest review is saved and shown again until the user
// replaces the CV in the profile, so Claude is not called again.
// =========================================================
 
class CVImprovementScreen extends StatefulWidget {
  const CVImprovementScreen({super.key});
 
  @override
  State<CVImprovementScreen> createState() => _CVImprovementScreenState();
}
 
class _CVImprovementScreenState extends State<CVImprovementScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final ClaudeService _claudeService = ClaudeService();
  final CareerPathService _careerPathService = CareerPathService();
 
  bool _isLoading = true;
  bool _isReviewing = false;
  bool _showResults = false;
 
  int _reviewStep = 0;
 
  String? _cvText;
  String? _cvFileName;
  String? _careerGoalId;
  String? _errorMessage;
 
  late final AnimationController _iconController;
 
  // areaKey -> list of { issue, suggestion }
  Map<String, List<Map<String, dynamic>>> _results = {};
 
  final List<String> _reviewSteps = [
    'Reading your CV',
    'Checking ATS compatibility',
    'Preparing your suggestions',
  ];
 
  // The five areas from the backlog, in display order
  static const List<_ReviewArea> _areas = [
    _ReviewArea(
      key: 'cvStructure',
      title: 'CV Structure',
      icon: Icons.account_tree_outlined,
    ),
    _ReviewArea(
      key: 'sectionOrganization',
      title: 'Section Organization',
      icon: Icons.view_agenda_outlined,
    ),
    _ReviewArea(
      key: 'keywordUsage',
      title: 'Keyword Usage',
      icon: Icons.key_rounded,
    ),
    _ReviewArea(
      key: 'readability',
      title: 'Readability',
      icon: Icons.chrome_reader_mode_outlined,
    ),
    _ReviewArea(
      key: 'contentFormatting',
      title: 'Content Formatting',
      icon: Icons.format_align_left_rounded,
    ),
  ];
 
  @override
  void initState() {
    super.initState();
 
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
 
    _loadPage();
  }
 
  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }
 
  bool get _hasCv => _cvText != null && _cvText!.trim().isNotEmpty;
 
  // =========================================================
  // LOAD PAGE (CV saved in the profile)
  // =========================================================
 
  Future<void> _loadPage() async {
    try {
      final userData = await _userService.getUser();
      final cvText = await _userService.getCvText();
      final savedReview = await _userService.getValidLatestCvReview();
 
      if (!mounted) return;
 
      final cvData = userData?['cv'];
 
      setState(() {
        _cvText = cvText;
        _careerGoalId = userData?['careerGoalId']?.toString().trim();
 
        if (cvData is Map && cvData['fileName'] != null) {
          _cvFileName = cvData['fileName'].toString();
        }
 
        // Show the saved review if it belongs to the current CV
        if (savedReview != null) {
          _results = savedReview;
          _showResults = true;
        } else {
          _results = {};
          _showResults = false;
        }
 
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('LOAD CV IMPROVEMENT ERROR: $e');
 
      if (!mounted) return;
 
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load your CV. Please try again.';
      });
    }
  }
 
  // =========================================================
  // START REVIEW
  // =========================================================
 
  Future<void> _startReview() async {
    if (_isReviewing) return;
 
    if (!_hasCv) {
      setState(() {
        _errorMessage = 'No CV found. Please upload your CV first.';
      });
      return;
    }
 
    setState(() {
      _isReviewing = true;
      _showResults = false;
      _reviewStep = 0;
      _errorMessage = null;
    });
 
    try {
      // 1) Career goal name (used to judge relevant keywords)
      String careerName = 'Computing and IT';
 
      if (_careerGoalId != null && _careerGoalId!.isNotEmpty) {
        careerName = await _careerPathService.getCareerName(_careerGoalId!);
      }
 
      if (!mounted) return;
      setState(() => _reviewStep = 1);
 
      // 2) ATS review by Claude
      final results = await _claudeService.improveCv(
        cvText: _cvText!,
        careerName: careerName,
      );
 
      if (!mounted) return;
      setState(() => _reviewStep = 2);
 
      // 3) Save the review and link it to the current CV
      await _userService.saveLatestCvReview(results);
 
      if (!mounted) return;
 
      setState(() {
        _results = results;
        _isReviewing = false;
        _showResults = true;
      });
 
      debugPrint('CV IMPROVEMENT SUCCESS');
      for (final area in _areas) {
        debugPrint('${area.title}: ${_results[area.key]?.length ?? 0} issues');
      }
    } catch (e) {
      debugPrint('CV IMPROVEMENT ERROR: $e');
 
      if (!mounted) return;
 
      setState(() {
        _isReviewing = false;
        _showResults = false;
        _errorMessage = 'Could not review your CV. Please try again.';
      });
    }
  }
 
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
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
    if (_isReviewing) {
      return KeyedSubtree(
        key: const ValueKey('reviewing'),
        child: _buildReviewingContent(),
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
        const Expanded(
          child: Text(
            'CV Improvement Assistant',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
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
 
  // =========================================================
  // START CONTENT
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
            'Your review will cover',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _entrance(
          delay: 180,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _areas.map(_buildAreaChip).toList(),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(),
        ],
        const SizedBox(height: 26),
        _entrance(
          delay: 260,
          child: _buildStartButton(),
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
                        'Make your CV ATS-ready',
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
                        'Find out what applicant tracking systems may miss in your CV and get clear suggestions to improve it.',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                      SizedBox(height: 15),
                      _SuggestionsOnlyBadge(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedBuilder(
                  animation: _iconController,
                  builder: (context, child) {
                    final movement =
                        math.sin(_iconController.value * 2 * math.pi) * 5;
                    final rotation =
                        math.sin(_iconController.value * 2 * math.pi) * 0.04;
 
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
                          color: AppColors.teal.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.edit_document,
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
 
  // =========================================================
  // CV CARD (saved CV from the profile)
  // =========================================================
 
  Widget _buildCvCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGray),
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
                  _hasCv ? (_cvFileName ?? 'Uploaded CV') : 'No CV uploaded',
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
                      ? 'Ready for review'
                      : 'Upload your CV in your profile before starting.',
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
 
  Widget _buildAreaChip(_ReviewArea area) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGray),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(area.icon, color: AppColors.teal, size: 18),
          const SizedBox(width: 8),
          Text(
            area.title,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
 
  // =========================================================
  // REVIEWING
  // =========================================================
 
  Widget _buildReviewingContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reviewing your CV',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Masra is checking your CV against common ATS requirements.',
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
              _buildReviewingIcon(),
              const SizedBox(height: 20),
              const Text(
                'Preparing your review',
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
                _reviewSteps.length,
                (index) => _buildReviewStep(index, _reviewSteps[index]),
              ),
            ],
          ),
        ),
      ],
    );
  }
 
  Widget _buildReviewingIcon() {
    return AnimatedBuilder(
      animation: _iconController,
      builder: (context, child) {
        final pulse =
            1 + math.sin(_iconController.value * 2 * math.pi) * 0.04;
 
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
          Icons.edit_document,
          color: AppColors.teal,
          size: 34,
        ),
      ),
    );
  }
 
  Widget _buildReviewStep(int index, String text) {
    final isCompleted = _reviewStep > index;
    final isCurrent = _reviewStep == index;
 
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
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
                'CV Improvement Results',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Review the issues found in each area and the suggested improvements.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 22),
        ...List.generate(_areas.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _entrance(
              delay: 100 + index * 60,
              child: _buildAreaResultCard(_areas[index]),
            ),
          );
        }),
      ],
    );
  }
 
  
 
  Widget _buildAreaResultCard(_ReviewArea area) {
    final issues = _results[area.key] ?? [];
    final hasIssues = issues.isNotEmpty;
 
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        color: AppColors.softBackground,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.lightGray),
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          iconColor: AppColors.teal,
          collapsedIconColor: AppColors.secondaryText,
          leading: Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.lightTeal,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(area.icon, color: AppColors.teal, size: 23),
          ),
          title: Text(
            area.title,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            hasIssues
                ? '${issues.length} ${issues.length == 1 ? 'issue' : 'issues'} found'
                : 'No issues found',
            style: TextStyle(
              color: hasIssues ? AppColors.secondaryText : AppColors.teal,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: hasIssues
              ? List.generate(
                  issues.length,
                  (index) => _buildIssueItem(issues[index]),
                )
              : [_buildNoIssueItem()],
        ),
      ),
    );
  }
 
  Widget _buildIssueItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7),
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
                  item['issue'].toString(),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 18),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.lightTeal.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.teal,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item['suggestion'].toString(),
                    style: const TextStyle(
                      color: AppColors.secondaryNavy,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
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
 
  Widget _buildNoIssueItem() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.teal,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No improvement currently required.',
              style: TextStyle(
                color: AppColors.secondaryNavy,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  // =========================================================
  // BUTTONS
  // =========================================================
 
  Widget _buildStartButton() {
    final isDisabled = !_hasCv || _isReviewing;
 
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDisabled
              ? [AppColors.mediumGray, AppColors.mediumGray]
              : [AppColors.navy, AppColors.secondaryNavy, AppColors.teal],
        ),
        boxShadow: isDisabled
            ? []
            : [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: isDisabled ? null : _startReview,
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
          'Start Review',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
// REVIEW AREA (one of the five ATS-related areas)
// =========================================================
 
class _ReviewArea {
  final String key;
  final String title;
  final IconData icon;
 
  const _ReviewArea({
    required this.key,
    required this.title,
    required this.icon,
  });
}
 
// =========================================================
// SMALL BADGE INSIDE HERO
// =========================================================
 
class _SuggestionsOnlyBadge extends StatelessWidget {
  const _SuggestionsOnlyBadge();
 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            color: AppColors.teal,
            size: 14,
          ),
          SizedBox(width: 6),
          Text(
            'Your CV stays unchanged',
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
 