import 'package:flutter/material.dart';

import '../theme/dashboard_colors.dart';

class DashboardSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const DashboardSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DashboardColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DashboardColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: DashboardColors.primaryDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: DashboardColors.text, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: DashboardColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: DashboardColors.muted,
                          fontSize: 11,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class DashboardInlineEmpty extends StatelessWidget {
  final String message;

  const DashboardInlineEmpty({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: DashboardColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: DashboardColors.muted,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
