import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class HeatmapScreen extends StatelessWidget {
  const HeatmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Job Demand Heatmap',
      description: 'Explore job demand and career opportunities across Saudi Arabia.',
      icon: Icons.map_outlined,
    );
  }
}