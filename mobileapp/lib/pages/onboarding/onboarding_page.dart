import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';

@RoutePage()
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                  SizedBox(width: 9),
                  Text(
                    'Airpix',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.burst_mode_rounded,
                        color: AppColors.primary,
                        size: 25,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Photos delivered\nwhile the moment lives.',
                      style: TextStyle(
                        color: AppColors.foreground,
                        fontSize: 24,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'A focused workspace for photographers, planners and guests — from capture to live gallery delivery.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Row(
                children: [
                  Expanded(
                    child: _OnboardingBenefit(
                      icon: Icons.cloud_upload_outlined,
                      label: 'Fast upload',
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _OnboardingBenefit(
                      icon: Icons.collections_outlined,
                      label: 'Live galleries',
                      color: AppColors.secondary,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _OnboardingBenefit(
                      icon: Icons.qr_code_2_rounded,
                      label: 'Guest delivery',
                      color: AppColors.tertiary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await UserStorage.saveSeenOnboarding();
                    if (context.mounted) {
                      await goHome(context);
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Enter Airpix'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingBenefit extends StatelessWidget {
  const _OnboardingBenefit({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: color == AppColors.tertiary
                  ? const Color(0xFFA16207)
                  : color,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
