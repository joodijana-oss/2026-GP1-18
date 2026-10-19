import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:file_picker/file_picker.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';



import '../constants/profile_options.dart';

import '../features/community/community_screen.dart';

import '../utils/cv_validator.dart';

import '../utils/validators.dart';

import '../services/user_service.dart';

import '../theme/app_colors.dart';

import 'explore_screen.dart';

import 'home_screen.dart';

import 'login_screen.dart';

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



class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {

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

    WidgetsBinding.instance.addObserver(this);

    // Load first, then compare the Auth email with the loaded one
    _loadProfile().then((_) => _syncAuthEmail());

  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back to the app while on Profile (e.g. after confirming the new
  // email from the inbox)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncAuthEmail();
  }

  // ============================================================
  // EMAIL SYNC (Auth -> Firestore)
  // After an email change is confirmed, Auth has the new email.
  // reload() gets it; if the session was revoked, log in again.
  // ============================================================

  bool _isSyncingEmail = false;

  Future<void> _syncAuthEmail() async {
    if (_isSyncingEmail) return;
    _isSyncingEmail = true;

    try {
      await FirebaseAuth.instance.currentUser?.reload();

      final authEmail = FirebaseAuth.instance.currentUser?.email;
      final savedEmail = _user['email'];

      // Skip if the profile didn't load (nothing to compare)
      if (!mounted || authEmail == null || savedEmail == null) return;
      if (authEmail == savedEmail) return;

      await _userService.updateUser({'email': authEmail});

      if (!mounted) return;
      setState(() => _user = {..._user, 'email': authEmail});
    } on FirebaseAuthException catch (e) {
      debugPrint('EMAIL SYNC ERROR: ${e.code}');

      // Session no longer valid (e.g. the email was changed)
      const sessionEnded = {
        'user-token-expired',
        'invalid-user-token',
        'user-not-found',
        'user-disabled',
      };

      if (sessionEnded.contains(e.code)) await _logInAgain();
    } catch (e) {
      // e.g. no internet: keep showing the page as it is
      debugPrint('EMAIL SYNC ERROR: $e');
    } finally {
      _isSyncingEmail = false;
    }
  }

  Future<void> _logInAgain() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;

    _showFieldMessage(
      'Your email was changed. Please log in again.',
      isError: true,
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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

                // TOP BAR (same height as before, so the avatar row
                // below keeps its position)

                SizedBox(

                  height: 42,

                  child: Row(

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

                  ],

                  ),

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

          // Changing the email needs the password + a verification link
          _infoRow(Icons.email_outlined, 'Email Address', _text('email'),
              onEdit: _editEmail),

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

          _infoRow(Icons.flag_outlined, 'Academic Status',

              ProfileOptions.normalizeGraduationStatus(
                    _user['graduationStatus']?.toString(),
                  ) ??
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



      // Same rules as Profile Setup (size, PDF, 1-3 pages, has text).
      // Runs on the freshly picked file, before anything is saved.

      final result = await CvValidator.validate(

        fileName: file.name,

        sizeInBytes: await file.length(),

        readBytes: file.readAsBytes,

      );



      // Invalid: show the reason, old CV stays untouched

      if (!result.isValid) {

        _showMessage(result.error!, isError: true);

        return;

      }



      // Saves name + date + text together. If it fails, the old CV stays.

      await _userService.saveCv(fileName: file.name, text: result.text!);



      await _loadProfile();

      _showMessage('Your CV has been replaced successfully.');

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
  // Graduate: January 2000 -> current month
  DateTimeRange? _graduationDateRange(String? status) {
    status = ProfileOptions.normalizeGraduationStatus(status);
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
  // buildUpdate = fields saved with updateUser (Firestore).
  // customSave = any other save (Email). It returns the SnackBar to show
  // after closing the sheet, or null to keep the sheet open (field error).
  // canSave = Save stays disabled while it returns false; fields call
  // setSheetState on change so it updates live.
  Future<void> _showEditSheet({
    required String label,
    required Widget Function(BuildContext sheetContext, StateSetter setSheetState)
        buildField,
    Map<String, dynamic> Function()? buildUpdate,
    Future<_EditResult?> Function(StateSetter setSheetState)? customSave,
    bool Function()? canSave,
  }) async {
    final formKey = GlobalKey<FormState>();
    var isSaving = false;
    Map<String, dynamic>? savedUpdate;
    var savedOffline = false;

    final result = await showModalBottomSheet<_EditResult>(
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
              FocusScope.of(sheetContext).unfocus();
              if (!formKey.currentState!.validate()) return;

              setSheetState(() => isSaving = true);

              if (customSave != null) {
                final custom = await customSave(setSheetState);
                if (!sheetContext.mounted) return;

                if (custom == null) {
                  setSheetState(() => isSaving = false);
                } else {
                  Navigator.pop(sheetContext, custom);
                }
                return;
              }

              final update = buildUpdate!();

              try {
                // Offline, update() waits for the server forever
                await _userService
                    .updateUser(update)
                    .timeout(const Duration(seconds: 10));
                savedUpdate = update;
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, (
                    message: '$label updated successfully.',
                    isError: false,
                    duration: null,
                  ));
                }
              } on TimeoutException {
                // Firestore keeps the write queued and saves it when online,
                // so the page shows the new value right away
                savedOffline = true;
                savedUpdate = update;
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, (
                    message: "You're offline. Your change will be saved "
                        "when you're back online.",
                    isError: false,
                    duration: const Duration(seconds: 4),
                  ));
                }
              } catch (e) {
                debugPrint('PROFILE FIELD UPDATE ERROR: $e');
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, (
                    message: 'Could not save your changes. Please try again.',
                    isError: true,
                    duration: null,
                  ));
                }
              }
            }

            final saveEnabled = canSave?.call() ?? true;

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
                                // Dimmed and disabled until the field is valid
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: saveEnabled || isSaving ? 1 : 0.5,
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
                                    onPressed:
                                        isSaving || !saveEnabled ? null : save,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      disabledBackgroundColor:
                                          Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      foregroundColor: AppColors.white,
                                      disabledForegroundColor: AppColors.white,
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

    if (!mounted || result == null) return;

    final update = savedUpdate;
    if (update != null) {
      setState(() => _user = {..._user, ...update});
      _loadProfile(silent: true);
    }

    _showFieldMessage(
      result.message,
      isError: result.isError,
      isInfo: savedOffline,
      duration: result.duration,
    );
  }

  // Email: re-authenticate with the current password, then Firebase sends
  // a verification link to the new email. The email changes in Auth only
  // after the link is opened; Firestore is synced on the next log in.
  Future<void> _editEmail() async {
    final currentEmail = FirebaseAuth.instance.currentUser?.email ??
        _user['email']?.toString() ??
        '';

    var newEmail = '';
    var password = '';
    var hidePassword = true;

    // Errors from Firebase shown under the field (sheet stays open)
    String? emailError;
    String? passwordError;

    const loginAgainMessage =
        'For your security, please log in again and then change your email.';

    // Same rules as Sign Up + must be a different email
    String? validateNewEmail(String? value) {
      final error = Validators.email(value);
      if (error != null) return error;

      if (value!.trim().toLowerCase() == currentEmail.toLowerCase()) {
        return 'This is already your email address.';
      }
      return null;
    }

    await _showEditSheet(
      label: 'Email Address',
      // Save only when both fields are valid and no Firebase error is showing
      canSave: () =>
          validateNewEmail(newEmail) == null &&
          Validators.enteredPassword(password) == null &&
          emailError == null &&
          passwordError == null,
      buildField: (_, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            forceErrorText: emailError,
            // Live: error updates on every keystroke once typing starts
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (value) {
              // Rebuild so the Save button follows the field
              setSheetState(() {
                newEmail = value;
                emailError = null;
              });
            },
            validator: validateNewEmail,
            style: const TextStyle(color: AppColors.navy, fontSize: 14),
            decoration: _inputDecoration(
              hint: Validators.emailHint,
              icon: Icons.email_outlined,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            obscureText: hidePassword,
            forceErrorText: passwordError,
            // "Password is required" only after the user has typed here
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (value) {
              setSheetState(() {
                password = value;
                passwordError = null;
              });
            },
            validator: Validators.enteredPassword,
            style: const TextStyle(color: AppColors.navy, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Enter your current password',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                onPressed: () =>
                    setSheetState(() => hidePassword = !hidePassword),
                icon: Icon(
                  hidePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.secondaryText,
                  size: 21,
                ),
              ),
            ),
          ),
        ],
      ),
      customSave: (setSheetState) async {
        final user = FirebaseAuth.instance.currentUser;
        final email = user?.email;

        if (user == null || email == null) {
          return (message: loginAgainMessage, isError: true, duration: null);
        }

        try {
          await user.reauthenticateWithCredential(
            EmailAuthProvider.credential(email: email, password: password),
          );

          await user.verifyBeforeUpdateEmail(newEmail.trim());

          return (
            message: 'If this email address is available, a verification '
                'link has been sent to it. Your email will change after '
                'you confirm it.',
            isError: false,
            duration: const Duration(seconds: 6),
          );
        } on FirebaseAuthException catch (e) {
          debugPrint('CHANGE EMAIL ERROR: ${e.code}');

          if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
            setSheetState(() => passwordError = 'Incorrect password.');
            return null;
          }

          if (e.code == 'email-already-in-use') {
            setSheetState(
              () => emailError = 'An account with this email already exists.',
            );
            return null;
          }

          if (e.code == 'invalid-email') {
            setSheetState(() => emailError = 'Enter a valid email address.');
            return null;
          }

          final message = switch (e.code) {
            'requires-recent-login' => loginAgainMessage,
            'network-request-failed' =>
              'No internet connection. Please try again.',
            'too-many-requests' =>
              'Too many attempts. Please try again later.',
            _ => 'Something went wrong. Please try again.',
          };
          return (message: message, isError: true, duration: null);
        } catch (e) {
          debugPrint('CHANGE EMAIL ERROR: $e');
          return (
            message: 'Something went wrong. Please try again.',
            isError: true,
            duration: null,
          );
        }
      },
    );
  }

  Future<void> _editFullName() async {
    var name = _user['fullName']?.toString().trim() ?? '';

    await _showEditSheet(
      label: 'Full Name',
      canSave: () => Validators.fullName(name) == null,
      buildField: (_, setSheetState) => TextFormField(
        initialValue: name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        // Live: "required" shows as soon as the name is cleared
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: (value) => setSheetState(() => name = value),
        validator: Validators.fullName,
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
      canSave: () => selected != null,
      buildField: (_, setSheetState) => _dropdownField(
        hint: hint,
        icon: icon,
        value: selected,
        options: options,
        onChanged: (value) => setSheetState(() => selected = value),
      ),
      buildUpdate: () => {fieldKey: selected},
    );
  }

  Future<void> _editGraduationStatus() async {
    final savedStatus = _user['graduationStatus']?.toString();
    final savedDate = _savedGraduationDate;

    // Old 'Fresh Graduate' values open the sheet as 'Graduate'
    String? status = ProfileOptions.normalizeGraduationStatus(savedStatus);
    DateTime? date = savedDate;

    // True when the saved graduation date doesn't fit the new status
    // (e.g. Graduate -> Student needs a future date), same rule as
    // Profile Setup. Then a new date is required in the same sheet.
    var needsDate = false;

    await _showEditSheet(
      label: 'Academic Status',
      // A new date is required when the old one doesn't fit the status
      canSave: () => status != null && (!needsDate || date != null),
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
        'Please select your academic status first.',
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
      canSave: () => date != null,
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
  // isInfo = neutral notice (teal), e.g. a change saved while offline
  void _showFieldMessage(
    String title, {
    bool isError = false,
    bool isInfo = false,
    Duration? duration,
  }) {
    if (!mounted) return;

    // Kept so the SnackBar (and its close button) still works if this
    // page is replaced, e.g. by Log In
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.softBackground,
        elevation: 8,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: duration ?? Duration(seconds: isError ? 3 : 1),
        content: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFFDECEC)
                    : isInfo
                        ? AppColors.teal.withValues(alpha: 0.12)
                        : const Color(0xFFE4F6EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : isInfo
                        ? Icons.cloud_off_rounded
                        : Icons.check_rounded,
                color: isError
                    ? const Color(0xFFD64545)
                    : isInfo
                        ? AppColors.teal
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
              onPressed: () => messenger.hideCurrentSnackBar(),
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

// What an edit sheet shows after closing (SnackBar text, style, how long)
typedef _EditResult = ({String message, bool isError, Duration? duration});
