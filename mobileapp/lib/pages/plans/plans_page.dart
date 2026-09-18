import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:mobileapp/core/constants/feature_mapping.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/widgets/app_ui.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  bool _isYearly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plans & billing'),
            SizedBox(height: 3),
            Text(
              'Storage, delivery tools and credits',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBillingToggle(),
            const SizedBox(height: 24),
            _buildPlansSection(),
            const SizedBox(height: 32),
            _buildAddonsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleButton(
              label: 'Monthly',
              isSelected: !_isYearly,
              onTap: () => setState(() => _isYearly = false),
            ),
          ),
          Expanded(
            child: _ToggleButton(
              label: 'Yearly',
              isSelected: _isYearly,
              onTap: () => setState(() => _isYearly = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlansSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subscription Plans',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the perfect plan for your needs',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadPlans(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final plans = snapshot.data ?? [];
            final filteredPlans = plans
                .where(
                  (p) =>
                      p['billingUnit'] ==
                      (_isYearly ? 'PER_YEAR' : 'PER_MONTH'),
                )
                .toList();
            if (filteredPlans.isEmpty) {
              return _buildDefaultPlans();
            }
            return Column(
              children: filteredPlans
                  .map(
                    (plan) => _PlanCard(
                      plan: plan,
                      isYearly: _isYearly,
                      onBuy: () => _openMobilePaymentSheet(
                        endpoint: '/subscription-plan/mobile-payment-sheet',
                        verifyEndpoint:
                            '/subscription-plan/verify-mobile-payment',
                        data: {'id': plan['_id']},
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDefaultPlans() {
    final plans = _isYearly
        ? [
            {
              'title': 'Silver',
              'price': 199.0,
              'features': [
                '50GB Storage',
                'Unlimited Photographers',
                'Brand Card',
                'URL Customization',
                'AI Reviewer',
              ],
            },
            {
              'title': 'Gold',
              'price': 799.0,
              'features': [
                '300GB Storage',
                'AI Retouch & Search',
                'Video Live',
                'Premium Features',
              ],
              'popular': true,
            },
            {
              'title': 'Platinum',
              'price': 2999.0,
              'features': [
                '1TB Storage',
                'Premium Branding',
                'API Access',
                'Best for Events',
              ],
            },
          ]
        : [
            {
              'title': 'Silver',
              'price': 19.9,
              'features': [
                '50GB Storage',
                'Unlimited Photographers',
                'Brand Card',
                'URL Customization',
                'AI Reviewer',
              ],
            },
            {
              'title': 'Gold',
              'price': 79.9,
              'features': [
                '300GB Storage',
                'AI Retouch & Search',
                'Video Live',
                'Premium Features',
              ],
              'popular': true,
            },
            {
              'title': 'Platinum',
              'price': 299.9,
              'features': [
                '1TB Storage',
                'Premium Branding',
                'Video Live',
                'API Access',
              ],
            },
          ];
    return Column(
      children: plans
          .map(
            (plan) => _DefaultPlanCard(
              title: plan['title'] as String,
              price: plan['price'] as double,
              features: plan['features'] as List<String>,
              isPopular: plan['popular'] == true,
              isYearly: _isYearly,
              onBuy: () {},
            ),
          )
          .toList(),
    );
  }

  Widget _buildAddonsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Credit Addons',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Buy extra credits anytime',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadAddons(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final addons = snapshot.data ?? [];
            return Column(
              children: addons
                  .map(
                    (addon) => _AddonCard(
                      addon: addon,
                      onBuy: () => _openMobilePaymentSheet(
                        endpoint: '/addon/mobile-payment-sheet',
                        verifyEndpoint: '/addon/verify-mobile-payment',
                        data: {'addonId': addon['_id']},
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadPlans() async {
    final response = await DioHelper.get(
      '/subscription-plan/get-all?limit=100&isActive=true',
    );
    final data = response.data['data'] as List? ?? [];
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadAddons() async {
    final response = await DioHelper.get(
      '/addon/get-all?limit=100&isActive=true',
    );
    final data = response.data['data'] as List? ?? [];
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> _openMobilePaymentSheet({
    required String endpoint,
    required String verifyEndpoint,
    required Map<String, dynamic> data,
  }) async {
    final user = UserStorage.currentUser.value;
    if (user == null) {
      context.router.root.push(const LoginRoute());
      return;
    }

    try {
      final response = await DioHelper.post(endpoint, data: data);
      final paymentData = Map<String, dynamic>.from(
        response.data['data'] as Map? ?? {},
      );
      final publishableKey = paymentData['publishableKey']?.toString();
      final clientSecret = paymentData['paymentIntentClientSecret']?.toString();
      final paymentIntentId = paymentData['paymentIntentId']?.toString();

      if (publishableKey == null ||
          publishableKey.isEmpty ||
          clientSecret == null ||
          clientSecret.isEmpty ||
          paymentIntentId == null ||
          paymentIntentId.isEmpty) {
        throw Exception('Mobile payment data missing');
      }

      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Airpix',
          style: ThemeMode.light,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      await DioHelper.get(
        verifyEndpoint,
        queryParameters: {'paymentIntentId': paymentIntentId},
      );
      try {
        await _refreshCurrentUser();
      } catch (_) {}
      AppToast.success('Payment successful');
    } catch (e) {
      if (e is StripeException) {
        AppToast.error(e.error.localizedMessage ?? 'Payment cancelled');
        return;
      }
      AppToast.error('Payment failed');
    }
  }

  Future<void> _refreshCurrentUser() async {
    final response = await DioHelper.get('/user/get-my-profile');
    final rawUser = response.data['data'] ?? response.data;
    if (rawUser is Map) {
      await UserStorage.saveUser(
        UserModel.fromJson(Map<String, dynamic>.from(rawUser)),
      );
    }
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected ? AppColors.border : Colors.transparent,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? AppColors.foreground
                : AppColors.mutedForeground,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final bool isYearly;
  final VoidCallback onBuy;

  const _PlanCard({
    required this.plan,
    required this.isYearly,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final title = plan['title']?.toString() ?? '';
    final price = (plan['discount_price'] ?? plan['price'] ?? 0).toString();
    final originalPrice =
        plan['discount_price'] != null && plan['price'] != null
        ? plan['price'].toString()
        : null;
    final isPopular = plan['isPopular'] == true;

    final features = FeatureMapping.normalizeFeatures(
      plan['features'] as List?,
    );
    final permissions = FeatureMapping.normalizePermissions(
      plan['permissions'] as List?,
    );
    final allItems = [...features, ...permissions];

    final tierColor = _getTierColor(title);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: isPopular
            ? Border.all(color: AppColors.primary, width: 1.6)
            : Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: isPopular
                ? AppColors.primary.withValues(alpha: 0.18)
                : AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.1),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                AppIconTile(
                  icon: Icons.workspace_premium,
                  size: 46,
                  iconSize: 23,
                  background: tierColor.withValues(alpha: 0.18),
                  foreground: tierColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (isPopular) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppGradients.brand,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Popular',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$$price',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: tierColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              isYearly ? '/year' : '/month',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ),
                          if (originalPrice != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '\$$originalPrice',
                              style: const TextStyle(
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (allItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: allItems
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 18,
                              color: tierColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: AppColors.foreground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: isPopular ? AppColors.primary : tierColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text(
                  'Choose plan',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('platinum')) return AppColors.secondary;
    if (lower.contains('gold')) return const Color(0xFFA16207);
    if (lower.contains('silver')) return const Color(0xFF78716C);
    return AppColors.primary;
  }
}

class _DefaultPlanCard extends StatelessWidget {
  final String title;
  final double price;
  final List<String> features;
  final bool isPopular;
  final bool isYearly;
  final VoidCallback onBuy;

  const _DefaultPlanCard({
    required this.title,
    required this.price,
    required this.features,
    required this.isPopular,
    required this.isYearly,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor(title);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: isPopular
            ? Border.all(color: AppColors.primary, width: 1.6)
            : Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: isPopular
                ? AppColors.primary.withValues(alpha: 0.18)
                : AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.1),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                AppIconTile(
                  icon: Icons.workspace_premium,
                  size: 46,
                  iconSize: 23,
                  background: tierColor.withValues(alpha: 0.18),
                  foreground: tierColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (isPopular) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppGradients.brand,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Popular',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)}',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tierColor,
                                ),
                          ),
                          Text(
                            isYearly ? '/year' : '/month',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: features
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: tierColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: isPopular ? AppColors.primary : tierColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text(
                  'Choose plan',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('platinum')) return AppColors.secondary;
    if (lower.contains('gold')) return const Color(0xFFA16207);
    if (lower.contains('silver')) return const Color(0xFF78716C);
    return AppColors.primary;
  }
}

class _AddonCard extends StatelessWidget {
  final Map<String, dynamic> addon;
  final VoidCallback onBuy;

  const _AddonCard({required this.addon, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final title = addon['title']?.toString() ?? '';
    final credits = addon['credit'] ?? 0;
    final price = addon['price'] ?? 0;
    final description = addon['description']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_circle,
              color: Theme.of(context).colorScheme.secondary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$credits Credits',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Buy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
