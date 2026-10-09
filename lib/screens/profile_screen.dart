import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:file_picker/file_picker.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';



import '../constants/profile_options.dart';

import '../features/community/community_screen.dart';

import '../services/cv_service.dart';

import '../services/user_service.dart';

import '../theme/app_colors.dart';

import 'explore_screen.dart';

import 'home_screen.dart';

import 'onboarding_screen.dart';




// ============================================================

// PROFILE SCREEN

// Shows only what the backlog (View Profile) asks for:

// Basic Information, Academic Information, Career Profile,

// Skills, Certifications, Projects, Experience (from the latest

// AI Career Analysis), CV (with Replace CV), and Log Out.

// Each editable field has a pencil icon to edit that one field.

// Data is loaded from Firestore every time the page opens.

// ============================================================



class ProfileScreen extends StatefulWidget {

  const ProfileScreen({super.key});



  @override

  State<ProfileScreen> createState() => _ProfileScreenState();

}



class _ProfileScreenState extends State<ProfileScreen> {

  static const Color _logoutRed = Color(0xFFD64545);

  static const String _emptyMessage = 'No information added yet.';



  final UserService _userService = UserService();



  bool _isLoading = true;

  bool _hasError = false;

  bool _isReplacingCv = false;



  // users/{uid}

  Map<String, dynamic> _user = {};



  // users/{uid}/analysis/latest (null = no analysis yet)

  Map<String, dynamic>? _analysis;



  @override

  void initState() {

    super.initState();

    _loadProfile();

  }



  // ============================================================

  // LOAD DATA

  // ============================================================



  // silent = reload in place (after editing a field) without the
  // full-page loader, so the page keeps its scroll position.
  Future<void> _loadProfile({bool silent = false}) async {

    if (!silent) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }



    try {

      final user = await _userService.getUser();

      final analysis = await _userService.getLatestAnalysis();



      if (!mounted) return;



      setState(() {

        _user = user ?? {};

        _analysis = analysis;

        _isLoading = false;

      });

    } catch (e) {

      debugPrint('PROFILE LOAD ERROR: $e');



      if (!mounted) return;

      // Keep showing the current data if a silent reload fails
      if (silent) return;



      setState(() {

        _isLoading = false;

        _hasError = true;

      });

    }

  }



  // ============================================================

  // DATA HELPERS

  // ============================================================



  String _text(String key) {

    final value = _user[key];

    if (value == null) return '-';

    final text = value.toString().trim();

    return text.isEmpty ? '-' : text;

  }



  String get _fullName => _text('fullName');



  String get _careerGoalLabel {

    final id = _user['careerGoalId'];

    if (id == null) return '-';

    return ProfileOptions.careerGoals[id] ?? id.toString();

  }



  String get _initial {

    final name = _user['fullName']?.toString().trim() ?? '';

    return name.isEmpty ? '?' : name[0].toUpperCase();

  }



  List<String> _analysisStrings(String key) {

    final value = _analysis?[key];

    if (value is! List) return [];

    return value

        .map((item) => item.toString().trim())

        .where((item) => item.isNotEmpty)

        .toList();

  }



  List<Map<String, dynamic>> _analysisMaps(String key) {
    final value = _analysis?[key];

    if (value is! List) return [];

    final result = <Map<String, dynamic>>[];

    for (final item in value) {
      // New structured format saved by the latest Career Analysis.
      if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
        continue;
      }

      // Backward compatibility for older analyses that were saved as
      // strings such as: {title: ..., description: ...}
      final text = item.toString().trim();

      if (text.startsWith('{') && text.endsWith('}')) {
        final parsed = _parseLegacyAnalysisMap(text);
        if (parsed.isNotEmpty) {
          result.add(parsed);
          continue;
        }
      }

      // Final fallback for a plain text item.
      if (text.isNotEmpty) {
        result.add({'name': text});
      }
    }

    return result;
  }

  Map<String, dynamic> _parseLegacyAnalysisMap(String value) {
    String clean = value.trim();

    if (clean.startsWith('{')) {
      clean = clean.substring(1);
    }

    if (clean.endsWith('}')) {
      clean = clean.substring(0, clean.length - 1);
    }

    final keyPattern = RegExp(
      r'(?:^|,\s*)([A-Za-z][A-Za-z0-9_]*)\s*:',
    );

    final matches = keyPattern.allMatches(clean).toList();
    if (matches.isEmpty) return {};

    final result = <String, dynamic>{};

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final key = match.group(1)?.trim();

      if (key == null || key.isEmpty) continue;

      final valueStart = match.end;
      final valueEnd =
          i + 1 < matches.length ? matches[i + 1].start : clean.length;

      String itemValue = clean.substring(valueStart, valueEnd).trim();

      if (itemValue.startsWith(',')) {
        itemValue = itemValue.substring(1).trim();
      }

      result[key] = itemValue;
    }

    return result;
  }

  String _joinParts(List<dynamic> parts) {

    return parts

        .where((part) => part != null && part.toString().trim().isNotEmpty)

        .map((part) => part.toString().trim())

        .join(' • ');

  }



  String _formatDate(dynamic value) {

    if (value is! Timestamp) return '';

    final date = value.toDate();

    const months = [

      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',

      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',

    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';

  }



  // ============================================================

  // BUILD

  // ============================================================



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: AppColors.background,

      bottomNavigationBar: _buildBottomNavigation(),

      body: SafeArea(

        bottom: false,

        child: _buildBody(),

      ),

    );

  }



  Widget _buildBody() {

    if (_isLoading) {

      return const Center(

        child: CircularProgressIndicator(color: AppColors.teal),

      );

    }



    if (_hasError) {

      return Center(

        child: Padding(

          padding: const EdgeInsets.all(30),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              const Text(

                'Could not load your profile. Please try again.',

                textAlign: TextAlign.center,

                style: TextStyle(

                  color: AppColors.navy,

                  fontSize: 14,

                  fontWeight: FontWeight.w600,

                ),

              ),

              const SizedBox(height: 16),

              TextButton(

                onPressed: _loadProfile,

                child: const Text(

                  'Try Again',

                  style: TextStyle(

                    color: AppColors.teal,

                    fontWeight: FontWeight.w700,

                  ),

                ),

              ),

            ],

          ),

        ),

      );

    }



    return RefreshIndicator(

      color: AppColors.teal,

      onRefresh: _loadProfile,

      child: SingleChildScrollView(

        physics: const AlwaysScrollableScrollPhysics(

          parent: BouncingScrollPhysics(),

        ),

        padding: const EdgeInsets.only(bottom: 35),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            _buildProfileHero(),

            const SizedBox(height: 28),

            _padded(_buildBasicInformation()),

            const SizedBox(height: 24),

            _padded(_buildAcademicInformation()),

            const SizedBox(height: 24),

            _padded(_buildCareerProfile()),

            const SizedBox(height: 24),

            _padded(_buildSkills()),

            const SizedBox(height: 24),

            _padded(_buildCertifications()),

            const SizedBox(height: 24),

            _padded(_buildProjects()),

            const SizedBox(height: 24),

            _padded(_buildExperience()),

            const SizedBox(height: 24),

            _padded(_buildCVCard()),

            const SizedBox(height: 28),

            _padded(

              _profileAction(

                icon: Icons.logout_rounded,

                title: 'Log Out',

                accent: _logoutRed,

                onTap: _confirmLogout,

              ),

            ),

          ],

        ),

      ),

    );

  }



  Widget _padded(Widget child) {

    return Padding(

      padding: const EdgeInsets.symmetric(horizontal: 20),

      child: child,

    );

  }



  // ============================================================

  // HERO

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

          Positioned(

            right: -65,

            top: -80,

            child: Container(

              width: 210,

              height: 210,

              decoration: BoxDecoration(

                shape: BoxShape.circle,

                color: AppColors.lightTeal.withValues(alpha: 0.08),

              ),

            ),

          ),

          Positioned(

            left: -85,

            bottom: -80,

            child: Container(

              width: 190,

              height: 190,

              decoration: BoxDecoration(

                shape: BoxShape.circle,

                border: Border.all(

                  color: AppColors.gold.withValues(alpha: 0.09),

                  width: 25,

                ),

              ),

            ),

          ),

          Padding(

            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),

            child: Column(

              children: [

                // TOP BAR

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

                    Container(

                      width: 62,

                      height: 42,

                      padding: const EdgeInsets.symmetric(horizontal: 7),

                      decoration: BoxDecoration(

                        color: AppColors.white.withValues(alpha: 0.10),

                        borderRadius: BorderRadius.circular(14),

                        border: Border.all(

                          color: AppColors.white.withValues(alpha: 0.12),

                        ),

                      ),

                      child: Image.asset(

                        'lib/assets/images/Logoo.png',

                        fit: BoxFit.contain,

                        errorBuilder: (context, error, stackTrace) {

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

                  ],

                ),

                const SizedBox(height: 27),



                // AVATAR + NAME + MAJOR + GOAL

                Row(

                  crossAxisAlignment: CrossAxisAlignment.center,

                  children: [

                    Container(

                      width: 78,

                      height: 78,

                      decoration: BoxDecoration(

                        gradient: const LinearGradient(

                          begin: Alignment.topLeft,

                          end: Alignment.bottomRight,

                          colors: [AppColors.teal, AppColors.lightTeal],

                        ),

                        borderRadius: BorderRadius.circular(25),

                        border: Border.all(

                          color: AppColors.white.withValues(alpha: 0.18),

                          width: 1.5,

                        ),

                      ),

                      alignment: Alignment.center,

                      child: Text(

                        _initial,

                        style: const TextStyle(

                          color: AppColors.white,

                          fontSize: 35,

                          fontWeight: FontWeight.w800,

                        ),

                      ),

                    ),

                    const SizedBox(width: 17),

                    Expanded(

                      child: Column(

                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [

                          Text(

                            _fullName,

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

                            _text('major'),

                            maxLines: 1,

                            overflow: TextOverflow.ellipsis,

                            style: TextStyle(

                              color: AppColors.white.withValues(alpha: 0.70),

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

                              color: AppColors.gold.withValues(alpha: 0.15),

                              borderRadius: BorderRadius.circular(20),

                              border: Border.all(

                                color: AppColors.gold.withValues(alpha: 0.18),

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

                                Flexible(

                                  child: Text(

                                    _careerGoalLabel,

                                    overflow: TextOverflow.ellipsis,

                                    style: const TextStyle(

                                      color: AppColors.gold,

                                      fontSize: 11.5,

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

                  ],

                ),

              ],

            ),

          ),

        ],

      ),

    );

  }



  // ============================================================

  // BASIC INFORMATION

  // ============================================================



  Widget _buildBasicInformation() {

    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Basic Information',

            subtitle: 'Your account details.',

            icon: Icons.person_outline_rounded,

            accent: AppColors.navy,

          ),

          const SizedBox(height: 18),

          _infoRow(Icons.badge_outlined, 'Full Name', _fullName,
              onEdit: _editFullName),

          // Read-only: changing the email needs Firebase Auth re-verification
          _infoRow(Icons.email_outlined, 'Email Address', _text('email')),

        ],

      ),

    );

  }



  // ============================================================

  // ACADEMIC INFORMATION

  // ============================================================



  Widget _buildAcademicInformation() {

    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Academic Information',

            subtitle: 'Your study background.',

            icon: Icons.school_outlined,

            accent: AppColors.teal,

          ),

          const SizedBox(height: 18),

          _infoRow(Icons.account_balance_outlined, 'University',

              _text('university'),
              onEdit: () => _editDropdownField(
                    fieldKey: 'university',
                    label: 'University',
                    hint: 'Select your university',
                    icon: Icons.account_balance_outlined,
                    options: {
                      for (final u in ProfileOptions.universities) u: u,
                    },
                  )),

          _infoRow(Icons.workspace_premium_outlined, 'Degree',

              _text('degree'),
              onEdit: () => _editDropdownField(
                    fieldKey: 'degree',
                    label: 'Degree',
                    hint: 'Select your degree',
                    icon: Icons.school_outlined,
                    options: {for (final d in ProfileOptions.degrees) d: d},
                  )),

          _infoRow(Icons.menu_book_outlined, 'Major', _text('major'),
              onEdit: () => _editDropdownField(
                    fieldKey: 'major',
                    label: 'Major',
                    hint: 'Select your major',
                    icon: Icons.menu_book_outlined,
                    options: {for (final m in ProfileOptions.majors) m: m},
                  )),

          _infoRow(Icons.flag_outlined, 'Graduation Status',

              _text('graduationStatus'),
              onEdit: _editGraduationStatus),

          _infoRow(Icons.calendar_today_outlined, 'Graduation Date',

              _graduationDateLabel,
              onEdit: _editGraduationDate),

        ],

      ),

    );

  }



  // ============================================================

  // CAREER PROFILE

  // ============================================================



  Widget _buildCareerProfile() {

    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Career Profile',

            subtitle: 'Where you are heading.',

            icon: Icons.route_rounded,

            accent: AppColors.gold,

          ),

          const SizedBox(height: 18),

          _infoRow(Icons.auto_awesome_rounded, 'Career Goal',

              _careerGoalLabel,
              onEdit: () => _editDropdownField(
                    fieldKey: 'careerGoalId',
                    label: 'Career Goal',
                    hint: 'Select your career goal',
                    icon: Icons.flag_outlined,
                    options: ProfileOptions.careerGoals,
                  )),

          _infoRow(Icons.trending_up_rounded, 'Current Experience Level',

              _text('experienceLevel'),
              onEdit: () => _editDropdownField(
                    fieldKey: 'experienceLevel',
                    label: 'Current Experience Level',
                    hint: 'Select your experience level',
                    icon: Icons.trending_up_rounded,
                    options: {
                      for (final l in ProfileOptions.experienceLevels) l: l,
                    },
                  )),

        ],

      ),

    );

  }



  // onEdit != null -> shows a pencil to edit only this field
  Widget _infoRow(IconData icon, String label, String value,
      {VoidCallback? onEdit}) {

    return Padding(

      padding: const EdgeInsets.only(bottom: 12),

      child: Container(

        padding: const EdgeInsets.all(13),

        decoration: BoxDecoration(

          color: AppColors.background,

          borderRadius: BorderRadius.circular(18),

          border: Border.all(color: AppColors.lightGray),

        ),

        child: Row(

          children: [

            Container(

              width: 35,

              height: 35,

              decoration: BoxDecoration(

                color: AppColors.teal.withValues(alpha: 0.10),

                borderRadius: BorderRadius.circular(11),

              ),

              child: Icon(icon, color: AppColors.teal, size: 19),

            ),

            const SizedBox(width: 12),

            Expanded(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

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

                    style: const TextStyle(

                      color: AppColors.navy,

                      fontSize: 13,

                      fontWeight: FontWeight.w700,

                      height: 1.25,

                    ),

                  ),

                ],

              ),

            ),

            if (onEdit != null)
              IconButton(
                onPressed: onEdit,
                tooltip: 'Edit $label',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.teal,
                  size: 18,
                ),
              ),

          ],

        ),

      ),

    );

  }



  // ============================================================

  // SKILLS (latest analysis -> currentSkills)

  // ============================================================



  Widget _buildSkills() {

    final skills = _analysisStrings('currentSkills');



    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Skills',

            subtitle: 'From your latest AI Career Analysis.',

            icon: Icons.auto_graph_rounded,

            accent: AppColors.teal,

          ),

          const SizedBox(height: 18),

          if (skills.isEmpty)

            _emptyState()

          else

            Wrap(

              spacing: 8,

              runSpacing: 8,

              children: skills.map(_skillChip).toList(),

            ),

        ],

      ),

    );

  }



  Widget _skillChip(String skill) {

    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

      decoration: BoxDecoration(

        color: AppColors.teal.withValues(alpha: 0.08),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: AppColors.teal.withValues(alpha: 0.15)),

      ),

      child: Text(

        skill,

        style: const TextStyle(

          color: AppColors.navy,

          fontSize: 12.5,

          fontWeight: FontWeight.w700,

        ),

      ),

    );

  }



  // ============================================================

  // CERTIFICATIONS (latest analysis -> certifications)

  // ============================================================



  Widget _buildCertifications() {

    final items = _analysisMaps('certifications');



    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Certifications',

            subtitle: 'From your latest AI Career Analysis.',

            icon: Icons.workspace_premium_outlined,

            accent: AppColors.gold,

          ),

          const SizedBox(height: 18),

          if (items.isEmpty)

            _emptyState()

          else

            ..._listItems(

              items: items,

              icon: Icons.workspace_premium_rounded,

              accent: AppColors.gold,

              title: (item) =>
                  item['name']?.toString() ??
                  item['title']?.toString() ??
                  '-',
              subtitle: (item) => _joinParts([
                item['issuer'] ?? item['provider'],
                item['year'],
              ]),

            ),

        ],

      ),

    );

  }



  // ============================================================

  // PROJECTS (latest analysis -> projects)

  // ============================================================



  Widget _buildProjects() {

    final items = _analysisMaps('projects');



    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Projects',

            subtitle: 'From your latest AI Career Analysis.',

            icon: Icons.code_rounded,

            accent: AppColors.teal,

          ),

          const SizedBox(height: 18),

          if (items.isEmpty)

            _emptyState()

          else

            ..._listItems(

              items: items,

              icon: Icons.folder_open_rounded,

              accent: AppColors.teal,

              title: (item) =>
                  item['name']?.toString() ??
                  item['title']?.toString() ??
                  '-',
              subtitle: (item) => item['description']?.toString() ?? '', 

            ),

        ],

      ),

    );

  }



  // ============================================================

  // EXPERIENCE (latest analysis -> experience)

  // ============================================================



  Widget _buildExperience() {

    final items = _analysisMaps('experience');



    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'Experience',

            subtitle: 'From your latest AI Career Analysis.',

            icon: Icons.work_outline_rounded,

            accent: AppColors.teal,

          ),

          const SizedBox(height: 18),

          if (items.isEmpty)

            _emptyState()

          else

            ..._listItems(

              items: items,

              icon: Icons.business_center_outlined,

              accent: AppColors.teal,

              title: (item) =>
                  item['title']?.toString() ??
                  item['name']?.toString() ??
                  '-',
              subtitle: (item) => _joinParts([
                item['organization'] ?? item['company'],
                item['duration'],
              ]),

            ),

        ],

      ),

    );

  }



  List<Widget> _listItems({

    required List<Map<String, dynamic>> items,

    required IconData icon,

    required Color accent,

    required String Function(Map<String, dynamic>) title,

    required String Function(Map<String, dynamic>) subtitle,

  }) {

    return List.generate(items.length, (index) {

      final item = items[index];

      final itemSubtitle = subtitle(item);



      return Padding(

        padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 12),

        child: Container(

          padding: const EdgeInsets.all(14),

          decoration: BoxDecoration(

            color: AppColors.background,

            borderRadius: BorderRadius.circular(19),

            border: Border.all(color: AppColors.lightGray),

          ),

          child: Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Container(

                width: 46,

                height: 46,

                decoration: BoxDecoration(

                  color: accent.withValues(alpha: 0.10),

                  borderRadius: BorderRadius.circular(15),

                ),

                child: Icon(icon, color: accent, size: 23),

              ),

              const SizedBox(width: 13),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      title(item),

                      style: const TextStyle(

                        color: AppColors.navy,

                        fontSize: 14,

                        fontWeight: FontWeight.w800,

                      ),

                    ),

                    if (itemSubtitle.isNotEmpty) ...[

                      const SizedBox(height: 4),

                      Text(

                        itemSubtitle,

                        style: const TextStyle(

                          color: AppColors.secondaryText,

                          fontSize: 11.5,

                          height: 1.35,

                        ),

                      ),

                    ],

                  ],

                ),

              ),

            ],

          ),

        ),

      );

    });

  }



  // ============================================================

  // CV (users/{uid}.cv)

  // ============================================================



  Widget _buildCVCard() {

    final cv = _user['cv'];

    final fileName = cv is Map ? cv['fileName']?.toString() : null;

    final uploadedAt = cv is Map ? _formatDate(cv['uploadedAt']) : '';



    return _profileCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          _sectionHeader(

            title: 'CV',

            subtitle: 'The CV saved in your profile.',

            icon: Icons.description_outlined,

            accent: AppColors.navy,

          ),

          const SizedBox(height: 18),

          if (fileName == null || fileName.isEmpty) ...[

            _emptyState(),

            const SizedBox(height: 12),

            _replaceCvButton('Upload CV'),

          ] else



            Container(

              padding: const EdgeInsets.all(13),

              decoration: BoxDecoration(

                color: AppColors.background,

                borderRadius: BorderRadius.circular(20),

                border: Border.all(color: AppColors.lightGray),

              ),

              child: Row(

                children: [

                  Container(

                    width: 52,

                    height: 58,

                    decoration: BoxDecoration(

                      gradient: const LinearGradient(

                        begin: Alignment.topLeft,

                        end: Alignment.bottomRight,

                        colors: [AppColors.navy, AppColors.secondaryNavy],

                      ),

                      borderRadius: BorderRadius.circular(15),

                    ),

                    child: const Icon(

                      Icons.picture_as_pdf_outlined,

                      color: AppColors.white,

                      size: 25,

                    ),

                  ),

                  const SizedBox(width: 13),

                  Expanded(

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text(

                          fileName,

                          maxLines: 2,

                          overflow: TextOverflow.ellipsis,

                          style: const TextStyle(

                            color: AppColors.navy,

                            fontSize: 13.5,

                            fontWeight: FontWeight.w800,

                          ),

                        ),

                        if (uploadedAt.isNotEmpty) ...[

                          const SizedBox(height: 4),

                          Text(

                            'Uploaded $uploadedAt',

                            style: const TextStyle(

                              color: AppColors.secondaryText,

                              fontSize: 10.5,

                            ),

                          ),

                        ],

                      ],

                    ),

                  ),

                  const SizedBox(width: 8),

                  _replaceCvButton('Replace'),

                ],

              ),

            ),

        ],

      ),

    );

  }



  Widget _replaceCvButton(String label) {

    return InkWell(

      onTap: _isReplacingCv ? null : _replaceCv,

      borderRadius: BorderRadius.circular(12),

      child: Container(

        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),

        decoration: BoxDecoration(

          color: AppColors.gold.withValues(alpha: 0.10),

          borderRadius: BorderRadius.circular(12),

        ),

        child: _isReplacingCv

            ? const SizedBox(

                width: 16,

                height: 16,

                child: CircularProgressIndicator(

                  strokeWidth: 2,

                  color: AppColors.gold,

                ),

              )

            : Text(

                label,

                style: const TextStyle(

                  color: AppColors.gold,

                  fontSize: 11,

                  fontWeight: FontWeight.w800,

                ),

              ),

      ),

    );

  }



  // ============================================================

  // REPLACE CV (backlog: PDF only, old CV stays if anything fails,

  // analysis sections are NOT changed until a new analysis)

  // ============================================================



  Future<void> _replaceCv() async {

    if (_isReplacingCv) return;



    setState(() {

      _isReplacingCv = true;

    });



    try {

      // Any file type, so a non-PDF gets the backlog message

      final file = await FilePicker.pickFile(type: FileType.any);

      if (file == null) return;



      final bytes = await file.readAsBytes();



      // Throws CvReadException with the exact backlog messages

      final text = CvService.extractText(

        fileName: file.name,

        bytes: bytes,

      );



      // Saves name + date + text together. If it fails, the old CV stays.

      await _userService.saveCv(fileName: file.name, text: text);



      await _loadProfile();

      _showMessage('Your CV has been replaced successfully.');

    } on CvReadException catch (e) {

      _showMessage(e.message, isError: true);

    } catch (e) {

      debugPrint('REPLACE CV ERROR: $e');

      _showMessage('Could not replace your CV. Please try again.',

          isError: true);

    } finally {

      if (mounted) {

        setState(() {

          _isReplacingCv = false;

        });

      }

    }

  }



  // ============================================================

  // SHARED WIDGETS

  // ============================================================



  Widget _emptyState() {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(

        color: AppColors.background,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: AppColors.lightGray),

      ),

      child: const Text(

        _emptyMessage,

        style: TextStyle(

          color: AppColors.secondaryText,

          fontSize: 12.5,

          fontWeight: FontWeight.w500,

        ),

      ),

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

        padding: const EdgeInsets.symmetric(horizontal: 15),

        decoration: BoxDecoration(

          color: AppColors.softBackground,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(color: accent.withValues(alpha: 0.15)),

          boxShadow: [

            BoxShadow(

              color: AppColors.navy.withValues(alpha: 0.045),

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

                color: accent.withValues(alpha: 0.10),

                borderRadius: BorderRadius.circular(12),

              ),

              child: Icon(icon, color: accent, size: 20),

            ),

            const SizedBox(width: 9),

            Text(

              title,

              style: const TextStyle(

                color: AppColors.navy,

                fontSize: 13.5,

                fontWeight: FontWeight.w700,

              ),

            ),

          ],

        ),

      ),

    );

  }



  Widget _profileCard({required Widget child}) {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(

        color: AppColors.softBackground,

        borderRadius: BorderRadius.circular(27),

        border: Border.all(

          color: AppColors.lightGray.withValues(alpha: 0.85),

        ),

        boxShadow: [

          BoxShadow(

            color: AppColors.navy.withValues(alpha: 0.045),

            blurRadius: 18,

            offset: const Offset(0, 7),

          ),

        ],

      ),

      child: child,

    );

  }



  Widget _sectionHeader({

    required String title,

    required String subtitle,

    required IconData icon,

    required Color accent,

  }) {

    return Row(

      children: [

        Container(

          width: 43,

          height: 43,

          decoration: BoxDecoration(

            color: accent.withValues(alpha: 0.09),

            borderRadius: BorderRadius.circular(14),

          ),

          child: Icon(icon, color: accent, size: 21),

        ),

        const SizedBox(width: 12),

        Expanded(

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text(

                title,

                style: const TextStyle(

                  color: AppColors.navy,

                  fontSize: 19,

                  fontWeight: FontWeight.w800,

                  letterSpacing: -0.3,

                ),

              ),

              const SizedBox(height: 3),

              Text(

                subtitle,

                maxLines: 1,

                overflow: TextOverflow.ellipsis,

                style: const TextStyle(

                  color: AppColors.secondaryText,

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

                selected: false,

                onTap: _goHome,

              ),

              _navItem(

                icon: Icons.explore_outlined,

                label: 'Explore',

                selected: false,

                onTap: _openExplore,

              ),

              _navItem(

                icon: Icons.groups_2_outlined,

                label: 'Community',

                selected: false,

                onTap: _openCommunity,

              ),

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

              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),

              decoration: BoxDecoration(

                color: selected

                    ? AppColors.lightTeal.withValues(alpha: 0.58)

                    : Colors.transparent,

                borderRadius: BorderRadius.circular(20),

              ),

              child: Stack(

                clipBehavior: Clip.none,

                children: [

                  Icon(

                    icon,

                    size: 24,

                    color: selected ? AppColors.teal : AppColors.secondaryText,

                  ),

                  if (selected)

                    Positioned(

                      top: -7,

                      right: -2,

                      child: Container(

                        width: 6,

                        height: 6,

                        decoration: const BoxDecoration(

                          color: AppColors.gold,

                          shape: BoxShape.circle,

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

                color: selected ? AppColors.teal : AppColors.secondaryText,

                fontSize: 11,

                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,

              ),

            ),

          ],

        ),

      ),

    );

  }



  // ============================================================

  // NAVIGATION

  // ============================================================



  // ============================================================
  // EDIT ONE FIELD (pencil next to each field)
  // Same inputs, options and validation as Profile Setup.
  // Only the edited field (+ updatedAt from updateUser) is written.
  // ============================================================

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // e.g. "June 2027" (older profiles may only have graduationYear)
  String get _graduationDateLabel {
    final year = _user['graduationYear'];
    if (year == null) return '-';

    final month = _user['graduationMonth'];
    if (month is int && month >= 1 && month <= 12) {
      return '${_monthNames[month - 1]} $year';
    }
    return year.toString();
  }

  DateTime? get _savedGraduationDate {
    final year = _user['graduationYear'];
    if (year is! int) return null;

    final month = _user['graduationMonth'];
    return DateTime(year, month is int && month >= 1 && month <= 12 ? month : 1);
  }

  DateTime get _currentMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  // Same ranges as Profile Setup (null if no status yet)
  // Student: current month -> 6 years ahead
  // Graduate / Fresh Graduate: January 2000 -> current month
  DateTimeRange? _graduationDateRange(String? status) {
    if (status == null) return null;

    final current = _currentMonth;

    if (status == 'Student') {
      return DateTimeRange(
        start: current,
        end: DateTime(current.year + 6, current.month),
      );
    }

    return DateTimeRange(start: DateTime(2000, 1), end: current);
  }

  bool _isDateInRange(DateTime date, DateTimeRange range) {
    return !date.isBefore(range.start) && !date.isAfter(range.end);
  }

  // Bottom sheet with one field + Cancel / Save.
  // On success the page shows the new value; on error the old value stays.
  Future<void> _showEditSheet({
    required String label,
    required Widget Function(BuildContext sheetContext, StateSetter setSheetState)
        buildField,
    required Map<String, dynamic> Function() buildUpdate,
  }) async {
    final formKey = GlobalKey<FormState>();
    var isSaving = false;
    Map<String, dynamic>? savedUpdate;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              if (!formKey.currentState!.validate()) return;

              final update = buildUpdate();
              setSheetState(() => isSaving = true);

              try {
                await _userService.updateUser(update);
                savedUpdate = update;
                if (sheetContext.mounted) Navigator.pop(sheetContext, true);
              } catch (e) {
                debugPrint('PROFILE FIELD UPDATE ERROR: $e');
                if (sheetContext.mounted) Navigator.pop(sheetContext, false);
              }
            }

            return PopScope(
              // Don't close the sheet while saving
              canPop: !isSaving,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit $label',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          buildField(sheetContext, setSheetState),
                          const SizedBox(height: 22),
                          // Same styles as the Sign Up (secondary) and
                          // Log In (primary) buttons in login_screen.dart
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: isSaving
                                        ? null
                                        : () => Navigator.pop(sheetContext),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.navy,
                                      side: BorderSide(
                                        color: AppColors.navy.withValues(
                                          alpha: 0.20,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 52,
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
                                        color: AppColors.teal.withValues(
                                          alpha: 0.24,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: isSaving ? null : save,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      disabledBackgroundColor:
                                          Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      foregroundColor: AppColors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    child: isSaving
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: AppColors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Save',
                                            style: TextStyle(
                                              fontSize: 16,
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
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || saved == null) return;

    if (saved) {
      setState(() => _user = {..._user, ...savedUpdate!});
      _showFieldMessage('$label updated successfully.');
      _loadProfile(silent: true);
    } else {
      _showFieldMessage(
        'Could not save your changes. Please try again.',
        isError: true,
      );
    }
  }

  Future<void> _editFullName() async {
    var name = _user['fullName']?.toString().trim() ?? '';

    await _showEditSheet(
      label: 'Full Name',
      buildField: (_, _) => TextFormField(
        initialValue: name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onChanged: (value) => name = value,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Full name is required.';
          }
          return null;
        },
        style: const TextStyle(color: AppColors.navy, fontSize: 14),
        decoration: _inputDecoration(
          hint: 'Enter your full name',
          icon: Icons.person_outline_rounded,
        ),
      ),
      buildUpdate: () => {'fullName': name.trim()},
    );
  }

  // University, Degree, Major, Career Goal, Experience Level.
  // options: saved value -> shown label (Career Goal saves the ID).
  Future<void> _editDropdownField({
    required String fieldKey,
    required String label,
    required String hint,
    required IconData icon,
    required Map<String, String> options,
  }) async {
    final current = _user[fieldKey]?.toString();
    String? selected = options.containsKey(current) ? current : null;

    await _showEditSheet(
      label: label,
      buildField: (_, _) => _dropdownField(
        hint: hint,
        icon: icon,
        value: selected,
        options: options,
        onChanged: (value) => selected = value,
      ),
      buildUpdate: () => {fieldKey: selected},
    );
  }

  Future<void> _editGraduationStatus() async {
    final savedStatus = _user['graduationStatus']?.toString();
    final savedDate = _savedGraduationDate;

    String? status = ProfileOptions.graduationStatuses.contains(savedStatus)
        ? savedStatus
        : null;
    DateTime? date = savedDate;

    // True when the saved graduation date doesn't fit the new status
    // (e.g. Graduate -> Student needs a future date), same rule as
    // Profile Setup. Then a new date is required in the same sheet.
    var needsDate = false;

    await _showEditSheet(
      label: 'Graduation Status',
      buildField: (sheetContext, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dropdownField(
            hint: 'Select your status',
            icon: Icons.workspace_premium_outlined,
            value: status,
            options: {for (final s in ProfileOptions.graduationStatuses) s: s},
            onChanged: (value) {
              setSheetState(() {
                status = value;
                final range = _graduationDateRange(value);
                needsDate = range != null &&
                    (savedDate == null || !_isDateInRange(savedDate, range));
                date = needsDate ? null : savedDate;
              });
            },
          ),
          if (needsDate) ...[
            const SizedBox(height: 14),
            const Text(
              "Your graduation date doesn't match this status. "
              'Please select a new one.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            _graduationDateField(
              sheetContext: sheetContext,
              date: date,
              range: _graduationDateRange(status),
              onPicked: (picked) => setSheetState(() => date = picked),
            ),
          ],
        ],
      ),
      buildUpdate: () {
        final newDate = date;
        return {
          'graduationStatus': status,
          if (needsDate && newDate != null) ...{
            'graduationYear': newDate.year,
            'graduationMonth': newDate.month,
          },
        };
      },
    );
  }

  Future<void> _editGraduationDate() async {
    final range =
        _graduationDateRange(_user['graduationStatus']?.toString());

    if (range == null) {
      _showFieldMessage(
        'Please select your graduation status first.',
        isError: true,
      );
      return;
    }

    // A saved date outside the allowed range must be picked again
    final savedDate = _savedGraduationDate;
    DateTime? date =
        savedDate != null && _isDateInRange(savedDate, range) ? savedDate : null;

    await _showEditSheet(
      label: 'Graduation Date',
      buildField: (sheetContext, setSheetState) => _graduationDateField(
        sheetContext: sheetContext,
        date: date,
        range: range,
        onPicked: (picked) => setSheetState(() => date = picked),
      ),
      buildUpdate: () {
        final newDate = date!;
        return {
          'graduationYear': newDate.year,
          'graduationMonth': newDate.month,
        };
      },
    );
  }

  // Same CupertinoDatePicker (monthYear) bottom sheet as Profile Setup
  Future<DateTime?> _pickGraduationDate(
    BuildContext pickerContext,
    DateTimeRange range,
    DateTime? current,
  ) {
    FocusScope.of(pickerContext).unfocus();

    // Value shown in the sheet; only applied when Done is pressed
    var tempDate = current != null && _isDateInRange(current, range)
        ? current
        : _currentMonth;

    return showModalBottomSheet<DateTime>(
      context: pickerContext,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext, tempDate),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.lightGray),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.monthYear,
                    initialDateTime: tempDate,
                    minimumDate: range.start,
                    maximumDate: range.end,
                    minimumYear: range.start.year,
                    maximumYear: range.end.year,
                    onDateTimeChanged: (date) {
                      tempDate = DateTime(date.year, date.month);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _graduationDateField({
    required BuildContext sheetContext,
    required DateTime? date,
    required DateTimeRange? range,
    required ValueChanged<DateTime> onPicked,
  }) {
    return FormField<DateTime>(
      validator: (_) => date == null ? 'This field is required.' : null,
      builder: (field) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            if (range == null) return;

            final picked = await _pickGraduationDate(sheetContext, range, date);
            if (picked == null) return;

            onPicked(picked);
            field.didChange(picked);

            // Clear the "required" error if it was showing
            if (field.hasError) field.validate();
          },
          child: InputDecorator(
            isEmpty: date == null,
            decoration: _inputDecoration(
              hint: 'Select your graduation month and year',
              icon: Icons.calendar_month_outlined,
              errorText: field.errorText,
              suffixIcon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.secondaryText,
              ),
            ),
            child: Text(
              date == null
                  ? ''
                  : '${_monthNames[date.month - 1]} ${date.year}',
              style: const TextStyle(color: AppColors.navy, fontSize: 14),
            ),
          ),
        );
      },
    );
  }

  Widget _dropdownField({
    required String hint,
    required IconData icon,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: options.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'This field is required.';
        }
        return null;
      },
      style: const TextStyle(color: AppColors.navy, fontSize: 14),
      dropdownColor: AppColors.softBackground,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.secondaryText,
      ),
      decoration: _inputDecoration(hint: hint, icon: icon),
    );
  }

  // Same input style as Profile Setup
  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? errorText,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.mediumGray, fontSize: 13),
      errorText: errorText,
      prefixIcon: Icon(icon, color: AppColors.secondaryText, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.softBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
      border: border(AppColors.lightGray),
      enabledBorder: border(AppColors.lightGray),
      focusedBorder: border(AppColors.teal, 1.5),
      errorBorder: border(const Color(0xFFC94C4C)),
    );
  }

  // Same style as _showMessage in login_screen.dart
  void _showFieldMessage(String title, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.softBackground,
        elevation: 8,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: Duration(seconds: isError ? 3 : 1),
        content: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFFDECEC)
                    : const Color(0xFFE4F6EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isError ? Icons.error_outline_rounded : Icons.check_rounded,
                color: isError
                    ? const Color(0xFFD64545)
                    : const Color(0xFF23966F),
                size: 22,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 5),
            IconButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.secondaryText,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }



  void _goHome() {

    Navigator.pushReplacement(

      context,

      MaterialPageRoute(builder: (_) => const HomeScreen()),

    );

  }



  void _openExplore() {

    Navigator.pushReplacement(

      context,

      MaterialPageRoute(builder: (_) => const ExploreScreen()),

    );

  }



  void _openCommunity() {

    Navigator.pushReplacement(

      context,

      MaterialPageRoute(builder: (_) => const CommunityScreen()),

    );

  }



  // ============================================================

  // LOG OUT (backlog: confirmation, then Welcome screen)

  // ============================================================



  Future<void> _confirmLogout() async {

    final confirmed = await showDialog<bool>(

      context: context,

      builder: (dialogContext) {

        return AlertDialog(

          backgroundColor: AppColors.softBackground,

          shape: RoundedRectangleBorder(

            borderRadius: BorderRadius.circular(24),

          ),

          title: const Text(

            'Log Out',

            style: TextStyle(

              color: AppColors.navy,

              fontSize: 19,

              fontWeight: FontWeight.w800,

            ),

          ),

          content: const Text(

            'Are you sure you want to log out?',

            style: TextStyle(

              color: AppColors.secondaryText,

              fontSize: 13,

              height: 1.45,

            ),

          ),

          actions: [

            TextButton(

              onPressed: () => Navigator.pop(dialogContext, false),

              child: const Text(

                'Cancel',

                style: TextStyle(

                  color: AppColors.secondaryText,

                  fontWeight: FontWeight.w700,

                ),

              ),

            ),

            TextButton(

              onPressed: () => Navigator.pop(dialogContext, true),

              child: const Text(

                'Confirm',

                style: TextStyle(

                  color: _logoutRed,

                  fontWeight: FontWeight.w700,

                ),

              ),

            ),

          ],

        );

      },

    );



    if (confirmed != true) return;



    try {

      await FirebaseAuth.instance.signOut();

    } catch (_) {

      _showMessage('Log out failed. Please try again.', isError: true);

      return;

    }



    if (!mounted) return;



    Navigator.pushAndRemoveUntil(

      context,

      MaterialPageRoute(builder: (_) => const OnboardingScreen()),

      (route) => false,

    );

  }



  void _showMessage(String message, {bool isError = false}) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(

        behavior: SnackBarBehavior.floating,

        backgroundColor: AppColors.softBackground,

        margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

        content: Row(

          children: [

            Icon(

              isError ? Icons.error_outline_rounded : Icons.check_rounded,

              color: isError ? _logoutRed : const Color(0xFF23966F),

              size: 22,

            ),

            const SizedBox(width: 12),

            Expanded(

              child: Text(

                message,

                style: const TextStyle(

                  color: AppColors.navy,

                  fontSize: 13,

                  fontWeight: FontWeight.w600,

                  height: 1.4,

                ),

              ),

            ),

          ],

        ),

      ),

    );

  }

}
