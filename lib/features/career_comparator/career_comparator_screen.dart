import 'package:flutter/material.dart';
import '../../widgets/feature_placeholder.dart';

class CareerComparatorScreen extends StatelessWidget {
  const CareerComparatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Career Path Comparator',
      description: 'Compare different career paths and discover which one fits you best.',
      icon: Icons.alt_route,
    );
  }
}