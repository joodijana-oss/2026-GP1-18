import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class ProjectDiscoveryScreen extends StatelessWidget {
  const ProjectDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Smart Project Discovery',
      description: 'Discover GitHub projects matched to your skills and interests.',
      icon: Icons.code_outlined,
    );
  }
}