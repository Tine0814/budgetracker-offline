import 'package:flutter/material.dart';

/// The canonical Budget Flow mark used across the application shell.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.size,
    this.semanticLabel = 'Budget Flow logo',
  });

  static const assetPath = 'assets/branding/budget_flow_mark.png';

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticLabel,
    child: SizedBox.square(
      dimension: size,
      child: Image.asset(
        assetPath,
        excludeFromSemantics: true,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    ),
  );
}
