import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class OpportunitiesScreen extends StatelessWidget {
  const OpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Opportunity Radar',
      description: 'Discover development opportunities that match your profile.',
      icon: Icons.radar_outlined,
    );
  }
}