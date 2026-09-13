import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class JobMatchScreen extends StatelessWidget {
  const JobMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Job Match',
      description: 'Compare your profile with job requirements and discover your match.',
      icon: Icons.work_outline,
    );
  }
}