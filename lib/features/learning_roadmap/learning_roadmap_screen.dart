import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class LearningRoadmapScreen extends StatelessWidget {
  const LearningRoadmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Personalized Learning Roadmap',
      description: 'Follow a personalized path to develop the skills you need.',
      icon: Icons.account_tree_outlined,
    );
  }
}