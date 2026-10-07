import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/password_validator.dart';
import 'forgot_password_screen.dart';
import 'login_screen.dart';

// ============================================================
// NEW PASSWORD SCREEN
// Opened from the reset link in the email (oobCode = the link's code)
// ============================================================

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.oobCode});

  final String oobCode;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

// checking = verifying the link, valid = show the form,
// invalid = expired / used / wrong link, error = couldn't check (e.g. no internet)
enum _LinkState { checking, valid, invalid, error }

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool hidePassword = true;
  bool hideConfirmPassword = true;

  _LinkState _linkState = _LinkState.checking;
  String? _email;
  bool _loading = false;

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

    _verifyLink();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // ===============================================================
  // 1) CHECK THE LINK
  // ===============================================================
  Future<void> _verifyLink() async {
    setState(() => _linkState = _LinkState.checking);

    try {
      final email =
          await FirebaseAuth.instance.verifyPasswordResetCode(widget.oobCode);
      if (!mounted) return;
      setState(() {
        _email = email;
        _linkState = _LinkState.valid;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'network-request-failed') {
        setState(() => _linkState = _LinkState.error);
        _showMessage('No internet connection. Please try again.',
            isError: true);
      } else {
        // expired-action-code, invalid-action-code, user-disabled,
        // user-not-found
        setState(() => _linkState = _LinkState.invalid);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _linkState = _LinkState.error);
    }
  }

  // ===============================================================
  // 2) SAVE THE NEW PASSWORD
  // ===============================================================
  Future<void> _resetPassword() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: passwordController.text,
      );

      // Any old session is no longer valid after a password change
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      if (!mounted) return;

      // Keep the messenger so the SnackBar shows on the Log In page
      final messenger = ScaffoldMessenger.of(context);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );

      _showMessage(
        'Password updated successfully!',
        subtitle: 'Log in with your new password.',
        messenger: messenger,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // The link expired or was used while the page was open
      if (e.code == 'expired-action-code' ||
          e.code == 'invalid-action-code') {
        setState(() => _linkState = _LinkState.invalid);
        return;
      }

      final message = switch (e.code) {
        'weak-password' =>
          'This password is too weak. Please choose a stronger one.',
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
  // REQUEST NEW LINK -> Password Reset page (Log In underneath)
  // ===============================================================
  void _requestNewLink() {
    final navigator = Navigator.of(context);

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
    navigator.push(
      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // ===============================================================
  // SNACKBAR MESSAGE (success / error) - same style as Log In
  // ===============================================================
  void _showMessage(
    String title, {
    String? subtitle,
    bool isError = false,
    ScaffoldMessengerState? messenger,
  }) {
    if (messenger == null) {
      if (!mounted) return;
      messenger = ScaffoldMessenger.of(context);
    }
    final target = messenger;

    target.hideCurrentSnackBar();
    target.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.softBackground,
        elevation: 8,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(seconds: 3),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 5),
            IconButton(
              onPressed: () => target.hideCurrentSnackBar(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      children: [
                        // BACK BUTTON
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 43,
                            height: 43,
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.white.withValues(alpha: 0.20),
                              ),
                            ),
                            child: IconButton(
                              onPressed: _loading ? null : _goBack,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: AppColors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 123),
                      ],
                    ),
                  ),

                  // =========================
                  // BOTTOM SHEET
                  // =========================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 35),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(38),
                        topRight: Radius.circular(38),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // TEAL ACCENT
                        Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.teal,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildContent(),
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

  Widget _buildContent() {
    switch (_linkState) {
      case _LinkState.checking:
        return _buildChecking();
      case _LinkState.valid:
        return _buildForm();
      case _LinkState.invalid:
        return _buildMessageState(
          icon: Icons.link_off_rounded,
          title: 'Link Not Valid',
          message: 'This password reset link is invalid or has expired.',
          buttonText: 'Request New Link',
          onPressed: _requestNewLink,
        );
      case _LinkState.error:
        return _buildMessageState(
          icon: Icons.wifi_off_rounded,
          title: 'Couldn’t Check Link',
          message:
              'We couldn’t check your reset link. Please check your connection and try again.',
          buttonText: 'Try Again',
          onPressed: _verifyLink,
        );
    }
  }

  // ===============================================================
  // CHECKING LINK
  // ===============================================================
  Widget _buildChecking() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: AppColors.teal,
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Checking your reset link...',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // INVALID / ERROR STATE
  // ===============================================================
  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 29,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFD64545), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _buildMainButton(
          text: buttonText,
          icon: Icons.arrow_forward_rounded,
          onPressed: onPressed,
        ),
      ],
    );
  }

  // ===============================================================
  // NEW PASSWORD FORM
  // ===============================================================
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New Password',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _email == null
                ? 'Create a new password for your account.'
                : 'Create a new password for $_email.',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),

          // NEW PASSWORD
          _buildField(
            controller: passwordController,
            label: 'New Password',
            hint: 'Create a new password',
            icon: Icons.lock_outline_rounded,
            obscureText: hidePassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => hidePassword = !hidePassword),
              icon: Icon(
                hidePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.secondaryText,
                size: 21,
              ),
            ),
            validator: (value) => PasswordValidator.validate(
              value,
              requiredMessage: 'New password is required.',
            ),
          ),

          const SizedBox(height: 17),

          // CONFIRM NEW PASSWORD
          _buildField(
            controller: confirmPasswordController,
            label: 'Confirm New Password',
            hint: 'Re-enter your new password',
            icon: Icons.verified_user_outlined,
            obscureText: hideConfirmPassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => hideConfirmPassword = !hideConfirmPassword),
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
                return 'Please confirm your new password.';
              }
              if (value != passwordController.text) {
                return 'Passwords do not match.';
              }
              return null;
            },
          ),

          const SizedBox(height: 28),

          _buildMainButton(
            text: 'Reset Password',
            icon: Icons.check_rounded,
            onPressed: _resetPassword,
            loading: _loading,
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // MAIN BUTTON (same gradient as the other auth pages)
  // ===============================================================
  Widget _buildMainButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    bool loading = false,
  }) {
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
        onPressed: loading ? null : onPressed,
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
        child: loading
            ? const SizedBox(
                width: 23,
                height: 23,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 22),
                ],
              ),
      ),
    );
  }

  // ===============================================================
  // FIELD (same style as Log In)
  // ===============================================================
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
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
            // Room for the list of unmet password rules
            errorMaxLines: 8,
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
