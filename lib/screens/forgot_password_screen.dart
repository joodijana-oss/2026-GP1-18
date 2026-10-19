import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/validators.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();

  bool _loading = false;

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  // Send stays disabled until the email is valid
  bool get _isFormValid => Validators.email(emailController.text) == null;

  @override
  void initState() {
    super.initState();

    // Refresh the button state on every keystroke
    emailController.addListener(() => setState(() {}));

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
    emailController.dispose();
    super.dispose();
  }
  // ===============================================================
  // SEND RESET LINK
  // ===============================================================
  // Same message whether or not the email has an account,
  // so the page never reveals which emails are registered.
  static const _neutralSuccessMessage =
      'If an account exists for this email, a password reset link has been sent.';

  Future<void> sendResetLink() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );
      _showMessage(_neutralSuccessMessage);
    } on FirebaseAuthException catch (e) {
      // user-not-found only happens when Email Enumeration Protection
      // is off; still show the neutral message.
      if (e.code == 'user-not-found') {
        _showMessage(_neutralSuccessMessage);
        return;
      }

      final message = switch (e.code) {
        'invalid-email' => 'Enter a valid email address.',
        'network-request-failed' =>
          'No internet connection. Please try again.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => 'Something went wrong. Please try again.',
      };
      _showMessage(message, isError: true);
    } catch (_) {
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===============================================================
  // SNACKBAR MESSAGE (success / error) - same style as Log In
  // ===============================================================
  void _showMessage(String title, {bool isError = false}) {
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
        duration: Duration(seconds: isError ? 3 : 5),
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
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // =========================
          // TOP GRADIENT
          // =========================
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

          // =========================
          // ANIMATED CIRCLES
          // =========================
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

          // =========================
          // PAGE CONTENT
          // =========================
          SafeArea(
            child: SingleChildScrollView(
              
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                    ),
                    child: Column(
                      children: [
                        // =========================
                        // BACK BUTTON
                        // =========================
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


                        const SizedBox(height: 28),
                      ],
                    ),
                  ),

                  // =========================
                  // BOTTOM SHEET
                  // =========================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      24,
                      30,
                      24,
                      35,
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
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          // TEAL ACCENT
                          Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppColors.teal,
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),

                          const SizedBox(height: 7),

                          const Text(
                            'Enter the email address associated with your account and we’ll send you a link to reset your password.',
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // =========================
                          // EMAIL FIELD
                          // =========================
                          _buildField(
                            controller: emailController,
                            label: 'Email Address',
                            hint: Validators.emailHint,
                            icon: Icons.mail_outline_rounded,
                            keyboardType:
                                TextInputType.emailAddress,
                            validator: Validators.email,
                          ),

                          const SizedBox(height: 28),

                          // =========================
                          // SEND BUTTON
                          // Dimmed and disabled until the email is valid
                          // =========================
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isFormValid || _loading ? 1 : 0.5,
                            child: Container(
                            width: double.infinity,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(20),
                              gradient:
                                  const LinearGradient(
                                colors: [
                                  AppColors.navy,
                                  AppColors.secondaryNavy,
                                  AppColors.teal,
                                ],
                              ),
                              boxShadow: [
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
                              onPressed: _loading || !_isFormValid
                                  ? null
                                  : sendResetLink,
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
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                    20,
                                  ),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 23,
                                      height: 23,
                                      child: CircularProgressIndicator(
                                        color: AppColors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Send Reset Link',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight:
                                          FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Icon(
                                    Icons
                                        .arrow_forward_rounded,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ),

                          const SizedBox(height: 26),

                          // =========================
                          // BACK TO LOGIN
                          // =========================
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color:
                                      AppColors.lightGray,
                                ),
                              ),
                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'Remember your password?',
                                  style: TextStyle(
                                    color: AppColors
                                        .secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color:
                                      AppColors.lightGray,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style:
                                  OutlinedButton.styleFrom(
                                foregroundColor:
                                    AppColors.navy,
                                side: BorderSide(
                                  color: AppColors.navy
                                      .withValues(
                                    alpha: 0.20,
                                  ),
                                ),
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(
                                    18,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'Back to Log In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight.w700,
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
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
          keyboardType: keyboardType,
          validator: validator,
          // Live: re-validates on every change once the user has typed
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
                color:
                    AppColors.teal.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: AppColors.teal,
                size: 20,
              ),
            ),
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