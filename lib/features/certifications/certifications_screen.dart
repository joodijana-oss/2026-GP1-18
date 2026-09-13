import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class CertificationsScreen extends StatelessWidget {
  const CertificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Professional Certification Recommender',
      description: 'Find certifications that match your career goals and skills.',
      icon: Icons.workspace_premium_outlined,
    );
  }
}