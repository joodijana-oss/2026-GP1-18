import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class CareerAnalysisScreen extends StatelessWidget {
  const CareerAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'AI Career Analysis',
      description: 'Understand your career readiness with AI-powered analysis.',
      icon: Icons.psychology_outlined,
    );
  }
}