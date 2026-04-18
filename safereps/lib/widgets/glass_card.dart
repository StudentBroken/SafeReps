import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Frosted-glass morphism card. Blurs whatever is behind it.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20.0,
    this.tint,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? tint;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: tint ?? colors.glassFill,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border
                ? Border.all(color: colors.glassBorder, width: 0.8)
                : null,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
