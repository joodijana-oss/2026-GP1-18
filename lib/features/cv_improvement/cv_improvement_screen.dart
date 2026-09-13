import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class CVImprovementScreen extends StatelessWidget {
  const CVImprovementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'CV Improvement Assistant',
      description: 'Optimize your CV and make it stronger with AI.',
      icon: Icons.edit_document,
    );
  }
}