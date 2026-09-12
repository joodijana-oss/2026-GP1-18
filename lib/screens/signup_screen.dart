import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool hidePassword = true;
  bool hideConfirmPassword = true;

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

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

  @override
  void dispose() {
    _backgroundController.dispose();

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }
void createAccount() {
  if (_formKey.currentState!.validate()) {
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
        duration: const Duration(seconds: 1),

        content: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE4F6EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF23966F),
                size: 22,
              ),
            ),

            const SizedBox(width: 13),

            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account created successfully!',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Welcome to Masra.',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 5),

            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
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

    Future.delayed(
      const Duration(milliseconds: 700),
      () {
        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
          (route) => false,
        );
      },
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
          // ANIMATED BACKGROUND CIRCLES
          // =====================================================
          SizedBox(
            height: 315,
            width: double.infinity,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _backgroundAnimation,
                builder: (context, child) {
                  final value = _backgroundAnimation.value;

                  return Stack(
                    children: [
                      // ---------------------------------------------
                      // LARGE LEFT RING
                      // ---------------------------------------------
                      Positioned(
                        top: 35 + (value * 22),
                        left: -70 + (value * 14),
                        child: Container(
                          width: 175,
                          height: 175,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.lightTeal.withValues(
                                alpha: 0.12,
                              ),
                              width: 28,
                            ),
                          ),
                        ),
                      ),

                      // ---------------------------------------------
                      // TOP RIGHT SOFT CIRCLE
                      // ---------------------------------------------
                      Positioned(
                        top: -95 + (value * 18),
                        right: -60 - (value * 14),
                        child: Container(
                          width: 225,
                          height: 225,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.lightTeal.withValues(
                              alpha: 0.10,
                            ),
                          ),
                        ),
                      ),

                      // ---------------------------------------------
                      // BOTTOM RIGHT RING
                      // ---------------------------------------------
                      Positioned(
                        top: 190 - (value * 20),
                        right: -80 + (value * 12),
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.lightTeal.withValues(
                                alpha: 0.10,
                              ),
                              width: 22,
                            ),
                          ),
                        ),
                      ),

                      // ---------------------------------------------
                      // SMALL FLOATING CIRCLE
                      // ---------------------------------------------
                      Positioned(
                        top: 115 + (value * 18),
                        left: 135 - (value * 20),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.lightTeal.withValues(
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

          // =====================================================
          // PAGE CONTENT
          // =====================================================
          SafeArea(
            child: SingleChildScrollView(
    
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
                              color: AppColors.white.withValues(
                                alpha: 0.13,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.white.withValues(
                                  alpha: 0.20,
                                ),
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

                        const SizedBox(height: 95),

                        // ---------------------------------------------
                        // SUBTITLE
                        // ---------------------------------------------
                        /*const Text(
                          'Your journey starts here.',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
*/
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

  final email = value.trim();

  final emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  if (!emailRegex.hasMatch(email)) {
    return 'Please enter a valid email address';
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

  if (!RegExp(r'[A-Z]').hasMatch(value)) {
    return 'Password must contain an uppercase letter';
  }

  if (!RegExp(r'[a-z]').hasMatch(value)) {
    return 'Password must contain a lowercase letter';
  }

  if (!RegExp(r'[0-9]').hasMatch(value)) {
    return 'Password must contain a number';
  }

  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(value)) {
    return 'Password must contain a special character';
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
                                  color: AppColors.teal.withValues(
                                    alpha: 0.24,
                                  ),
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
   Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const LoginScreen(),
    ),
  );
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