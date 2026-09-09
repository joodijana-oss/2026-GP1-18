import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool hidePassword = true;
  bool hideConfirmPassword = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void createAccount() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account information is valid'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // =====================================================
          // TOP GRADIENT BACKGROUND
          // =====================================================
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

          // =====================================================
          // DECORATIVE GLOW - TOP RIGHT
          // =====================================================
          Positioned(
            top: -70,
            right: -50,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.lightTeal.withValues(alpha: 0.18),
              ),
            ),
          ),

          // =====================================================
          // DECORATIVE GOLD CIRCLE
          // =====================================================
          Positioned(
            top: 115,
            right: 38,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.4),
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
          ),

          // =====================================================
          // DECORATIVE TRANSPARENT CIRCLE
          // =====================================================
          Positioned(
            top: 80,
            left: -55,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.10),
                  width: 24,
                ),
              ),
            ),
          ),

          // =====================================================
          // PAGE CONTENT
          // =====================================================
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // =================================================
                  // TOP SECTION
                  // =================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      children: [
                        // ---------------------------------------------
                        // BACK BUTTON
                        // ---------------------------------------------
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 43,
                            height: 43,
                            decoration: BoxDecoration(
                              color:
                                  AppColors.white.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    AppColors.white.withValues(alpha: 0.20),
                              ),
                            ),
                            child: IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: AppColors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ---------------------------------------------
                        // MASRA LOGO
                        // ---------------------------------------------
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'lib/assets/images/Logoo.png',
                            width: 155,
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: 15),

                        // ---------------------------------------------
                        // SUBTITLE
                        // ---------------------------------------------
                        const Text(
                          'Your journey starts here.',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),

                        const SizedBox(height: 28),
                      ],
                    ),
                  ),

                  // =================================================
                  // FORM SHEET
                  // =================================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      24,
                      30,
                      24,
                      28,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(38),
                        topRight: Radius.circular(38),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---------------------------------------------
                          // SMALL TEAL ACCENT
                          // ---------------------------------------------
                          Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppColors.teal,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ---------------------------------------------
                          // TITLE
                          // ---------------------------------------------
                          const Text(
                            'Create Your Account',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),

                          const SizedBox(height: 7),

                          const Text(
                            'Join Masra and start building a career path made for you.',
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 27),

                          // =================================================
                          // FULL NAME
                          // =================================================
                          _buildField(
                            controller: nameController,
                            label: 'Full Name',
                            hint: 'Enter your full name',
                            icon: Icons.person_outline_rounded,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your name';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 17),

                          // =================================================
                          // EMAIL
                          // =================================================
                          _buildField(
                            controller: emailController,
                            label: 'Email Address',
                            hint: 'name@example.com',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your email';
                              }

                              if (!value.contains('@')) {
                                return 'Enter a valid email';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 17),

                          // =================================================
                          // PASSWORD
                          // =================================================
                          _buildField(
                            controller: passwordController,
                            label: 'Password',
                            hint: 'Create a password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: hidePassword,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  hidePassword = !hidePassword;
                                });
                              },
                              icon: Icon(
                                hidePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.secondaryText,
                                size: 21,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a password';
                              }

                              if (value.length < 8) {
                                return 'Password must be at least 8 characters';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 17),

                          // =================================================
                          // CONFIRM PASSWORD
                          // =================================================
                          _buildField(
                            controller: confirmPasswordController,
                            label: 'Confirm Password',
                            hint: 'Re-enter your password',
                            icon: Icons.verified_user_outlined,
                            obscureText: hideConfirmPassword,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  hideConfirmPassword =
                                      !hideConfirmPassword;
                                });
                              },
                              icon: Icon(
                                hideConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.secondaryText,
                                size: 21,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }

                              if (value != passwordController.text) {
                                return 'Passwords do not match';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 28),

                          // =================================================
                          // CREATE ACCOUNT BUTTON
                          // =================================================
                          Container(
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
                                  color:
                                      AppColors.teal.withValues(alpha: 0.24),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: createAccount,
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
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 17,
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
                          ),

                          const SizedBox(height: 25),

                          // =================================================
                          // ALREADY WITH US
                          // =================================================
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: AppColors.lightGray,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'Already with us?',
                                  style: TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: AppColors.lightGray,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // =================================================
                          // LOGIN BUTTON
                          // =================================================
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: OutlinedButton(
                              onPressed: () {
                                // لاحقاً نربطه بصفحة Login
                              },
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
                                'Log In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),
                        ],
                      ),
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

  // ===============================================================
  // REUSABLE TEXT FIELD
  // ===============================================================
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 14,
            ),

            prefixIcon: Container(
              margin: const EdgeInsets.all(9),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.teal.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppColors.teal,
                size: 20,
              ),
            ),

            suffixIcon: suffixIcon,

            filled: true,
            fillColor: AppColors.softBackground,

            contentPadding: const EdgeInsets.symmetric(
              vertical: 18,
              horizontal: 15,
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(
                color: AppColors.lightGray,
              ),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(
                color: AppColors.teal,
                width: 1.5,
              ),
            ),

            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(
                color: Colors.redAccent,
              ),
            ),

            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(
                color: Colors.redAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}