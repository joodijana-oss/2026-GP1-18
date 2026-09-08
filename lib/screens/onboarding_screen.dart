import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int currentPage = 0;

  static const Color navy = Color(0xFF06365A);
  static const Color teal = Color(0xFF0B91A6);
  static const Color lightDot = Color(0xFFD7E1E5);

  void goToLogin() {
    // لاحقًا اربطيها بصفحة الـ Login
    // مثال:
    // Navigator.pushReplacement(
    //   context,
    //   MaterialPageRoute(builder: (_) => const LoginScreen()),
    // );
  }

  void goToNextPage() {
    // حاليًا هذا أول تصميم فقط.
    // لما نسوي باقي صفحات الـ onboarding
    // نخلي الزر ينتقل للصفحة التالية.

    if (currentPage < 2) {
      setState(() {
        currentPage++;
      });
    } else {
      goToLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ==========================
          // BACKGROUND IMAGE
          // ==========================
          Positioned.fill(
            child: Image.asset(
              'lib/assets/images/welcome_background.PNG',
              fit: BoxFit.cover,
            ),
          ),

          // طبقة خفيفة جدًا لتحسين وضوح العناصر
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.02),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // ==========================
                  // SKIP
                  // ==========================
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: goToLogin,
                      style: TextButton.styleFrom(
                        foregroundColor: navy,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: size.height * 0.16),

                  // ==========================
                  // YOUR LOGO GOES HERE
                  // ==========================
                  Image.asset(
                     'lib/assets/images/Logoo.png',
                    width: size.width * 0.62,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: 14),

                  // ==========================
                  // GUIDE • DEVELOP • ACHIEVE
                  // ==========================
                  const Text(
                    'G U I D E   •   D E V E L O P   •   A C H I E V E',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF60788C),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2.2,
                    ),
                  ),

                  const Spacer(),

                  // ==========================
                  // GET STARTED BUTTON
                  // ==========================
                  SizedBox(
                    width: double.infinity,
                    height: 62,
                    child: ElevatedButton(
                      onPressed: goToNextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: navy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                        ),
                      ),
                      child: Row(
                        children: const [
                          Expanded(
                            child: Text(
                              "Let's Get Started",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ==========================
                  // PAGE INDICATORS
                  // ==========================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (index) => GestureDetector(
                        onTap: () {
                          setState(() {
                            currentPage = index;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: currentPage == index
                                ? teal
                                : lightDot,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 34),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}