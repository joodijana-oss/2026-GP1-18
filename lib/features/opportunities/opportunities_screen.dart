import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/profile_options.dart';
import '../../models/opportunity.dart';
import '../../services/opportunity_recommender.dart';
import '../../services/opportunity_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../career_analysis/career_analysis_screen.dart';
import 'opportunity_details_screen.dart';
import 'opportunity_labels.dart';

/// Opportunity Radar: training programs, bootcamps, hackathons, meetups,
/// webinars and courses that match the user's career goal and skill gaps.
///
/// Flow:
///  - no valid AI Career Analysis -> ask the user to complete it first
///  - analysis found              -> every matching open opportunity, with
///                                   type and source filters
///  - nothing open right now      -> friendly "check back soon" message
///
/// Matching runs on the phone, so changing a filter updates the list
/// instantly. The chosen filters are remembered on this device.
class OpportunitiesScreen extends StatefulWidget {
  const OpportunitiesScreen({super.key});

  @override
  State<OpportunitiesScreen> createState() => _OpportunitiesScreenState();
}

enum _ScreenState { loading, noAnalysis, error, empty, ready }

class _OpportunitiesScreenState extends State<OpportunitiesScreen>
    with SingleTickerProviderStateMixin {
  static const String _typeKey = 'opportunity_filter_type';
  static const String _sourceKey = 'opportunity_filter_source';

  final UserService _userService = UserService();
  final OpportunityService _opportunityService = OpportunityService();
  final OpportunityRecommender _recommender = const OpportunityRecommender();

  late final AnimationController _iconController;

  _ScreenState _state = _ScreenState.loading;
  OpportunityRecommendations? _recs;
  List<OpportunityMatch> _shown = const [];
  String _careerName = '';
  DateTime _now = DateTime.now();

  /// Selected filters (null means "All").
  String? _type;
  String? _source;
  bool _filtersLoaded = false;

  /// Ignores the result of an older load when a newer one started.
  int _loadId = 0;

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
  // FILTERS (remembered on this device)
  // ---------------------------------------------------------
  Future<void> _loadSavedFilters() async {
    if (_filtersLoaded) return;
    _filtersLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _type = _clean(prefs.getString(_typeKey));
      _source = _clean(prefs.getString(_sourceKey));
    } catch (_) {
      // Keep "All"
    }
  }

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Future<void> _saveFilters() async {
    final type = _type;
    final source = _source;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (type == null) {
        await prefs.remove(_typeKey);
      } else {
        await prefs.setString(_typeKey, type);
      }
      if (source == null) {
        await prefs.remove(_sourceKey);
      } else {
        await prefs.setString(_sourceKey, source);
      }
    } catch (_) {
      // Only a convenience: the filter still works for this visit
    }
  }

  void _applyFilters() {
    _shown = _recs?.filter(type: _type, source: _source) ?? const [];
  }

  void _chooseType(String? type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _applyFilters();
    });
    _saveFilters();
  }

  void _chooseSource(String? source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      _applyFilters();
    });
    _saveFilters();
  }

  void _clearFilters() {
    setState(() {
      _type = null;
      _source = null;
      _applyFilters();
    });
    _saveFilters();
  }

  // ---------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------
  /// Loads the analysis and the opportunities, then matches them.
  /// [quiet] keeps the current list on screen (pull to refresh).
  Future<void> _load({bool forceRefresh = false, bool quiet = false}) async {
    final loadId = ++_loadId;
    if (!quiet && mounted) setState(() => _state = _ScreenState.loading);
    try {
      await _loadSavedFilters();
      // Only an analysis that belongs to the current CV (and career goal)
      // counts.
      final analysis = await _userService.getValidLatestAnalysis();
      if (!mounted || loadId != _loadId) return;
      if (analysis == null) {
        setState(() {
          _recs = null;
          _shown = const [];
          _state = _ScreenState.noAnalysis;
        });
        return;
      }

      final opportunities =
          await _opportunityService.getAll(forceRefresh: forceRefresh);
      final now = DateTime.now();
      final recs = _recommender.recommend(
        analysis: analysis,
        opportunities: opportunities,
        now: now,
      );
      if (!mounted || loadId != _loadId) return;

      setState(() {
        _careerName = _careerNameOf(analysis);
        _recs = recs;
        _now = now;
        // A saved filter that is not available now is ignored.
        if (_type != null && !recs.types.contains(_type)) _type = null;
        if (_source != null && !recs.sources.contains(_source)) {
          _source = null;
        }
        _applyFilters();
        _state = recs.isEmpty ? _ScreenState.empty : _ScreenState.ready;
      });
    } catch (e) {
      debugPrint('OpportunitiesScreen: $e');
      if (!mounted || loadId != _loadId) return;
      // Keep the current list when only the refresh failed.
      final hasList =
          _state == _ScreenState.ready || _state == _ScreenState.empty;
      if (quiet && hasList) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not refresh opportunities. Check your connection.',
            ),
          ),
        );
        return;
      }
      setState(() => _state = _ScreenState.error);
    }
  }

  Future<void> _refresh() => _load(forceRefresh: true, quiet: true);

  /// Same as the certifications screen: the saved name, or the name of the
  /// career goal id.
  String _careerNameOf(Map<String, dynamic> analysis) {
    final savedName = analysis['careerGoalName']?.toString().trim();
    if (savedName != null && savedName.isNotEmpty) return savedName;
    final goalId = analysis['careerGoalId']?.toString() ?? '';
    return ProfileOptions.careerGoals[goalId] ?? '';
  }

  Future<void> _openCareerAnalysis() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CareerAnalysisScreen()),
    );
    if (!mounted) return;
    _load();
  }

  void _openDetails(OpportunityMatch match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpportunityDetailsScreen(
          match: match,
          careerGoalName: _careerName,
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
            : RefreshIndicator(
                color: AppColors.teal,
                backgroundColor: AppColors.softBackground,
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    _padded(
                      _buildHeader(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    ),
                    ..._buildContent(),
                    const SliverToBoxAdapter(child: SizedBox(height: 30)),
                  ],
                ),
              ),
      ),
    );
  }

  /// A normal widget as a sliver, with the page side padding.
  Widget _padded(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 20),
  }) {
    return SliverToBoxAdapter(
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _gap(double height) =>
      SliverToBoxAdapter(child: SizedBox(height: height));

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
            'Opportunity Radar',
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

  List<Widget> _buildContent() {
    switch (_state) {
      case _ScreenState.noAnalysis:
        return [_padded(_buildNoAnalysis())];
      case _ScreenState.error:
        return [_padded(_buildError())];
      case _ScreenState.empty:
        return [_padded(_buildEmpty())];
      case _ScreenState.ready:
        return _buildReady();
      case _ScreenState.loading:
        return const [];
    }
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
                'Opportunity recommendations are built from your skill gaps and your career goal, so Masra needs your AI Career Analysis results first.',
            badge: 'Based on your career goal',
            icon: Icons.insights_rounded,
          ),
        ),
        const SizedBox(height: 22),
        _entrance(
          delay: 80,
          child: _buildInfoCard(
            icon: Icons.analytics_rounded,
            title: 'AI Career Analysis required',
            subtitle:
                'Analyze your CV to unlock training programs, bootcamps and hackathons that match you.',
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
            'We could not load your opportunities. Check your connection and try again.',
          ),
        ),
        const SizedBox(height: 20),
        _entrance(
          delay: 60,
          child: _buildPrimaryButton(
            label: 'Try Again',
            onPressed: _load,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // STATE: EMPTY (nothing open right now)
  // ---------------------------------------------------------
  Widget _buildEmpty() {
    final recs = _recs!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _entrance(delay: 0, child: _buildSummaryCard(recs)),
        const SizedBox(height: 22),
        _entrance(
          delay: 80,
          child: _buildInfoCard(
            icon: Icons.event_busy_rounded,
            title: 'No open opportunities right now',
            subtitle:
                'Nothing matches your career goal and skill gaps at the moment. New programs, bootcamps and hackathons are added often, so pull down to refresh or check back soon.',
          ),
        ),
        const SizedBox(height: 26),
        _entrance(
          delay: 140,
          child: _buildPrimaryButton(
            label: 'Refresh',
            onPressed: () => _load(forceRefresh: true),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  // STATE: READY
  // ---------------------------------------------------------
  List<Widget> _buildReady() {
    final recs = _recs!;
    final shown = _shown;

    return [
      _padded(
        _entrance(
          delay: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Opportunity Matches',
                style: TextStyle(
                  color: AppColors.navyText,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Training programs, bootcamps, hackathons and more that match your career goal and skill gaps.',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      _gap(22),
      _padded(_entrance(delay: 60, child: _buildSummaryCard(recs))),
      _gap(24),
      SliverToBoxAdapter(
        child: _entrance(delay: 100, child: _buildFilters(recs)),
      ),
      _gap(16),
      _padded(_buildShowingRow(shown.length, recs.matched.length)),
      _gap(14),
      if (shown.isEmpty)
        _padded(
          _buildInfoCard(
            icon: Icons.filter_alt_off_rounded,
            title: 'Nothing matches these filters',
            subtitle: 'Try another type or source, or clear the filters.',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          // Built lazily: only the cards on screen are created.
          sliver: SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) =>
                _buildCard(shown[index], animate: index < 4),
          ),
        ),
      _gap(8),
      _padded(
        _entrance(
          delay: 120,
          child: _buildNextCard(
            title: 'Always up to date',
            text:
                'New opportunities are added often. Pull down to refresh, or run a new analysis after you change your CV or career goal.',
          ),
        ),
      ),
    ];
  }

  Widget _buildSummaryCard(OpportunityRecommendations recs) {
    final count = recs.matched.length;
    final gaps = recs.skillGaps.length;

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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _stat(
                    '$count',
                    count == 1
                        ? 'matching opportunity'
                        : 'matching opportunities',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _stat(
                    '$gaps',
                    gaps == 1
                        ? 'skill gap considered'
                        : 'skill gaps considered',
                  ),
                ),
              ],
            ),
          ),
          if (recs.closedHidden > 0) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.secondaryText,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recs.closedHidden == 1
                        ? '1 opportunity with closed registration is hidden.'
                        : '${recs.closedHidden} opportunities with closed registration are hidden.',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.lightTeal.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppColors.tealText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppColors.secondaryNavyText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // FILTER CHIPS
  // ---------------------------------------------------------
  Widget _buildFilters(OpportunityRecommendations recs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _choiceLabel('Type'),
        ),
        const SizedBox(height: 10),
        _chipRow([
          _filterChip(
            label: 'All',
            icon: Icons.apps_rounded,
            selected: _type == null,
            onTap: () => _chooseType(null),
          ),
          for (final type in recs.types)
            _filterChip(
              label: type,
              icon: OpportunityLabels.typeIcon(type),
              selected: _type == type,
              onTap: () => _chooseType(type),
            ),
        ]),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _choiceLabel('Source'),
        ),
        const SizedBox(height: 10),
        _chipRow([
          _filterChip(
            label: 'All sources',
            selected: _source == null,
            onTap: () => _chooseSource(null),
          ),
          for (final source in recs.sources)
            _filterChip(
              label: source,
              selected: _source == source,
              onTap: () => _chooseSource(source),
            ),
        ]),
      ],
    );
  }

  /// A horizontal row of chips that scrolls when it is too wide.
  Widget _chipRow(List<Widget> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
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

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : AppColors.softBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.lightGray,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: selected ? AppColors.onBrand : AppColors.tealText,
                  size: 16,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.onBrand : AppColors.navyText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShowingRow(int shown, int total) {
    final filtered = _type != null || _source != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Showing $shown of $total',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (filtered)
          GestureDetector(
            onTap: _clearFilters,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Clear filters',
                style: TextStyle(
                  color: AppColors.tealText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------
  // OPPORTUNITY CARD
  // ---------------------------------------------------------
  Widget _buildCard(OpportunityMatch match, {bool animate = false}) {
    final o = match.opportunity;
    final cost = OpportunityLabels.cost(o);

    final card = _PressableCard(
      onTap: () => _openDetails(match),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(radius: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _typeBadge(o.type),
                if (o.sourceLabel.isNotEmpty) _sourceTag(o.sourceLabel),
                if (cost != null) _costPill(cost, free: o.isFree == true),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    o.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.navyText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.secondaryText,
                  size: 24,
                ),
              ],
            ),
            if (o.providerLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                o.providerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildDateLine(o),
            if (o.location.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _iconLine(Icons.place_outlined, o.location.trim()),
            ],
            const SizedBox(height: 14),
            _buildWhyBox(match),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: animate ? _entrance(delay: 0, child: card) : card,
    );
  }

  /// The one date line of a card.
  ({String text, IconData icon, bool urgent}) _dateInfo(Opportunity o) {
    final deadline = o.registrationDeadline;
    if (deadline != null) {
      final days = o.daysLeft(_now);
      final date = OpportunityLabels.date(deadline);
      if (days == 0) {
        return (
          text: 'Last day to register · $date',
          icon: Icons.alarm_rounded,
          urgent: true,
        );
      }
      return (
        text: days == null
            ? 'Register by $date'
            : 'Register by $date · ${OpportunityLabels.daysLeft(days)}',
        icon: Icons.event_available_rounded,
        urgent: OpportunityLabels.isUrgent(days),
      );
    }

    // Without a deadline, an open event has not started yet.
    final start = o.startDate;
    if (start != null) {
      return (
        text: 'Starts ${OpportunityLabels.date(start)}',
        icon: Icons.event_rounded,
        urgent: false,
      );
    }
    final end = o.endDate;
    if (end != null) {
      return (
        text: 'Ends ${OpportunityLabels.date(end)}',
        icon: Icons.event_rounded,
        urgent: false,
      );
    }

    final duration = o.duration.trim();
    return (
      text: duration.isEmpty
          ? 'Always available · self-paced'
          : 'Always available · self-paced · $duration',
      icon: Icons.all_inclusive_rounded,
      urgent: false,
    );
  }

  Widget _buildDateLine(Opportunity o) {
    final info = _dateInfo(o);
    final color = info.urgent
        ? OpportunityLabels.urgentText
        : AppColors.secondaryNavyText;

    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            info.icon,
            color: info.urgent ? color : AppColors.tealText,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            info.text,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: info.urgent ? FontWeight.w800 : FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );

    if (!info.urgent) return line;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: line,
    );
  }

  Widget _iconLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, color: AppColors.tealText, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhyBox(OpportunityMatch match) {
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

    Widget reason(String label, List<String> items) {
      final list = OpportunityLabels.shortList(items);
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: label),
            TextSpan(text: list.shown, style: boldStyle),
            if (list.more > 0) TextSpan(text: ' +${list.more} more'),
          ],
        ),
      );
    }

    final lines = <Widget>[
      if (match.gapSkills.isNotEmpty)
        reason('Covers your skill gaps: ', match.gapSkills),
      if (match.goalRelated)
        _careerName.isEmpty
            ? Text('Related to your career goal.', style: baseStyle)
            : Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: [
                    const TextSpan(text: 'Related to your career goal: '),
                    TextSpan(text: _careerName, style: boldStyle),
                  ],
                ),
              ),
      if (match.currentSkills.isNotEmpty)
        reason('Builds on: ', match.currentSkills),
    ];
    if (lines.isEmpty) {
      lines.add(Text('Matches your career goal.', style: baseStyle));
    }

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
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  lines[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.lightTeal,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            OpportunityLabels.typeIcon(type),
            color: AppColors.tealText,
            size: 14,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  Widget _sourceTag(String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightGray),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.public_rounded,
            color: AppColors.secondaryText,
            size: 13,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _costPill(String text, {required bool free}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: free
            ? AppColors.gold.withValues(alpha: 0.22)
            : AppColors.softBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: free ? Colors.transparent : AppColors.lightGray,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.navyText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // SMALL PIECES (same look as the certifications screen)
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
                            Flexible(
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: AppColors.tealText,
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w700,
                                ),
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
