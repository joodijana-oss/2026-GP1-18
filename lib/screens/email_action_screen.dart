import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

// ============================================================
// EMAIL CHANGE LINK SCREEN
// Opened from the email change link (same layout as Reset Password):
// verifyAndChangeEmail = confirm the new email
// recoverEmail = undo the change (link sent to the old email)
// On success the user is signed out and logs in with the right email.
// ============================================================

class EmailActionScreen extends StatefulWidget {
  const EmailActionScreen({
    super.key,
    required this.mode,
    required this.oobCode,
  });

  final String mode;
  final String oobCode;

  @override
  State<EmailActionScreen> createState() => _EmailActionScreenState();
}

// applying = sending the code to Firebase, invalid = expired / used / wrong
// link, error = couldn't check (e.g. no internet)
enum _LinkState { applying, invalid, error }

class _EmailActionScreenState extends State<EmailActionScreen>
    with SingleTickerProviderStateMixin {
  _LinkState _linkState = _LinkState.applying;

  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  bool get _isRecover => widget.mode == 'recoverEmail';

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

    _applyLink();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  // ===============================================================
  // APPLY THE LINK
  // ===============================================================
  Future<void> _applyLink() async {
    setState(() => _linkState = _LinkState.applying);

    try {
      await FirebaseAuth.instance.applyActionCode(widget.oobCode);

      // The old session belongs to the old email: log in again
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
        _isRecover
            ? 'Email address restored successfully!'
            : 'Email address updated successfully!',
        subtitle: _isRecover
            ? 'Log in with your original email address.'
            : 'Log in with your new email address.',
        messenger: messenger,
      );
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

  void _goToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      _goToLogin();
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
                              onPressed: _linkState == _LinkState.applying
                                  ? null
                                  : _goBack,
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
      case _LinkState.applying:
        return _buildApplying();
      case _LinkState.invalid:
        return _buildMessageState(
          icon: Icons.link_off_rounded,
          title: 'Link Not Valid',
          message: 'This link is invalid or has expired.',
          buttonText: 'Go to Log In',
          onPressed: _goToLogin,
        );
      case _LinkState.error:
        return _buildMessageState(
          icon: Icons.wifi_off_rounded,
          title: 'Couldn’t Check Link',
          message:
              'We couldn’t check your link. Please check your connection and try again.',
          buttonText: 'Try Again',
          onPressed: _applyLink,
        );
    }
  }

  // ===============================================================
  // APPLYING LINK
  // ===============================================================
  Widget _buildApplying() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: AppColors.teal,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isRecover
                  ? 'Restoring your email address...'
                  : 'Confirming your new email address...',
              style: const TextStyle(
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
  // MAIN BUTTON (same gradient as the other auth pages)
  // ===============================================================
  Widget _buildMainButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
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
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
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
}
