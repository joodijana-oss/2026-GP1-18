import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class MockInterviewScreen extends StatelessWidget {
  const MockInterviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'AI Mock Interview Simulator',
      description: 'Practice realistic interviews and improve your interview skills with AI.',
      icon: Icons.chat_bubble_outline,
    );
  }
}