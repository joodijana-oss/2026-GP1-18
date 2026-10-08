import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:file_picker/file_picker.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';



import '../constants/profile_options.dart';

import '../features/community/community_screen.dart';

import '../services/cv_service.dart';

import '../services/user_service.dart';

import '../theme/app_colors.dart';

import 'explore_screen.dart';

import 'home_screen.dart';

import 'onboarding_screen.dart';

import 'profile_setup_screen.dart';



// ============================================================

// PROFILE SCREEN

// Shows only what the backlog (View Profile) asks for:

// Basic Information, Academic Information, Career Profile,

// Skills, Certifications, Projects, Experience (from the latest

// AI Career Analysis), CV (with Replace CV), Edit Profile, and Log Out.

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



  Future<void> _loadProfile() async {

    setState(() {

      _isLoading = true;

      _hasError = false;

    });



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

            const SizedBox(height: 22),

            _padded(

              _profileAction(

                icon: Icons.edit_note_rounded,

                title: 'Edit Profile',

                accent: AppColors.teal,

                onTap: _openEditProfile,

              ),

            ),

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

          _infoRow(Icons.badge_outlined, 'Full Name', _fullName),

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

              _text('university')),

          _infoRow(Icons.workspace_premium_outlined, 'Degree',

              _text('degree')),

          _infoRow(Icons.menu_book_outlined, 'Major', _text('major')),

          _infoRow(Icons.flag_outlined, 'Graduation Status',

              _text('graduationStatus')),

          _infoRow(Icons.calendar_today_outlined, 'Graduation Year',

              _text('graduationYear')),

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

              _careerGoalLabel),

          _infoRow(Icons.trending_up_rounded, 'Current Experience Level',

              _text('experienceLevel')),

        ],

      ),

    );

  }



  Widget _infoRow(IconData icon, String label, String value) {

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



  // After editing, reload so the page shows the latest saved data

  Future<void> _openEditProfile() async {

    await Navigator.push(

      context,

      MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),

    );



    if (!mounted) return;

    _loadProfile();

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
