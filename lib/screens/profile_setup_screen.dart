
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../services/user_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  // =========================================================
  // FORM KEYS
  // =========================================================

  final _academicFormKey = GlobalKey<FormState>();
  final _careerFormKey = GlobalKey<FormState>();

  // =========================================================
  // CONTROLLERS
  // =========================================================

  final universityController = TextEditingController();
  final majorController = TextEditingController();
  final graduationYearController = TextEditingController();

  // =========================================================
  // SELECTED VALUES
  // =========================================================

  String? selectedDegree;
  String? selectedGraduationStatus;
  String? selectedCareerGoalId;
  String? selectedExperienceLevel;

  // =========================================================
  // CV DATA
  // =========================================================

  Uint8List? selectedCvBytes;
  String? selectedCvName;

  // =========================================================
  // PAGE STATE
  // =========================================================

  int currentStep = 0;

  bool isPickingCv = false;
  bool isSaving = false;

  final ScrollController _scrollController = ScrollController();

  // =========================================================
  // BACKGROUND ANIMATION
  // =========================================================

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  // =========================================================
  // OPTIONS
  // =========================================================

  final List<String> degreeOptions = [
    'Diploma',
    'Bachelor',
    'Master',
    'PhD',
  ];

  final List<String> graduationStatusOptions = [
    'Student',
    'Fresh Graduate',
    'Graduate',
  ];

  final List<String> experienceOptions = [
    'No Experience',
    'Beginner',
    'Intermediate',
    'Advanced',
  ];

  // IMPORTANT:
  // Career Goal IDs must be agreed upon by the team.
  // Replace these IDs if the team uses different IDs
  // in Firestore.

  final Map<String, String> careerGoals = {
    'software_engineer': 'Software Engineer',
    'web_developer': 'Web Developer',
    'mobile_developer': 'Mobile Developer',
    'ai_specialist': 'AI Specialist',
    'data_analyst': 'Data Analyst',
    'data_scientist': 'Data Scientist',
    'cybersecurity_analyst': 'Cybersecurity Analyst',
    'cloud_engineer': 'Cloud Engineer',
    'network_engineer': 'Network Engineer',
    'database_administrator': 'Database Administrator',
    'ui_ux_designer': 'UI/UX Designer',
    'it_specialist': 'IT Specialist',
  };

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _backgroundAnimation = CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    );
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    universityController.dispose();
    majorController.dispose();
    graduationYearController.dispose();

    _backgroundController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  // =========================================================
  // SHOW MESSAGE
  // =========================================================

  void showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.softBackground,
        elevation: 8,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        content: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFFCE8E8)
                    : const Color(0xFFE4F6EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_rounded,
                color: isError
                    ? const Color(0xFFC94C4C)
                    : const Color(0xFF23966F),
                size: 22,
              ),
            ),

            const SizedBox(width: 13),

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

  // =========================================================
  // CHANGE STEP
  // =========================================================

  void goToStep(int step) {
    setState(() {
      currentStep = step;
    });

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  // =========================================================
  // NEXT BUTTON
  // =========================================================

  void nextStep() {
    FocusScope.of(context).unfocus();

    if (currentStep == 0) {
      if (_academicFormKey.currentState!.validate()) {
        goToStep(1);
      }

      return;
    }

    if (currentStep == 1) {
      if (_careerFormKey.currentState!.validate()) {
        goToStep(2);
      }

      return;
    }

    if (currentStep == 2) {
      saveProfile();
    }
  }

  // =========================================================
  // BACK BUTTON
  // =========================================================

  void previousStep() {
    if (isSaving || isPickingCv) return;

    if (currentStep > 0) {
      goToStep(currentStep - 1);
    }
  }

  // =========================================================
  // SELECT AND VALIDATE CV
  // =========================================================

  Future<void> pickCv() async {
    if (isPickingCv || isSaving) return;

    setState(() {
      isPickingCv = true;
    });

    try {
      final file = await FilePicker.pickFile(
  type: FileType.any,
);

if (file == null) {
  return;
}

      // ---------------------------------------------
      // CHECK FILE EXTENSION
      // ---------------------------------------------

      if (!file.name.toLowerCase().endsWith('.pdf')) {
        showMessage(
          'Unsupported file format. Please upload your CV as a PDF file.',
          isError: true,
        );

        return;
      }

     final bytes = await file.readAsBytes();

      if (bytes == null || bytes.isEmpty) {
        showMessage(
          'The uploaded PDF could not be read. Please upload a valid PDF file.',
          isError: true,
        );

        return;
      }

      // ---------------------------------------------
      // CHECK PDF HEADER
      // ---------------------------------------------

      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46 ||
          bytes[4] != 0x2D) {
        showMessage(
          'The uploaded PDF could not be read. Please upload a valid PDF file.',
          isError: true,
        );

        return;
      }

      // ---------------------------------------------
      // TRY TO OPEN THE PDF
      // ---------------------------------------------

      try {
        final document = await PdfDocument.openData(bytes);

        final pageCount = document.pagesCount;

        await document.close();

        if (pageCount < 1) {
          throw Exception('PDF has no readable pages');
        }
      } catch (_) {
        showMessage(
          'The uploaded PDF could not be read. Please upload a valid PDF file.',
          isError: true,
        );

        return;
      }

      // ---------------------------------------------
      // VALID PDF
      // ---------------------------------------------

      if (!mounted) return;

      setState(() {
        selectedCvBytes = bytes;
        selectedCvName = file.name;
      });

      showMessage(
        'Your CV has been selected successfully.',
      );
    } catch (_) {
      showMessage(
        'Unable to select the file. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isPickingCv = false;
        });
      }
    }
  }

  // =========================================================
  // REMOVE SELECTED CV
  // =========================================================

  void removeCv() {
    if (isSaving) return;

    setState(() {
      selectedCvBytes = null;
      selectedCvName = null;
    });
  }

  // =========================================================
  // UPLOAD CV TO FIREBASE STORAGE
  // =========================================================

  Future<Map<String, String>> uploadCv({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeFileName = fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final storagePath =
        'users/$uid/cv/${timestamp}_$safeFileName';

    final storageRef = FirebaseStorage.instance.ref(
      storagePath,
    );

    await storageRef.putData(
      bytes,
      SettableMetadata(
        contentType: 'application/pdf',
      ),
    );

    final downloadUrl =
        await storageRef.getDownloadURL();

    return {
      'url': downloadUrl,
      'path': storagePath,
    };
  }

  // =========================================================
  // SAVE PROFILE
  // =========================================================

  Future<void> saveProfile() async {
    if (isSaving || isPickingCv) return;

    // ---------------------------------------------
    // CHECK REQUIRED INFORMATION
    // ---------------------------------------------

    if (universityController.text.trim().isEmpty ||
        majorController.text.trim().isEmpty ||
        selectedDegree == null ||
        selectedGraduationStatus == null ||
        selectedCareerGoalId == null ||
        selectedExperienceLevel == null ||
        graduationYearController.text.trim().isEmpty) {
      showMessage(
        'Please complete all required profile fields.',
        isError: true,
      );

      return;
    }

    // ---------------------------------------------
    // CHECK CV
    // ---------------------------------------------

    if (selectedCvBytes == null ||
        selectedCvName == null) {
      showMessage(
        'Please upload your CV as a PDF file.',
        isError: true,
      );

      return;
    }

    // ---------------------------------------------
    // CHECK AUTHENTICATED USER
    // ---------------------------------------------

   final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage(
        'Your session has expired. Please log in again.',
        isError: true,
      );

      return;
    }

    final graduationYear = int.tryParse(
      graduationYearController.text.trim(),
    );

    if (graduationYear == null) {
      showMessage(
        'Please enter a valid graduation year.',
        isError: true,
      );

      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      // ---------------------------------------------
      // 1. UPLOAD CV
      // ---------------------------------------------

      final cvResult = await uploadCv(
        uid: user.uid,
        bytes: selectedCvBytes!,
        fileName: selectedCvName!,
      );

      // ---------------------------------------------
      // 2. SAVE CV INFORMATION IN FIRESTORE
      // ---------------------------------------------

      await UserService().updateUser({
        'cvUrl': cvResult['url'],
        'cvStoragePath': cvResult['path'],
        'cvFileName': selectedCvName,
      });

      // ---------------------------------------------
      // 3. SAVE ACADEMIC AND CAREER INFORMATION
      // ---------------------------------------------

      await UserService().saveProfile(
        university: universityController.text.trim(),
        degree: selectedDegree!,
        major: majorController.text.trim(),
        graduationStatus: selectedGraduationStatus!,
        graduationYear: graduationYear,
        careerGoalId: selectedCareerGoalId!,
        experienceLevel: selectedExperienceLevel!,
      );

      // saveProfile() sets profileCompleted = true
      // according to the team's UserService.

      if (!mounted) return;

      // ---------------------------------------------
      // 4. NAVIGATE TO HOME
      // ---------------------------------------------

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        ),
        (route) => false,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      if (e.code == 'unauthorized' ||
          e.code == 'permission-denied') {
        showMessage(
          'CV upload permission was denied. Please contact the team.',
          isError: true,
        );
      } else {
        showMessage(
          'Could not upload your CV or save your profile. Please try again.',
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) return;

      showMessage(
        'Something went wrong while saving your profile. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // =================================================
          // TOP GRADIENT
          // =================================================

          Container(
            height: 315,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.secondaryNavy,
                  AppColors.navy,
                  AppColors.teal,
                ],
              ),
            ),
          ),

          // =================================================
          // ANIMATED BACKGROUND CIRCLES
          // =================================================

          SizedBox(
            height: 315,
            width: double.infinity,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _backgroundAnimation,
                builder: (context, child) {
                  final value =
                      _backgroundAnimation.value;

                  return Stack(
                    children: [
                      // LARGE LEFT RING

                      Positioned(
                        top: 35 + (value * 22),
                        left: -70 + (value * 14),
                        child: Container(
                          width: 175,
                          height: 175,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.lightTeal
                                  .withValues(
                                alpha: 0.12,
                              ),
                              width: 28,
                            ),
                          ),
                        ),
                      ),

                      // TOP RIGHT SOFT CIRCLE

                      Positioned(
                        top: -95 + (value * 18),
                        right: -60 - (value * 14),
                        child: Container(
                          width: 225,
                          height: 225,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.lightTeal
                                .withValues(
                              alpha: 0.10,
                            ),
                          ),
                        ),
                      ),

                      // BOTTOM RIGHT RING

                      Positioned(
                        top: 190 - (value * 20),
                        right: -80 + (value * 12),
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.lightTeal
                                  .withValues(
                                alpha: 0.10,
                              ),
                              width: 22,
                            ),
                          ),
                        ),
                      ),

                      // SMALL FLOATING CIRCLE

                      Positioned(
                        top: 115 + (value * 18),
                        left: 135 - (value * 20),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.lightTeal
                                .withValues(
                              alpha: 0.07,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // =================================================
          // PAGE CONTENT
          // =================================================

          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                // =========================================
// TOP SECTION
// =========================================

SizedBox(
  height: 180,
  child: Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: 22,
    ),
    child: Column(
      children: [
        const SizedBox(height: 8),

        Row(
          children: [
            // BACK ARROW
            GestureDetector(
              onTap: currentStep > 0
                  ? previousStep
                  : () => Navigator.pop(context),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(
                    alpha: 0.13,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.white.withValues(
                      alpha: 0.18,
                    ),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.white,
                  size: 22,
                ),
              ),
            ),

            const Spacer(),

            // STEP NUMBER
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(
                  alpha: 0.13,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.white.withValues(
                    alpha: 0.18,
                  ),
                ),
              ),
              child: Text(
                'Step ${currentStep + 1} of 3',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
),

                  // =========================================
                  // FORM SHEET
                  // =========================================

                  Container(
                    width: double.infinity,
                    constraints:
                        const BoxConstraints(
                      minHeight: 650,
                    ),
                    padding:
                        const EdgeInsets.fromLTRB(
                      24,
                      30,
                      24,
                      35,
                    ),
                    decoration:
                        const BoxDecoration(
                      color:
                          AppColors.background,
                      borderRadius:
                          BorderRadius.only(
                        topLeft:
                            Radius.circular(38),
                        topRight:
                            Radius.circular(38),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // TEAL ACCENT

                        Container(
                          width: 42,
                          height: 5,
                          decoration:
                              BoxDecoration(
                            color: AppColors.teal,
                            borderRadius:
                                BorderRadius.circular(
                              20,
                            ),
                          ),
                        ),

                        const SizedBox(height: 19),

                        // =================================
                        // TITLE
                        // =================================

                        Text(
                          getStepTitle(),
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 28,
                            fontWeight:
                                FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          getStepSubtitle(),
                          style: const TextStyle(
                            color: AppColors
                                .secondaryText,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 25),

                        // =================================
                        // PROGRESS INDICATOR
                        // =================================

                        buildProgressIndicator(),

                        const SizedBox(height: 32),

                        // =================================
                        // CURRENT STEP CONTENT
                        // =================================

                        AnimatedSwitcher(
                          duration: const Duration(
                            milliseconds: 280,
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(currentStep),
                            child:
                                buildCurrentStep(),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // =================================
                        // CONTINUE / SAVE BUTTON
                        // =================================

                        buildMainButton(),

                        const SizedBox(height: 17),

                        // =================================
                        // PREVIOUS BUTTON
                        // =================================

                        if (currentStep > 0)
                          Center(
                            child: TextButton(
                              onPressed: isSaving
                                  ? null
                                  : previousStep,
                              child: const Text(
                                'Previous Step',
                                style: TextStyle(
                                  color: AppColors
                                      .secondaryText,
                                  fontSize: 14,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // STEP TITLES
  // =========================================================

  String getStepTitle() {
    switch (currentStep) {
      case 0:
        return 'Academic Information';

      case 1:
        return 'Career Information';

      case 2:
        return 'Upload Your CV';

      default:
        return 'Complete Your Profile';
    }
  }

  String getStepSubtitle() {
    switch (currentStep) {
      case 0:
        return 'Let’s start with your educational background.';

      case 1:
        return 'Help Masra understand your career goals and experience.';

      case 2:
        return 'One last step! Upload your CV to complete your profile.';

      default:
        return '';
    }
  }

  // =========================================================
  // PROGRESS INDICATOR
  // =========================================================

  Widget buildProgressIndicator() {
    return Row(
      children: List.generate(3, (index) {
        final isCompleted =
            index < currentStep;

        final isCurrent =
            index == currentStep;

        return Expanded(
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(
                  milliseconds: 250,
                ),
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.teal
                      : isCurrent
                          ? AppColors.navy
                          : AppColors.lightGray,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.white,
                          size: 18,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isCurrent
                                ? AppColors.white
                                : AppColors
                                    .secondaryText,
                            fontSize: 13,
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),
                ),
              ),

              if (index < 2)
                Expanded(
                  child: Container(
                    height: 3,
                    margin:
                        const EdgeInsets.symmetric(
                      horizontal: 7,
                    ),
                    decoration: BoxDecoration(
                      color: index < currentStep
                          ? AppColors.teal
                          : AppColors.lightGray,
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // =========================================================
  // CURRENT STEP
  // =========================================================

  Widget buildCurrentStep() {
    switch (currentStep) {
      case 0:
        return buildAcademicStep();

      case 1:
        return buildCareerStep();

      case 2:
        return buildCvStep();

      default:
        return const SizedBox.shrink();
    }
  }

  // =========================================================
  // STEP 1: ACADEMIC INFORMATION
  // =========================================================

  Widget buildAcademicStep() {
    return Form(
      key: _academicFormKey,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // UNIVERSITY

          buildTextField(
            controller: universityController,
            label: 'University',
            hint: 'Enter your university',
            icon: Icons
                .account_balance_outlined,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'This field is required.';
              }

              return null;
            },
          ),

          const SizedBox(height: 20),

          // DEGREE

          buildDropdown(
            label: 'Degree',
            hint: 'Select your degree',
            icon: Icons.school_outlined,
            value: selectedDegree,
            items: degreeOptions
                .map(
                  (degree) =>
                      DropdownMenuItem(
                    value: degree,
                    child: Text(degree),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedDegree = value;
              });
            },
          ),

          const SizedBox(height: 20),

          // MAJOR

          buildTextField(
            controller: majorController,
            label: 'Major',
            hint: 'e.g. Information Technology',
            icon: Icons
                .menu_book_outlined,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'This field is required.';
              }

              return null;
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // STEP 2: CAREER INFORMATION
  // =========================================================

  Widget buildCareerStep() {
    return Form(
      key: _careerFormKey,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // GRADUATION STATUS

          buildDropdown(
            label: 'Graduation Status',
            hint: 'Select your status',
            icon: Icons
                .workspace_premium_outlined,
            value:
                selectedGraduationStatus,
            items: graduationStatusOptions
                .map(
                  (status) =>
                      DropdownMenuItem(
                    value: status,
                    child: Text(status),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedGraduationStatus =
                    value;
              });
            },
          ),

          const SizedBox(height: 20),

          // GRADUATION YEAR

          buildTextField(
            controller:
                graduationYearController,
            label: 'Graduation Year',
            hint: 'e.g. 2026',
            icon: Icons
                .calendar_month_outlined,
            keyboardType:
                TextInputType.number,
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'This field is required.';
              }

              final year = int.tryParse(
                value.trim(),
              );

              if (year == null ||
                  value.trim().length != 4 ||
                  year < 1950 ||
                  year >
                      DateTime.now().year +
                          10) {
                return 'Please enter a valid graduation year.';
              }

              return null;
            },
          ),

          const SizedBox(height: 20),

          // CAREER GOAL

          buildDropdown(
            label: 'Career Goal',
            hint: 'Select your career goal',
            icon: Icons.flag_outlined,
            value: selectedCareerGoalId,
            items: careerGoals.entries
                .map(
                  (entry) =>
                      DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedCareerGoalId =
                    value;
              });
            },
          ),

          const SizedBox(height: 20),

          // EXPERIENCE LEVEL

          buildDropdown(
            label: 'Current Experience Level',
            hint: 'Select your experience level',
            icon: Icons
                .trending_up_rounded,
            value:
                selectedExperienceLevel,
            items: experienceOptions
                .map(
                  (level) =>
                      DropdownMenuItem(
                    value: level,
                    child: Text(level),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedExperienceLevel =
                    value;
              });
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // STEP 3: CV UPLOAD
  // =========================================================

  Widget buildCvStep() {
    final hasCv =
        selectedCvBytes != null &&
        selectedCvName != null;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        // =========================================
        // UPLOAD CARD
        // =========================================

        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 30,
          ),
          decoration: BoxDecoration(
            color: AppColors
                .softBackground,
            borderRadius:
                BorderRadius.circular(
              22,
            ),
            border: Border.all(
              color: hasCv
                  ? AppColors.teal
                  : AppColors.lightGray,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              // ICON

              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: hasCv
                      ? AppColors.lightTeal
                      : AppColors.lightTeal
                          .withValues(
                        alpha: 0.65,
                      ),
                  borderRadius:
                      BorderRadius.circular(
                    21,
                  ),
                ),
                child: Icon(
                  hasCv
                      ? Icons
                          .description_rounded
                      : Icons
                          .upload_file_rounded,
                  color: AppColors.teal,
                  size: 33,
                ),
              ),

              const SizedBox(height: 20),

              // TITLE

              Text(
                hasCv
                    ? 'CV Selected'
                    : 'Upload Your CV',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(height: 8),

              // DESCRIPTION

              Text(
                hasCv
                    ? selectedCvName!
                    : 'Choose your CV to complete your profile.',
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  color: AppColors
                      .secondaryText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'PDF format only',
                style: TextStyle(
                  color: AppColors.teal,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              const SizedBox(height: 24),

              // SELECT FILE BUTTON

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed:
                      isPickingCv || isSaving
                          ? null
                          : pickCv,
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        AppColors.navy,
                    side: const BorderSide(
                      color: AppColors.teal,
                      width: 1.3,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        16,
                      ),
                    ),
                  ),
                  icon: isPickingCv
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                AppColors.teal,
                          ),
                        )
                      : Icon(
                          hasCv
                              ? Icons
                                  .refresh_rounded
                              : Icons
                                  .upload_rounded,
                          size: 21,
                        ),
                  label: Text(
                    isPickingCv
                        ? 'Checking File...'
                        : hasCv
                            ? 'Change CV'
                            : 'Choose PDF File',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // REMOVE BUTTON

              if (hasCv) ...[
                const SizedBox(
                  height: 12,
                ),

                TextButton.icon(
                  onPressed: isSaving
                      ? null
                      : removeCv,
                  icon: const Icon(
                    Icons
                        .delete_outline_rounded,
                    size: 18,
                  ),
                  label: const Text(
                    'Remove File',
                  ),
                  style:
                      TextButton.styleFrom(
                    foregroundColor:
                        const Color(
                      0xFFC94C4C,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 22),

        // =========================================
        // INFORMATION CARD
        // =========================================

        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: AppColors.lightTeal
                .withValues(
              alpha: 0.45,
            ),
            borderRadius:
                BorderRadius.circular(
              17,
            ),
          ),
          child: const Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                Icons
                    .info_outline_rounded,
                color: AppColors.teal,
                size: 21,
              ),

              SizedBox(width: 12),

              Expanded(
                child: Text(
                  'Your CV helps Masra understand your skills, experience, and qualifications to provide personalized recommendations.',
                  style: TextStyle(
                    color: AppColors
                        .secondaryNavy,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // TEXT FIELD
  // =========================================================

  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType =
        TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
            fontWeight:
                FontWeight.w700,
          ),
        ),

        const SizedBox(height: 9),

        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(
              color: AppColors
                  .mediumGray,
              fontSize: 13,
            ),
            prefixIcon: Icon(
              icon,
              color: AppColors
                  .secondaryText,
              size: 21,
            ),
            filled: true,
            fillColor: AppColors
                .softBackground,
            contentPadding:
                const EdgeInsets.symmetric(
              horizontal: 17,
              vertical: 18,
            ),
            border:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: AppColors
                    .lightGray,
              ),
            ),
            enabledBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: AppColors
                    .lightGray,
              ),
            ),
            focusedBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: AppColors.teal,
                width: 1.5,
              ),
            ),
            errorBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: Color(
                  0xFFC94C4C,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // DROPDOWN FIELD
  // =========================================================

  Widget buildDropdown({
    required String label,
    required String hint,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>>
        items,
    required ValueChanged<String?>
        onChanged,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
            fontWeight:
                FontWeight.w700,
          ),
        ),

        const SizedBox(height: 9),

        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          validator: (value) {
            if (value == null ||
                value.isEmpty) {
              return 'This field is required.';
            }

            return null;
          },
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
          ),
          dropdownColor:
              AppColors.softBackground,
          icon: const Icon(
            Icons
                .keyboard_arrow_down_rounded,
            color: AppColors
                .secondaryText,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(
              color: AppColors
                  .mediumGray,
              fontSize: 13,
            ),
            prefixIcon: Icon(
              icon,
              color: AppColors
                  .secondaryText,
              size: 21,
            ),
            filled: true,
            fillColor: AppColors
                .softBackground,
            contentPadding:
                const EdgeInsets.symmetric(
              horizontal: 17,
              vertical: 18,
            ),
            border:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: AppColors
                    .lightGray,
              ),
            ),
            enabledBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: AppColors
                    .lightGray,
              ),
            ),
            focusedBorder:
                OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(
                15,
              ),
              borderSide:
                  const BorderSide(
                color: AppColors.teal,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // MAIN BUTTON
  // =========================================================

  Widget buildMainButton() {
    final isLastStep =
        currentStep == 2;

    final canFinish =
        selectedCvBytes != null &&
        selectedCvName != null;

    final isDisabled =
        isSaving ||
        isPickingCv ||
        (isLastStep && !canFinish);

    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(
          20,
        ),
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
                  color: AppColors.teal
                      .withValues(
                    alpha: 0.24,
                  ),
                  blurRadius: 18,
                  offset:
                      const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed:
            isDisabled
                ? null
                : nextStep,
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              Colors.transparent,
          disabledBackgroundColor:
              Colors.transparent,
          shadowColor:
              Colors.transparent,
          foregroundColor:
              AppColors.white,
          disabledForegroundColor:
              AppColors.white,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              20,
            ),
          ),
        ),
        child: isSaving
            ? const SizedBox(
                width: 23,
                height: 23,
                child:
                    CircularProgressIndicator(
                  color:
                      AppColors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Text(
                    isLastStep
                        ? 'Save & Finish'
                        : 'Continue',
                    style:
                        const TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Icon(
                    isLastStep
                        ? Icons
                            .check_rounded
                        : Icons
                            .arrow_forward_rounded,
                    size: 22,
                  ),
                ],
              ),
      ),
    );
  }
}
